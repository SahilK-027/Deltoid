import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regimes are additive: creating one only moves the active flag. These are the
/// rules that make "I made a new regime and the old one disappeared" false.
void main() {
  late AppDatabase db;
  late RegimeRepository repo;
  late TrainingRepository training;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RegimeRepository(db);
    training = TrainingRepository(db);
    await ensureStarterCatalog(db);
  });

  tearDown(() => db.close());

  Future<List<Regime>> living() => (db.select(db.regimes)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
      .get();

  test('creating a regime keeps the ones before it', () async {
    final first = await repo.createRegime('PPL');
    final second = await repo.createRegime('Upper / Lower');

    final all = await living();
    expect(all.map((r) => r.id), [first, second]);
    expect(all.where((r) => r.isActive).map((r) => r.id), [second]);

    final summaries = await repo.regimeSummaries();
    expect(summaries.map((s) => s.regime.name), ['PPL', 'Upper / Lower']);
  });

  test('switching back makes exactly one regime active', () async {
    final first = await repo.createRegime('PPL');
    await repo.createRegime('Upper / Lower');

    await repo.setActiveRegime(first);

    final active = (await living()).where((r) => r.isActive).toList();
    expect(active, hasLength(1));
    expect(active.single.id, first);
  });

  test('summaries count sessions and logged workouts per regime', () async {
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    final regime = (await living()).single;
    final push1 = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();

    final id = await training.startWorkout(
        regimeId: regime.id, sessionId: push1.id);
    final detail = await training.workoutDetail(id);
    await training.updateSet(detail!.entries.first.sets.first.id,
        weight: const Value(20),
        reps: const Value(8),
        isDone: const Value(true));
    await training.completeWorkout(id);

    final summary = (await repo.regimeSummaries()).single;
    expect(summary.sessionCount, 6);
    expect(summary.workoutCount, 1);
  });

  test('deleting the active regime hands over to another one', () async {
    final first = await repo.createRegime('PPL');
    final second = await repo.createRegime('Upper / Lower');

    await repo.deleteRegime(second);

    final all = await living();
    expect(all.map((r) => r.id), [first]);
    expect(all.single.isActive, isTrue,
        reason: 'the app must never be left with no regime while one exists');
  });

  test('deleting a regime leaves its workouts in history', () async {
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    final regime = (await living()).single;
    final push1 = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();

    final id = await training.startWorkout(
        regimeId: regime.id, sessionId: push1.id);
    final detail = await training.workoutDetail(id);
    await training.updateSet(detail!.entries.first.sets.first.id,
        weight: const Value(22.5),
        reps: const Value(8),
        isDone: const Value(true));
    await training.completeWorkout(id);

    await repo.createRegime('Upper / Lower');
    await repo.deleteRegime(regime.id);

    final feed = await training.workoutFeed();
    expect(feed, hasLength(1));
    expect(feed.single.workout.id, id);
    expect(feed.single.sessionName, 'Push 1');
  });

  test('a removed exercise slot can be put back with its numbers intact',
      () async {
    final regimeId = await repo.createRegime('PPL');
    final sessionId = await repo.addSession(regimeId, 'Push 1');
    final exercise = await (db.select(db.exercises)..limit(1)).getSingle();
    final slotId = await repo.addExerciseToSession(sessionId, exercise.id);
    await repo.updateSessionExercise(slotId, targetSets: const Value(5));

    await repo.removeSessionExercise(slotId);
    expect(
      await (db.select(db.sessionExercises)..where((t) => t.deletedAt.isNull()))
          .get(),
      isEmpty,
    );

    await repo.restoreSessionExercise(slotId);
    final restored = await (db.select(db.sessionExercises)
          ..where((t) => t.deletedAt.isNull()))
        .getSingle();
    expect(restored.id, slotId);
    expect(restored.targetSets, 5);
  });

  test('an archived exercise keeps the workouts that used it', () async {
    final exercise = await (db.select(db.exercises)..limit(1)).getSingle();
    await repo.updateExercise(exercise.id, archived: const Value(true));

    final row = await (db.select(db.exercises)
          ..where((t) => t.id.equals(exercise.id)))
        .getSingle();
    expect(row.archived, isTrue);
    expect(row.deletedAt, isNull, reason: 'past logs point at this row');
  });

  test('load mode survives an edit to the catalog entry', () async {
    final exercise = await (db.select(db.exercises)..limit(1)).getSingle();
    await repo.updateExercise(exercise.id,
        name: const Value('Renamed'), loadMode: const Value(LoadMode.perSide));

    final row = await (db.select(db.exercises)
          ..where((t) => t.id.equals(exercise.id)))
        .getSingle();
    expect(row.name, 'Renamed');
    expect(row.loadMode, LoadMode.perSide);
  });
}
