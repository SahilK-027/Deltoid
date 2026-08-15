import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/enums.dart';
import '../db/database.dart';
import '../repositories/repairs.dart';
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
    this.cursor = _idOf,
    this.keep,
  });

  final String name;

  /// One window of rows, oldest id first, starting after the id `after`.
  ///
  /// A page rather than the whole table, because the export writes as it reads:
  /// `set_logs` alone is 168k rows at fifty years, and turning all of them into
  /// maps before a byte reaches the disk is most of what an export used to cost.
  /// Ordered by id so the windows tile exactly — ids are UUID v7, so this is
  /// also creation order.
  ///
  /// **Keyset, not offset.** See [BackupService._pageOf].
  final Future<List<Map<String, dynamic>>> Function(int limit, String? after)
      page;

  /// How many rows there are, for the header the file carries and for progress.
  final Future<int> Function() count;

  /// The table itself, so a restore can insert a whole file in batches rather
  /// than a row at a time. 120k round trips through the platform channel took
  /// minutes on a phone with the screen frozen, which reads as a crash and got
  /// backups abandoned halfway.
  final TableInfo<Table, dynamic> table;

  /// The value a keyset page resumes after. Every syncable table takes its `id`
  /// from `SyncColumns`, so [_idOf] serves all of them; `app_settings` is keyed
  /// by its `key` instead and says so.
  final String Function(Map<String, dynamic> row) cursor;

  /// Which rows of a *file* this codec will write, or null for all of them.
  ///
  /// The pager already refuses to export anything else, so this only ever bites
  /// on a file that was not written by this build — a hand edit, or a merge.
  /// Restoring `device_id` out of one would give two installs the same identity.
  final bool Function(Map<String, dynamic> row)? keep;

  /// JSON row → something `Batch.insertAll` can write.
  final T Function(Map<String, dynamic> row) parse;

  final Future<void> Function() clear;
}

String _idOf(Map<String, dynamic> row) => row['id']! as String;

/// What a test sees of one codec: enough to ask a table's columns what the
/// parser does without them. See [BackupService.codecsForTesting].
typedef BackupCodecView = ({
  String name,
  TableInfo<Table, dynamic> table,
  Insertable<dynamic> Function(Map<String, dynamic> row) parse,
});

/// The `app_settings` keys a backup carries, and the only ones it restores.
///
/// A whitelist rather than the table, because the table mixes two unlike
/// things. `units` is a preference of the *user* — storage is kilograms
/// whatever it says, so a pounds user restoring onto a new phone found their
/// whole history redrawn in kilos with nothing said. `device_id` is a property
/// of the *install*, minted at open (`database.dart`) and never to be copied:
/// two phones sharing one would make `deviceId` name a history rather than a
/// writer, which is what [SYNC.md](SYNC.md) leans on to resolve a conflict.
/// `last_pull_at` and `user_id` are this install's bookkeeping with the server,
/// and `theme_mode` is deliberately out too — which theme suits a phone is a
/// property of the phone.
const backedUpSettingKeys = {'units'};

/// The zone offset a workout written before `tz_offset_minutes` existed implies.
///
/// The column arrived alongside the CHECK that ties `day_key` to `started_at`,
/// so a row without one cannot be inserted at all — and since nothing reads the
/// offset for its own sake, *any* value that reconciles the two columns the file
/// already carries is a correct one.
///
/// This phone's offset at that instant is the honest first guess, and for the
/// case that actually happens — a file written on this phone, in this zone —
/// it is not a guess at all but the very offset that produced the day key.
/// Restored after a move across zones it will not reconcile, and refusing the
/// whole file over a column the file predates would be the wrong answer, so it
/// is nudged by the fewest whole minutes that put the instant back on the day
/// the file names.
///
/// A row the two columns of which no real offset can reconcile lands outside
/// the ±(12, 14) hours the CHECK allows and the restore refuses the file. That
/// is the right answer too: such a row was already claiming two days.
int impliedTzOffset(int startedAt, int dayKey) {
  const minute = Duration.millisecondsPerMinute;
  const day = Duration.millisecondsPerDay;

  final device =
      DateTime.fromMillisecondsSinceEpoch(startedAt).timeZoneOffset.inMinutes;
  // Wall clock as an instant: the day key read as if it were UTC, which is the
  // same arithmetic the CHECK does.
  final dayStart =
      DateTime.utc(dayKey ~/ 10000, (dayKey ~/ 100) % 100, dayKey % 100)
          .millisecondsSinceEpoch;
  final local = startedAt + device * minute;

  if (local >= dayStart && local < dayStart + day) return device;
  if (local < dayStart) return device + ((dayStart - local) / minute).ceil();
  return device - ((local - dayStart - day) / minute).floor() - 1;
}

