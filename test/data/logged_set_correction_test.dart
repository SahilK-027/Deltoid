import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Correcting a set in a session that has already ended.
///
/// The numbers downstream of the log are all derived at read time, so a
/// corrected row is a corrected chart. What is not automatic is that the
/// readers find out: cycle progress leaves `set_logs` unwatched on purpose, and
/// a correction writes nothing else. These tests hold the announcement that
/// closes that gap, and the two things a correction must leave alone — when the
/// set was done, and a session that is still open.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

void main() {
  late AppDatabase db;
  late TrainingRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  Future<Regime> activeRegime() =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
          .getSingle();

  Future<List<Session>> sessions() async {
    final regime = await activeRegime();
    return (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
  }

  /// Trains every session of the regime once at [weight] for ten reps, which
  /// is one cycle. Returns the workout ids in the order trained.
  Future<List<String>> trainCycle(double weight) async {
    final regime = await activeRegime();
    final ids = <String>[];
    for (final s in await sessions()) {
      final id = await repo.startWorkout(regimeId: regime.id, sessionId: s.id);
      final detail = await repo.workoutDetail(id);
      for (final entry in detail!.entries) {
        for (final set in entry.sets) {
          await repo.updateSet(
            set.id,
            weight: Value(weight),
            reps: const Value(10),
            isDone: const Value(true),
          );
        }
      }
      await repo.completeWorkout(id);
      ids.add(id);
    }
    await repo.closeCycleIfSatisfied(regime.id);
    return ids;
  }

  Future<SetLog> setOf(String id) =>
      (db.select(db.setLogs)..where((t) => t.id.equals(id))).getSingle();

  test('a corrected baseline rescores every later cycle', () async {
    final first = await trainCycle(50);
    await trainCycle(55);

    // Up before anything is corrected: every movement that takes a load moved
    // by ten per cent.
    final before = (await repo.activeRegimeProgress())!.progress;
    expect(before.cycles[1].value, greaterThan(5));

    // Every set of the first cycle was meant to be 55 and was typed as 50.
    for (final workoutId in first) {
      final detail = await repo.workoutDetail(workoutId);
      for (final entry in detail!.entries) {
        for (final set in entry.sets) {
          await repo.correctLoggedSet(set.id, weight: const Value(55));
        }
      }
    }

    final after = (await repo.activeRegimeProgress())!.progress;
    expect(after.cycles[1].value, closeTo(0, 1e-9));
  });

  test('a correction reaches the cycle card without a session being finished',
      () async {
    final first = await trainCycle(50);
    await trainCycle(55);

    final seen = <double?>[];
    final sub = repo.watchActiveRegimeProgress().listen(
          (p) => seen.add(p?.progress.cycles[1].value),
        );
    await pumpEventQueue();
    final shown = seen.last!;
    expect(shown, greaterThan(5));
    final emitted = seen.length;

    // One set of one lift in the baseline, typed as 50 and meant as 100. The
    // cycle's mean moves, and the card has to hear about it from this write
    // alone.
    final detail = await repo.workoutDetail(first.first);
    final set = detail!.entries.first.sets.first;
    await repo.correctLoggedSet(set.id, weight: const Value(100));
    await pumpEventQueue();

    expect(seen.length, greaterThan(emitted));
    expect(seen.last, lessThan(shown));
    await sub.cancel();
  });

  test('the plain set write does not wake the cycle card', () async {
    // The other half of the test above: the watch really is deaf to
    // `set_logs`, so the announcement is what woke it and not the row.
    final first = await trainCycle(50);
    await trainCycle(55);

    var emitted = 0;
    final sub = repo.watchActiveRegimeProgress().listen((_) => emitted++);
    await pumpEventQueue();
    final before = emitted;

    final detail = await repo.workoutDetail(first.first);
    await repo.updateSet(
      detail!.entries.first.sets.first.id,
      weight: const Value(100),
    );
    await pumpEventQueue();

    expect(emitted, before);
    await sub.cancel();
  });

  test('a correction changes what was lifted and not when', () async {
    final first = await trainCycle(50);
    final detail = await repo.workoutDetail(first.first);
    final before = await setOf(detail!.entries.first.sets.first.id);
    await (db.update(db.setLogs)..where((t) => t.id.equals(before.id)))
        .write(const SetLogsCompanion(dirty: Value(false)));

    await repo.correctLoggedSet(
      before.id,
      weight: const Value(62.5),
      reps: const Value(8),
      partialReps: const Value(2),
    );

    final after = await setOf(before.id);
    expect(after.weight, 62.5);
    expect(after.reps, 8);
    expect(after.partialReps, 2);
    expect(after.isDone, isTrue);
    expect(after.completedAt, before.completedAt);
    expect(after.setIndex, before.setIndex);
    // Owed to the cloud again, on a later stamp than the one it replaces.
    expect(after.dirty, isTrue);
    expect(after.updatedAt, greaterThan(before.updatedAt));
  });

  test('a correction never stamps the exercise row above the set', () async {
    // A fresh `updatedAt` there would carry this phone's copy of the day's
    // note over a newer one from another device.
    final first = await trainCycle(50);
    final detail = await repo.workoutDetail(first.first);
    final entry = detail!.entries.first;

    await repo.correctLoggedSet(entry.sets.first.id, reps: const Value(9));

    final row = await (db.select(db.workoutExercises)
          ..where((t) => t.id.equals(entry.workoutExercise.id)))
        .getSingle();
    expect(row.updatedAt, entry.workoutExercise.updatedAt);
  });

  test('a warm-up logged as a working set can be put right', () async {
    final first = await trainCycle(50);
    final detail = await repo.workoutDetail(first.first);
    final set = detail!.entries.first.sets.first;

    await repo.correctLoggedSet(set.id, setType: const Value(SetType.warmup));

    expect((await setOf(set.id)).setType, SetType.warmup);
  });

  test('a set that never happened can be removed from a finished day',
      () async {
    final first = await trainCycle(50);
    final detail = await repo.workoutDetail(first.first);
    final entry = detail!.entries.first;

    var emitted = 0;
    final sub = repo.watchActiveRegimeProgress().listen((_) => emitted++);
    await pumpEventQueue();
    final before = emitted;

    await repo.deleteLoggedSets([entry.sets.first.id]);
    await pumpEventQueue();

    final after = await repo.workoutDetail(first.first);
    expect(after!.entries.first.sets.length, entry.sets.length - 1);
    expect((await setOf(entry.sets.first.id)).deletedAt, isNotNull);
    expect(emitted, greaterThan(before));
    await sub.cancel();
  });

  test('a session still in progress is refused', () async {
    final regime = await activeRegime();
    final id = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: (await sessions()).first.id,
    );
    final set = (await repo.workoutDetail(id))!.entries.first.sets.first;

    await expectLater(
      repo.correctLoggedSet(set.id, weight: const Value(40)),
      throwsStateError,
    );
    await expectLater(repo.deleteLoggedSets([set.id]), throwsStateError);

    final untouched = await setOf(set.id);
    expect(untouched.weight, isNull);
    expect(untouched.deletedAt, isNull);
  });
}
