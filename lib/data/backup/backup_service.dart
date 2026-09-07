import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/failure.dart';
import '../../core/progress.dart';
import '../db/database.dart';
import '../db/invariants.dart';
import '../db/table_spec.dart';
import '../repositories/repairs.dart';
import '../seed/seeder.dart';
import '../../domain/table_labels.dart';

/// Bumped whenever the export shape changes in a way an older build could not
/// read. Import refuses anything newer than it understands rather than
/// half-restoring a file from the future.
const backupFormatVersion = 1;


/// JSON in another isolate.
///
/// Top-level, and deliberately not a method: a closure written inside
/// [BackupService] captures the whole enclosing context, `this` included, and
/// `this` holds an `AppDatabase` wrapping an FFI handle that cannot cross an
/// isolate boundary — `Isolate.run` fails at the send, not at the JSON.
///
/// Only the *read* side needs this. Sending encoding through here as well would
/// put the entire history across the port twice — out as rows and back as a
/// 70 MB string — to save a freeze that [BackupService.writeBackup] avoids by
/// never building either one.
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

/// One table's dump/restore pair: what [TableSpec] says about the table, plus
/// the parts that are only a *file's* problem.
///
/// The name, the table and the parser with its defaults come from the shared
/// registry in `data/db/table_spec.dart`, because the pull applier needs
/// exactly those three and must not grow a second list of defaults beside this
/// one — [SYNC.md § 17](SYNC.md#17-the-architecture). Paging, counting,
/// clearing and the settings whitelist stay here: a server has no pages and
/// never clears a table.
class _TableCodec {
  const _TableCodec({
    required this.spec,
    required this.page,
    required this.count,
    required this.clear,
    this.cursor = _idOf,
    this.keep,
  });

  final TableSpec spec;

  String get name => spec.name;

  /// The table itself, so a restore can insert a whole file in batches rather
  /// than a row at a time. 120k round trips through the platform channel took
  /// minutes on a phone with the screen frozen, which reads as a crash and got
  /// backups abandoned halfway.
  TableInfo<Table, dynamic> get table => spec.table;

  /// JSON row → something `Batch.insertAll` can write. See [TableSpec.parse].
  Insertable<dynamic> Function(Map<String, dynamic> row) get parse => spec.parse;

  /// One window of rows, oldest id first, starting after the id `after`.
  ///
  /// A page rather than the whole table, because the export writes as it reads:
  /// `set_logs` alone is 168k rows at fifty years, and turning all of them into
  /// maps before a byte reaches the disk is most of what an export would cost.
  /// Ordered by id so the windows tile exactly — ids are UUID v7, so this is
  /// also creation order.
  ///
  /// Keyset paging rather than offset paging. See [BackupService._pageOf].
  final Future<List<Map<String, dynamic>>> Function(int limit, String? after)
      page;

  /// How many rows there are, for the header the file carries and for progress.
  final Future<int> Function() count;

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

  final Future<void> Function() clear;
}

String _idOf(Map<String, dynamic> row) => row['id']! as String;


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