/// Whole-database export and restore.
///
/// Deliberately separate from cloud sync: sync propagates whatever state the
/// app is in, bugs included. A file you hold is the only backup that survives
/// the app corrupting its own data, and it is what makes moving to a new phone
/// a copy rather than a migration.
class BackupService {
  BackupService(this.db, {this.pageSize = _defaultPageSize, this.betweenPages});

  final AppDatabase db;

  /// Rows read per pass. Big enough that the query overhead disappears, small
  /// enough that a chunk of encoded JSON is a megabyte rather than a hundred.
  ///
  /// Injectable only so a test can put a page boundary between two rows instead
  /// of between two thousand.
  final int pageSize;

  /// Run after every page the export reads, before the next one is asked for.
  ///
  /// **A test seam, and the only way to stand in the gap this class is built
  /// around.** The export deliberately yields between pages — that is what
  /// keeps the app usable while it runs — so the interesting states are the
  /// ones where a write lands in that gap. Null in every production path.
  final Future<void> Function()? betweenPages;

  /// Parents before children, so a restore never inserts a row whose foreign
  /// key has not been written yet.
  late final List<_TableCodec> _codecs = [
    // Points at nothing and nothing points at it, so it may sit anywhere; first
    // because it is the smallest and a restore that fails on it should fail
    // before it has written a decade of sets.
    _TableCodec(
      name: 'app_settings',
      page: _pageOfSettings,
      count: _countOfSettings,
      cursor: (row) => row['key']! as String,
      table: db.appSettings,
      keep: (row) => backedUpSettingKeys.contains(row['key']),
      parse: AppSetting.fromJson,
      // Only the keys this file carries. Clearing the table would take
      // `device_id` with it, and the restore runs long after `beforeOpen` has
      // minted one — so the phone would finish the restore with no identity at
      // all until its next launch.
      clear: () => (db.delete(db.appSettings)
            ..where((t) => t.key.isIn(backedUpSettingKeys)))
          .go(),
    ),
    _TableCodec(
      name: 'exercises',
      page: (limit, after) => _pageOf(db.exercises, limit, after),
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
      page: (limit, after) => _pageOf(db.regimes, limit, after),
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
      page: (limit, after) => _pageOf(db.sessions, limit, after),
      count: () => _countOf(db.sessions),
      table: db.sessions,
      parse: Session.fromJson,
      clear: () => db.delete(db.sessions).go(),
    ),
    _TableCodec(
      name: 'session_exercises',
      page: (limit, after) => _pageOf(db.sessionExercises, limit, after),
      count: () => _countOf(db.sessionExercises),
      table: db.sessionExercises,
      parse: SessionExercise.fromJson,
      clear: () => db.delete(db.sessionExercises).go(),
    ),
    _TableCodec(
      name: 'cycles',
      page: (limit, after) => _pageOf(db.cycles, limit, after),
      count: () => _countOf(db.cycles),
      table: db.cycles,
      parse: Cycle.fromJson,
      clear: () => db.delete(db.cycles).go(),
    ),
    _TableCodec(
      name: 'workouts',
      page: (limit, after) => _pageOf(db.workouts, limit, after),
      count: () => _countOf(db.workouts),
      table: db.workouts,
      // A file written before the zone offset existed has no key for it, and
      // the row cannot land without one — see [impliedTzOffset].
      parse: (row) => Workout.fromJson({
        'tzOffsetMinutes':
            impliedTzOffset(row['startedAt'] as int, row['dayKey'] as int),
        ...row,
      }),
      clear: () => db.delete(db.workouts).go(),
    ),
    _TableCodec(
      name: 'workout_exercises',
      page: (limit, after) => _pageOf(db.workoutExercises, limit, after),
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
      page: (limit, after) => _pageOf(db.setLogs, limit, after),
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
      page: (limit, after) => _pageOf(db.bodyweightLogs, limit, after),
      count: () => _countOf(db.bodyweightLogs),
      table: db.bodyweightLogs,
      parse: BodyweightLog.fromJson,
      clear: () => db.delete(db.bodyweightLogs).go(),
    ),
  ];

