import '../db/database.dart';
import '../db/table_spec.dart';
import '../db/watch.dart';
import 'push.dart';

/// Which of [SYNC.md § 2](SYNC.md#2-the-three-states)'s three this install is
/// in.
///
/// **There is no state for *syncing right now*.** A spinner on a background job
/// nobody is waiting for is a spinner that teaches the user to wait — so this
/// is derived from what is on disk and nothing keeps it in step, because there
/// is no second copy of the answer.
enum SyncStatus {
  /// Never connected, or declined at first launch.
  local,

  /// Signed in, nothing owed.
  synced,

  /// Signed in, rows owed — offline, or a push that failed.
  ///
  /// **Normal, not an error.** A session logged in a basement gym is pending
  /// for an hour and that is the design working. The only thing that makes it
  /// worth mentioning is how long it has been true.
  pending,
}

/// The state, and the two numbers a screen needs to say more than its name.
class SyncState {
  const SyncState({
    required this.status,
    required this.owed,
    required this.lastPushAt,
  });

  /// What a build with no configuration, or a phone that declined, is in.
  static const local = SyncState(
    status: SyncStatus.local,
    owed: 0,
    lastPushAt: null,
  );

  final SyncStatus status;

  /// Rows this device still owes the server. Zero unless [status] is
  /// [SyncStatus.pending].
  final int owed;

  /// When the last drain finished, or null if none has on this install.
  final DateTime? lastPushAt;
}

/// What is on disk, watched: how much is owed and when the last push landed.
///
/// Through [WatchTables.watchQuery] rather than a watched `customSelect`. The
/// question sync wants is *is anything owed*, which is exactly the shape that
/// tempts a `customSelect('SELECT 1', readsFrom: …)` sentinel — and that fires
/// once and then goes silent forever, with no error anywhere
/// ([SYNC.md § 19](SYNC.md#19-traps)).
Stream<SyncState> watchSyncState(AppDatabase db, {required bool signedIn}) {
  final specs = tableSpecs(db).where((s) => s.syncs).toList();
  if (!signedIn) {
    // Still watched rather than a single value: the account can be signed into
    // from Settings without this stream being rebuilt from scratch, and a
    // stream that ends would leave the row it feeds frozen.
    return Stream.value(SyncState.local);
  }

  final owedSql = specs
      .map((s) => '(SELECT COUNT(*) FROM ${s.name} WHERE dirty = 1)')
      .join(' + ');

  return db.watchQuery(
    [...specs.map((s) => s.table), db.appSettings],
    () async {
      // One statement over nine partial indexes, each of them empty whenever
      // that table owes nothing — so the common answer costs nine index probes
      // rather than a scan of 168k set logs, on a query re-run every time a set
      // is ticked.
      final owed = await db
          .customSelect('SELECT $owedSql AS owed')
          .map((row) => row.read<int>('owed'))
          .getSingle();

      final stamp = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(lastPushKey)))
          .getSingleOrNull();
      final lastPushAt = switch (int.tryParse(stamp?.value ?? '')) {
        final ms? => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        _ => null,
      };

      return SyncState(
        status: owed == 0 ? SyncStatus.synced : SyncStatus.pending,
        owed: owed,
        lastPushAt: lastPushAt,
      );
    },
  );
}
