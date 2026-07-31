import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/enums.dart';
import '../db/database.dart';

/// Bumped whenever the export shape changes in a way an older build could not
/// read. Import refuses anything newer than it understands rather than
/// half-restoring a file from the future.
const backupFormatVersion = 1;

class BackupSummary {
  const BackupSummary({required this.counts, required this.exportedAt});

  final Map<String, int> counts;
  final DateTime exportedAt;

  int get totalRows => counts.values.fold(0, (a, b) => a + b);
}

class ImportResult {
  const ImportResult({required this.summary, required this.rowsWritten});

  final BackupSummary summary;
  final int rowsWritten;
}

/// One table's dump/restore pair.
///
/// Explicit rather than a generic loop over `TableInfo`, because reconstructing
/// a row from JSON needs the generated `fromJson` for its data class — the
/// generic `map()` reads database rows, not serialised ones, and would quietly
/// mangle enum and converter columns.
class _TableCodec {
  const _TableCodec({
    required this.name,
    required this.dump,
    required this.insert,
    required this.clear,
  });

  final String name;
  final Future<List<Map<String, dynamic>>> Function() dump;
  final Future<void> Function(Map<String, dynamic> row) insert;
  final Future<void> Function() clear;
}

/// Whole-database export and restore.
///
/// Deliberately separate from cloud sync: sync propagates whatever state the
/// app is in, bugs included. A file you hold is the only backup that survives
/// the app corrupting its own data, and it is what makes moving to a new phone
/// a copy rather than a migration.
class BackupService {
  BackupService(this.db);

  final AppDatabase db;

  /// Parents before children, so a restore never inserts a row whose foreign
  /// key has not been written yet.
  late final List<_TableCodec> _codecs = [
    _TableCodec(
      name: 'exercises',
      dump: () async => (await db.select(db.exercises).get())
          .map((e) => e.toJson())
          .toList(),
      // `fromJson` is generated against *today's* columns and reads every one
      // of them unconditionally, so a file written before a column existed
      // dies on a null cast — with the user's only copy of their history in
      // the picker. A default for anything added after v1 keeps old files
      // restorable; add one here whenever a column is added to this table.
      insert: (row) => db.into(db.exercises).insert(
            Exercise.fromJson({'barKind': BarKind.none.name, ...row}),
          ),
      clear: () => db.delete(db.exercises).go(),
    ),
    _TableCodec(
      name: 'regimes',
      dump: () async =>
          (await db.select(db.regimes).get()).map((e) => e.toJson()).toList(),
      insert: (row) => db.into(db.regimes).insert(Regime.fromJson(row)),
      clear: () => db.delete(db.regimes).go(),
    ),
    _TableCodec(
      name: 'sessions',
      dump: () async =>
          (await db.select(db.sessions).get()).map((e) => e.toJson()).toList(),
      insert: (row) => db.into(db.sessions).insert(Session.fromJson(row)),
      clear: () => db.delete(db.sessions).go(),
    ),
    _TableCodec(
      name: 'session_exercises',
      dump: () async => (await db.select(db.sessionExercises).get())
          .map((e) => e.toJson())
          .toList(),
      insert: (row) =>
          db.into(db.sessionExercises).insert(SessionExercise.fromJson(row)),
      clear: () => db.delete(db.sessionExercises).go(),
    ),
    _TableCodec(
      name: 'cycles',
      dump: () async =>
          (await db.select(db.cycles).get()).map((e) => e.toJson()).toList(),
      insert: (row) => db.into(db.cycles).insert(Cycle.fromJson(row)),
      clear: () => db.delete(db.cycles).go(),
    ),
    _TableCodec(
      name: 'workouts',
      dump: () async =>
          (await db.select(db.workouts).get()).map((e) => e.toJson()).toList(),
      insert: (row) => db.into(db.workouts).insert(Workout.fromJson(row)),
      clear: () => db.delete(db.workouts).go(),
    ),
    _TableCodec(
      name: 'workout_exercises',
      dump: () async => (await db.select(db.workoutExercises).get())
          .map((e) => e.toJson())
          .toList(),
      insert: (row) =>
          db.into(db.workoutExercises).insert(WorkoutExercise.fromJson(row)),
      clear: () => db.delete(db.workoutExercises).go(),
    ),
    _TableCodec(
      name: 'set_logs',
      dump: () async =>
          (await db.select(db.setLogs).get()).map((e) => e.toJson()).toList(),
      insert: (row) => db.into(db.setLogs).insert(SetLog.fromJson(row)),
      clear: () => db.delete(db.setLogs).go(),
    ),
    _TableCodec(
      name: 'bodyweight_logs',
      dump: () async => (await db.select(db.bodyweightLogs).get())
          .map((e) => e.toJson())
          .toList(),
      insert: (row) =>
          db.into(db.bodyweightLogs).insert(BodyweightLog.fromJson(row)),
      clear: () => db.delete(db.bodyweightLogs).go(),
    ),
  ];

