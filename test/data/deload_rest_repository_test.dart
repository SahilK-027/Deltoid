import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/deload_rest.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rest days of a deload: written by `Rest today` and `Rest the remaining
/// days`, taken back by `Undo`, by cancelling, by training the day after all,
/// and by turning the deload off.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late Regime regime;

  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
  int today() => dayKeyOf(DateTime.now());

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
    regime = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
  });

  tearDown(() => db.close());

  Future<Session> sessionNamed(String name) =>
      (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();

  /// Turns the open cycle into a deload and returns its id.
  Future<String> openDeload() async {
    final status = await repo.cycleStatus(regime.id);
    await repo.setCycleDeload(status!.cycleId, true);
    return status.cycleId;
  }

  Future<void> train(String name) async {
    final session = await sessionNamed(name);
    final id =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    final detail = await repo.workoutDetail(id);
    final set = detail!.entries.first.sets.first;
    await repo.updateSet(set.id,
        weight: const Value(20), reps: const Value(8), isDone: const Value(true));
    await repo.completeWorkout(id);
  }

  Future<List<CycleRest>> liveRests() =>
      (db.select(db.cycleRests)..where((t) => t.deletedAt.isNull())).get();

  test('resting today spends the session due, once a day', () async {
    await openDeload();
    final push1 = await sessionNamed('Push 1');

    final ids = await repo.restToday(regime.id);
    expect(ids, hasLength(1));
    final status = await repo.cycleStatus(regime.id);
    expect(status!.restedTodaySessionId, push1.id);
    expect(status.nextSessionId, (await sessionNamed('Pull 1')).id);

    expect(await repo.restToday(regime.id), isEmpty,
        reason: 'a day holds one choice');
    expect(await liveRests(), hasLength(1));
  });

  test('undo takes the rest back', () async {
    await openDeload();
    final ids = await repo.restToday(regime.id);
    await repo.removeRests(ids);
    expect(await liveRests(), isEmpty);
    final status = await repo.cycleStatus(regime.id);
    expect(status!.canRestToday, isTrue);
  });

  test('a day already trained light cannot also be rested', () async {
    await openDeload();
    await train('Push 1');
    final status = await repo.cycleStatus(regime.id);
    expect(status!.trainedToday, isTrue);
    expect(await repo.restToday(regime.id), isEmpty);
  });

  test('outside a deload nothing is rested', () async {
    expect(await repo.restToday(regime.id), isEmpty);
    expect(await repo.restRemainingDays(regime.id), isEmpty);
  });

  test('resting the remaining days plans one a day, from tomorrow after '
      'a session today', () async {
    await openDeload();
    await train('Push 1');
    final ids = await repo.restRemainingDays(regime.id);
    expect(ids, hasLength(5));

    final rests = await liveRests();
    final days = rests.map((r) => r.dayKey).toList()..sort();
    expect(days, [
      for (var i = 1; i <= 5; i++) addDaysToKey(today(), i),
    ]);
    final status = await repo.cycleStatus(regime.id);
    expect(status!.hasOpenPosition, isFalse);
    expect(status.cycleIndex, 1, reason: 'planned rest closes nothing yet');
  });

  test('resting the remaining days starts today when today is free',
      () async {
    await openDeload();
    await repo.restRemainingDays(regime.id);
    final days = (await liveRests()).map((r) => r.dayKey).toList()..sort();
    expect(days.first, today());
    expect(days, hasLength(6));
  });

  test('cancelling the planned rest keeps today and frees the rest', () async {
    final cycleId = await openDeload();
    await repo.restRemainingDays(regime.id);
    await repo.cancelPlannedRests(cycleId);

    final rests = await liveRests();
    expect(rests.map((r) => r.dayKey), [today()]);
    final status = await repo.cycleStatus(regime.id);
    expect(status!.remainingSessionIds, hasLength(5));
  });

  test('ending the deload clears every rest day', () async {
    final cycleId = await openDeload();
    await repo.restRemainingDays(regime.id);
    await repo.setCycleDeload(cycleId, false);
    expect(await liveRests(), isEmpty);
  });

  test('training a rested session gives it its position back', () async {
    await openDeload();
    await repo.restToday(regime.id);
    await repo.unrestToday((await repo.cycleStatus(regime.id))!.cycleId);
    expect(await liveRests(), isEmpty);

    await repo.restRemainingDays(regime.id);
    await train('Leg 2');
    final leg2 = await sessionNamed('Leg 2');
    final rests = await liveRests();
    expect(rests.where((r) => r.sessionId == leg2.id), isEmpty);
    final status = await repo.cycleStatus(regime.id);
    expect(status!.completedSessionIds, contains(leg2.id));
  });

  test('a deload whose last rest day has passed closes, and the next cycle '
      'starts after it', () async {
    final cycleId = await openDeload();
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id)))
        .get();
    // Six rest days ending yesterday.
    for (var i = 0; i < sessions.length; i++) {
      await db.into(db.cycleRests).insert(
            CycleRestsCompanion.insert(
              id: Value(newId()),
              cycleId: cycleId,
              sessionId: sessions[i].id,
              dayKey: addDaysToKey(today(), i - sessions.length),
            ),
          );
    }

    final status = await repo.cycleStatus(regime.id);
    expect(status!.cycleIndex, 2);
    expect(status.isDeload, isFalse);

    final closed = await (db.select(db.cycles)
          ..where((t) => t.id.equals(cycleId)))
        .getSingle();
    expect(closed.completedAt, isNotNull);
    final opened = await (db.select(db.cycles)
          ..where((t) => t.id.equals(status.cycleId)))
        .getSingle();
    expect(opened.startedAt, greaterThan(closed.completedAt!));
  });

  test('a deload resting its last day today stays open until tomorrow',
      () async {
    await openDeload();
    for (final name in ['Push 1', 'Pull 1', 'Leg 1', 'Push 2', 'Pull 2']) {
      await train(name);
    }
    expect(await repo.restToday(regime.id), isEmpty,
        reason: 'today was trained');
    await repo.restRemainingDays(regime.id);
    final status = await repo.cycleStatus(regime.id);
    expect(status!.cycleIndex, 1);
    expect(status.plannedRestSessionIds, hasLength(1));
  });

  test('the calendar marks a rested today', () async {
    await openDeload();
    expect(await repo.deloadRestDayKeys(), isNot(contains(today())));
    await repo.restToday(regime.id);
    expect(await repo.deloadRestDayKeys(), contains(today()));
  });

  test('a cycle made a deload part way dots nothing before its first rest',
      () async {
    // A session at full weight first: the cycle was an ordinary one until
    // the switch on the cycle sheet, and its untrained days were not rest.
    await train('Push 1');
    await openDeload();
    expect(await repo.deloadRestDayKeys(), isEmpty);
    await repo.restRemainingDays(regime.id);
    expect(await repo.deloadRestDayKeys(), isEmpty,
        reason: 'today was trained, so the rest starts tomorrow');
  });

  test('the calendar never marks a planned day', () async {
    await openDeload();
    await train('Push 1');
    await repo.restRemainingDays(regime.id);
    final days = await repo.deloadRestDayKeys();
    expect(days.where((d) => d > today()), isEmpty);
    expect(days, isNot(contains(today())), reason: 'today was trained');
  });
  test('a rest synced in after the deload ended spends nothing', () async {
    // Phone A ends the deload, which clears its rests; phone B rested Push 1
    // offline and its row lands afterwards. The cycle is ordinary again, so
    // the row is read by nothing.
    final cycleId = await openDeload();
    await repo.setCycleDeload(cycleId, false);
    final push1 = await sessionNamed('Push 1');
    await db.into(db.cycleRests).insert(
          CycleRestsCompanion.insert(
            id: Value(newId()),
            cycleId: cycleId,
            sessionId: push1.id,
            dayKey: today(),
          ),
        );

    final status = await repo.cycleStatus(regime.id);
    expect(status!.rests, isEmpty);
    expect(status.restedTodaySessionId, isNull);
    expect(status.nextSessionId, push1.id);
    expect(status.done, 0);
    expect(await repo.deloadRestDayKeys(), isEmpty);
    expect(await repo.closeCycleIfSatisfied(regime.id), isFalse);
  });
}
