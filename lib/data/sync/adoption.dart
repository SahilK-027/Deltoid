import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/progress.dart';
import '../backup/backup_service.dart';
import '../db/database.dart';
import '../db/table_spec.dart';
import '../seed/seeder.dart';
import 'catalog_dedup.dart';
import 'forget.dart';
import 'pull.dart';
import 'push.dart';
import 'sync_backend.dart';

/// What the first sign-in on this phone turns out to be.
///
/// [SYNC.md § 10](SYNC.md#10-adoption), the three shapes:
///
/// | Local | Cloud | |
/// | --- | --- | --- |
/// | nothing | data | [pull] — new phone, nothing to lose |
/// | training | empty | [push] — the device already in use |
/// | training | training | [ask] — never resolved silently |
enum AdoptionShape {
  /// Both sides empty, or the account holds the only history. Adopt it.
  pull,

  /// The phone holds the only history. Send it.
  push,

  /// Two independent histories. Every id is UUID v7, so they share none, and a
  /// merge is not a reconciliation but a union — one that claims the user
  /// trained twice as often as they did on every day both sides recorded.
  ask,
}

/// The numbers the [AdoptionShape.ask] prompt puts on screen.
///
/// *214 sessions, most recently 3 March* rather than *some* — which is the only
/// reason [SyncBackend.count] and [SyncBackend.latestAt] exist at all.
typedef AdoptionSurvey = ({
  AdoptionShape shape,
  int phoneSessions,
  DateTime? phoneLatest,
  int accountSessions,
  DateTime? accountLatest,
});

/// The user's answer to [AdoptionShape.ask].
enum AdoptionChoice {
  /// The account's history is the one that survives. The phone's is written to
  /// a backup file and then cleared.
  keepAccount,

  /// The phone's history is the one that survives. The account's is written to
  /// a backup file, then tombstoned so it does not come back on the next pull.
  keepPhone,

  /// Both. Nothing is lost and the result is not clean — duplicated exercises
  /// deduped where the app seeded them, left alone where the user made them.
  merge,
}

/// The three shapes at sign-in, and the `starterKey` dedup that follows the
/// third.
///
/// No step here is silent. [survey] reads both sides and decides nothing;
/// [adopt] does only what it was told. The one rule that outranks the rest:
/// *whichever side is not kept is written to a backup file first, automatically,
/// before anything is overwritten* — a decision made once at a sign-in screen
/// must not be the only thing between a user and a deleted history.
///
/// Not a rare path. Installing with no signal, training for a month and signing
/// in afterwards is the *likely* order, and it seeds a catalog locally before
/// ever meeting the account's.
class AdoptionService {
  AdoptionService(
    this._db,
    this._backend, {
    BackupService? backup,
    PullService? pull,
    PushService? push,
    Future<Directory> Function()? directory,
    this.pageSize = 400,
  }) : _backup = backup ?? BackupService(_db),
       _pull = pull ?? PullService(_db, _backend),
       _push = push ?? PushService(_db, _backend),
       _directory = directory;

  final AppDatabase _db;
  final SyncBackend _backend;
  final BackupService _backup;
  final PullService _pull;
  final PushService _push;

  /// Where the two backup files land. Defaults to the folder every other export
  /// goes to — *the same folder as every other export, and the prompt says so*
  /// — and is injected by the tests, which have no `path_provider`.
  final Future<Directory> Function()? _directory;

  /// Rows per request while reading the account, both to size it up and to
  /// write it to a file.
  final int pageSize;

  /// The tables that say whether a side has been trained on, as opposed to
  /// merely installed.
  ///
  /// A catalog is not a history: a phone that has been opened once and never
  /// used has 120 exercises on it and nothing to lose, and asking that user
  /// which history to keep would be asking them about nothing.
  static const _historyTables = ['workouts', 'regimes', 'bodyweight_logs'];

  /// The table the prompt counts. Sessions, in the user's language.
  static const _sessionTable = 'workouts';

  /// Reads both sides and says which shape this sign-in is, without writing
  /// anything anywhere.
  Future<AdoptionSurvey> survey() async {
    var phoneHistory = false;
    for (final table in _historyTables) {
      if (await _liveCount(table) > 0) phoneHistory = true;
    }

    var accountHistory = false;
    for (final table in _historyTables) {
      if (await _backend.count(table) > 0) accountHistory = true;
    }

    final shape = !phoneHistory
        ? AdoptionShape.pull
        : accountHistory
        ? AdoptionShape.ask
        : AdoptionShape.push;

    return (
      shape: shape,
      phoneSessions: await _liveCount(_sessionTable),
      phoneLatest: await _phoneLatest(),
      accountSessions: await _backend.count(_sessionTable),
      accountLatest: await _backend.latestAt(_sessionTable, 'started_at'),
    );
  }

