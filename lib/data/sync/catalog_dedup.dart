import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/catalog_merge.dart';
import '../db/database.dart';

/// Folds two seeded catalogs into one, on `starterKey`.
///
/// **Run after every pull, not only at sign-in.** Adoption is where two
/// catalogs usually meet ([SYNC.md § 10](SYNC.md#10-adoption)), but it is not
/// the only way: a sign-in whose pull failed halfway seeds locally and meets
/// the account's catalog on the next drain instead. Deterministic and
/// idempotent, so running it on a catalog that holds no duplicates costs one
/// scan of ~120 rows and writes nothing.
///
/// The plan is [planCatalogMerge] and it is pure. This is only the writing:
/// every reference to a duplicate moves to the survivor, and the duplicate is
/// tombstoned.
///
/// **`workout_exercises.muscle` is never touched.** It is a snapshot of what
/// the movement trained on the day it was logged, and repointing a row at
/// another exercise does not change what the user did that day
/// ([RULES § 2](RULES.md)). The same goes for every other snapshot column on
/// a logged row: only the id moves.
Future<int> dedupeCatalog(AppDatabase db) async {
  final rows = await db.select(db.exercises).get();
  final plan = planCatalogMerge([
    for (final row in rows)
      (id: row.id, starterKey: row.starterKey, deletedAt: row.deletedAt),
  ]);
  if (plan.repoint.isEmpty) return 0;

  final now = nowMs();
  await db.transaction(() async {
    for (final entry in plan.repoint.entries) {
      for (final table in ['workout_exercises', 'session_exercises']) {
        await db.customUpdate(
          'UPDATE $table SET exercise_id = ?, updated_at = ?, dirty = 1 '
          'WHERE exercise_id = ?',
          variables: [
            Variable(entry.value),
            Variable(now),
            Variable(entry.key),
          ],
        );
      }
    }
    for (final id in plan.tombstone) {
      await db.customUpdate(
        'UPDATE exercises SET deleted_at = ?, updated_at = ?, dirty = 1 '
        'WHERE id = ? AND deleted_at IS NULL',
        variables: [Variable(now), Variable(now), Variable(id)],
      );
    }
  });
  return plan.tombstone.length;
}
