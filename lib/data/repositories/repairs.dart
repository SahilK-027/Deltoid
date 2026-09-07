import '../db/database.dart';
import '../seed/seeder.dart';
import 'training_repository.dart';

/// Everything that looks at a database it did not write, in one list.
///
/// A launch is one caller and a restore is the other, and they must be the same
/// list: a restore is the single act that replaces every row at once, so it is
/// the *most* likely moment for a database to arrive in a state this build's
/// writers could not have produced. `appInitProvider` is a `FutureProvider`
/// that resolves once per process, so leaving these to the launch alone would
/// let a restore from Settings — which is every restore that is not a first
/// launch — go unexamined until the next cold start, with the user training on
/// top of the file's rows in the meantime.
///
/// Order is the launch order and matters in one place: the catalog has to exist
/// before anything else asks a question about exercises.
///
/// Cheap on a database with nothing wrong with it — each step is a scan that
/// finds nothing and opens no transaction — which is what lets it sit on the
/// path before first paint.
/// [seed] is false for exactly one moment in the app's life: a first launch
/// that has not answered the welcome screen yet. Seeding before that answer is
/// what places two catalogs on a device that subsequently signs in: roughly
/// 120
/// exercises, `Bench Press` twice under different ids, and a history split
/// across both, which breaks the one thing the app exists for because
/// per-session progression is keyed to an exercise id
/// ([SYNC.md § 10](SYNC.md#10-adoption)). `answerWelcome` seeds instead, before
/// it records the answer.
///
/// A restore passes true and seeds nothing anyway — the seeder declines a table
/// that is not empty, and a file that carries no catalog at all is a file
/// exported before anything was seeded.
Future<void> repairDatabase(AppDatabase db, {bool seed = true}) async {
  // A database with no exercise catalog at all cannot start a session. A file
  // that carries its own is left alone; this only fills an empty table.
  if (seed) await ensureStarterCatalog(db);

  final repo = TrainingRepository(db);
  // A mis-tapped Start leaves a workout that blocks every other session behind
  // a prompt to finish the open one. Only those with nothing logged are
  // removed;
  // see [TrainingRepository.sweepAbandonedWorkouts].
  await repo.sweepAbandonedWorkouts();
  // A phone that ran a build where `ensureOpenCycle` was not a transaction can
  // be carrying two or three open cycles for one regime — see
  // [TrainingRepository.healDuplicateOpenCycles]. Nothing else notices.
  //
  // A *file* cannot deliver this state: `idx_cycles_regime_open_live` refuses
  // the insert and the whole restore with it. The call stays because the list
  // is the point — a repair that is in one caller and not the other is how the
  // two drift apart.
  await repo.healDuplicateOpenCycles();
  // Snapshots and sets left alive under a tombstoned workout — see
  // [TrainingRepository.healOrphanedSnapshots]. Invisible on screen, and
  // precisely what a first sync push would send. This is the one of the four a
  // backup file can still carry: a tombstone is a column, not a foreign key,
  // so nothing in the schema refuses it on the way in.
  await repo.healOrphanedSnapshots();
  // A cycle left alive under a programme the *other phone* deleted. No tap can
  // produce it — `deleteRegime` takes its cycles with it — and a merge can. It
  // runs here for the same reason as the four above: the list is the point, and
  // a repair in one caller and not the other is how the two drift apart.
  await repo.healCyclesUnderDeadRegimes();
  // And a workout left naming a cycle the *other* phone tombstoned. After the
  // step above, so a regime deleted on one device settles before this asks
  // which of its cycles a workout should be on.
  await repo.healWorkoutsNamingDeadCycles();
}
