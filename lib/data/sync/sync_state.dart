import '../db/database.dart';
import '../db/table_spec.dart';
import '../db/watch.dart';
import 'push.dart';

/// Which of [SYNC.md § 2](SYNC.md#2-the-three-states)'s three this install is
/// in.
///
/// There is no state representing synchronisation in progress. A progress
/// indicator on a background job
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
  /// A normal state rather than an error. A session logged without network
  /// access is pending
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
    this.owedSince,
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

  /// When the oldest thing still owed was written, or null when nothing is.
  ///
  /// The complete answer to how long ([SYNC.md § 2](SYNC.md#2-the-three-states)).
  /// Pending is normal — a session logged in a basement gym is pending for an
  /// hour and that is the design working — and the only thing that makes it
  /// worth mentioning is how long it has been true. A screen that says *3
  /// changes waiting* says nothing; one that says *since Tuesday* says
  /// something has gone wrong.
  final DateTime? owedSince;
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
  // MIN over MINs: each inner one rides the same partial index the count does,
  // so the oldest thing owed costs no more than counting it.
  final oldestSql = specs
      .map((s) => 'SELECT MIN(updated_at) AS t FROM ${s.name} WHERE dirty = 1')
      .join(' UNION ALL ');

  return db.watchQuery(
    [...specs.map((s) => s.table), db.appSettings],
    () async {
      // One statement over nine partial indexes, each of them empty whenever
      // that table owes nothing — so the common answer costs nine index probes
      // rather than a scan of 168k set logs, on a query re-run every time a set
      // is ticked.
      final counted = await db
          .customSelect(
            'SELECT $owedSql AS owed, '
            '(SELECT MIN(t) FROM ($oldestSql)) AS oldest',
          )
          .getSingle();
      final owed = counted.read<int>('owed');
      final oldest = counted.read<int?>('oldest');

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
        owedSince:
            oldest == null ? null : DateTime.fromMillisecondsSinceEpoch(oldest),
      );
    },
  );
}