  /// Each codec's table and its JSON → row parser, for the one test that has to
  /// see all of them at once.
  ///
  /// [RULES.md § 3](RULES.md#3-schema-and-migrations) step 3 — *give a new
  /// column a default here* — is prose, and prose is remembered rather than
  /// enforced. The check that makes it mechanical has to walk `table.$columns`
  /// and ask each parser what it does with the column missing, which needs both
  /// halves of a codec and nothing else in it.
  @visibleForTesting
  List<BackupCodecView> get codecsForTesting => [
        for (final c in _codecs)
          (name: c.name, table: c.table, parse: c.parse),
      ];

  /// One page of [table] as JSON, ordered by id, resuming after [after].
  ///
  /// **Keyset, and for the reason [CLAUDE.md](CLAUDE.md) rule 6 gives.** Offset
  /// paging is only correct over a table nothing is writing, and this one is
  /// read across minutes while the app stays usable — that is the whole point
  /// of the flush between pages. Under `..limit(n, offset: k)` any row that
  /// appears or disappears *behind* the cursor renumbers everything after it:
  ///
  /// - a row inserted behind the cursor shifts the rest one place forward, and
  ///   the row on the boundary is read a **second** time. A restore refuses the
  ///   duplicate on the primary key, so the file is simply unusable.
  /// - a row hard-deleted behind the cursor shifts the rest one place back, and
  ///   the row on the boundary is **stepped over**. It is absent from the file
  ///   with nothing said, and that is found out on the new phone, after the old
  ///   one has been wiped.
  ///
  /// Neither was reachable today, by accident rather than by design: ids are
  /// UUID v7, so a locally created row always sorts *after* every existing one,
  /// and nothing outside the restore's own `clear()` closures hard-deletes.
  /// Both of those are properties of other files, neither is written down as
  /// load-bearing, and **the first stops being true the day sync lands** — a row
  /// merged from the other phone was created there, earlier, and carries that
  /// earlier time in its leading bits. A cursor cannot be renumbered, so this
  /// stops depending on either.
  ///
  /// **Not wrapped in a transaction, deliberately.** That is the other way to
  /// get a stable read, and here it is the wrong one: drift serialises on one
  /// connection, so a transaction spanning a minutes-long export blocks every
  /// write the app makes for its whole duration — exactly the freeze the paging
  /// exists to avoid, and worse, because it would freeze mid-session. Keyset
  /// gives the guarantee that matters, which is that no row present for the
  /// whole export is missed. Rows written *during* one may or may not be in the
  /// file; a backup is a moment, and that moment is when it started.
  Future<List<Map<String, dynamic>>>
      _pageOf<T extends HasResultSet, D extends DataClass>(
    ResultSetImplementation<T, D> table,
    int limit,
    String? after,
  ) async {
    final id = table.columnsByName['id']! as GeneratedColumn<String>;
    final q = db.select(table)
      ..orderBy([(_) => OrderingTerm(expression: id)])
      ..limit(limit);
    if (after != null) q.where((_) => id.isBiggerThanValue(after));
    return (await q.get()).map((row) => row.toJson()).toList();
  }

