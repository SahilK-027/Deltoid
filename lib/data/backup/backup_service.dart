import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/enums.dart';
import '../db/database.dart';
import '../seed/seeder.dart';

/// Bumped whenever the export shape changes in a way an older build could not
/// read. Import refuses anything newer than it understands rather than
/// half-restoring a file from the future.
const backupFormatVersion = 1;

/// Which half of a long job is running, so the screen can say something more
/// useful than "working".
enum BackupPhase { reading, encoding, writing, decoding, clearing }

/// A step of a long job: what it is doing, what on, and how far through.
///
/// [fraction] is null while a phase genuinely cannot say — a `jsonEncode` of a
/// hundred thousand rows is one opaque call. A bar that sits still is honest;
/// one that invents a percentage and then jumps is not.
typedef BackupStep = ({
  BackupPhase phase,
  String detail,
  int rows,
  double? fraction,
});

typedef BackupProgress = void Function(BackupStep step);

/// `set_logs` → `set logs`. The table names are the wire format, not English.
String _label(String table) => table.replaceAll('_', ' ');

/// JSON in another isolate.
///
/// Top-level, and deliberately not methods: a closure written inside
/// [BackupService] captures the whole enclosing context, `this` included, and
/// `this` holds an `AppDatabase` wrapping an FFI handle that cannot cross an
/// isolate boundary — `Isolate.run` fails at the send, not at the JSON.
Future<String> _encodeOffIsolate(Map<String, dynamic> payload) =>
    Isolate.run(() => jsonEncode(payload));

