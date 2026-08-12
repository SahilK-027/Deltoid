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
/// Top-level, and deliberately not a method: a closure written inside
/// [BackupService] captures the whole enclosing context, `this` included, and
/// `this` holds an `AppDatabase` wrapping an FFI handle that cannot cross an
/// isolate boundary — `Isolate.run` fails at the send, not at the JSON.
///
/// Only the *read* side needs this now. Encoding used to come through here too,
/// which meant the entire history crossed the port twice — out as rows and back
/// as a 70 MB string — to save a freeze that [BackupService.writeBackup] avoids
/// by never building either one.
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
    required this.page,
    required this.count,
    required this.table,
    required this.parse,
    required this.clear,
  });

  final String name;

  /// One window of rows, oldest id first.
  ///
  /// A page rather than the whole table, because the export writes as it reads:
  /// `set_logs` alone is 168k rows at fifty years, and turning all of them into
  /// maps before a byte reaches the disk is most of what an export used to cost.
  /// Ordered by id so the windows tile exactly — ids are UUID v7, so this is
  /// also creation order.
  final Future<List<Map<String, dynamic>>> Function(int limit, int offset) page;

  /// How many rows there are, for the header the file carries and for progress.
  final Future<int> Function() count;

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
      page: (limit, offset) async => (await (db.select(db.exercises)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.exercises),
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
      page: (limit, offset) async => (await (db.select(db.regimes)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.regimes),
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
      page: (limit, offset) async => (await (db.select(db.sessions)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.sessions),
      table: db.sessions,
      parse: Session.fromJson,
      clear: () => db.delete(db.sessions).go(),
    ),
    _TableCodec(
      name: 'session_exercises',
      page: (limit, offset) async => (await (db.select(db.sessionExercises)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.sessionExercises),
      table: db.sessionExercises,
      parse: SessionExercise.fromJson,
      clear: () => db.delete(db.sessionExercises).go(),
    ),
    _TableCodec(
      name: 'cycles',
      page: (limit, offset) async => (await (db.select(db.cycles)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.cycles),
      table: db.cycles,
      parse: Cycle.fromJson,
      clear: () => db.delete(db.cycles).go(),
    ),
    _TableCodec(
      name: 'workouts',
      page: (limit, offset) async => (await (db.select(db.workouts)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.workouts),
      table: db.workouts,
      parse: Workout.fromJson,
      clear: () => db.delete(db.workouts).go(),
    ),
    _TableCodec(
      name: 'workout_exercises',
      page: (limit, offset) async => (await (db.select(db.workoutExercises)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.workoutExercises),
      table: db.workoutExercises,
      // A file written before the muscle snapshot existed has no key for it,
      // and null is the honest value: the row predates the column, so readers
      // fall back to the catalog rather than being told it was `other`.
      parse: (row) => WorkoutExercise.fromJson({'muscle': null, ...row}),
      clear: () => db.delete(db.workoutExercises).go(),
    ),
    _TableCodec(
      name: 'set_logs',
      page: (limit, offset) async => (await (db.select(db.setLogs)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.setLogs),
      table: db.setLogs,
      // Partials arrived at v8. Nullable, so a file written before it simply
      // has no key here and every restored set reads as all-full — which is
      // what those sets meant when they were logged.
      parse: (row) => SetLog.fromJson({'partialReps': null, ...row}),
      clear: () => db.delete(db.setLogs).go(),
    ),
    _TableCodec(
      name: 'bodyweight_logs',
      page: (limit, offset) async => (await (db.select(db.bodyweightLogs)
                ..orderBy([(t) => OrderingTerm(expression: t.id)])
                ..limit(limit, offset: offset))
              .get())
          .map((e) => e.toJson())
          .toList(),
      count: () => _countOf(db.bodyweightLogs),
      table: db.bodyweightLogs,
      parse: BodyweightLog.fromJson,
      clear: () => db.delete(db.bodyweightLogs).go(),
    ),
  ];

  /// How many rows a table holds, asked of SQLite rather than of Dart.
  Future<int> _countOf(TableInfo<Table, dynamic> table) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS c FROM ${table.actualTableName}',
      readsFrom: {table},
    ).getSingle();
    return row.read<int>('c');
  }

  /// Rows read per pass. Big enough that the query overhead disappears, small
  /// enough that a chunk of encoded JSON is a megabyte rather than a hundred.
  static const _pageSize = 2000;

  /// The whole database as one map. Kept for the tests and the seed tool, which
  /// want a payload in hand; **the app writes files with [writeBackup]**, which
  /// never holds one.
  Future<Map<String, dynamic>> buildPayload({BackupProgress? onProgress}) async {
    final data = <String, dynamic>{};
    final counts = <String, int>{};

    var read = 0;
    for (var i = 0; i < _codecs.length; i++) {
      final codec = _codecs[i];
      final rows = <Map<String, dynamic>>[];
      for (var offset = 0;; offset += _pageSize) {
        final page = await codec.page(_pageSize, offset);
        rows.addAll(page);
        if (page.length < _pageSize) break;
      }
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

  /// Writes the whole database to [file] as JSON, a page of rows at a time.
  ///
  /// **Nothing here ever holds the backup.** The export used to build every row
  /// of every table as a map, send that structure across an isolate port to be
  /// encoded, take a 70 MB string back across the port, and hand it to
  /// `writeAsString`, which encoded it to UTF-8 a third time — several hundred
  /// megabytes of peak heap to produce a file the disk was going to receive in
  /// 64 kB pieces anyway. It ran unasked after every session, which made it the
  /// most expensive thing the app did and the one nobody had asked for.
  ///
  /// So the structure is written by hand and only the *rows* go through
  /// `jsonEncode`. Awaiting the sink between pages hands the frame back, so a
  /// long export is slow rather than frozen — and peak memory is one page.
  ///
  /// The shape is byte-identical to what [buildPayload] produces, which is what
  /// the round-trip tests hold it to.
  Future<File> writeBackup(File file, {BackupProgress? onProgress}) async {
    final counts = <String, int>{};
    for (final codec in _codecs) {
      counts[codec.name] = await codec.count();
    }
    final total = counts.values.fold(0, (a, b) => a + b);

    final sink = file.openWrite();
    var written = 0;
    try {
      sink
        ..write('{"format":$backupFormatVersion')
        ..write(',"schemaVersion":${db.schemaVersion}')
        ..write(',"exportedAt":'
            '${jsonEncode(DateTime.now().toUtc().toIso8601String())}')
        ..write(',"counts":${jsonEncode(counts)}')
        ..write(',"data":{');

      for (var i = 0; i < _codecs.length; i++) {
        final codec = _codecs[i];
        if (i > 0) sink.write(',');
        sink.write('${jsonEncode(codec.name)}:[');

        var first = true;
        for (var offset = 0;; offset += _pageSize) {
          final page = await codec.page(_pageSize, offset);
          if (page.isNotEmpty) {
            final buffer = StringBuffer();
            for (final row in page) {
              if (!first) buffer.write(',');
              first = false;
              buffer.write(jsonEncode(row));
            }
            sink.write(buffer.toString());
            // Back-pressure, and the only reason this does not freeze the UI:
            // the sink is drained before the next page is read.
            await sink.flush();

            written += page.length;
            onProgress?.call((
              phase: BackupPhase.writing,
              detail: _label(codec.name),
              rows: written,
              fraction: total == 0 ? null : (written / total).clamp(0.0, 1.0),
            ));
          }
          if (page.length < _pageSize) break;
        }
        sink.write(']');
      }
      sink.write('}}');
    } finally {
      await sink.close();
    }
    return file;
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
  /// Streamed row by row through [writeBackup]: the file is never a string, and
  /// the indent is gone with it — nothing reads this by eye, and pretty
  /// printing a decade of sets doubled both the time and the file.
  Future<File> exportToFile({BackupProgress? onProgress}) async {
    final dir = await backupDirectory();
    final name =
        'deltoid-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.json';
    return writeBackup(File('${dir.path}/$name'), onProgress: onProgress);
  }

  /// Keeps the last [keep] automatic exports in app storage, so a phone that
  /// dies between manual backups still has something recent to lose least from.
  Future<void> autoExport({int keep = 4}) async {
    final dir = Directory('${(await backupDirectory()).path}/auto');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final name =
        'deltoid-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.json';
    // Streamed, and that matters most here: this one runs unasked, on the
    // summary screen, right after a session is saved — the last place to build
    // the whole history in memory.
    await writeBackup(File('${dir.path}/$name'));

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

  /// Parses a backup straight off a byte stream, never holding the file as one
  /// string.
  ///
  /// Reading a backup with `utf8.decode(await file.readAsBytes())` costs the
  /// file twice over and the second copy is the expensive one: Dart strings are
  /// UTF-16, so a 67 MB export asks Android for a single 134 MB allocation on
  /// top of the bytes it was decoded from. It threw `OutOfMemoryError` and took
  /// the process down before the restore had written a row — on the one screen
  /// that exists to get a history back. The chunked decoders below walk the
  /// file instead, so the peak is the parsed rows and nothing else.
  Future<Map<String, dynamic>> decodeStream(Stream<List<int>> bytes) async {
    final Object? decoded;
    try {
      decoded = await bytes.transform(utf8.decoder).transform(json.decoder).first;
    } on FormatException {
      throw const FormatException('That file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('That file is not a Deltoid backup.');
    }
    return decoded;
  }

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
      // The counts are a header, not the data — they say what the restore is
      // about to write so the prompt can quote a number. A cast straight to
      // `num` threw a raw `TypeError` on a file whose counts were anything
      // else, which is not the `FormatException` this method's callers handle
      // by name. A count that cannot be read is a count this file does not
      // have; the rows themselves are still checked properly on the way in.
      counts: {
        if (counts is Map)
          for (final entry in counts.entries)
            if (entry.value is num)
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
    String? json, {
    BackupProgress? onProgress,
    /// An already-parsed file, from [decode] or [decodeStream]. Passing it is
    /// the difference between reading a fifty-year backup once and reading it
    /// twice — and it is the only form that never needs the file as a string,
    /// so [json] may be null when it is given.
    Map<String, dynamic>? decoded,
  }) async {
    final payload = decoded ?? await _decodeOffIsolate(json!);
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
      // Checked at commit rather than at every row, for this transaction only.
      //
      // The codecs are ordered so no table arrives before the tables it points
      // at, but `set_logs.parent_set_id` points *into its own table*: a
      // drop-set leg sitting ahead of its head in the file fails against an id
      // that is two rows further down. Deferring moves the question to the
      // end, where the answer is known. A file that really is inconsistent
      // still fails, and still takes the whole restore back with it.
      //
      // Not covered by drift's own batch deferral — that is a different code
      // path from the one `db.batch` takes here. `schema_constraints_test`
      // fails without this line.
      await db.customStatement('PRAGMA defer_foreign_keys = ON');

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

      // A pre-v5 file carries no identity slots, so every regime came in on 0 —
      // one colour for the whole shelf, and the uniqueness the mark depends on
      // gone. Deal them out, exactly as the schema migration does. A file that
      // does carry slots is left alone: they are the colours the user has been
      // looking at.
      //
      // **Inside the transaction**, because it is part of restoring rather than
      // a tidy-up after it. It ran after the commit, which left a window — a
      // crash, a kill, a battery — where the restore had landed and every
      // regime in it was wearing the same hue, with `nextIdentitySlot` then
      // handing slot 1 to the next new regime while five sat on 0. That is the
      // exact collision the column was added to prevent, reached through the
      // one screen that exists to put a history back.
      final regimeRows = data['regimes'];
      final needsSlots = regimeRows is List &&
          regimeRows.any((row) =>
              row is Map && !row.containsKey('identityIndex'));
      if (needsSlots) await backfillIdentityIndexes(db);
    });

    // A restore is the one moment the database goes from empty to a decade in
    // a single act, so the planner statistics gathered at open describe a
    // database that no longer exists — and the screens the user looks at next
    // are planned against them. `beforeOpen` would fix it on the following
    // launch; this fixes it now.
    await db.customStatement('ANALYZE');

    return ImportResult(summary: summary, rowsWritten: written);
  }
}