/// Whole-database export and restore.
///
/// Deliberately separate from cloud sync: sync propagates whatever state the
/// application is in, including defects. A file held locally is the only backup
/// that survives
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
  /// A test seam, and the only means of interposing in the gap this class is
  /// designed around. The export deliberately yields between pages, which is
  /// what
  /// keeps the app usable while it runs — so the interesting states are the
  /// ones where a write lands in that gap. Null in every production path.
  final Future<void> Function()? betweenPages;

  /// Parents before children, so a restore never inserts a row whose foreign
  /// key has not been written yet — which is the order the registry is already
  /// in, and the same order a push walks.
  ///
  /// Built from `tableSpecs` rather than written out again, so a table added to
  /// the schema cannot be added to sync and forgotten by backup, or the other
  /// way round. Everything special here is special about *files*.
  late final List<_TableCodec> _codecs = [
    for (final spec in tableSpecs(db))
      if (spec.name == 'app_settings')
        _TableCodec(
          spec: spec,
          page: _pageOfSettings,
          count: _countOfSettings,
          cursor: (row) => row['key']! as String,
          keep: (row) => backedUpSettingKeys.contains(row['key']),
          // Only the keys this file carries. Clearing the table would take
          // `device_id` with it, and the restore runs long after `beforeOpen`
          // has minted one — so the phone would finish the restore with no
          // identity at all until its next launch.
          clear: () => (db.delete(db.appSettings)
                ..where((t) => t.key.isIn(backedUpSettingKeys)))
              .go(),
        )
      else
        _TableCodec(
          spec: spec,
          page: (limit, after) => _pageOf(spec.table, limit, after),
          count: () => _countOf(spec.table),
          clear: () => db.delete(spec.table).go(),
        ),
  ];



  /// One page of [table] as JSON, ordered by id, resuming after [after].
  ///
  /// Keyset paging, for the reason [CLAUDE.md](CLAUDE.md) rule 6 gives. Offset
  /// paging is only correct over a table nothing is writing, and this one is
  /// read across minutes while the app stays usable — that is the whole point
  /// of the flush between pages. Under `..limit(n, offset: k)` any row that
  /// appears or disappears *behind* the cursor renumbers everything after it:
  ///
  /// - a row inserted behind the cursor shifts the rest one place forward, and
  ///   the row on the boundary is read a second time. A restore refuses the
  ///   duplicate on the primary key, so the file is simply unusable.
  /// - a row hard-deleted behind the cursor shifts the rest one place back, and
  ///   the row on the boundary is skipped. It is absent from the file
  ///   with nothing said, and that is found out on the new phone, after the old
  ///   one has been wiped.
  ///
  /// Neither was reachable today, by accident rather than by design: ids are
  /// UUID v7, so a locally created row always sorts *after* every existing one,
  /// and nothing outside the restore's own `clear()` closures hard-deletes.
  /// Both of those are properties of other files, neither is written down as
  /// load-bearing, and the first ceases to hold once sync is present: a row
  /// merged from the other phone was created there, earlier, and carries that
  /// earlier time in its leading bits. A cursor cannot be renumbered, so this
  /// stops depending on either.
  ///
  /// Deliberately not wrapped in a transaction. That is the alternative means
  /// of obtaining
  /// get a stable read, and here it is the wrong one: drift serialises on one
  /// connection, so a transaction spanning a minutes-long export blocks every
  /// write the app makes for its whole duration — exactly the freeze the paging
  /// exists to avoid, and worse, because it would freeze mid-session. Keyset
  /// gives the guarantee that matters, which is that no row present for the
  /// whole export is missed. Rows written *during* one may or may not be in the
  /// file; a backup is a moment, and that moment is when it started.
  Future<List<Map<String, dynamic>>> _pageOf(
    TableInfo<Table, dynamic> table,
    int limit,
    String? after,
  ) async {
    final id = table.columnsByName['id']! as GeneratedColumn<String>;
    final q = db.select(table)
      ..orderBy([(_) => OrderingTerm(expression: id)])
      ..limit(limit);
    if (after != null) q.where((_) => id.isBiggerThanValue(after));
    // `row` is a `DataClass` whose type the registry knows and this loop does
    // not; `toJson` is the one thing all ten of them have, and reaching it
    // through `dynamic` is what lets one pager serve every table.
    return [
      for (final dynamic row in await q.get())
        row.toJson() as Map<String, dynamic>,
    ];
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
  /// require a payload in memory. The application writes files with
  /// [writeBackup], which
  /// never holds one.
  Future<Map<String, dynamic>> buildPayload({ProgressReport? onProgress}) async {
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
        phase: JobPhase.reading,
        detail: tableLabel(codec.name),
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
  /// Nothing here holds the backup in memory. Building every row of every table
  /// as a map, sending that structure across an isolate port to be encoded,
  /// taking a 70 MB string back across the port and handing it to
  /// `writeAsString` — which encodes it to UTF-8 a third time — is several
  /// hundred megabytes of peak heap to produce a file the disk receives in
  /// 64 kB pieces anyway.
  ///
  /// So the structure is written by hand and only the *rows* go through
  /// `jsonEncode`. Awaiting the sink between pages hands the frame back, so a
  /// long export is slow rather than frozen — and peak memory is one page.
  ///
  /// The shape is byte-identical to what [buildPayload] produces, which is what
  /// the round-trip tests hold it to.
  ///
  /// The file appears complete or not at all. Streamed directly into its final
  /// name, a crash, a kill, a full disk or an OOM halfway through leaves a
  /// truncated `.json` sitting under a legitimate backup filename —
  /// indistinguishable from a good one until the day it is needed, with the
  /// restore's own counts check the thing that eventually says so, months
  /// later. [autoExport] compounds it: it prunes by filename, so a run of
  /// half-written files evicts the last complete one.
  ///
  /// So the rows go to a sibling `.part` and the finished file arrives by
  /// rename, which is atomic within a filesystem — a reader sees the old file
  /// or the new one, never half of either. A write that does not finish takes
  /// its `.part` with it and leaves what was already there alone.
  Future<File> writeBackup(File file, {ProgressReport? onProgress}) async {
    final counts = <String, int>{};
    for (final codec in _codecs) {
      counts[codec.name] = await codec.count();
    }
    final total = counts.values.fold(0, (a, b) => a + b);

    // Beside the destination rather than in a temp directory, so the rename
    // below cannot cross a filesystem — across one it is a copy and a delete,
    // which is the very thing being avoided.
    final partial = File('${file.path}.part');
    final sink = partial.openWrite();
    var written = 0;
    var complete = false;
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
              phase: JobPhase.writing,
              detail: tableLabel(codec.name),
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
      complete = true;
    } finally {
      await sink.close();
      if (!complete && partial.existsSync()) partial.deleteSync();
    }
    return partial.rename(file.path);
  }

  /// Where backups live: a `Deltoid` folder the user can actually open.
  ///
  /// Temp storage covers handing a file to the share sheet and nothing else —
  /// it is removed on the next boot, and a backup that cannot be located in a
  /// file manager cannot be verified. External
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
  /// there is no indent — nothing reads this by eye, and pretty printing a
  /// decade of sets doubles both the time and the file.
  Future<File> exportToFile({ProgressReport? onProgress}) async {
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

    // A `.part` that [writeBackup] did not clean up after itself, which means
    // the process was killed rather than the write failing — the one case its
    // `finally` cannot cover. Swept here rather than there: this is the caller
    // that runs after every session, and a half-file from a session two weeks
    // ago is otherwise a permanent resident. Never counted against [keep], and
    // never restorable, because nothing looks for anything but `.json`.
    for (final scrap in dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.json.part'),
        )) {
      scrap.deleteSync();
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
  /// whole file on the calling isolate. Calling it as well as `restore` parses
  /// the file twice over, and on fifty years of training that is two full
  /// parses of a multi-megabyte string, one of them on the thread trying to
  /// draw the confirmation dialog.
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
  /// top of the bytes it was decoded from. That throws `OutOfMemoryError` and
  /// takes the process down before the restore has written a row — on the one
  /// screen that exists to get a history back. The chunked decoders below walk
  /// the
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

    // The schema the file was written against, recorded on write and checked
    // here. Older is fine, and is the case the default map under each restored
    // row exists for. *Newer* is not: a column this build has never
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
      // `num` throws a raw `TypeError` on a file whose counts are anything
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
    ProgressReport? onProgress,
    /// An already-parsed file, from [decode] or [decodeStream]. Passing it is
    /// the difference between reading a fifty-year backup once and reading it
    /// twice — and it is the only form that never needs the file as a string,
    /// so [json] may be null when it is given.
    Map<String, dynamic>? decoded,
  }) async {
    final payload = decoded ?? await _decodeOffIsolate(json!);
    final summary = summarise(payload);

    onProgress?.call((
      phase: JobPhase.decoding,
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
        phase: JobPhase.clearing,
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
            phase: JobPhase.writing,
            detail: tableLabel(codec.name),
            rows: written,
            fraction: total == 0 ? null : (written / total).clamp(0.0, 1.0),
          ));
        }
      }

      // Every row the header promised is on disk, or none of them are.
      //
      // The `counts` header was written from `codec.count()` before a
      // single row was streamed (see [writeBackup]). Read only to size a
      // progress bar, it would let a file whose body is short restore
      // silently, *after* these tables have been cleared, with the screen
      // saying it worked. Three ways to be holding one: an export that
      // skipped a row, a hand edit, and a merge.
      //
      // `landed < declared` rather than `!=`. The header is counted before the
      // pages are read, so a set logged while the export was running makes the
      // body honestly longer than the header. That file is complete and must
      // not be refused.
      for (final codec in _codecs) {
        final declared = summary.counts[codec.name];
        if (declared == null) continue;
        final landed = await codec.count();
        if (landed < declared) {
          throw FormatException(
            'This backup is incomplete: it records $declared '
            '${tableLabel(codec.name)} but contains only $landed. Nothing has '
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
      // Inside the transaction, because it is part of the restore rather than
      // a tidy-up after it. After the commit it would leave a window — a crash,
      // a kill, a battery — where the restore has landed and every regime in it
      // is wearing the same hue, with `nextIdentitySlot` then handing slot 1 to
      // the next new regime while five sit on 0. That is the exact collision
      // the column exists to prevent, reached through the one screen that
      // exists to put a history back.
      final regimeRows = data['regimes'];
      final needsSlots = regimeRows is List &&
          regimeRows.any((row) =>
              row is Map && !row.containsKey('identityIndex'));
      if (needsSlots) await backfillIdentityIndexes(db);

      // And the rows describe a database that could exist.
      //
      // The counts check above asks whether the *file* arrived whole. This
      // asks whether what it holds is coherent — the same rules the fuzz
      // harness judges every operation by, re-derived in SQL rather than
      // delegated to the constraints that normally enforce them
      // (`invariants.dart` says why). A restore is the writer those rules were
      // written for: it clears every table and streams a file this build did
      // not necessarily export, under `defer_foreign_keys`, and a partial
      // index says nothing about a file that arrived already wrong.
      //
      // Only the rules no repair can address. A backup legitimately carries
      // the healable ones — `healOrphanedSnapshots` exists for the live
      // snapshots an older build left under a tombstoned workout, and nothing
      // in the schema refuses one on the way in. Refusing those files
      // would be refusing histories the app has always straightened out on the
      // next launch. What is left is the states nothing knows a move for: two
      // workouts in progress, a day carrying two bodyweights, a workout filed
      // under one day and ringed on another.
      //
      // Inside the transaction, unlike `repairDatabase` below, and the
      // distinction is the one that comment already draws. A repair is a
      // judgement about rows that are legitimately there, so a healer failing
      // must not take a correctly restored history down with it. This is not a
      // repair — it is the same refusal as the counts check, and the whole
      // point of making it here is that the old rows are still on disk to go
      // back to.
      //
      // After `backfillIdentityIndexes`, because a pre-v5 file legitimately
      // arrives with every regime on slot 0 and the backfill is what makes
      // `two live regimes wear one identity` true again.
      final unfixable = await invariantViolations(
        db,
        only: unhealableInvariantNames,
      );
      if (unfixable.isNotEmpty) {
        throw FormatException(
          'This backup describes a history that cannot be put back '
          'together, so nothing has been restored.',
        );
      }
    });

    // A restore is the one moment the database goes from empty to a decade in
    // a single act, so the planner statistics gathered at open describe a
    // database that no longer exists — and the screens the user looks at next
    // are planned against them. `beforeOpen` would put it right on the
    // following launch, which is a launch too late.
    await db.customStatement('ANALYZE');

    // The same list a launch runs, and deliberately the same list rather than a
    // second one written here.
    //
    // After the commit rather than inside it. The transaction above is the
    // all-or-nothing guarantee a restore rests on: what it holds is that the
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

    // What the repairs did not put right.
    //
    // The check inside the transaction refused the states nothing knows a move
    // for; the repairs have now made their moves on the rest. Anything still
    // standing is a shape neither half accounted for, and the user is holding
    // it — the file is committed and there is nothing left to roll back to. So
    // it is said out loud rather than swallowed: the alternative is the
    // silence this whole file was written against, where the restore reports
    // success and the wrong number turns up in a chart months later.
    for (final violation in await invariantViolations(db)) {
      reportFailure(
        StateError(violation.toString()),
        StackTrace.current,
        what: 'Your history was restored, but some records are inconsistent. '
            'Review your recent sessions before training.',
      );
    }

    return ImportResult(summary: summary, rowsWritten: written);
  }
}