  Future<Map<String, dynamic>> buildPayload() async {
    final data = <String, dynamic>{};
    final counts = <String, int>{};

    for (final codec in _codecs) {
      final rows = await codec.dump();
      data[codec.name] = rows;
      counts[codec.name] = rows.length;
    }

    return {
      'format': backupFormatVersion,
      'schemaVersion': db.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'counts': counts,
      'data': data,
    };
  }

  /// Writes a timestamped JSON file to temp storage, ready for the share sheet.
  Future<File> exportToFile() async {
    final payload = await buildPayload();
    final dir = await getTemporaryDirectory();
    final name =
        'deltoid-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
    final file = File('${dir.path}/$name');
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file;
  }

  /// Keeps the last [keep] automatic exports in app storage, so a phone that
  /// dies between manual backups still has something recent to lose least from.
  Future<void> autoExport({int keep = 4}) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/backups');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final payload = await buildPayload();
    final name =
        'deltoid-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.json';
    await File('${dir.path}/$name').writeAsString(jsonEncode(payload));

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final stale in files.skip(keep)) {
      stale.deleteSync();
    }
  }

  /// When the most recent automatic export ran, or null if none has.
  ///
  /// A backup nobody can see is a backup nobody trusts: Settings offers
  /// "restore" without ever saying whether there is anything recent behind it.
  Future<DateTime?> lastAutoExportAt() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/backups');
    if (!dir.existsSync()) return null;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    if (files.isEmpty) return null;

    return files
        .map((f) => f.statSync().modified)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Reads a backup's header without touching the database, so the restore
  /// prompt can say exactly what is about to be written.
  BackupSummary inspect(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('That file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic> || decoded['data'] is! Map) {
      throw const FormatException('That file is not a Deltoid backup.');
    }

    final format = decoded['format'];
    if (format is! int) {
      throw const FormatException('That file is not a Deltoid backup.');
    }
    if (format > backupFormatVersion) {
      throw FormatException(
        'This backup was written by a newer version of Deltoid '
        '(format $format). Update the app before restoring it.',
      );
    }

    final counts = decoded['counts'];
    return BackupSummary(
      counts: {
        if (counts is Map)
          for (final entry in counts.entries)
            entry.key.toString(): (entry.value as num).toInt(),
      },
      exportedAt: DateTime.tryParse(decoded['exportedAt']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }

  /// Replaces everything with the file's contents.
  ///
  /// Replace rather than merge: restoring onto a new phone should reproduce the
  /// old one exactly. Merging two histories by row id would silently invent
  /// workouts that never happened.
  ///
  /// The whole restore runs in one transaction, so a malformed file leaves the
  /// existing database untouched instead of half-erased.
  Future<ImportResult> restore(String json) async {
    final summary = inspect(json);
    final payload = jsonDecode(json) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(payload['data'] as Map);

    var written = 0;

    await db.transaction(() async {
      // Children first so foreign keys hold at every intermediate point.
      for (final codec in _codecs.reversed) {
        await codec.clear();
      }
      for (final codec in _codecs) {
        final rows = data[codec.name];
        if (rows is! List) continue;
        for (final row in rows) {
          await codec.insert(Map<String, dynamic>.from(row as Map));
          written++;
        }
      }
    });

    return ImportResult(summary: summary, rowsWritten: written);
  }
}