Future<Map<String, dynamic>> _decodeOffIsolate(String json) =>
    Isolate.run(() => jsonDecode(json) as Map<String, dynamic>);

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
      parse: (row) => Exercise.fromJson({
        'barKind': BarKind.none.name,
        'measureMode': MeasureMode.reps.name,
        ...row,
      }),
      clear: () => db.delete(db.exercises).go(),
    ),
    _TableCodec(
      name: 'regimes',
      dump: () async =>
          (await db.select(db.regimes).get()).map((e) => e.toJson()).toList(),
      table: db.regimes,
      // A file written before v5 has no identity slot in it, and
      // `Regime.fromJson` casts the missing key straight to int. Everything
      // lands on 0 here and the slots are dealt out properly once the restore
      // is written — see the backfill at the end of [restore].
      parse: (row) => Regime.fromJson({'identityIndex': 0, ...row}),
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
      // Partials arrived at v8. Nullable, so a file written before it simply
      // has no key here and every restored set reads as all-full — which is
      // what those sets meant when they were logged.
      parse: (row) => SetLog.fromJson({'partialReps': null, ...row}),
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

  Future<Map<String, dynamic>> buildPayload({BackupProgress? onProgress}) async {
    final data = <String, dynamic>{};
    final counts = <String, int>{};

    var read = 0;
    for (var i = 0; i < _codecs.length; i++) {
      final codec = _codecs[i];
      final rows = await codec.dump();
      data[codec.name] = rows;
      counts[codec.name] = rows.length;
      read += rows.length;
      onProgress?.call((
        phase: BackupPhase.reading,
        detail: _label(codec.name),
        rows: read,
        // The tables are read one at a time and nothing knows the total until
        // the last one lands, so this half of the job reports how far through
        // the tables it is rather than a row count out of nothing.
        fraction: (i + 1) / _codecs.length * 0.5,
      ));
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
  ///
  /// The encode runs in another isolate. It is one synchronous call over the
  /// whole history, and on the UI isolate it froze the app for as long as it
  /// took — no frames, no progress, no way to tell a slow export from a hung
  /// one. The indent went with it: nothing reads this by eye, and pretty
  /// printing a decade of sets doubled both the time and the file.
  Future<File> exportToFile({BackupProgress? onProgress}) async {
    final payload = await buildPayload(onProgress: onProgress);
    final rows = _totalOf(payload);

    onProgress?.call((
      phase: BackupPhase.encoding,
      detail: '$rows rows',
      rows: rows,
      fraction: null,
    ));
    final contents = await _encodeOffIsolate(payload);

    final dir = await backupDirectory();
    final name =
        'deltoid-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.json';
    final file = File('${dir.path}/$name');

    onProgress?.call((
      phase: BackupPhase.writing,
      detail: name,
      rows: rows,
      fraction: 0.95,
    ));
    await file.writeAsString(contents);
    return file;
  }

  static int _totalOf(Map<String, dynamic> payload) {
    final counts = payload['counts'];
    if (counts is! Map) return 0;
    return counts.values.fold(0, (a, b) => a + (b as num).toInt());
  }

  /// Keeps the last [keep] automatic exports in app storage, so a phone that
  /// dies between manual backups still has something recent to lose least from.
  Future<void> autoExport({int keep = 4}) async {
    final dir = Directory('${(await backupDirectory()).path}/auto');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final payload = await buildPayload();
    final name =
        'deltoid-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.json';
    // Also off-isolate: this one runs unasked, on the summary screen, right
    // after a session is saved — the last place a two-second freeze belongs.
    final contents = await _encodeOffIsolate(payload);
    await File('${dir.path}/$name').writeAsString(contents);

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
  ///
  /// Prefer [decode] + [summarise] on anything user-facing: this parses the
  /// whole file on the calling isolate, and a restore used to do it **three
  /// times** — once here for the prompt, once inside `restore`, and once more
  /// off-isolate to actually read the rows. On fifty years of training that is
  /// three full parses of a multi-megabyte string, two of them on the thread
  /// trying to draw the confirmation dialog.
  BackupSummary inspect(String json) => summarise(_decode(json));

  /// Parses a backup off the UI isolate. The result feeds both [summarise] and
  /// [restore], so the file is read exactly once.
  Future<Map<String, dynamic>> decode(String json) => _decodeOffIsolate(json);

  static Map<String, dynamic> _decode(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('That file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('That file is not a Deltoid backup.');
    }
    return decoded;
  }

  /// The header of an already-parsed backup.
  BackupSummary summarise(Map<String, dynamic> decoded) {
    if (decoded['data'] is! Map) {
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

    // The schema the file was written against, which until now was recorded
    // and never read. Older is fine and is the case the default map under each
    // restored row exists for. *Newer* is not: a column this build has never
    // heard of is dropped silently, and an enum value it cannot parse throws
    // halfway through the write — after the tables have been cleared, inside a
    // transaction, with the user's only copy in the file picker. Refusing is
    // the answer the tooling has claimed all along.
    final schema = decoded['schemaVersion'];
    if (schema is int && schema > db.schemaVersion) {
      throw FormatException(
        'This backup was written by a newer version of Deltoid '
        '(schema $schema, this build reads ${db.schemaVersion}). Update the '
        'app before restoring it.',
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
    BackupProgress? onProgress,
    /// An already-parsed file, from [decode]. Passing it is the difference
    /// between reading a fifty-year backup once and reading it twice.
    Map<String, dynamic>? decoded,
  }) async {
    final payload = decoded ?? await _decodeOffIsolate(json);
    final summary = summarise(payload);

    onProgress?.call((
      phase: BackupPhase.decoding,
      detail: '${summary.totalRows} rows',
      rows: 0,
      fraction: null,
    ));
    final data = Map<String, dynamic>.from(payload['data'] as Map);

    final total = summary.totalRows;
    var written = 0;

    await db.transaction(() async {
      onProgress?.call((
        phase: BackupPhase.clearing,
        detail: 'making room',
        rows: 0,
        fraction: 0,
      ));
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
          onProgress?.call((
            phase: BackupPhase.writing,
            detail: _label(codec.name),
            rows: written,
            fraction: total == 0 ? null : (written / total).clamp(0.0, 1.0),
          ));
        }
      }
    });

    // A pre-v5 file carries no identity slots, so every regime came in on 0 —
    // one colour for the whole shelf, and the uniqueness the mark depends on
    // gone. Deal them out, exactly as the schema migration does. A file that
    // does carry slots is left alone: they are the colours the user has been
    // looking at.
    final regimeRows = data['regimes'];
    final needsSlots = regimeRows is List &&
        regimeRows.any((row) =>
            row is Map && !row.containsKey('identityIndex'));
    if (needsSlots) await backfillIdentityIndexes(db);

    return ImportResult(summary: summary, rowsWritten: written);
  }
}