  /// Runs the shape [survey] found, and returns the backup file it wrote, if
  /// any.
  ///
  /// [choice] is required for [AdoptionShape.ask] and ignored otherwise — the
  /// other two shapes have nothing to choose between. Being handed [ask] with
  /// no choice is a bug in the caller rather than a state to recover from, and
  /// it throws.
  Future<File?> adopt(
    AdoptionShape shape, {
    AdoptionChoice? choice,
    ProgressReport? onProgress,
  }) async {
    switch (shape) {
      case AdoptionShape.pull:
        try {
          await _pull.pull(
            onProgress: onProgress,
            expectedRows: onProgress == null ? null : await _accountRows(),
          );
        } finally {
          // Seeded even when the pull did not finish. A phone with no catalog
          // cannot be trained on at all, and the welcome screen has already
          // been answered, so nothing else would seed it. The duplicate this
          // risks —
          // the account's catalog arriving behind a locally seeded one — is
          // what [dedupeCatalog] is for, and the engine runs it after every
          // pull rather than only here.
          await ensureStarterCatalog(_db);
        }
        return null;

      case AdoptionShape.push:
        await _markEverythingDirty();
        await _push.drain();
        return null;

      case AdoptionShape.ask:
        if (choice == null) {
          throw ArgumentError('The third shape is never resolved silently.');
        }
        return _resolve(choice, onProgress);
    }
  }

  Future<File?> _resolve(
    AdoptionChoice choice,
    ProgressReport? onProgress,
  ) async {
    switch (choice) {
      case AdoptionChoice.keepAccount:
        final backup = await _writePhoneBackup();
        // Not seeded: the account's own catalog is about to arrive, and
        // seeding here is exactly how a phone ends up with two.
        await forgetLocalHistory(_db, seed: false);
        await _pull.pull(
          onProgress: onProgress,
          expectedRows: onProgress == null ? null : await _accountRows(),
        );
        await ensureStarterCatalog(_db);
        return backup;

      case AdoptionChoice.keepPhone:
        final backup = await _writeAccountBackup();
        await _tombstoneTheAccount();
        await _markEverythingDirty();
        await _push.drain();
        return backup;

      case AdoptionChoice.merge:
        // No loser, so no backup: a union overwrites nothing.
        await _pull.pull(
          onProgress: onProgress,
          expectedRows: onProgress == null ? null : await _accountRows(),
        );
        await dedupeCatalog(_db);
        await _markEverythingDirty();
        await _push.drain();
        return null;
    }
  }

  /// How many rows the account holds in total, for a bar with a denominator.
  ///
  /// Nine counts, and they are worth it exactly once: this runs only where a
  /// human is watching a first pull land. Every background drain passes no
  /// progress and so never asks.
  Future<int> _accountRows() async {
    var total = 0;
    for (final spec in tableSpecs(_db).where((s) => s.syncs)) {
      total += await _backend.count(spec.name);
    }
    return total;
  }

  /// Every row the account holds that this phone does not, written locally as a
  /// tombstone and owed to the server.
  ///
  /// This is what `Keep this phone's history` costs mechanically: the transport
  /// upserts and never deletes, so the only way the account's history stops
  /// arriving on the next pull is for this phone to say, row by row, that it is
  /// gone. A tombstone claims nothing — every unique index in
  /// [SYNC.md § 9](SYNC.md#9-collision--two-rows-one-slot) is partial on
  /// `deleted_at IS NULL` — so none of them can collide with the history being
  /// kept.
  Future<void> _tombstoneTheAccount() async {
    final now = nowMs();
    DateTime? newest;

    for (final spec in tableSpecs(_db).where((s) => s.syncs)) {
      await for (final page in _accountPages(spec.name)) {
        final unknown = <Map<String, dynamic>>[];
        for (final wire in page) {
          final stamp = DateTime.tryParse('${wire[serverUpdatedAtColumn]}');
          if (stamp != null && (newest == null || stamp.isAfter(newest))) {
            newest = stamp;
          }
          final id = wire['id'] as String;
          final mine = await (_db
              .customSelect(
                'SELECT 1 FROM ${spec.name} WHERE id = ?',
                variables: [Variable(id)],
              )
              .get());
          if (mine.isEmpty) unknown.add(wire);
        }
        if (unknown.isEmpty) continue;

        await _db.batch((batch) {
          for (final wire in unknown) {
            final json = jsonRow(wire)
              ..['deletedAt'] = now
              ..['updatedAt'] = now
              ..['dirty'] = true;
            batch.insert(
              spec.table,
              spec.parse(json),
              mode: InsertMode.replace,
            );
          }
        });
      }
    }

    // The rows above have been dealt with, so a later pull re-reading them
    // would only re-resolve what is already settled. `>=`, as everywhere.
    final last = newest;
    if (last != null) await _setCursor(last);
  }