  /// One page of the settings a backup carries, ordered by key.
  ///
  /// Its own pager because `app_settings` has no `id` — the key is the primary
  /// key — and because the whitelist belongs in the query rather than after it:
  /// a key this build has never heard of must not reach the file at all.
  Future<List<Map<String, dynamic>>> _pageOfSettings(
    int limit,
    String? after,
  ) async {
    final q = db.select(db.appSettings)
      ..where((t) => t.key.isIn(backedUpSettingKeys))
      ..orderBy([(t) => OrderingTerm(expression: t.key)])
      ..limit(limit);
    if (after != null) q.where((t) => t.key.isBiggerThanValue(after));
    return (await q.get()).map((row) => row.toJson()).toList();
  }

  /// How many of them there are — the same whitelist, so the header the file
  /// carries and the count a restore checks it against describe one set of rows.
  Future<int> _countOfSettings() async {
    final rows = await (db.select(db.appSettings)
          ..where((t) => t.key.isIn(backedUpSettingKeys)))
        .get();
    return rows.length;
  }

  /// How many rows a table holds, asked of SQLite rather than of Dart.
  Future<int> _countOf(TableInfo<Table, dynamic> table) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS c FROM ${table.actualTableName}',
      readsFrom: {table},
    ).getSingle();
    return row.read<int>('c');
  }

  static const _defaultPageSize = 2000;

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
      String? after;
      while (true) {
        final page = await codec.page(pageSize, after);
        rows.addAll(page);
        if (page.length < pageSize) break;
        after = codec.cursor(page.last);
        if (betweenPages != null) await betweenPages!();
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
        String? after;
        while (true) {
          final page = await codec.page(pageSize, after);
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
          if (page.length < pageSize) break;
          after = codec.cursor(page.last);
          if (betweenPages != null) await betweenPages!();
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
        var rows = data[codec.name];
        if (rows is! List || rows.isEmpty) continue;
        // A file this build did not write may carry rows this codec refuses —
        // see [_TableCodec.keep]. Dropped here rather than at parse, so the
        // count check below sees what actually landed.
        final keep = codec.keep;
        if (keep != null) {
          rows = rows
              .where((row) => row is Map && keep(Map<String, dynamic>.from(row)))
              .toList();
          if (rows.isEmpty) continue;
        }

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

      // Every row the header promised is on disk, or none of them are.
      //
      // The `counts` header was written from `codec.count()` **before** a
      // single row was streamed (see [writeBackup]), and until now it was read
      // only to size a progress bar — the comment in [summarise] says so
      // outright. So a file whose body is short restored silently, *after*
      // these tables had already been cleared, and the screen said it worked.
      // Three ways to be holding one: an export that skipped a row, a hand
      // edit, and — once the pull applier exists — a merge.
      //
      // **`landed < declared`, not `!=`.** The header is counted before the
      // pages are read, so a set logged while the export was running makes the
      // body honestly longer than the header. That file is complete and must
      // not be refused. INVARIANTS.md § 6.
      for (final codec in _codecs) {
        final declared = summary.counts[codec.name];
        if (declared == null) continue;
        final landed = await codec.count();
        if (landed < declared) {
          throw FormatException(
            'This backup is incomplete. It says it holds $declared '
            '${_label(codec.name)} and only $landed arrived, so nothing has '
            'been restored.',
          );
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

    // The same list a launch runs, and deliberately the same list rather than a
    // second one written here — INVARIANTS.md § 22.
    //
    // **After the commit, not inside it.** The transaction above is the
    // all-or-nothing guarantee entry 4 rests on: what it holds is that the
    // *file* landed whole. A repair is a judgement about the rows once they are
    // there, and folding it in would mean a healer failing took the user's
    // history back down with it — the file would be correctly restored and the
    // app would say nothing had been. `healOrphanedSnapshots` opens its own
    // transaction anyway, which is not a thing to nest for no reason.
    //
    // Nothing was reading the restored rows before this point: `restore` is
    // awaited by the screen that called it, and the streams behind Today rebuild
    // on the table updates the commit emits.
    await repairDatabase(db);

    return ImportResult(summary: summary, rowsWritten: written);
  }
}
