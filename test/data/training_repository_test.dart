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
}
