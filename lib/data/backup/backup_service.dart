import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
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
class _TableCodec<T extends Insertable<dynamic>> {
  const _TableCodec({
    required this.name,
    required this.dump,
    required this.table,
    required this.parse,
    required this.clear,
  });

  final String name;
  final Future<List<Map<String, dynamic>>> Function() dump;

  /// The table itself, so a restore can insert a whole file in batches rather
  /// than a row at a time. 120k round trips through the platform channel took
  /// minutes on a phone with the screen frozen, which reads as a crash and got
  /// backups abandoned halfway.
  final TableInfo<Table, dynamic> table;

  /// JSON row → something `Batch.insertAll` can write.
  final T Function(Map<String, dynamic> row) parse;

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
      table: db.exercises,
      parse: (row) => Exercise.fromJson({'barKind': BarKind.none.name, ...row}),
      clear: () => db.delete(db.exercises).go(),
    ),
    _TableCodec(
      name: 'regimes',
      dump: () async =>
          (await db.select(db.regimes).get()).map((e) => e.toJson()).toList(),
      table: db.regimes,
      parse: Regime.fromJson,
      clear: () => db.delete(db.regimes).go(),
    ),
    _TableCodec(
      name: 'sessions',
      dump: () async =>
          (await db.select(db.sessions).get()).map((e) => e.toJson()).toList(),
      table: db.sessions,
      parse: Session.fromJson,
      clear: () => db.delete(db.sessions).go(),
    ),
    _TableCodec(
      name: 'session_exercises',
      dump: () async => (await db.select(db.sessionExercises).get())
          .map((e) => e.toJson())
          .toList(),
      table: db.sessionExercises,
      parse: SessionExercise.fromJson,
      clear: () => db.delete(db.sessionExercises).go(),
    ),
    _TableCodec(
      name: 'cycles',
      dump: () async =>
          (await db.select(db.cycles).get()).map((e) => e.toJson()).toList(),
      table: db.cycles,
      parse: Cycle.fromJson,
      clear: () => db.delete(db.cycles).go(),
    ),
    _TableCodec(
      name: 'workouts',
      dump: () async =>
          (await db.select(db.workouts).get()).map((e) => e.toJson()).toList(),
      table: db.workouts,
      parse: Workout.fromJson,
      clear: () => db.delete(db.workouts).go(),
    ),
    _TableCodec(
      name: 'workout_exercises',
      dump: () async => (await db.select(db.workoutExercises).get())
          .map((e) => e.toJson())
          .toList(),
      table: db.workoutExercises,
      parse: WorkoutExercise.fromJson,
      clear: () => db.delete(db.workoutExercises).go(),
    ),
    _TableCodec(
      name: 'set_logs',
      dump: () async =>
          (await db.select(db.setLogs).get()).map((e) => e.toJson()).toList(),
      table: db.setLogs,
      parse: SetLog.fromJson,
      clear: () => db.delete(db.setLogs).go(),
    ),
    _TableCodec(
      name: 'bodyweight_logs',
      dump: () async => (await db.select(db.bodyweightLogs).get())
          .map((e) => e.toJson())
          .toList(),
      table: db.bodyweightLogs,
      parse: BodyweightLog.fromJson,
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

  /// Where backups live: a `Deltoid` folder the user can actually open.
  ///
  /// Temp storage was fine for handing a file to the share sheet and useless
  /// for everything else — the file was gone by the next boot, and a backup you
  /// cannot find in a file manager is one you have to take on faith. External
  /// app storage is visible over USB and to any file browser, and needs no
  /// permission on any Android version this app supports.
  Future<Directory> backupDirectory() async {
    final root = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/Deltoid');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Writes a timestamped JSON file into [backupDirectory], ready for the share
  /// sheet — and still there afterwards, whether it was shared or not.
  Future<File> exportToFile() async {
    final payload = await buildPayload();
    final dir = await backupDirectory();
    final name =
        'deltoid-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.json';
    final file = File('${dir.path}/$name');
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file;
  }

  /// Keeps the last [keep] automatic exports in app storage, so a phone that
  /// dies between manual backups still has something recent to lose least from.
  Future<void> autoExport({int keep = 4}) async {
    final dir = Directory('${(await backupDirectory()).path}/auto');
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
    final dir = Directory('${(await backupDirectory()).path}/auto');
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
  /// Replaces the database with a backup's contents.
  ///
  /// [onProgress] is called with the table being written and how many rows have
  /// landed so far. A restore of a long history is thousands of rows and the
  /// screen has to say so — silence for a minute is indistinguishable from a
  /// hang, and the natural response to a hung restore is to kill the app
  /// halfway through it.
  Future<ImportResult> restore(
    String json, {
    void Function(String table, int rowsWritten)? onProgress,
  }) async {
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
        if (rows is! List || rows.isEmpty) continue;

        // In chunks, not one statement per row: a year of training is ~40k
        // rows and a decade is ten times that. Chunked rather than one giant
        // batch so a huge file does not hold every parsed row in memory at
        // once alongside the JSON it came from.
        const chunk = 500;
        for (var i = 0; i < rows.length; i += chunk) {
          final slice = rows.skip(i).take(chunk).map(
                (row) => codec.parse(Map<String, dynamic>.from(row as Map)),
              );
          await db.batch((b) => b.insertAll(codec.table, slice.toList()));
          written += slice.length;
          onProgress?.call(codec.name, written);
        }
      }
    });

    return ImportResult(summary: summary, rowsWritten: written);
  }
}
