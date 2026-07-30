import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/prefill.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app ships with no programme, so tests build one the same way the user
/// does: starter catalog, then a template.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

void main() {
  late AppDatabase db;
  late TrainingRepository repo;

  setUpAll(() {
    // One test opens a second database to stand in for a fresh install.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  Future<Session> sessionNamed(String name) async {
    return (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();
  }

  Future<Regime> activeRegime() async {
    return (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
        .getSingle();
  }

  test('a fresh database has a catalog but no programme of its own', () async {
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);

    await ensureStarterCatalog(fresh);

    expect((await fresh.select(fresh.exercises).get()).length, greaterThan(20));
    expect(await fresh.select(fresh.regimes).get(), isEmpty);
    expect(await fresh.select(fresh.sessions).get(), isEmpty);
  });

  test('seeding the catalog twice does not duplicate it', () async {
    final before = (await db.select(db.exercises).get()).length;
    await ensureStarterCatalog(db);
    expect((await db.select(db.exercises).get()).length, before);
  });

  test('a template writes an ordinary, editable regime', () async {
    final regime = await activeRegime();
    expect(regime.name, ppl.name);

    final sessions = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    expect(sessions.map((s) => s.name),
        ppl.sessions.map((s) => s.name).toList());

    // Renaming a session is a plain update; nothing marks it as template-owned.
    await (db.update(db.sessions)..where((t) => t.id.equals(sessions.first.id)))
        .write(const SessionsCompanion(name: Value('Chest day')));
    expect((await sessionNamed('Chest day')).orderIndex, 0);
  });

  test('a second template reuses catalog rows instead of duplicating them',
      () async {
    final before = (await db.select(db.exercises).get()).length;
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'upper_lower'),
    );

    expect((await db.select(db.exercises).get()).length, before);
    expect((await db.select(db.regimes).get()).length, 2);
    // Creating it active leaves exactly one active regime.
    final active = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true)))
        .get();
    expect(active, hasLength(1));
    expect(active.single.name, 'Upper / Lower');
  });

  test('renaming a starter exercise does not duplicate it on the next template',
      () async {
    // Templates used to look catalog rows up by name, so a renamed starter
    // came back as a second row under its old name — two entries in the picker
    // that nothing can tell apart.
    // Upper / Lower opens with barbell_bench, so renaming that row is what the
    // template has to survive.
    final bench = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Barbell Bench Press')))
        .getSingle();
    expect(bench.starterKey, 'barbell_bench');
    await (db.update(db.exercises)..where((t) => t.id.equals(bench.id)))
        .write(const ExercisesCompanion(name: Value('Comp bench')));

    final before = (await db.select(db.exercises).get()).length;
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'upper_lower'),
    );

    expect((await db.select(db.exercises).get()).length, before);
    expect(
      await (db.select(db.exercises)
            ..where((t) => t.name.equals('Barbell Bench Press')))
          .get(),
      isEmpty,
      reason: 'the renamed row was reused, not duplicated under its old name',
    );
  });

  test('starting a workout snapshots the template and creates set rows',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);

    expect(detail, isNotNull);
    expect(detail!.session!.name, 'Push 1');
    expect(detail.entries.length, ppl.sessions.first.slots.length);
    expect(detail.entries.first.exercise.name, 'Incline DB Press');
    expect(detail.entries.first.sets.length, 3);
    expect(detail.workout.status, WorkoutStatus.inProgress);
  });

  test('updateSet persists weight and reps', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    final set = detail!.entries.first.sets.first;

    await repo.updateSet(set.id, weight: const Value(22.5));
    await repo.updateSet(set.id, reps: const Value(12));
    await repo.updateSet(set.id, isDone: const Value(true));

    final reloaded = await repo.workoutDetail(id);
    final saved = reloaded!.entries.first.sets.first;

    expect(saved.weight, 22.5);
    expect(saved.reps, 12);
    expect(saved.isDone, isTrue);
    expect(saved.completedAt, isNotNull);
  });

  test('a completed workout becomes next week\'s prefill for the same session',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    final first =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    var detail = await repo.workoutDetail(first);
    for (final set in detail!.entries.first.sets) {
      await repo.updateSet(
        set.id,
        weight: const Value(22.5),
        reps: const Value(8),
        isDone: const Value(true),
      );
    }
    await repo.completeWorkout(first);

    final second =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    detail = await repo.workoutDetail(second);
    final exerciseId = detail!.entries.first.exercise.id;

    final past = await repo.pastPerformances(exerciseId, excludeWorkoutId: second);
    final prefill = resolvePrefill(candidates: past, sessionId: push1.id);

    expect(prefill.source, PrefillSource.sameSession);
    expect(prefill.sets.length, 3);
    expect(prefill.sets.first.weight, 22.5);
    expect(prefill.sets.first.reps, 8);
  });

  test('Push 2 does not inherit Push 1 numbers for the same exercise', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final push2 = await sessionNamed('Push 2');

    // Push 1: incline press at 22.5.
    final w1 = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    var detail = await repo.workoutDetail(w1);
    final incline = detail!.entries
        .firstWhere((e) => e.exercise.name == 'Incline DB Press');
    for (final set in incline.sets) {
      await repo.updateSet(set.id,
          weight: const Value(22.5), reps: const Value(8), isDone: const Value(true));
    }
    await repo.completeWorkout(w1);

    // Push 2: same exercise, deliberately lighter.
    final w2 = await repo.startWorkout(regimeId: regime.id, sessionId: push2.id);
    detail = await repo.workoutDetail(w2);
    final incline2 = detail!.entries
        .firstWhere((e) => e.exercise.name == 'Incline DB Press');
    for (final set in incline2.sets) {
      await repo.updateSet(set.id,
          weight: const Value(20), reps: const Value(12), isDone: const Value(true));
    }
    await repo.completeWorkout(w2);

    // Opening Push 1 again must suggest 22.5, not the more recent 20.
    final w3 = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final past = await repo.pastPerformances(incline.exercise.id,
        excludeWorkoutId: w3);
    final forPush1 = resolvePrefill(candidates: past, sessionId: push1.id);
    final forPush2 = resolvePrefill(candidates: past, sessionId: push2.id);

    expect(forPush1.sets.first.weight, 22.5);
    expect(forPush1.source, PrefillSource.sameSession);
    expect(forPush2.sets.first.weight, 20);
    expect(forPush2.source, PrefillSource.sameSession);
  });

  test('completing a workout drops the empty set rows nobody filled in',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    final first = detail!.entries.first.sets.first;
    await repo.updateSet(first.id,
        weight: const Value(22.5), reps: const Value(8), isDone: const Value(true));

    await repo.completeWorkout(id);

    final reloaded = await repo.workoutDetail(id);
    final allSets = reloaded!.entries.expand((e) => e.sets).toList();
    expect(allSets.length, 1);
    expect(allSets.single.weight, 22.5);
  });

  test('the cycle advances only when every session has been trained', () async {
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    for (var i = 0; i < sessions.length; i++) {
      final status = await repo.cycleStatus(regime.id);
      expect(status.cycleIndex, 1);
      expect(status.done, i);
      expect(status.nextSessionId, sessions[i].id);

      final id =
          await repo.startWorkout(regimeId: regime.id, sessionId: sessions[i].id);
      final detail = await repo.workoutDetail(id);
      final set = detail!.entries.first.sets.first;
      await repo.updateSet(set.id,
          weight: const Value(20), reps: const Value(8), isDone: const Value(true));
      await repo.completeWorkout(id);
    }

    // Sixth completion closes cycle 1 and opens cycle 2.
    final status = await repo.cycleStatus(regime.id);
    expect(status.cycleIndex, 2);
    expect(status.done, 0);
    expect(status.nextSessionId, sessions.first.id);
  });

  test('the deload cycle arrives after the configured number of cycles',
      () async {
    final regime = await activeRegime();
    // Shorten the interval so the test is not six cycles long.
    await (db.update(db.regimes)..where((t) => t.id.equals(regime.id)))
        .write(const RegimesCompanion(deloadAfterCycles: Value(2)));

    final sessions = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    Future<void> runCycle() async {
      for (final s in sessions) {
        final id = await repo.startWorkout(regimeId: regime.id, sessionId: s.id);
        final detail = await repo.workoutDetail(id);
        final set = detail!.entries.first.sets.first;
        await repo.updateSet(set.id,
            weight: const Value(20), reps: const Value(8), isDone: const Value(true));
        await repo.completeWorkout(id);
      }
    }

    expect((await repo.cycleStatus(regime.id)).isDeload, isFalse);
    await runCycle();
    expect((await repo.cycleStatus(regime.id)).isDeload, isFalse);
    await runCycle();

    final third = await repo.cycleStatus(regime.id);
    expect(third.cycleIndex, 3);
    expect(third.isDeload, isTrue);
  });

  test('closing a cycle early skips what is left and counts towards the deload',
      () async {
    // The escape hatch for "I'm not training Leg 2 this round". Without it a
    // permanently skipped session stalls the programme: the cycle never
    // closes, the index never moves, and the deload never arrives.
    final regime = await activeRegime();
    await (db.update(db.regimes)..where((t) => t.id.equals(regime.id)))
        .write(const RegimesCompanion(deloadAfterCycles: Value(1)));

    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);
    final set = detail!.entries.first.sets.first;
    await repo.updateSet(set.id,
        weight: const Value(20), reps: const Value(8), isDone: const Value(true));
    await repo.completeWorkout(id);

    final before = await repo.cycleStatus(regime.id);
    expect(before.cycleIndex, 1);
    expect(before.remainingSessionIds, isNotEmpty);

    await repo.advanceCycle(regime.id);

    final after = await repo.cycleStatus(regime.id);
    expect(after.cycleIndex, 2);
    expect(after.done, 0);
    // The skipped cycle still counted, so the deload lands on schedule rather
    // than never.
    expect(after.isDeload, isTrue);
  });

  test('a forced deload cycle does not scale an already light week', () async {
    // 80% of 80% is 64%. Reachable only now that a deload can be forced two
    // cycles running from the regime screen.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    Future<void> forceDeload() async {
      final cycle = await repo.ensureOpenCycle(regime.id);
      await repo.setCycleDeload(cycle.id, true);
    }

    // The slot's only history is itself a light week.
    await forceDeload();
    final first =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(first);
    for (final s in detail!.entries.first.sets) {
      await repo.updateSet(s.id,
          weight: const Value(18), reps: const Value(8), isDone: const Value(true));
    }
    await repo.completeWorkout(first);

    // A second deload back to back — only reachable because the override
    // exists, which is exactly why the guard had to land with it.
    await forceDeload();
    final exerciseId = detail.entries.first.exercise.id;
    final past = await repo.pastPerformances(exerciseId);
    final prefill = resolvePrefill(
      candidates: past,
      sessionId: push1.id,
      targetIsDeload: true,
    );

    expect(prefill.source, PrefillSource.sameSessionDeload);
    expect(prefill.deloadApplied, isFalse);
    expect(prefill.sets.first.weight, 18); // not 14.4
  });

  test('a deload workout prefills fewer sets at a lighter load', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    final first =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    var detail = await repo.workoutDetail(first);
    for (final set in detail!.entries.first.sets) {
      await repo.updateSet(set.id,
          weight: const Value(22.5), reps: const Value(8), isDone: const Value(true));
    }
    await repo.completeWorkout(first);

    // Force the open cycle into deload.
    final cycle = await repo.ensureOpenCycle(regime.id);
    await repo.setCycleDeload(cycle.id, true);

    final second =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    detail = await repo.workoutDetail(second);

    expect(detail!.workout.isDeload, isTrue);
    // 3 target sets − 1 = 2.
    expect(detail.entries.first.sets.length, 2);

    final past = await repo.pastPerformances(detail.entries.first.exercise.id,
        excludeWorkoutId: second);
    final prefill = resolvePrefill(
      candidates: past,
      sessionId: push1.id,
      targetIsDeload: true,
    );
    expect(prefill.sets.length, 2);
    expect(prefill.sets.first.weight, 18); // 22.5 × 80%
  });

  test('swapping an exercise keeps its place in the workout', () async {
    // A swap is a substitution, not a delete plus an append: the page you are
    // standing on must not jump to the end of the session mid-set.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final before = await repo.workoutDetail(id);
    final second = before!.entries[1];
    final replacement = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Cable Crossover')))
        .getSingle();

    await repo.replaceExerciseInWorkout(
      second.workoutExercise.id,
      replacement.id,
    );

    final after = await repo.workoutDetail(id);
    expect(after!.entries.length, before.entries.length);
    expect(after.entries[1].exercise.id, replacement.id);
    expect(
      after.entries[1].workoutExercise.targetSets,
      second.workoutExercise.targetSets,
    );
    // Everything else stayed where it was.
    expect(
      after.entries.map((e) => e.exercise.id).skip(2),
      before.entries.map((e) => e.exercise.id).skip(2),
    );
  });

  test('an exercise added mid-session knows its own history', () async {
    // Resolving prefill once when the log opened meant an exercise added at
    // 19:40 read "first time" with a year behind it, and a set typed with only
    // reps was stored against a null weight.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final pull1 = await sessionNamed('Pull 1');

    // Train an exercise that is not in Push 1, so it can be added later.
    final rows = await repo.startWorkout(regimeId: regime.id, sessionId: pull1.id);
    final rowDetail = await repo.workoutDetail(rows);
    final rowEntry = rowDetail!.entries.first;
    for (final s in rowEntry.sets) {
      await repo.updateSet(s.id,
          weight: const Value(60), reps: const Value(10), isDone: const Value(true));
    }
    await repo.completeWorkout(rows);

    final push = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    await repo.addExerciseToWorkout(push, rowEntry.exercise.id);

    final prefill = await repo.prefillForWorkout(
      workoutId: push,
      exerciseId: rowEntry.exercise.id,
    );
    expect(prefill.source, PrefillSource.otherSession);
    expect(prefill.sets.first.weight, 60);

    // And the rows it arrived with mirror that shape rather than a flat three.
    final detail = await repo.workoutDetail(push);
    final added = detail!.entries
        .firstWhere((e) => e.exercise.id == rowEntry.exercise.id);
    expect(added.sets.length, prefill.sets.length);
  });

  test('a logged day can be moved to the date it was actually trained',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    await repo.completeWorkout(id);

    final before = await repo.workoutDetail(id);
    final monday = DateTime.now().subtract(const Duration(days: 2));
    await repo.setWorkoutDate(id, monday);

    final after = await repo.workoutDetail(id);
    expect(after!.workout.dayKey, dayKeyOf(monday));
    // History pages on startedAt, so it has to follow the day key or a row
    // sorts by one date and displays another.
    expect(after.workout.startedAt, lessThan(before!.workout.startedAt));
    // The session's own duration is untouched by the move.
    expect(
      after.workout.endedAt! - after.workout.startedAt,
      before.workout.endedAt! - before.workout.startedAt,
    );
  });

  test('a session can be logged for a past date', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final wednesday = DateTime.now().subtract(const Duration(days: 3));

    final id = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: push1.id,
      at: wednesday,
    );

    final detail = await repo.workoutDetail(id);
    expect(detail!.workout.dayKey, dayKeyOf(wednesday));
    expect(
      DateTime.fromMillisecondsSinceEpoch(detail.workout.startedAt).day,
      wednesday.day,
    );
  });

  test('workout notes can be written and cleared', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    await repo.setWorkoutNotes(id, '  slept badly, everything felt heavy  ');
    var detail = await repo.workoutDetail(id);
    expect(detail!.workout.notes, 'slept badly, everything felt heavy');

    await repo.setWorkoutNotes(id, '   ');
    detail = await repo.workoutDetail(id);
    expect(detail!.workout.notes, isNull);
  });

  test('a bodyweight entry can be corrected and deleted', () async {
    final day = DateTime.now().subtract(const Duration(days: 1));
    await repo.logBodyweight(day, 81.4);
    expect((await repo.bodyweightSeries()).single.weightKg, 81.4);

    // Editing is a re-log: the table is keyed by day.
    await repo.logBodyweight(day, 79.9);
    expect(await repo.bodyweightSeries(), hasLength(1));
    expect((await repo.bodyweightSeries()).single.weightKg, 79.9);

    await repo.deleteBodyweight(dayKeyOf(day));
    expect(await repo.bodyweightSeries(), isEmpty);
  });

  test('the same-session lookup has no horizon', () async {
    // Fan one movement across many training days and the slot you care about
    // can fall out of a fixed candidate window, dropping prefill to another
    // session — labelled honestly, but not the number you wanted.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final push2 = await sessionNamed('Push 2');

    final firstPush1 =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(firstPush1);
    final exercise = detail!.entries.first.exercise;
    for (final s in detail.entries.first.sets) {
      await repo.updateSet(s.id,
          weight: const Value(42.5), reps: const Value(6), isDone: const Value(true));
    }
    await repo.completeWorkout(firstPush1);

    // Bury it under a pile of performances in another session.
    for (var i = 0; i < 8; i++) {
      final w = await repo.startWorkout(regimeId: regime.id, sessionId: push2.id);
      final d = await repo.workoutDetail(w);
      final entry =
          d!.entries.firstWhere((e) => e.exercise.id == exercise.id);
      for (final s in entry.sets) {
        await repo.updateSet(s.id,
            weight: const Value(20), reps: const Value(12), isDone: const Value(true));
      }
      await repo.completeWorkout(w);
    }

    // A window of 3 cannot reach the Push 1 performance on recency alone.
    final candidates = await repo.pastPerformances(
      exercise.id,
      limit: 3,
      sessionId: push1.id,
    );
    final prefill =
        resolvePrefill(candidates: candidates, sessionId: push1.id);

    expect(prefill.source, PrefillSource.sameSession);
    expect(prefill.sets.first.weight, 42.5);
  });

  test('a skipped slot is not counted as a session trained', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);
    final entry = detail!.entries.first;
    // Two sets in, then the shoulder says no.
    await repo.updateSet(entry.sets.first.id,
        weight: const Value(22.5), reps: const Value(8), isDone: const Value(true));
    await repo.setSkipReason(entry.workoutExercise.id, SkipReason.injury);
    await repo.completeWorkout(id);

    final index = await repo.exercisesWithHistory();
    expect(
      index.where((e) => e.exercise.id == entry.exercise.id),
      isEmpty,
      reason: 'a skipped slot did not happen, so it is not a session trained',
    );

    // But the sets that were logged before the skip did happen, and stay
    // visible to everything downstream.
    final past = await repo.pastPerformances(entry.exercise.id);
    expect(past.single.skipReason, SkipReason.injury);
    expect(past.single.sets.single.weight, 22.5);
  });

  test('deleting the last untrained session closes the cycle', () async {
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    for (final s in sessions.take(sessions.length - 1)) {
      final id = await repo.startWorkout(regimeId: regime.id, sessionId: s.id);
      await repo.completeWorkout(id);
    }

    final before = await repo.cycleStatus(regime.id);
    expect(before.cycleIndex, 1);
    expect(before.isComplete, isFalse);

    // Delete the one day still owed: the cycle is now satisfied.
    await (db.update(db.sessions)..where((t) => t.id.equals(sessions.last.id)))
        .write(SessionsCompanion(deletedAt: Value(nowMs())));
    expect(await repo.closeCycleIfSatisfied(regime.id), isTrue);

    final after = await repo.cycleStatus(regime.id);
    expect(after.cycleIndex, 2);
    expect(after.done, 0);
  });

  test('a running workout can be identified without its regime being active',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final owner = await repo.workoutOwner(id);
    expect(owner!.sessionName, 'Push 1');
    expect(owner.regimeId, regime.id);
    expect(owner.regimeName, regime.name);
  });

  test('finishing tombstones the untouched sets rather than deleting them',
      () async {
    // A row deleted outright has no deleted_at to push, so the first pull from
    // another device would resurrect it once sync lands.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    final entry = detail!.entries.first;
    await repo.updateSet(entry.sets.first.id,
        weight: const Value(22.5), reps: const Value(8), isDone: const Value(true));

    await repo.completeWorkout(id);

    // The blanks are gone from every read path…
    final after = await repo.workoutDetail(id);
    expect(after!.entries.first.sets, hasLength(1));

    // …but the rows are still there, carrying a tombstone to push.
    final raw = await (db.select(db.setLogs)
          ..where((t) => t.workoutExerciseId.equals(entry.workoutExercise.id)))
        .get();
    expect(raw.length, entry.sets.length);
    final dropped = raw.where((s) => !s.isDone);
    expect(dropped, isNotEmpty);
    for (final s in dropped) {
      expect(s.deletedAt, isNotNull);
      expect(s.dirty, isTrue);
    }
  });

  test('logged sets are counted before a load mode is reinterpreted', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    final entry = detail!.entries.first;
    for (final s in entry.sets.take(2)) {
      await repo.updateSet(s.id,
          weight: const Value(22.5), reps: const Value(8), isDone: const Value(true));
    }
    await repo.completeWorkout(id);

    expect(await repo.loggedSetCount(entry.exercise.id), 2);
  });

  test('rest is recorded, and its target is remembered per exercise', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    final entry = detail!.entries.first;

    // Two minutes until something says otherwise.
    expect(
      await repo.restTargetFor(
          exerciseId: entry.exercise.id, sessionId: push1.id),
      120,
    );

    await repo.setRestTarget(
      exerciseId: entry.exercise.id,
      sessionId: push1.id,
      seconds: 180,
    );
    expect(
      await repo.restTargetFor(
          exerciseId: entry.exercise.id, sessionId: push1.id),
      180,
      reason: 'a heavy compound should not forget it wants three minutes',
    );

    // The rest a set actually got is stored with the set.
    await repo.updateSet(entry.sets.first.id,
        weight: const Value(60),
        reps: const Value(5),
        isDone: const Value(true),
        restSeconds: const Value(174));
    final reloaded = await repo.workoutDetail(id);
    expect(reloaded!.entries.first.sets.first.restSeconds, 174);

    // A second exercise keeps its own number rather than inheriting.
    final other = detail.entries[1];
    expect(
      await repo.restTargetFor(
          exerciseId: other.exercise.id, sessionId: push1.id),
      120,
    );
  });

  test('reordering a workout does not touch the session template', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    final ids = detail!.entries.map((e) => e.workoutExercise.id).toList();
    await repo.reorderWorkoutExercises([ids[1], ids[0], ...ids.skip(2)]);

    final reordered = await repo.workoutDetail(id);
    expect(reordered!.entries.first.exercise.name, 'Flat DB Bench Press');

    final template = await (db.select(db.sessionExercises).join([
      innerJoin(db.exercises,
          db.exercises.id.equalsExp(db.sessionExercises.exerciseId)),
    ])
          ..where(db.sessionExercises.sessionId.equals(push1.id))
          ..orderBy([OrderingTerm(expression: db.sessionExercises.orderIndex)]))
        .get();
    expect(template.first.readTable(db.exercises).name, 'Incline DB Press');
  });

  // ── History paging ──────────────────────────────────────────────────────

  /// Writes [count] finished workouts one day apart, oldest last, without
  /// going through the logging flow — enough history to page through.
  Future<void> writeHistory(int count) async {
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    final base = DateTime(2026, 1, 1);

    for (var i = 0; i < count; i++) {
      final date = base.add(Duration(days: i));
      await db.into(db.workouts).insert(
            WorkoutsCompanion.insert(
              id: Value(newId()),
              regimeId: regime.id,
              sessionId: Value(sessions[i % sessions.length].id),
              dayKey: dayKeyOf(date),
              startedAt: Value(date.millisecondsSinceEpoch),
              endedAt: Value(date
                  .add(const Duration(minutes: 61))
                  .millisecondsSinceEpoch),
              status: const Value(WorkoutStatus.completed),
            ),
          );
    }
  }

  test('the history feed pages backwards without gaps or repeats', () async {
    await writeHistory(25);

    final seen = <String>[];
    var page = await repo.workoutFeed(limit: 10);
    while (page.isNotEmpty) {
      seen.addAll(page.map((s) => s.workout.id));
      page = await repo.workoutFeed(limit: 10, olderThan: page.last.cursor);
    }

    expect(seen, hasLength(25));
    expect(seen.toSet(), hasLength(25));

    // Newest first, all the way down.
    final ordered = await (db.select(db.workouts)
          ..orderBy([
            (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)
          ]))
        .get();
    expect(seen, ordered.map((w) => w.id).toList());
  });

  test('a workout logged after the first page does not shift the second',
      () async {
    await writeHistory(25);

    final first = await repo.workoutFeed(limit: 10);
    // Finishing a session mid-scroll prepends a row; keyset paging must not
    // let that push an unseen row past the cursor.
    await writeHistory(1);

    final second =
        await repo.workoutFeed(limit: 10, olderThan: first.last.cursor);
    expect(
      second.map((s) => s.workout.id).toSet().intersection(
            first.map((s) => s.workout.id).toSet(),
          ),
      isEmpty,
    );
  });

  test('feed rows carry the counts the list shows', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    for (final set in detail!.entries.first.sets) {
      await repo.updateSet(set.id,
          weight: const Value(22.5),
          reps: const Value(8),
          isDone: const Value(true));
    }
    await repo.setSkipReason(
        detail.entries.last.workoutExercise.id, SkipReason.shortOnTime);
    await repo.completeWorkout(id);

    final feed = await repo.workoutFeed();
    expect(feed, hasLength(1));
    expect(feed.single.sessionName, 'Push 1');
    expect(feed.single.exerciseCount, ppl.sessions.first.slots.length);
    expect(feed.single.setCount, 3);
    expect(feed.single.skippedCount, 1);
    expect(feed.single.durationMinutes, isNotNull);
  });

  test('a session filter narrows the feed to that session', () async {
    await writeHistory(12);
    final push1 = await sessionNamed('Push 1');

    final all = await repo.workoutFeed(limit: 50);
    final mine = await repo.workoutFeed(limit: 50, sessionId: push1.id);

    expect(all, hasLength(12));
    expect(mine, hasLength(2));
    expect(mine.every((s) => s.workout.sessionId == push1.id), isTrue);
  });

  test('exercise history pages, newest first, keeping session identity',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final push2 = await sessionNamed('Push 2');

    Future<void> log(Session session, double weight) async {
      final id =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      final detail = await repo.workoutDetail(id);
      final incline = detail!.entries
          .firstWhere((e) => e.exercise.name == 'Incline DB Press');
      for (final set in incline.sets) {
        await repo.updateSet(set.id,
            weight: Value(weight),
            reps: const Value(8),
            isDone: const Value(true));
      }
      await repo.completeWorkout(id);
    }

    await log(push1, 22.5);
    await log(push2, 20);

    final incline = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Incline DB Press')))
        .getSingle();

    final firstPage = await repo.exerciseHistoryPage(incline.id, limit: 1);
    expect(firstPage, hasLength(1));
    expect(firstPage.single.sessionName, 'Push 2');
    expect(firstPage.single.sets.first.weight, 20);

    final secondPage = await repo.exerciseHistoryPage(
      incline.id,
      limit: 1,
      olderThan: firstPage.single.cursor,
    );
    expect(secondPage.single.sessionName, 'Push 1');
    expect(secondPage.single.sets.first.weight, 22.5);
    // Dumbbells: 22.5 in each hand scores as 45kg of load.
    expect(secondPage.single.topSetLoad, 45);

    final third = await repo.exerciseHistoryPage(
      incline.id,
      limit: 1,
      olderThan: secondPage.single.cursor,
    );
    expect(third, isEmpty);
  });

  test('the exercise index only lists what has actually been trained',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);
    final first = detail!.entries.first;
    for (final set in first.sets) {
      await repo.updateSet(set.id,
          weight: const Value(20),
          reps: const Value(8),
          isDone: const Value(true));
    }
    await repo.completeWorkout(id);

    final index = await repo.exercisesWithHistory();
    final names = index.map((e) => e.exercise.name).toSet();

    // Every slot in the session was performed, even the ones left blank …
    expect(names, contains(first.exercise.name));
    expect(index, hasLength(ppl.sessions.first.slots.length));
    // … and nothing that was never opened is in there.
    expect(names, isNot(contains('Deadlift')));
    expect(index.first.timesPerformed, 1);
  });

  /// Logs one session end to end and returns its workout id.
  Future<String> logSession(Session session, {double weight = 20}) async {
    final regime = await activeRegime();
    final id =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    final detail = await repo.workoutDetail(id);
    final set = detail!.entries.first.sets.first;
    await repo.updateSet(set.id,
        weight: Value(weight), reps: const Value(8), isDone: const Value(true));
    await repo.completeWorkout(id);
    return id;
  }

  test('starting the same session twice returns the workout already running',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    final first =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final second =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    expect(second, first);
    final open = await (db.select(db.workouts)
          ..where((t) => t.status.equalsValue(WorkoutStatus.inProgress)))
        .get();
    expect(open, hasLength(1));
  });

  test('deleting a workout removes it from every history view', () async {
    final push1 = await sessionNamed('Push 1');
    final id = await logSession(push1);

    expect(await repo.workoutFeed(), hasLength(1));
    await repo.deleteWorkout(id);

    expect(await repo.workoutFeed(), isEmpty);
    expect(await repo.workoutDetail(id), isNull);
    expect(await repo.exercisesWithHistory(), isEmpty);
    expect(await repo.sessionsWithHistory(), isEmpty);

    // Prefill must forget it too, or next week suggests numbers from a day
    // that no longer exists.
    final detail = await repo.workoutDetail(id);
    expect(detail, isNull);
    final incline = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Incline Dumbbell Press')))
        .getSingleOrNull();
    if (incline != null) {
      expect(await repo.pastPerformances(incline.id), isEmpty);
    }
  });

  test('deleting the workout that closed a cycle reopens it', () async {
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    String? last;
    for (final session in sessions) {
      last = await logSession(session);
    }

    // Every session trained: cycle 1 closed and cycle 2 opened.
    expect((await repo.cycleStatus(regime.id)).cycleIndex, 2);

    await repo.deleteWorkout(last!);

    final status = await repo.cycleStatus(regime.id);
    expect(status.cycleIndex, 1, reason: 'the cycle was never finished');
    expect(status.done, sessions.length - 1);
    expect(status.nextSessionId, sessions.last.id);
  });

  test('deleting an ordinary workout leaves the cycle alone', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final pull1 = await sessionNamed('Pull 1');

    await logSession(push1);
    final second = await logSession(pull1);
    await repo.deleteWorkout(second);

    final status = await repo.cycleStatus(regime.id);
    expect(status.cycleIndex, 1);
    expect(status.completedSessionIds, {push1.id});
  });

  test('the table lists sessions from older regimes too', () async {
    final push1 = await sessionNamed('Push 1');
    await logSession(push1);

    // Switching programmes must not hide what was trained under the old one.
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'upper_lower'),
    );

    final sessions = await repo.sessionsWithHistory();
    expect(sessions.map((s) => s.id), [push1.id]);
  });
}
