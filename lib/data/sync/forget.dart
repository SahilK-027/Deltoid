import '../db/database.dart';
import '../db/table_spec.dart';
import '../seed/seeder.dart';
import 'pull.dart';
import 'push.dart';

/// Everything that syncs, hard-deleted, children first.
///
/// Two callers, and they are the same act under two names: the second door of
/// [SYNC.md § 11](SYNC.md#11-signing-out) — *sign out and remove the history
/// from this phone* — and `Keep the account's history` in
/// [§ 10](#10-adoption), which clears the phone before pulling the account
/// over it.
///
/// **The one place in the app that hard-deletes outside a restore**, and the
/// rule both callers obey is the same: the confirmation naming what is about to
/// go, or the backup file, comes first. Nothing here asks.
///
/// A tombstone would be wrong. This is not *the user deleted their training*,
/// which the account would then hear about and apply to every other phone — it
/// is *this phone is no longer carrying it*. The rows must leave without a
/// trace to push.
///
/// [seed] refills the catalog afterwards, because a phone with no exercises has
/// nothing to train from. A pull that is about to arrive brings the account's
/// own catalog instead, and passes false.
Future<void> forgetLocalHistory(AppDatabase db, {bool seed = true}) async {
  await db.transaction(() async {
    for (final spec in tableSpecs(db).where((s) => s.syncs).toList().reversed) {
      await db.customStatement('DELETE FROM ${spec.name}');
    }
    // Bookkeeping about rows that no longer exist. Left behind, a cursor would
    // make the next pull start after a history this phone no longer has.
    await (db.delete(
      db.appSettings,
    )..where((t) => t.key.isIn([lastPullKey, lastPushKey]))).go();
  });
  if (seed) await ensureStarterCatalog(db);
}

/// How many finished sessions are about to go, for the sentence that asks.
///
/// [SYNC.md § 11](SYNC.md#11-signing-out): the confirmation names the number. A
/// prompt that says *everything* is a prompt nobody can weigh.
Future<int> localSessionCount(AppDatabase db) => db
    .customSelect('SELECT COUNT(*) AS n FROM workouts WHERE deleted_at IS NULL')
    .map((row) => row.read<int>('n'))
    .getSingle();
