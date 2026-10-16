import 'package:deltoid/core/providers.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:deltoid/features/progress/volume_providers.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The volume screen stops querying once it is left.
///
/// `volumeHistoryProvider` watches `set_logs` — the hot table during a session,
/// written once per set ticked. Without `autoDispose`, opening the screen once
/// subscribes it for the rest of the app's life: pick `All`, go and train, and
/// every set ticked re-queries and re-folds the whole history on the UI isolate
/// for a screen nobody is looking at.
///
/// `exerciseProgressProvider` had exactly this bug and its doc comment explains
/// the fix at length. The lesson was learned in one file and not carried to the
/// other, which is why this is a test rather than a second comment.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

/// Counts the two queries the volume screens make. A spy rather than a mock:
/// every call goes through to the real repository, so what is being counted is
/// the real work.
class CountingRepository extends TrainingRepository {
  CountingRepository(super.db);

  int dailyCalls = 0;
  int exerciseCalls = 0;

  @override
  Future<List<({int dayKey, MuscleGroup muscle, int sets})>> setsByMuscleDaily({
    required int fromDayKey,
    required int toDayKey,
  }) {
    dailyCalls++;
    return super
        .setsByMuscleDaily(fromDayKey: fromDayKey, toDayKey: toDayKey);
  }

  @override
  Future<List<({String exerciseId, String name, int sets})>> setsByExercise({
    required int fromDayKey,
    required int toDayKey,
    required List<MuscleGroup> muscles,
  }) {
    exerciseCalls++;
    return super.setsByExercise(
      fromDayKey: fromDayKey,
      toDayKey: toDayKey,
      muscles: muscles,
    );
  }
}

void main() {
  late AppDatabase db;
  late CountingRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CountingRepository(db);
    await ensureStarterCatalog(db);
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      trainingRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  });

  tearDown(() => db.close());

  /// A completed session, so there is history for the screen to draw, and an
  /// open one to tick sets into afterwards.
  Future<String> openWorkout() async {
    final regimeId = await createRegimeFromTemplate(db, ppl);
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    final done = await repo.startWorkout(
      regimeId: regimeId,
      sessionId: sessions.first.id,
    );
    final first = await repo.workoutDetail(done);
    await repo.updateSet(
      first!.entries.first.sets.first.id,
      weight: const Value(40),
      reps: const Value(8),
      isDone: const Value(true),
    );
    await repo.completeWorkout(done);

    return repo.startWorkout(
      regimeId: regimeId,
      sessionId: sessions[1].id,
    );
  }

  /// Ticks one set of [workoutId], which is a write to `set_logs`.
  Future<void> tickASet(String workoutId, int index) async {
    final detail = await repo.workoutDetail(workoutId);
    await repo.updateSet(
      detail!.entries.first.sets[index].id,
      weight: const Value(60),
      reps: const Value(5),
      isDone: const Value(true),
    );
    // Long enough for a stream that is still listening to fire.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('ticking a set with the volume screen closed runs no volume query',
      () async {
    final open = await openWorkout();

    final sub = container.listen(volumeHistoryProvider, (_, _) {});
    await container.read(volumeHistoryProvider.future);
    expect(repo.dailyCalls, greaterThan(0), reason: 'the screen has to query');

    // Leaving the screen. Every widget that watched it is gone.
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = repo.dailyCalls;
    await tickASet(open, 0);
    await tickASet(open, 1);

    expect(
      repo.dailyCalls,
      after,
      reason: 'a screen nobody is looking at re-folded the whole history, '
          'twice, on the UI isolate',
    );
  });

  test('ticking a set with a region screen closed runs no region query',
      () async {
    final open = await openWorkout();

    final sub = container
        .listen(regionExercisesProvider(MuscleRegion.chest), (_, _) {});
    await container.read(regionExercisesProvider(MuscleRegion.chest).future);
    expect(repo.exerciseCalls, greaterThan(0));

    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = repo.exerciseCalls;
    await tickASet(open, 0);

    expect(repo.exerciseCalls, after);
  });

  test('the screen still updates live while it is open', () async {
    // The other half of the rule: `autoDispose` must not cost the property the
    // provider exists for. A set ticked in the session you are standing in
    // moves this week's bar while the screen is watching.
    final open = await openWorkout();

    final sub = container.listen(volumeHistoryProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(volumeHistoryProvider.future);
    final before = repo.dailyCalls;

    await tickASet(open, 0);

    expect(repo.dailyCalls, greaterThan(before));
  });
}