  /// The phone's whole database, into the folder every other export goes to.
  Future<File> _writePhoneBackup() async =>
      _backup.writeBackup(await _file('phone'));

  /// The account's whole history, in the same file format, read straight off
  /// the wire.
  ///
  /// Streamed a page at a time and never held: the reason [BackupService]
  /// writes its own JSON by hand applies here for the same reason, and the
  /// shape is byte-compatible with it so the file restores like any other.
  Future<File> _writeAccountBackup() async {
    final file = await _file('account');
    final specs = tableSpecs(_db).where((s) => s.syncs).toList();
    final counts = <String, int>{
      for (final spec in specs) spec.name: await _backend.count(spec.name),
    };

    final sink = file.openWrite();
    try {
      sink
        ..write('{"format":$backupFormatVersion')
        ..write(',"schemaVersion":${_db.schemaVersion}')
        ..write(
          ',"exportedAt":'
          '${jsonEncode(DateTime.now().toUtc().toIso8601String())}',
        )
        ..write(',"counts":${jsonEncode(counts)}')
        ..write(',"data":{');

      for (var i = 0; i < specs.length; i++) {
        if (i > 0) sink.write(',');
        sink.write('${jsonEncode(specs[i].name)}:[');
        var first = true;
        await for (final page in _accountPages(specs[i].name)) {
          final buffer = StringBuffer();
          for (final wire in page) {
            if (!first) buffer.write(',');
            first = false;
            buffer.write(jsonEncode(jsonRow(wire)));
          }
          sink.write(buffer.toString());
          await sink.flush();
        }
        sink.write(']');
      }
      sink.write('}}');
    } finally {
      await sink.close();
    }
    return file;
  }

  /// The account's rows in one table, oldest stamp first, a page at a time.
  ///
  /// The cursor walks on `server_updated_at` and compares `>=`, so a page whose
  /// rows all share one stamp would be read forever. Ids already seen are
  /// dropped, and a page that adds nothing new ends the walk.
  Stream<List<Map<String, dynamic>>> _accountPages(String table) async* {
    final seen = <String>{};
    DateTime? cursor;
    while (true) {
      final page = await _backend.since(table, cursor, limit: pageSize);
      if (page.isEmpty) return;

      final fresh = [
        for (final row in page)
          if (seen.add(row['id'] as String)) row,
      ];
      if (fresh.isNotEmpty) yield fresh;
      if (page.length < pageSize) return;
      if (fresh.isEmpty) return;

      final last = DateTime.tryParse('${page.last[serverUpdatedAtColumn]}');
      if (last == null) return;
      cursor = last;
    }
  }

  /// Marks every syncable row owed to the server.
  ///
  /// A phone that has never been signed in has been clearing `dirty` for
  /// nobody — and a row that was pushed to a *different* account is owed to
  /// this one. `dirty` is a flag about this phone's debt, not a version, so
  /// setting it mints nothing and cannot outrank a real delete
  /// ([SYNC.md § 17](SYNC.md#17-the-architecture) — what must never be
  /// re-stamped).
  Future<void> _markEverythingDirty() async {
    await _db.transaction(() async {
      for (final spec in tableSpecs(_db).where((s) => s.syncs)) {
        await _db.customStatement('UPDATE ${spec.name} SET dirty = 1');
      }
    });
  }

  Future<int> _liveCount(String table) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL',
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<DateTime?> _phoneLatest() async {
    final row = await _db
        .customSelect(
          'SELECT MAX(started_at) AS m FROM $_sessionTable WHERE deleted_at IS NULL',
        )
        .getSingle();
    final ms = row.read<int?>('m');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _setCursor(DateTime to) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: lastPullKey,
          value: to.toUtc().toIso8601String(),
        ),
      );

  Future<File> _file(String side) async {
    final dir = await (_directory ?? _backup.backupDirectory)();
    final stamp = DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now());
    return File('${dir.path}/deltoid-$side-before-sign-in-$stamp.json');
  }
}
