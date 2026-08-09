import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/session_diff.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a write leaves behind when it is not the only one happening.
///
/// Two shapes of the same fault, both of which used to be reachable with a
/// thumb rather than with a debugger:
///
/// * **A position taken from a count.** Every "append" here read the number of
///   live rows and used it as the next `orderIndex`. Deletes are tombstones and
///   nothing renumbers behind them, so after one removal the count names a
///   position a surviving row still holds — and two rows on one index leave the
///   order to whichever way SQLite breaks the tie.
/// * **A look-up and a write that are not one act.** Find-then-insert across an
///   `await` lets a second caller find the same nothing and insert a second row.
///
/// Both matter more than they read: once sync lands, a duplicate index or a
/// second open cycle is not one phone's confusion, it is what gets pushed.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late RegimeRepository regimes;

  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    regimes = RegimeRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  Future<Regime> activeRegime() =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true))).getSingle();

  Future<Session> sessionNamed(String name) =>
      (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();

  void expectDistinct(List<int> indexes) {
    expect(indexes.toSet().length, indexes.length,
        reason: 'two rows share a position: $indexes');
  }

  group('a position is never reused', () {
    test('an exercise added after one is dropped mid-session', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);

      final before = (await repo.workoutDetail(workoutId))!;
      await repo
          .removeExerciseFromWorkout(before.entries[1].workoutExercise.id);
      final spare = await (db.select(db.exercises)..limit(1)).getSingle();
      await repo.addExerciseToWorkout(workoutId, spare.id);

      final after = (await repo.workoutDetail(workoutId))!;
      expectDistinct(
        [for (final e in after.entries) e.workoutExercise.orderIndex],
      );
    });

    test('a slot added to a session after one is removed', () async {
      final session = await sessionNamed('Push 1');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.removeSessionExercise(slots[1].id);

      final spare = await (db.select(db.exercises)
            ..where((t) =>
                t.id.isNotIn([for (final s in slots) s.exerciseId]))
            ..limit(1))
          .getSingle();
      await regimes.addExerciseToSession(session.id, spare.id);

      final live = await (db.select(db.sessionExercises)
            ..where(
                (t) => t.sessionId.equals(session.id) & t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in live) s.orderIndex]);
    });

    test('a session added after one is deleted', () async {
      final regime = await activeRegime();
      final sessions = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regime.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.deleteSession(sessions[1].id);
      await regimes.addSession(regime.id, 'Extra');

      final live = await (db.select(db.sessions)
            ..where(
                (t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in live) s.orderIndex]);
    });

    test("keeping today's added movement, after one was removed before it",
        () async {
      final session = await sessionNamed('Push 1');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.removeSessionExercise(slots[1].id);

      final spare = await (db.select(db.exercises)
            ..where((t) =>
                t.id.isNotIn([for (final s in slots) s.exerciseId]))
            ..limit(1))
          .getSingle();
      await repo.applySessionChanges(
        sessionId: session.id,
        changes: [
          SessionChange(
            kind: SessionChangeKind.added,
            exerciseIds: [spare.id],
            label: 'Added ${spare.name}',
          ),
        ],
      );

      final live = await (db.select(db.sessionExercises)
            ..where(
                (t) => t.sessionId.equals(session.id) & t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in live) s.orderIndex]);
    });
  });

  group('a look-up and its write are one act', () {
    test('two taps on + never share a set index', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      final entry = (await repo.workoutDetail(workoutId))!.entries.first;

      await Future.wait([
        repo.addSet(entry.workoutExercise.id),
        repo.addSet(entry.workoutExercise.id),
      ]);

      final sets = await (db.select(db.setLogs)
            ..where((t) =>
                t.workoutExerciseId.equals(entry.workoutExercise.id) &
                t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in sets) s.setIndex]);
    });

    test('one day of bodyweight logged twice at once leaves one row', () async {
      final day = DateTime(2026, 8, 9);
      await Future.wait([
        repo.logBodyweight(day, 80),
        repo.logBodyweight(day, 81),
      ]);

      final rows = await (db.select(db.bodyweightLogs)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      expect(rows.length, 1);
    });

    test('two readers of a fresh regime open one cycle between them', () async {
      final regime = await activeRegime();

      // Today and the Regime screen both resolve the cycle, and on a regime
      // that has never been trained each of them found nothing to resolve.
      await Future.wait([
        repo.cycleStatus(regime.id),
        repo.cycleStatus(regime.id),
        repo.ensureOpenCycle(regime.id),
      ]);

      final open = await (db.select(db.cycles)
            ..where((t) =>
                t.regimeId.equals(regime.id) &
                t.completedAt.isNull() &
                t.deletedAt.isNull()))
          .get();
      expect(open.length, 1);
    });
  });

  test('a phone already carrying duplicate open cycles is healed', () async {
    final regime = await activeRegime();
    final keeper = await repo.ensureOpenCycle(regime.id);

    // What the old, untransacted `ensureOpenCycle` left behind.
    final stray = newId();
    await db.into(db.cycles).insert(
          CyclesCompanion.insert(
            id: Value(stray),
            regimeId: regime.id,
            cycleIndex: keeper.cycleIndex + 1,
          ),
        );
    final session = await sessionNamed('Push 1');
    final workoutId =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    // The workout attached itself to the stray, because that is the one
    // `ensureOpenCycle` hands back.
    await (db.update(db.workouts)..where((t) => t.id.equals(workoutId)))
        .write(WorkoutsCompanion(cycleId: Value(stray)));

    expect(await repo.healDuplicateOpenCycles(), 1);

    final open = await (db.select(db.cycles)
          ..where((t) =>
              t.regimeId.equals(regime.id) &
              t.completedAt.isNull() &
              t.deletedAt.isNull()))
        .get();
    expect(open.length, 1);
    expect(open.single.id, keeper.id);
    // Nothing logged under the stray is orphaned by its removal.
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId)))
        .getSingle();
    expect(workout.cycleId, keeper.id);
    // And running it again on a healthy database does nothing.
    expect(await repo.healDuplicateOpenCycles(), 0);
  });

  test('a second session cannot be opened while one is running', () async {
    final regime = await activeRegime();
    final push = await sessionNamed('Push 1');
    final pull = await sessionNamed('Pull 1');

    final running =
        await repo.startWorkout(regimeId: regime.id, sessionId: push.id);
    // The same session again is the double tap, and hands back the same log.
    expect(
      await repo.startWorkout(regimeId: regime.id, sessionId: push.id),
      running,
    );
    // A different one would be a second workout in progress, and `openWorkout`
    // only ever returns the newest — the older would be unreachable.
    expect(
      () => repo.startWorkout(regimeId: regime.id, sessionId: pull.id),
      throwsA(isA<StateError>()),
    );

    final open = await (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.inProgress) &
              t.deletedAt.isNull()))
        .get();
    expect(open.length, 1);
  });

  test('unticking a set takes its completion time with it', () async {
    final regime = await activeRegime();
    final session = await sessionNamed('Push 1');
    final workoutId =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    final set = (await repo.workoutDetail(workoutId))!.entries.first.sets.first;

    await repo.updateSet(set.id,
        weight: const Value(60), reps: const Value(8), isDone: const Value(true));
    expect(
      (await (db.select(db.setLogs)..where((t) => t.id.equals(set.id)))
              .getSingle())
          .completedAt,
      isNotNull,
    );

    await repo.updateSet(set.id, isDone: const Value(false));
    final after =
        await (db.select(db.setLogs)..where((t) => t.id.equals(set.id)))
            .getSingle();
    expect(after.isDone, isFalse);
    expect(after.completedAt, isNull);
  });
}
