import 'package:deltoid/domain/cycle_engine.dart';
import 'package:deltoid/domain/deload_rest.dart';
import 'package:flutter_test/flutter_test.dart';

const ppl = ['push1', 'pull1', 'leg1', 'push2', 'pull2', 'leg2'];

/// Monday 17 November 2026, the deload's first day in every case below.
const monday = 20261117;

CycleStatus deload({
  Set<String> done = const {},
  Map<String, int> rests = const {},
  int today = monday,
  bool trainedToday = false,
}) {
  return CycleStatus(
    cycleId: 'cycle-7',
    cycleIndex: 7,
    isDeload: true,
    sessionIds: ppl,
    completedSessionIds: done,
    cyclesSinceDeload: 6,
    deloadEnabled: true,
    deloadAfterCycles: 6,
    rests: rests,
    todayKey: today,
    trainedToday: trainedToday,
  );
}

void main() {
  group('day keys', () {
    test('move across a month and a year', () {
      expect(addDaysToKey(20261130, 1), 20261201);
      expect(addDaysToKey(20261231, 1), 20270101);
      expect(addDaysToKey(20270101, -1), 20261231);
    });

    test('move across a clock change without losing a day', () {
      // Europe and North America both change clocks in late October and
      // early November; a day computed in local time lands an hour short.
      expect(addDaysToKey(20261025, 1), 20261026);
      expect(addDaysToKey(20261101, 1), 20261102);
    });
  });

  group('rest days on the calendar', () {
    test('mark only the days chosen as rest', () {
      // 19 November passed untrained inside the deload, with nothing chosen:
      // the session due stayed due, so it is an ordinary rest day.
      final days = deloadRestDays(
        [20261117, 20261118],
        trainedDays: {20261118},
        todayKey: 20261120,
      );
      expect(days, {20261117});
    });

    test('mark today once it is chosen, and never a planned day ahead', () {
      expect(
        deloadRestDays([monday, 20261118], trainedDays: {}, todayKey: monday),
        {monday},
      );
    });
  });

  group('planned rest days', () {
    test('start today when today is free', () {
      expect(
        plannedRestDays(count: 3, todayKey: monday, todayTaken: false),
        [20261117, 20261118, 20261119],
      );
    });

    test('start tomorrow when today is already spent', () {
      expect(
        plannedRestDays(count: 2, todayKey: 20261130, todayTaken: true),
        [20261201, 20261202],
      );
    });
  });

  group('a cycle with rest days', () {
    test('a rest today spends the position, and the next one is due', () {
      final status = deload(rests: {'push1': monday});
      expect(status.restedTodaySessionId, 'push1');
      expect(status.nextSessionId, 'pull1');
      expect(status.done, 1);
      expect(status.states.first, PositionState.rested);
      expect(status.canRestToday, isFalse);
    });

    test('a planned rest is spoken for but not yet done', () {
      final status = deload(
        done: {'push1'},
        rests: {'pull1': 20261118, 'leg1': 20261119},
        trainedToday: true,
      );
      expect(status.states.take(3), [
        PositionState.trained,
        PositionState.planned,
        PositionState.planned,
      ]);
      expect(status.done, 1);
      expect(status.plannedRestSessionIds, ['pull1', 'leg1']);
      expect(status.lastRestDayKey, 20261119);
      expect(status.nextSessionId, 'push2');
    });

    test('is not complete while a rest is still planned', () {
      final status = deload(
        done: {'push1', 'pull1', 'leg1'},
        rests: {'push2': monday, 'pull2': 20261118, 'leg2': 20261119},
      );
      expect(status.hasOpenPosition, isFalse);
      expect(status.remainingSessionIds, isEmpty);
      expect(status.isComplete, isFalse);
    });

    test('is complete once every rest day has passed', () {
      final status = deload(
        done: {'push1', 'pull1', 'leg1'},
        rests: {'push2': monday, 'pull2': 20261118, 'leg2': 20261119},
        today: 20261120,
      );
      expect(status.isComplete, isTrue);
      expect(status.done, 6);
    });

    test('a day trained cannot also be rested', () {
      expect(deload(trainedToday: true).canRestToday, isFalse);
      expect(deload().canRestToday, isTrue);
    });

    test('an ordinary cycle offers no rest', () {
      final status = deload().copyWith(isDeload: false);
      expect(status.canRestToday, isFalse);
    });
  });
}
