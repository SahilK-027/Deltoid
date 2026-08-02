import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// What happens to a session you are *in the middle of* when you walk over to
/// the Regime tab and edit — or delete — the day it came from.
///
/// The answer has to be "nothing", and it has to be provable rather than
/// asserted: `WorkoutExercise` and `SetLog` are snapshots of the template
/// rather than pointers into it (README invariant 2), and this is the case that
/// invariant exists for.
void main() {
  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  late AppDatabase db;
  late TrainingRepository repo;
  late RegimeRepository regimes;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    regimes = RegimeRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  Future<Regime> activeRegime() async =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
          .getSingle();

  Future<Session> sessionNamed(String name) async =>
      (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();

  /// A workout open on Push 1, with its first set logged.
  Future<String> openWorkout() async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);
    final first = detail!.entries.first.sets.first;
    await repo.updateSet(
      first.id,
      weight: const Value(60),
      reps: const Value(8),
      isDone: const Value(true),
    );
    return id;
  }

  test('deleting the training day mid-session changes nothing in the log',
      () async {
    final id = await openWorkout();
    final before = await repo.workoutDetail(id);
    final push1 = await sessionNamed('Push 1');

    await regimes.deleteSession(push1.id);

    final after = await repo.workoutDetail(id);
    expect(after, isNotNull, reason: 'the log must still open');
    expect(after!.entries.map((e) => e.exercise.id).toList(),
        before!.entries.map((e) => e.exercise.id).toList());
    expect(after.entries.first.sets.first.weight, 60);
    // The name survives too: the detail reads the session row by id rather than
    // filtering it out for being tombstoned, so the log does not lose its title
    // out from under you mid-set.
    expect(after.session?.name, 'Push 1');
  });

  test('removing the exercise from the day mid-session leaves it in the log',
      () async {
    final id = await openWorkout();
    final push1 = await sessionNamed('Push 1');
    final slots = await (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(push1.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    await regimes.removeSessionExercise(slots.first.id);

    final after = await repo.workoutDetail(id);
    expect(after!.entries.first.exercise.id, slots.first.exerciseId);
    expect(after.entries.first.sets.first.isDone, isTrue);
  });

  test('deleting the whole regime mid-session still lets it be finished',
      () async {
    final id = await openWorkout();
    final regime = await activeRegime();

    // A second regime, so deleting this one is allowed at all.
    await regimes.createRegime('Other', activate: false);
    await regimes.deleteRegime(regime.id);

    // The open workout is still findable — the query is not scoped to whichever
    // regime happens to be active — so Today can still resume it.
    final open = await repo.openWorkout();
    expect(open?.id, id);

    await repo.completeWorkout(id);

    final done = await repo.workoutDetail(id);
    expect(done!.workout.status, WorkoutStatus.completed);
    // And it is in history, still attached to the regime that no longer exists
    // anywhere else.
    expect(await repo.workoutFeed(), hasLength(1));
  });

  test('renaming the exercise shows through to the running log', () async {
    final id = await openWorkout();
    final detail = await repo.workoutDetail(id);
    final exerciseId = detail!.entries.first.exercise.id;

    await (db.update(db.exercises)..where((t) => t.id.equals(exerciseId)))
        .write(const ExercisesCompanion(name: Value('Renamed press')));

    final after = await repo.workoutDetail(id);
    // Deliberate: the *name* is read live, so fixing a typo mid-session fixes
    // it everywhere. What is snapshotted is which exercise, in what order, with
    // what sets — not what it is called.
    expect(after!.entries.first.exercise.name, 'Renamed press');
  });
}
