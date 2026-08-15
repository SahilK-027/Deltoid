import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/prefill.dart';
import 'package:deltoid/domain/session_diff.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app ships with no programme, so tests build one the same way the user
/// does: starter catalog, then a template.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late RegimeRepository regimes;

  setUpAll(() {
    // One test opens a second database to stand in for a fresh install.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    regimes = RegimeRepository(db);
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
      final status = (await repo.cycleStatus(regime.id))!;
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
    final status = (await repo.cycleStatus(regime.id))!;
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

    expect(((await repo.cycleStatus(regime.id))!).isDeload, isFalse);
    await runCycle();
    expect(((await repo.cycleStatus(regime.id))!).isDeload, isFalse);
    await runCycle();

    final third = (await repo.cycleStatus(regime.id))!;
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

    final before = (await repo.cycleStatus(regime.id))!;
    expect(before.cycleIndex, 1);
    expect(before.remainingSessionIds, isNotEmpty);

    await repo.advanceCycle(regime.id);

    final after = (await repo.cycleStatus(regime.id))!;
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
      final cycle = (await repo.ensureOpenCycle(regime.id))!;
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
    final cycle = (await repo.ensureOpenCycle(regime.id))!;
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

  test('moving a logged day moves it into the cycle that covers the new date',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    // Cycle 1 runs, then closes. Cycle 2 opens behind it.
    final first =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    await repo.completeWorkout(first);
    final cycleOne = (await repo.workoutDetail(first))!.workout.cycleId;
    await repo.advanceCycle(regime.id);

    final second =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    await repo.completeWorkout(second);
    final cycleTwo = (await repo.workoutDetail(second))!.workout.cycleId;
    expect(cycleTwo, isNot(cycleOne));

    // Both cycles were minted in the same second here, so cycle 1 is given the
    // window a month of training would have left it: opened five weeks ago,
    // closed a week later.
    final now = DateTime.now();
    final opened = now.subtract(const Duration(days: 35));
    final closed = now.subtract(const Duration(days: 28));
    await (db.update(db.cycles)..where((t) => t.id.equals(cycleOne!))).write(
      CyclesCompanion(
        startedAt: Value(opened.millisecondsSinceEpoch),
        completedAt: Value(closed.millisecondsSinceEpoch),
      ),
    );

    // Re-dated into that window. `startWorkout` would have filed it under
    // cycle 1 had it been backfilled; moving it has to agree.
    await repo.setWorkoutDate(second, now.subtract(const Duration(days: 31)));

    final moved = await repo.workoutDetail(second);
    expect(moved!.workout.cycleId, cycleOne);
  });

  test('a day dragged out of a cycle it completed reopens that cycle',
      () async {
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    // Every session of the cycle trained, so the cycle closes on the last one.
    String? last;
    for (final session in sessions) {
      last = await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      await repo.completeWorkout(last);
    }
    final closed = (await repo.workoutDetail(last!))!.workout.cycleId;
    final before =
        await (db.select(db.cycles)..where((t) => t.id.equals(closed!)))
            .getSingle();
    expect(before.completedAt, isNotNull);

    // That day is dragged back to before the cycle began, so the cycle is a
    // session short again. A cycle counted for work that did not happen in it
    // lands the deload early.
    await repo.setWorkoutDate(
      last,
      DateTime.fromMillisecondsSinceEpoch(before.startedAt)
          .subtract(const Duration(days: 30)),
    );

    final after =
        await (db.select(db.cycles)..where((t) => t.id.equals(closed!)))
            .getSingle();
    expect(after.completedAt, isNull);
  });

  test('one movement run twice in a day keeps both slots as last time',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final opened = (await repo.workoutDetail(id))!;
    final first = opened.entries.first;

    // The same movement again, later in the day — a second pass, which the
    // picker marks but does not refuse.
    final secondSlot =
        await repo.addExerciseToWorkout(id, first.exercise.id);

    await repo.updateSet(
      first.sets.first.id,
      weight: const Value(60),
      reps: const Value(8),
      isDone: const Value(true),
    );
    final withBoth = (await repo.workoutDetail(id))!;
    final second = withBoth.entries
        .firstWhere((e) => e.workoutExercise.id == secondSlot);
    await repo.updateSet(
      second.sets.first.id,
      weight: const Value(40),
      reps: const Value(15),
      isDone: const Value(true),
    );
    await repo.completeWorkout(id);

    // Both slots survive the merge. Keyed on the workout, one of the two was
    // dropped before prefill ever saw it.
    final past = await repo.pastPerformances(
      first.exercise.id,
      sessionId: push1.id,
    );
    expect(past, hasLength(2));
    expect(
      past.map((p) => p.sets.first.weight),
      containsAll(<double>[60, 40]),
    );

    // And last time is the slot the session template opened with, not the one
    // improvised after it.
    final next = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: push1.id,
      at: DateTime.now().add(const Duration(days: 1)),
    );
    final prefill = await repo.prefillForWorkout(
      workoutId: next,
      exerciseId: first.exercise.id,
    );
    expect(prefill.source, PrefillSource.sameSession);
    expect(prefill.sets.first.weight, 60);
  });

  test('the tap hands its prefill to the screen, and only once', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    // A week with real numbers behind it.
    final logged =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final first = (await repo.workoutDetail(logged))!.entries.first;
    for (final set in first.sets) {
      await repo.updateSet(
        set.id,
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );
    }
    await repo.completeWorkout(logged);

    // Starting the next one resolves prefill to shape the rows, and hands that
    // answer to the log screen rather than making it walk history again.
    final next = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: push1.id,
      at: DateTime.now().add(const Duration(days: 1)),
    );
    final handed = await repo.prefillForWorkout(
      workoutId: next,
      exerciseId: first.exercise.id,
    );
    expect(handed.source, PrefillSource.sameSession);
    expect(handed.sets.first.weight, 60);

    // Taken, not kept: the day the numbers came from is deleted, and the very
    // next ask has to notice. An accelerator that outlived its tap would go on
    // showing ghosts from a workout that no longer exists.
    await repo.deleteWorkout(logged);
    final after = await repo.prefillForWorkout(
      workoutId: next,
      exerciseId: first.exercise.id,
    );
    expect(after.hasSuggestion, isFalse);
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

  test('a backdated session joins the cycle that was open on its date',
      () async {
    // Attaching it to whatever cycle is open *now* let a three-week-old
    // backfill complete the current cycle and move the deload counter early.
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    // Cycle 1, closed a week ago.
    final firstCycle = (await repo.ensureOpenCycle(regime.id))!;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    await (db.update(db.cycles)..where((t) => t.id.equals(firstCycle.id)))
        .write(CyclesCompanion(
      startedAt: Value(
        DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch,
      ),
      completedAt: Value(weekAgo.millisecondsSinceEpoch),
    ));

    // Cycle 2 opens where the first one ended.
    final second = (await repo.ensureOpenCycle(regime.id))!;
    expect(second.id, isNot(firstCycle.id));
    await (db.update(db.cycles)..where((t) => t.id.equals(second.id))).write(
      CyclesCompanion(
        startedAt: Value(weekAgo.millisecondsSinceEpoch + 1),
      ),
    );

    // Backfilled into the closed cycle's window.
    final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
    final old = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: sessions.first.id,
      at: tenDaysAgo,
    );
    var detail = await repo.workoutDetail(old);
    expect(detail!.workout.cycleId, firstCycle.id);

    // Finishing it must not stamp a new completion onto a cycle that already
    // closed, nor close the current one on its strength.
    await repo.completeWorkout(old);
    final reread = await (db.select(db.cycles)
          ..where((t) => t.id.equals(firstCycle.id)))
        .getSingle();
    expect(reread.completedAt, weekAgo.millisecondsSinceEpoch);
    expect(((await repo.cycleStatus(regime.id))!).cycleId, second.id);

    // And today's session still lands in the open cycle.
    final today = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: sessions[1].id,
    );
    detail = await repo.workoutDetail(today);
    expect(detail!.workout.cycleId, second.id);
  });

  test('a date older than every cycle belongs to no cycle', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    (await repo.ensureOpenCycle(regime.id))!;

    final id = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: push1.id,
      at: DateTime(2016, 3, 4),
    );

    final detail = await repo.workoutDetail(id);
    expect(detail!.workout.cycleId, isNull);
    // Finishing it is a no-op for cycles rather than a crash.
    await repo.completeWorkout(id);
    expect(((await repo.cycleStatus(regime.id))!).cycleIndex, 1);
  });

  test('only one workout can be open at a time', () async {
    // openWorkout returns the newest by startedAt, so an abandoned backdated
    // log would be hidden by the next session started and become unreachable.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    expect(
      () => repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
        at: DateTime.now().subtract(const Duration(days: 2)),
      ),
      throwsA(isA<StateError>()),
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

  test("an exercise's note for the day never reaches the catalog", () async {
    // The third note level: the catalog's cue is permanent, a set's note is one
    // row, and this one belongs to this exercise on this day only. Writing it
    // through the workout's snapshot row is what keeps a bad session out of
    // every future one.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final entry = (await repo.workoutDetail(id))!.entries.first;
    expect(entry.workoutExercise.notes, isNull,
        reason: 'a fresh workout row starts with no note of its own');
    final cue = entry.exercise.notes;

    await repo.setWorkoutExerciseNotes(
      entry.workoutExercise.id,
      '  shoulder felt off  ',
    );
    var after = (await repo.workoutDetail(id))!.entries.first;
    expect(after.workoutExercise.notes, 'shoulder felt off');
    expect(after.exercise.notes, cue);

    await repo.setWorkoutExerciseNotes(entry.workoutExercise.id, '  ');
    after = (await repo.workoutDetail(id))!.entries.first;
    expect(after.workoutExercise.notes, isNull);
  });

  group('making today permanent', () {
    // Improvising mid-session changes today only — that is invariant 2 and the
    // reason a workout is a snapshot. These write the *template*, and only the
    // parts the summary screen ticked.

    Future<List<String>> slotNames(String sessionId) async {
      final refs = await repo.sessionTemplate(sessionId);
      return [for (final r in refs) r.name];
    }

    test('an added exercise joins the session, at the end', () async {
      final push1 = await sessionNamed('Push 1');
      final before = await slotNames(push1.id);
      final extra = await (db.select(db.exercises)
            ..where((t) => t.name.isNotIn(before))
            ..limit(1))
          .getSingle();

      await repo.applySessionChanges(
        sessionId: push1.id,
        changes: [
          SessionChange(
            kind: SessionChangeKind.added,
            exerciseIds: [extra.id],
            label: 'Add ${extra.name}',
          ),
        ],
      );

      expect(await slotNames(push1.id), [...before, extra.name]);
    });

    test('re-adding a movement revives its old slot, targets and all', () async {
      final push1 = await sessionNamed('Push 1');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(push1.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      final victim = slots.first;
      await regimes.updateSessionExercise(victim.id, targetSets: const Value(7));
      await regimes.removeSessionExercise(victim.id);

      await repo.applySessionChanges(
        sessionId: push1.id,
        changes: [
          SessionChange(
            kind: SessionChangeKind.added,
            exerciseIds: [victim.exerciseId],
            label: 'Add it back',
          ),
        ],
      );

      final live = await (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(push1.id) &
                t.exerciseId.equals(victim.exerciseId) &
                t.deletedAt.isNull()))
          .get();
      expect(live, hasLength(1), reason: 'no second row for the same movement');
      expect(live.single.targetSets, 7);
    });

    test('the order applied is today order, with untrained slots after it',
        () async {
      final push1 = await sessionNamed('Push 1');
      final before = await repo.sessionTemplate(push1.id);
      expect(before.length, greaterThan(2));

      // Today ran the last two first and never reached the rest.
      final reordered = [before.last.exerciseId, before[before.length - 2].exerciseId];

      await repo.applySessionChanges(
        sessionId: push1.id,
        changes: [
          SessionChange(
            kind: SessionChangeKind.reordered,
            exerciseIds: reordered,
            label: "Keep today's order",
          ),
        ],
      );

      final after = await repo.sessionTemplate(push1.id);
      expect([for (final r in after.take(2)) r.exerciseId], reordered);
      expect(after.length, before.length, reason: 'nothing was dropped');
    });

    test('a change that was not ticked is not applied', () async {
      final push1 = await sessionNamed('Push 1');
      final before = await slotNames(push1.id);

      await repo.applySessionChanges(sessionId: push1.id, changes: const []);

      expect(await slotNames(push1.id), before);
    });

    test('editing the template leaves logged workouts alone', () async {
      // Invariant 2, the one this feature is closest to breaking.
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
      final logged = [
        for (final e in (await repo.workoutDetail(id))!.entries) e.exercise.name,
      ];

      final slots = await (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(push1.id) & t.deletedAt.isNull()))
          .get();
      await repo.applySessionChanges(
        sessionId: push1.id,
        changes: [
          SessionChange(
            kind: SessionChangeKind.removed,
            exerciseIds: [slots.first.exerciseId],
            label: 'Remove it',
          ),
        ],
      );

      final after = [
        for (final e in (await repo.workoutDetail(id))!.entries) e.exercise.name,
      ];
      expect(after, logged);
    });
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

  test('two performances on one day keep their order', () async {
    // Merging the same-session and recent queries and re-sorting on dayKey
    // alone left same-day rows in map insertion order, so prefill could pick
    // the earlier of two and call it last time.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');

    final morning =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    var detail = await repo.workoutDetail(morning);
    final exerciseId = detail!.entries.first.exercise.id;
    for (final s in detail.entries.first.sets) {
      await repo.updateSet(s.id,
          weight: const Value(20), reps: const Value(10), isDone: const Value(true));
    }
    await repo.completeWorkout(morning);

    // Same day, heavier, later.
    final evening =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    detail = await repo.workoutDetail(evening);
    for (final s in detail!.entries.first.sets) {
      await repo.updateSet(s.id,
          weight: const Value(25), reps: const Value(8), isDone: const Value(true));
    }
    await repo.completeWorkout(evening);

    final candidates =
        await repo.pastPerformances(exerciseId, sessionId: push1.id);
    expect(candidates.first.workoutId, evening);

    final prefill =
        resolvePrefill(candidates: candidates, sessionId: push1.id);
    expect(prefill.sets.first.weight, 25);
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

    final before = (await repo.cycleStatus(regime.id))!;
    expect(before.cycleIndex, 1);
    expect(before.isComplete, isFalse);

    // Delete the one day still owed: the cycle is now satisfied.
    await (db.update(db.sessions)..where((t) => t.id.equals(sessions.last.id)))
        .write(SessionsCompanion(deletedAt: Value(nowMs())));
    expect(await repo.closeCycleIfSatisfied(regime.id), isTrue);

    final after = (await repo.cycleStatus(regime.id))!;
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

  test('a rest target has nowhere to live on an exercise added mid-session',
      () async {
    // The target is stored on the session slot, and an exercise added today
    // has no slot. The write matched nothing and returned quietly, so the
    // timer was simply back at 120s next week with no explanation.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final curl = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Barbell Curl')))
        .getSingle();
    await repo.addExerciseToWorkout(id, curl.id);

    expect(
      await repo.setRestTarget(
        exerciseId: curl.id,
        sessionId: push1.id,
        seconds: 90,
      ),
      isFalse,
      reason: 'there is no template slot to remember it against',
    );

    // An exercise that *is* in the template still saves.
    final detail = await repo.workoutDetail(id);
    expect(
      await repo.setRestTarget(
        exerciseId: detail!.entries.first.exercise.id,
        sessionId: push1.id,
        seconds: 90,
      ),
      isTrue,
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

  test('feed rows list the movements in the order they were done', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);
    await repo.completeWorkout(id);

    final row = (await repo.workoutFeed()).single;
    expect(
      row.exerciseNames,
      detail!.entries.map((e) => e.exercise.name).toList(),
    );
  });

  test('the history overview counts sessions and spans the days they cover',
      () async {
    expect((await repo.historyOverview()).isEmpty, isTrue);

    await writeHistory(3);
    final overview = await repo.historyOverview();

    expect(overview.sessions, 3);
    expect(overview.spansMonths, isFalse,
        reason: 'three consecutive days in January are not a span');
    expect(overview.firstDayKey, isNotNull);
    expect(overview.lastDayKey, greaterThan(overview.firstDayKey!));

    // An in-progress session is not history yet, and a deleted day stops being
    // history — the masthead must not keep counting either.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    expect((await repo.historyOverview()).sessions, 3);

    final newest = (await repo.workoutFeed()).first;
    await repo.deleteWorkout(newest.workout.id);
    final after = await repo.historyOverview();
    expect(after.sessions, 2);
    expect(after.lastDayKey, lessThan(overview.lastDayKey!));
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

  test('a deload filter narrows the feed to the light weeks', () async {
    await writeHistory(6);
    final ids = (await repo.workoutFeed(limit: 50))
        .take(2)
        .map((s) => s.workout.id)
        .toList();
    for (final id in ids) {
      await (db.update(db.workouts)..where((t) => t.id.equals(id)))
          .write(const WorkoutsCompanion(isDeload: Value(true)));
    }

    final deloads = await repo.workoutFeed(limit: 50, deloadOnly: true);
    expect(deloads.map((s) => s.workout.id).toList()..sort(), ids..sort());
  });

  test('a filtered feed still pages by keyset, without gaps or repeats',
      () async {
    // Two of every session, so a single day's filter still spans pages.
    await writeHistory(30);
    final push1 = await sessionNamed('Push 1');

    final seen = <String>[];
    var page = await repo.workoutFeed(limit: 2, sessionId: push1.id);
    while (page.isNotEmpty) {
      seen.addAll(page.map((s) => s.workout.id));
      page = await repo.workoutFeed(
        limit: 2,
        sessionId: push1.id,
        olderThan: page.last.cursor,
      );
    }

    expect(seen, hasLength(5));
    expect(seen.toSet(), hasLength(5));
  });

  test('the heatmap reads one aggregated row per day, not every workout',
      () async {
    await writeHistory(6);
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    // A second session on a day already trained, and a light week.
    final twice = (await repo.workoutFeed(limit: 50)).first;
    await db.into(db.workouts).insert(
          WorkoutsCompanion.insert(
            id: Value(newId()),
            regimeId: regime.id,
            sessionId: Value(push1.id),
            dayKey: twice.workout.dayKey,
            startedAt: Value(twice.workout.startedAt + 1),
            status: const Value(WorkoutStatus.completed),
            isDeload: const Value(true),
          ),
        );

    final days = await repo.loggedDays();

    // Seven workouts, six days.
    expect(days, hasLength(6));
    expect(days.map((d) => d.dayKey).toList(),
        [...days.map((d) => d.dayKey)]..sort());

    final shared = days.firstWhere((d) => d.dayKey == twice.workout.dayKey);
    expect(shared.workouts, 2);
    // Any workout that day being a deload makes the day one.
    expect(shared.isDeload, isTrue);
    expect(shared.anyWorkoutId, isNotEmpty);

    expect(days.where((d) => d.isDeload), hasLength(1));
  });

  test('the filter only offers days that appear in history', () async {
    await writeHistory(3);
    final logged = await repo.loggedSessions();

    // Three workouts, three of the six days trained — the other three are not
    // on offer, because picking one would return an empty list.
    expect(logged, hasLength(3));
    expect(logged.every((s) => s.workouts == 1), isTrue);
    expect(logged.every((s) => s.regimeName == ppl.name), isTrue);

    // Most recently trained first.
    final days = logged.map((s) => s.lastDayKey).toList();
    expect(days, [...days]..sort((a, b) => b.compareTo(a)));
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

  test('the progress chart is given every performance, not a recent window',
      () async {
    final push1 = await sessionNamed('Push 1');
    for (var i = 0; i < 12; i++) {
      await logSession(push1, weight: 20 + i.toDouble());
    }

    final entry = (await repo.workoutDetail(await logSession(push1)))!
        .entries
        .first;
    final exerciseId = entry.exercise.id;

    // A window is a window whatever its size: what matters is that the chart
    // does not get one. Asking for five proves the horizon is real; asking for
    // none has to come back with the lot, or the early years of a long history
    // are missing from the axis and from the year picker built off it.
    expect(await repo.pastPerformances(exerciseId, limit: 5), hasLength(5));
    expect(
      await repo.pastPerformances(exerciseId, limit: null),
      hasLength(13),
    );
    expect(await repo.exerciseProgress(exerciseId), hasLength(13));
  });

  test('the chart reads left to right in the day trained, not the day logged',
      () async {
    final push1 = await sessionNamed('Push 1');
    final first = await logSession(push1, weight: 60);
    final second = await logSession(push1, weight: 65);
    // Logged second, trained first: a session written down a week late is not
    // where `startedAt` would put it, and the chart draws calendar time.
    await repo.setWorkoutDate(
      second,
      DateTime.now().subtract(const Duration(days: 30)),
    );

    final entry = (await repo.workoutDetail(first))!.entries.first;
    final points = await repo.exerciseProgress(entry.exercise.id);

    expect(points, hasLength(2));
    expect(points.first.dayKey, lessThan(points.last.dayKey));
    // Through the slot's load mode, which is what makes these effective loads
    // rather than the numbers typed in.
    expect(points.first.topSetLoad, greaterThan(points.last.topSetLoad!));
  });

  test('a chart point knows its session and whether the week was light',
      () async {
    // The chart reads its columns by name out of a raw statement, so this is
    // the test that fails if one of them is ever renamed — a mistake that
    // otherwise compiles and only shows up on a phone.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final first = await logSession(push1, weight: 40);

    await repo.setCycleDeload(
        (await repo.cycleStatus(regime.id))!.cycleId, true);
    await logSession(push1, weight: 30);

    final entry = (await repo.workoutDetail(first))!.entries.first;
    final points = await repo.exerciseProgress(entry.exercise.id);

    expect(points, hasLength(2));
    expect(points.every((p) => p.sessionName == 'Push 1'), isTrue);
    expect(points.first.isDeload, isFalse);
    expect(points.last.isDeload, isTrue);
    expect(points.last.topSetReps, 8);
    expect(points.last.best1RM, isNotNull);
  });

  test('a set taken back is not on the chart, and an emptied day is not either',
      () async {
    final push1 = await sessionNamed('Push 1');
    final id = await logSession(push1, weight: 80);
    final entry = (await repo.workoutDetail(id))!.entries.first;

    expect(await repo.exerciseProgress(entry.exercise.id), hasLength(1));

    await repo.updateSet(entry.sets.first.id, isDone: const Value(false));
    expect(await repo.exerciseProgress(entry.exercise.id), isEmpty);
  });

  test('deleting a workout removes it from every history view', () async {
    final push1 = await sessionNamed('Push 1');
    final id = await logSession(push1);

    expect(await repo.workoutFeed(), hasLength(1));
    await repo.deleteWorkout(id);

    expect(await repo.workoutFeed(), isEmpty);
    expect(await repo.workoutDetail(id), isNull);
    expect(await repo.exercisesWithHistory(), isEmpty);

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

  /// Live snapshot rows sitting under a workout that has been tombstoned.
  ///
  /// Invisible on every screen, because each read joins the workout and filters
  /// `deletedAt` — and precisely what a first sync push would hand another
  /// device.
  Future<int> orphanedSnapshots() async {
    final rows = await (db.select(db.workoutExercises).join([
      innerJoin(
          db.workouts, db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
    ])
          ..where(db.workoutExercises.deletedAt.isNull() &
              db.workouts.deletedAt.isNotNull()))
        .get();
    return rows.length;
  }

  test('discarding a session takes its sets and snapshots with it', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    await repo.updateSet(detail!.entries.first.sets.first.id,
        weight: const Value(40), reps: const Value(8), isDone: const Value(true));

    await repo.abandonWorkout(id);

    expect(await orphanedSnapshots(), 0);
    final live = await (db.select(db.setLogs)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    expect(live, isEmpty, reason: 'no set outlives the session it was in');
  });

  test('the heal at launch clears snapshots an older build left behind',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    // Exactly what the previous `abandonWorkout` wrote: the workout row only.
    await (db.update(db.workouts)..where((t) => t.id.equals(id))).write(
      WorkoutsCompanion(
        status: const Value(WorkoutStatus.abandoned),
        deletedAt: Value(nowMs()),
      ),
    );
    expect(await orphanedSnapshots(), greaterThan(0));

    expect(await repo.healOrphanedSnapshots(), greaterThan(0));
    expect(await orphanedSnapshots(), 0);

    // Runs at every launch, so it has to be free on a database with nothing
    // wrong with it.
    expect(await repo.healOrphanedSnapshots(), 0);
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
    expect(((await repo.cycleStatus(regime.id))!).cycleIndex, 2);

    await repo.deleteWorkout(last!);

    final status = (await repo.cycleStatus(regime.id))!;
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

    final status = (await repo.cycleStatus(regime.id))!;
    expect(status.cycleIndex, 1);
    expect(status.completedSessionIds, {push1.id});
  });

  group('sweeping sessions left open', () {
    /// Ages the row, which is what the sweep reads — see
    /// `sweepAbandonedWorkouts`.
    ///
    /// **Not `startedAt`.** The comment that used to sit here said
    /// `startWorkout(at:)` moved only the day key, which is false: it backdates
    /// `startedAt` too, so keying the sweep on that column deleted every
    /// backfilled session at the next launch. INVARIANTS.md § 2. Moving
    /// `updatedAt` is how you make a row old without also claiming the training
    /// happened at another time.
    Future<void> age(String workoutId, Duration by) async {
      await (db.update(db.workouts)..where((t) => t.id.equals(workoutId)))
          .write(WorkoutsCompanion(
        updatedAt: Value(nowMs() - by.inMilliseconds),
      ));
    }

    test('discards one started a day ago with nothing logged in it', () async {
      final id = await repo.startWorkout(
        regimeId: (await activeRegime()).id,
        sessionId: (await sessionNamed('Push 1')).id,
      );
      await age(id, const Duration(hours: 30));

      expect(await repo.sweepAbandonedWorkouts(), 1);

      final today = await repo.todaySnapshot(heatmapFromDayKey: 0);
      expect(today.openWorkout, isNull,
          reason: 'a mis-tapped Start blocks every other session behind '
              '"finish the one you are in" until it goes');
      // Abandoned, not completed: it never happened, and history must not
      // claim it did.
      expect(today.hasHistory, isFalse);
    });

    test('keeps one with sets logged in it, however old', () async {
      final id = await repo.startWorkout(
        regimeId: (await activeRegime()).id,
        sessionId: (await sessionNamed('Push 1')).id,
      );
      final detail = await repo.workoutDetail(id);
      await repo.updateSet(
        detail!.entries.first.sets.first.id,
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );
      await age(id, const Duration(days: 4));

      expect(await repo.sweepAbandonedWorkouts(), 0);

      final today = await repo.todaySnapshot(heatmapFromDayKey: 0);
      expect(today.openWorkout?.id, id,
          reason: 'trained it and forgot to press Finish is the common case; '
              'deleting a real day to save a tap is not a trade the app makes');
      expect(today.openWorkoutDoneSets, 1);
    });

    test('leaves a session started an hour ago alone', () async {
      final id = await repo.startWorkout(
        regimeId: (await activeRegime()).id,
        sessionId: (await sessionNamed('Push 1')).id,
      );
      await age(id, const Duration(hours: 1));

      expect(await repo.sweepAbandonedWorkouts(), 0);
      expect(
        (await repo.todaySnapshot(heatmapFromDayKey: 0)).openWorkout?.id,
        id,
      );
    });
  });

  group('the Today snapshot', () {
    test('answers the whole screen in one call', () async {
      final push1 = await sessionNamed('Push 1');
      await logSession(push1);
      final open = await repo.startWorkout(
        regimeId: (await activeRegime()).id,
        sessionId: (await sessionNamed('Pull 1')).id,
      );

      final today = await repo.todaySnapshot(heatmapFromDayKey: 0);

      expect(today.regime?.name, ppl.name);
      expect(today.sessions.map((s) => s.name), contains('Push 1'));
      expect(today.status?.completedSessionIds, {push1.id});
      expect(today.openWorkout?.id, open);
      expect(today.openWorkoutOwner?.sessionName, 'Pull 1');
      expect(today.hasHistory, isTrue);
      expect(today.recentCompleted, hasLength(1));
    });

    test('describes the open workout off the log, not the template', () async {
      final pull1 = await sessionNamed('Pull 1');
      final open = await repo.startWorkout(
        regimeId: (await activeRegime()).id,
        sessionId: pull1.id,
      );
      final detail = await repo.workoutDetail(open);
      await repo.updateSet(
        detail!.entries.first.sets.first.id,
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );

      final today = await repo.todaySnapshot(heatmapFromDayKey: 0);

      expect(today.openWorkoutDoneSets, 1);
      expect(today.openWorkoutTotalSets,
          greaterThan(today.openWorkoutDoneSets),
          reason: 'the denominator counts every set row, ticked or not');
      expect(
        today.openWorkoutExerciseNames,
        detail.entries.map((e) => e.exercise.name),
        reason: 'in slot order, off the workout it was snapshotted into',
      );
    });

    test('gives every session an entry, so empty is not "not loaded"',
        () async {
      final bare =
          await RegimeRepository(db).addSession((await activeRegime()).id, 'Bare');
      final today = await repo.todaySnapshot(heatmapFromDayKey: 0);
      final names = today.exerciseNamesBySession;

      // Every session is a key; a session with no slots maps to an empty list,
      // which is what the row reads to offer "add exercises" instead of "start".
      expect(names.keys.toSet(), today.sessions.map((s) => s.id).toSet());
      expect(names[(await sessionNamed('Push 1')).id], isNotEmpty);
      expect(names[bare], isEmpty);
    });

    test('has no regime, but still a heatmap, on a fresh install', () async {
      final fresh = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);
      await ensureStarterCatalog(fresh);

      final today = await TrainingRepository(fresh)
          .todaySnapshot(heatmapFromDayKey: 0);

      expect(today.regime, isNull);
      expect(today.status, isNull);
      expect(today.sessions, isEmpty);
      expect(today.hasHistory, isFalse);
      expect(today.recentCompleted, isEmpty);
    });

    test('excludes workouts older than the heatmap window', () async {
      await logSession(await sessionNamed('Push 1'));

      final today = await repo.todaySnapshot(heatmapFromDayKey: 99999999);
      // Still history — the flag is "ever", the grid is "recently".
      expect(today.hasHistory, isTrue);
      expect(today.recentCompleted, isEmpty);
    });
  });

  group('drop sets', () {
    /// The first exercise of a fresh Push 1, with its three template sets.
    Future<({String weId, List<SetLog> sets})> firstExercise() async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final detail = await repo.workoutDetail(id);
      final entry = detail!.entries.first;
      return (weId: entry.workoutExercise.id, sets: entry.sets);
    }

    Future<List<SetLog>> setsOf(String weId) async {
      final rows =
          await (db.select(db.setLogs)
                ..where(
                  (t) =>
                      t.workoutExerciseId.equals(weId) & t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
              .get();
      return rows;
    }

    test('a drop lands next to its own set, not at the end', () async {
      final (:weId, :sets) = await firstExercise();

      // The `+` on the first set's group. Appending would have put this row
      // at the bottom of the exercise — which is exactly what it did, and on
      // screen the new leg appeared under a different group entirely.
      final id = await repo.addSetAfter(
        weId,
        afterSetId: sets.first.id,
        type: SetType.drop,
      );

      final after = await setsOf(weId);
      expect(after.length, sets.length + 1);
      expect(after[1].id, id, reason: 'the leg belongs directly under its set');
      expect(after[1].setType, SetType.drop);
      // And everything below it shuffled down rather than colliding.
      expect(
        after.map((s) => s.setIndex),
        List.generate(after.length, (i) => i),
      );
      expect(after[2].id, sets[1].id);
    });

    test('an insert after a deleted set still lands on a free index', () async {
      final (:weId, :sets) = await firstExercise();

      // Deletes are tombstones and nothing renumbers behind them, so the live
      // rows are now 1, 2 held at positions 0, 1. Numbering the insert from the
      // position handed the new row index 1 — the one its own head already
      // held, two live rows on one index. Reachable from the log screen in two
      // taps: swipe the first set away, then turn the next one into a drop.
      await repo.deleteSet(sets.first.id);
      await repo.setSetType(sets[1].id, SetType.drop);

      final after = await setsOf(weId);
      final live = after.where((s) => s.deletedAt == null).toList();
      expect(
        live.map((s) => s.setIndex).toSet().length,
        live.length,
        reason: 'no two live sets may hold the same index',
      );
      // The leg still sits directly under the head it continues.
      final head = live.firstWhere((s) => s.id == sets[1].id);
      final leg = live.firstWhere((s) => s.parentSetId == sets[1].id);
      expect(leg.setIndex, head.setIndex + 1);
      expect(live.indexOf(leg), live.indexOf(head) + 1);
    });

    test('the + on a group adds a leg to that group, not a new drop set',
        () async {
      final (:weId, :sets) = await firstExercise();
      await repo.setSetType(sets.first.id, SetType.drop);

      // What the `+` under the spine calls. It used to call addSetAfter with
      // no parent, so every press produced another parentless `drop` row —
      // a whole new drop set, complete with its own chip and its own `+`.
      await repo.addDropLeg(weId, headSetId: sets.first.id);

      final after = await setsOf(weId);
      final legs = after.where((s) => s.parentSetId == sets.first.id).toList();
      expect(legs.length, 2, reason: 'the conversion leg plus this one');
      expect(legs.every((s) => s.setType == SetType.drop), isTrue);
      // Both sit directly under their head, in the order they were added.
      expect(after.map((s) => s.id).take(3), [
        sets.first.id,
        legs.first.id,
        legs.last.id,
      ]);
      expect(
        after.map((s) => s.setIndex),
        List.generate(after.length, (i) => i),
      );
    });

    test('converting to a drop makes exactly one leg, and re-tapping adds none',
        () async {
      final (:weId, :sets) = await firstExercise();

      await repo.setSetType(sets.first.id, SetType.drop);
      await repo.setSetType(sets.first.id, SetType.drop);

      final after = await setsOf(weId);
      expect(
        after.where((s) => s.parentSetId == sets.first.id).length,
        1,
        reason: 'the type it already has is not a change',
      );
    });

    test('converting back out of a drop takes the empty legs with it', () async {
      final (:weId, :sets) = await firstExercise();
      // One set, made a drop, grown to three legs, then changed back. It came
      // back as four separate working sets — the legs the conversion added for
      // you are not sets you decided to do.
      await repo.deleteSets([sets[1].id, sets[2].id]);
      await repo.setSetType(sets.first.id, SetType.drop);
      await repo.addDropLeg(weId, headSetId: sets.first.id);
      await repo.addDropLeg(weId, headSetId: sets.first.id);

      await repo.setSetType(sets.first.id, SetType.working);

      final after = await setsOf(weId);
      expect(after.map((s) => s.id), [sets.first.id]);
      expect(after.single.setType, SetType.working);
    });

    test('converting back out of a drop keeps a leg with numbers in it',
        () async {
      final (:weId, :sets) = await firstExercise();
      await repo.setSetType(sets.first.id, SetType.drop);
      final leg = (await setsOf(weId))[1];
      await repo.updateSet(
        leg.id,
        weight: const Value(40),
        reps: const Value(8),
      );

      await repo.setSetType(sets.first.id, SetType.working);

      final after = await setsOf(weId);
      final freed = after.firstWhere((s) => s.id == leg.id);
      // Promoted, not deleted: a leg you logged into is a set you did.
      expect(freed.parentSetId, isNull);
      expect(freed.setType, SetType.working);
      expect(freed.weight, 40);
      expect(freed.reps, 8);
    });

    test('a set added after a delete does not reuse a live index', () async {
      final (:weId, :sets) = await firstExercise();
      await repo.deleteSets([sets[1].id]);

      // Tombstones never renumber, so counting the survivors handed the new
      // row an index the last set still held.
      final id = await repo.addSet(weId);

      final after = await setsOf(weId);
      expect(after.last.id, id);
      expect(
        after.map((s) => s.setIndex).toSet().length,
        after.length,
        reason: 'no two live sets share an index',
      );
    });

    test('next week opens with the template\'s sets, not just the logged ones',
        () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');

      // One set logged out of three, which is what an unticked row leaves
      // behind: `completeWorkout` tombstones the rest on the way out.
      final first = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final entry = (await repo.workoutDetail(first))!.entries.first;
      final programmed = entry.sets.length;
      await repo.updateSet(
        entry.sets.first.id,
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );
      await repo.completeWorkout(first);

      final next = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final reopened = (await repo.workoutDetail(next))!.entries.first;
      expect(reopened.sets.length, programmed);
    });

    test('next week keeps the drop group, not a row of loose Ds', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');

      final first = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final entry = (await repo.workoutDetail(first))!.entries.first;
      final head = entry.sets.first;
      await repo.setSetType(head.id, SetType.drop);
      // Log the head and its leg; only ticked sets are mirrored.
      for (final s in await setsOf(entry.workoutExercise.id)) {
        await repo.updateSet(
          s.id,
          weight: const Value(60),
          reps: const Value(8),
          isDone: const Value(true),
        );
      }
      await repo.completeWorkout(first);

      final next = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final reopened = (await repo.workoutDetail(next))!.entries.first;
      // The head of a drop group is itself a `drop`, so parentage is what
      // separates a leg from the set it hangs off — not the type.
      final legs = reopened.sets.where((s) => s.parentSetId != null).toList();
      expect(legs, hasLength(1));
      expect(legs.single.setType, SetType.drop);
      expect(legs.single.parentSetId, reopened.sets.first.id);
      expect(reopened.sets.first.setType, SetType.drop);
      expect(reopened.sets.first.parentSetId, isNull);
    });

    test('deleting the head of a group takes its legs with it', () async {
      final (:weId, :sets) = await firstExercise();
      final legA = await repo.addSetAfter(
        weId,
        afterSetId: sets.first.id,
        type: SetType.drop,
      );
      final legB = await repo.addSetAfter(
        weId,
        afterSetId: legA,
        type: SetType.drop,
      );

      await repo.deleteSets([sets.first.id, legA, legB]);

      final after = await setsOf(weId);
      expect(after.map((s) => s.id), [sets[1].id, sets[2].id]);
    });
  });

  group('weekly sets per muscle', () {
    /// Ticks every set of the first exercise in a workout, and reports which
    /// muscle they counted toward and how many there were.
    ///
    /// The count is read back rather than assumed: a session opens with the
    /// sets the *last* performance had, so a workout logged after one with
    /// warmups in it starts with more rows than the template's three.
    Future<({MuscleGroup muscle, int sets})> tickFirstExercise(
      String workoutId, {
      SetType type = SetType.working,
      bool done = true,
    }) async {
      final detail = await repo.workoutDetail(workoutId);
      final entry = detail!.entries.first;
      for (final set in entry.sets) {
        await repo.updateSet(
          set.id,
          weight: const Value(40),
          reps: const Value(8),
          setType: Value(type),
          isDone: Value(done),
        );
      }
      return (muscle: entry.exercise.muscle, sets: entry.sets.length);
    }

    test('counts ticked sets in the window, per muscle', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final logged = await tickFirstExercise(id);
      await repo.completeWorkout(id);

      final counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts[logged.muscle], logged.sets);
    });

    test('a set that has not been ticked is not volume', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      // `startWorkout` writes the planned rows up front, so counting rows
      // would credit a session that has not happened.
      await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

      final counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts.values.fold(0, (a, b) => a + b), 0);
    });

    test('warmups and drop legs do not count; backoff sets do', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');

      final warm = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final warmed = await tickFirstExercise(warm, type: SetType.warmup);
      await repo.completeWorkout(warm);

      var counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts[warmed.muscle] ?? 0, 0);

      final back = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final backed = await tickFirstExercise(back, type: SetType.backoff);
      await repo.completeWorkout(back);

      counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts[backed.muscle], backed.sets);
    });

    test('the window is a cutoff, not the whole history', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final old = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
        at: DateTime.now().subtract(const Duration(days: 30)),
      );
      final logged = await tickFirstExercise(old);
      await repo.completeWorkout(old);

      final week = dayKeyOf(DateTime.now().subtract(const Duration(days: 6)));
      expect((await repo.setsByMuscleSince(week))[logged.muscle] ?? 0, 0);

      final month = dayKeyOf(DateTime.now().subtract(const Duration(days: 40)));
      expect((await repo.setsByMuscleSince(month))[logged.muscle], logged.sets);
    });

    test('sets count while the session is still open', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final logged = await tickFirstExercise(id);

      // Not finished: the bar list is read mid-workout, and a set you have
      // done is a set you have done.
      final counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts[logged.muscle], logged.sets);
    });

    test('a skipped slot contributes nothing', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final logged = await tickFirstExercise(id);
      final detail = await repo.workoutDetail(id);
      await repo.setSkipReason(
        detail!.entries.first.workoutExercise.id,
        SkipReason.shortOnTime,
      );

      final counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts[logged.muscle] ?? 0, 0);
    });

    test('the muscle is snapshotted onto the logged row', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final detail = await repo.workoutDetail(id);
      final entry = detail!.entries.first;

      expect(
        entry.workoutExercise.muscle,
        entry.exercise.muscle,
        reason: 'the row carries its own answer, not a pointer to the catalog',
      );
    });

    test('refiling an exercise does not rewrite what it trained in March',
        () async {
      // The reason the snapshot exists. Weekly volume used to count through a
      // join onto `exercises.muscle`, so correcting a movement's category today
      // silently redrew every week it had ever appeared in.
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final logged = await tickFirstExercise(id);
      await repo.completeWorkout(id);

      final detail = await repo.workoutDetail(id);
      final exerciseId = detail!.entries.first.exercise.id;
      // Anything the movement is definitely not.
      final refiled = logged.muscle == MuscleGroup.calves
          ? MuscleGroup.core
          : MuscleGroup.calves;
      await (db.update(db.exercises)..where((t) => t.id.equals(exerciseId)))
          .write(ExercisesCompanion(muscle: Value(refiled)));

      final counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts[logged.muscle], logged.sets);
      expect(counts[refiled] ?? 0, 0);
    });

    test('a row logged before the column falls back to the catalog', () async {
      // What a restore from an older backup lands: no snapshot on the row, and
      // the catalog is the best answer there is. Null must not read as `other`,
      // which belongs to no region and would drop the sets from every chart.
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final logged = await tickFirstExercise(id);
      await repo.completeWorkout(id);

      await db.customStatement(
        'UPDATE workout_exercises SET muscle = NULL',
      );

      final counts = await repo.setsByMuscleSince(dayKeyOf(DateTime.now()));
      expect(counts[logged.muscle], logged.sets);
    });

    test('daily counts carry the day, and agree with the rolling window',
        () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final logged = await tickFirstExercise(id);
      await repo.completeWorkout(id);

      final today = dayKeyOf(DateTime.now());
      final daily = await repo.setsByMuscleDaily(
        fromDayKey: today,
        toDayKey: today,
      );
      final row = daily.firstWhere((r) => r.muscle == logged.muscle);

      expect(row.dayKey, today);
      expect(row.sets, logged.sets);
      // Same filters, same definition of a hard set — the two screens cannot
      // disagree about the same week.
      final rolling = await repo.setsByMuscleSince(today);
      expect(row.sets, rolling[logged.muscle]);
    });

    test('the daily range is a bound, not a suggestion', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
        at: DateTime.now().subtract(const Duration(days: 40)),
      );
      await tickFirstExercise(id);
      await repo.completeWorkout(id);

      final today = dayKeyOf(DateTime.now());
      expect(
        await repo.setsByMuscleDaily(fromDayKey: today, toDayKey: today),
        isEmpty,
      );
      expect(
        await repo.setsByMuscleDaily(
          fromDayKey: dayKeyOf(
            DateTime.now().subtract(const Duration(days: 90)),
          ),
          toDayKey: today,
        ),
        isNotEmpty,
      );
    });

    test('the movements behind a region add up to it', () async {
      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
      );
      final logged = await tickFirstExercise(id);
      await repo.completeWorkout(id);

      final today = dayKeyOf(DateTime.now());
      final byExercise = await repo.setsByExercise(
        fromDayKey: today,
        toDayKey: today,
        muscles: [logged.muscle],
      );

      expect(byExercise, hasLength(1));
      expect(byExercise.single.sets, logged.sets);
      expect(byExercise.single.name, isNotEmpty);

      // The parts are the whole: a breakdown that does not sum to the total
      // above it is two different counts on one screen.
      final rolling = await repo.setsByMuscleSince(today);
      expect(
        byExercise.fold(0, (s, r) => s + r.sets),
        rolling[logged.muscle],
      );
    });

    test('a region nobody trained has no movements behind it', () async {
      final today = dayKeyOf(DateTime.now());
      expect(
        await repo.setsByExercise(
          fromDayKey: today,
          toDayKey: today,
          muscles: const [],
        ),
        isEmpty,
      );
    });

    test('the first logged day is where the year picker starts', () async {
      expect(await repo.firstLoggedDayKey(), isNull);

      final regime = await activeRegime();
      final push1 = await sessionNamed('Push 1');
      final old = DateTime.now().subtract(const Duration(days: 400));
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
        at: old,
      );
      await tickFirstExercise(id);
      await repo.completeWorkout(id);

      expect(await repo.firstLoggedDayKey(), dayKeyOf(old));
    });
  });
}
