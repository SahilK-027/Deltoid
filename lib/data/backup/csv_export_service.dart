import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../core/progress.dart';
import '../../domain/csv_export.dart';
import '../../domain/enums.dart';
import '../../domain/units.dart';
import '../db/database.dart';
import 'backup_service.dart';

/// The training log as two CSV files: every completed set, and every weigh-in.
///
/// Beside [BackupService] rather than inside it, because the two answer
/// different questions. A backup puts this phone back exactly as it was and is
/// read by nothing but this app; these files are read by a spreadsheet or by
/// another tracker, and by nothing in this one. See `domain/csv_export.dart`.
///
/// Completed sessions only, and only the sets ticked off in them: a session in
/// progress is not history yet, a discarded one never was, and a completed one
/// holds no unticked sets (`completeWorkout` tombstones them).
class CsvExportService {
  CsvExportService(this.db, {this.workoutsPerPage = 200});

  final AppDatabase db;

  /// Sessions read per pass. Injectable only so a test can put a page boundary
  /// between two sessions.
  final int workoutsPerPage;

  /// Writes the sets file and the bodyweight file into the backup folder and
  /// returns them in that order.
  Future<List<File>> exportToFiles(
    WeightUnit unit, {
    ProgressReport? onProgress,
  }) async {
    final dir = await BackupService(db).backupDirectory();
    final stamp = DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now());
    final sets = await writeSets(
      File('${dir.path}/deltoid-sets-$stamp.csv'),
      unit,
      onProgress: onProgress,
    );
    final bodyweight = await writeBodyweight(
      File('${dir.path}/deltoid-bodyweight-$stamp.csv'),
      unit,
    );
    return [sets, bodyweight];
  }

  /// Every completed set, oldest session first, one row each.
  ///
  /// Written a page of sessions at a time and arriving by rename, for the
  /// reasons [BackupService.writeBackup] gives: a decade of sets is never held
  /// in memory, and a write that dies leaves no half-file under a real name.
  ///
  /// Keyset-paged on `(started_at, id)`, the order History reads in, so a
  /// session logged while the export runs cannot shift the pages under it.
  Future<File> writeSets(
    File file,
    WeightUnit unit, {
    ProgressReport? onProgress,
  }) =>
      _writeAtomically(file, (sink) async {
        sink.write(csvLine(csvSetHeader(unit)));
        final total = await _doneSetCount();
        var written = 0;
        int? afterStartedAt;
        String? afterId;
        while (true) {
          final page = await _workoutPage(afterStartedAt, afterId);
          if (page.isEmpty) break;
          final rows = await _setsOf(page.map((w) => w.id).toList());
          final buffer = StringBuffer();
          for (final row in rows) {
            buffer.write(csvLine(csvSetCells(row, unit)));
          }
          sink.write(buffer.toString());
          await sink.flush();
          written += rows.length;
          onProgress?.call((
            phase: JobPhase.writing,
            detail: 'Sets',
            rows: written,
            fraction: total == 0 ? null : (written / total).clamp(0.0, 1.0),
          ));
          if (page.length < workoutsPerPage) break;
          afterStartedAt = page.last.startedAt;
          afterId = page.last.id;
        }
      });

  /// Every live weigh-in, oldest first. Small enough to read in one go: one
  /// row a day is eighteen thousand rows at fifty years.
  Future<File> writeBodyweight(File file, WeightUnit unit) =>
      _writeAtomically(file, (sink) async {
        sink.write(csvLine(csvBodyweightHeader(unit)));
        final rows = await (db.select(db.bodyweightLogs)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
            .get();
        final buffer = StringBuffer();
        for (final row in rows) {
          buffer.write(csvLine(csvBodyweightCells(row.dayKey, row.weightKg, unit)));
        }
        sink.write(buffer.toString());
      });

  /// Runs [body] into a `.part` beside [file] and renames it into place once
  /// [body] has finished, so the file appears complete or not at all.
  ///
  /// Opens with a UTF-8 byte order mark. Without one, Excel reads a CSV in the
  /// machine's legacy code page, and every accent in a note or a renamed
  /// exercise arrives mangled.
  Future<File> _writeAtomically(
    File file,
    Future<void> Function(IOSink sink) body,
  ) async {
    final partial = File('${file.path}.part');
    final sink = partial.openWrite(encoding: utf8)..write('﻿');
    var complete = false;
    try {
      await body(sink);
      complete = true;
    } finally {
      await sink.close();
      if (!complete && partial.existsSync()) partial.deleteSync();
    }
    return partial.rename(file.path);
  }

  static const _completed =
      "wo.status = 'completed' AND wo.deleted_at IS NULL";

  Future<int> _doneSetCount() async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS c FROM set_logs sl '
      'JOIN workout_exercises we ON we.id = sl.workout_exercise_id '
      'JOIN workouts wo ON wo.id = we.workout_id '
      'WHERE $_completed AND we.deleted_at IS NULL '
      'AND sl.deleted_at IS NULL AND sl.is_done = 1',
      readsFrom: {db.setLogs, db.workoutExercises, db.workouts},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<List<({String id, int startedAt})>> _workoutPage(
    int? afterStartedAt,
    String? afterId,
  ) async {
    final rows = await db.customSelect(
      'SELECT wo.id, wo.started_at FROM workouts wo WHERE $_completed '
      '${afterId == null ? '' : 'AND (wo.started_at > ? OR '
          '(wo.started_at = ? AND wo.id > ?)) '}'
      'ORDER BY wo.started_at, wo.id LIMIT ?',
      variables: [
        if (afterId != null) ...[
          Variable.withInt(afterStartedAt!),
          Variable.withInt(afterStartedAt),
          Variable.withString(afterId),
        ],
        Variable.withInt(workoutsPerPage),
      ],
      readsFrom: {db.workouts},
    ).get();
    return [
      for (final r in rows)
        (id: r.read<String>('id'), startedAt: r.read<int>('started_at')),
    ];
  }

  /// The done sets of [workoutIds], in the order they were logged.
  ///
  /// The muscle is the one recorded on the day where there is one — the
  /// snapshot rule — and the catalog's only for rows logged before that column
  /// existed. The exercise's name, equipment and load mode are read live: they
  /// are not snapshotted anywhere, and they are what the movement is called
  /// now.
  Future<List<CsvSet>> _setsOf(List<String> workoutIds) async {
    final marks = List.filled(workoutIds.length, '?').join(',');
    final rows = await db.customSelect(
      'SELECT wo.id AS wid, wo.day_key, wo.started_at, wo.tz_offset_minutes, '
      'wo.ended_at, wo.is_deload, wo.notes AS session_note, '
      'r.name AS regime, s.name AS session, '
      'we.id AS weid, we.notes AS exercise_note, '
      'COALESCE(we.muscle, e.muscle) AS muscle, '
      'e.name AS exercise, e.equipment, e.load_mode, e.measure_mode, '
      'sl.set_type, sl.weight, sl.added_weight, sl.reps, sl.partial_reps, '
      'sl.rest_seconds, sl.note AS set_note '
      'FROM set_logs sl '
      'JOIN workout_exercises we ON we.id = sl.workout_exercise_id '
      'JOIN workouts wo ON wo.id = we.workout_id '
      'JOIN regimes r ON r.id = wo.regime_id '
      'LEFT JOIN sessions s ON s.id = wo.session_id '
      'JOIN exercises e ON e.id = we.exercise_id '
      'WHERE wo.id IN ($marks) AND we.deleted_at IS NULL '
      'AND sl.deleted_at IS NULL AND sl.is_done = 1 '
      'ORDER BY wo.started_at, wo.id, we.order_index, sl.set_index',
      variables: [for (final id in workoutIds) Variable.withString(id)],
      readsFrom: {
        db.setLogs,
        db.workoutExercises,
        db.workouts,
        db.regimes,
        db.sessions,
        db.exercises,
      },
    ).get();

    // Numbered over what the file holds rather than read off `order_index` and
    // `set_index`, which keep the gaps a deleted set or a skipped exercise left
    // behind: the third set written is set 3.
    final out = <CsvSet>[];
    String? workout;
    String? slot;
    var exerciseOrder = 0;
    var setNumber = 0;
    for (final r in rows) {
      final wid = r.read<String>('wid');
      final weid = r.read<String>('weid');
      if (wid != workout) {
        workout = wid;
        exerciseOrder = 0;
        slot = null;
      }
      if (weid != slot) {
        slot = weid;
        exerciseOrder++;
        setNumber = 0;
      }
      setNumber++;
      out.add(CsvSet(
        dayKey: r.read<int>('day_key'),
        startedAt: r.read<int>('started_at'),
        tzOffsetMinutes: r.read<int>('tz_offset_minutes'),
        endedAt: r.readNullable<int>('ended_at'),
        regime: r.read<String>('regime'),
        session: r.readNullable<String>('session'),
        isDeload: r.read<bool>('is_deload'),
        exercise: r.read<String>('exercise'),
        muscle: MuscleGroup.values.byName(r.read<String>('muscle')),
        equipment: Equipment.values.byName(r.read<String>('equipment')),
        loadMode: LoadMode.values.byName(r.read<String>('load_mode')),
        measureMode: MeasureMode.values.byName(r.read<String>('measure_mode')),
        exerciseOrder: exerciseOrder,
        setNumber: setNumber,
        setType: SetType.values.byName(r.read<String>('set_type')),
        weightKg: r.readNullable<double>('weight'),
        addedWeightKg: r.readNullable<double>('added_weight'),
        count: r.readNullable<int>('reps'),
        partialReps: r.readNullable<int>('partial_reps'),
        restSeconds: r.readNullable<int>('rest_seconds'),
        setNote: r.readNullable<String>('set_note'),
        exerciseNote: r.readNullable<String>('exercise_note'),
        sessionNote: r.readNullable<String>('session_note'),
      ));
    }
    return out;
  }
}
