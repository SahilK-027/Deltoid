import 'package:deltoid/domain/cycle_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const ppl = ['push1', 'pull1', 'leg1', 'push2', 'pull2', 'leg2'];

CycleStatus status({
  int cycleIndex = 1,
  bool isDeload = false,
  Set<String> done = const {},
  int cyclesSinceDeload = 0,
  bool deloadEnabled = true,
  int deloadAfterCycles = 6,
}) {
  return CycleStatus(
    cycleId: 'cycle-$cycleIndex',
    cycleIndex: cycleIndex,
    isDeload: isDeload,
    sessionIds: ppl,
    completedSessionIds: done,
    cyclesSinceDeload: cyclesSinceDeload,
    deloadEnabled: deloadEnabled,
    deloadAfterCycles: deloadAfterCycles,
  );
}

void main() {
  group('next session', () {
    test('starts at the first session of an empty cycle', () {
      expect(status().nextSessionId, 'push1');
    });

    test('returns the first session not yet done, in programme order', () {
      expect(status(done: {'push1', 'pull1'}).nextSessionId, 'leg1');
    });

    test('training out of order still fills the gap first', () {
      // Did legs before pulls; the cycle still owes pull1.
      expect(status(done: {'push1', 'leg1'}).nextSessionId, 'pull1');
    });

    test('doing a session twice does not advance past what is owed', () {
      // completedSessionIds is a set, so a repeated Push 1 is still one entry.
      final s = status(done: {'push1'});
      expect(s.done, 1);
      expect(s.nextSessionId, 'pull1');
    });

    test('wraps to the start once every session is done', () {
      expect(status(done: ppl.toSet()).nextSessionId, 'push1');
    });
  });

  group('completion', () {
    test('is complete only when every session has been trained', () {
      expect(status(done: {'push1', 'pull1', 'leg1', 'push2', 'pull2'}).isComplete,
          isFalse);
      expect(status(done: ppl.toSet()).isComplete, isTrue);
    });

    test('reports remaining sessions in order', () {
      expect(
        status(done: {'pull1', 'push2'}).remainingSessionIds,
        ['push1', 'leg1', 'pull2', 'leg2'],
      );
    });

    test('progress is fractional over the whole cycle', () {
      expect(status(done: {'push1', 'pull1', 'leg1'}).progress, closeTo(0.5, 1e-9));
    });
  });

  group('deload trigger', () {
    test('fires on the cycle that completes the configured count', () {
      // deloadAfterCycles = 6, so cycle 6 (five completed before it) is the
      // last normal one.
      expect(status(cyclesSinceDeload: 4).nextCycleIsDeload, isFalse);
      expect(status(cyclesSinceDeload: 5).nextCycleIsDeload, isTrue);
    });

    test('a deload cycle never chains into another', () {
      expect(
        status(isDeload: true, cyclesSinceDeload: 5).nextCycleIsDeload,
        isFalse,
      );
    });

    test('respects the enabled toggle', () {
      expect(
        status(cyclesSinceDeload: 5, deloadEnabled: false).nextCycleIsDeload,
        isFalse,
      );
    });

    test('counts down cycles until the next deload', () {
      expect(status(cyclesSinceDeload: 0).cyclesUntilDeload, 5);
      expect(status(cyclesSinceDeload: 5).cyclesUntilDeload, 0);
    });

    test('a configurable interval shifts the trigger', () {
      expect(
        status(cyclesSinceDeload: 2, deloadAfterCycles: 4).nextCycleIsDeload,
        isFalse,
      );
      expect(
        status(cyclesSinceDeload: 3, deloadAfterCycles: 4).nextCycleIsDeload,
        isTrue,
      );
    });
  });

  group('planNextCycle', () {
    test('advances the index and carries the counter', () {
      final next = planNextCycle(status(cycleIndex: 3, cyclesSinceDeload: 2));
      expect(next.cycleIndex, 4);
      expect(next.isDeload, isFalse);
      expect(next.cyclesSinceDeload, 3);
    });

    test('resets the counter when the deload cycle begins', () {
      final next = planNextCycle(status(cycleIndex: 6, cyclesSinceDeload: 5));
      expect(next.isDeload, isTrue);
      expect(next.cyclesSinceDeload, 0);
    });

    test('the cycle after a deload starts a fresh count', () {
      final next = planNextCycle(
        status(cycleIndex: 7, isDeload: true, cyclesSinceDeload: 0),
      );
      expect(next.isDeload, isFalse);
      expect(next.cyclesSinceDeload, 0);
    });

    test('a full run reaches deload exactly every N cycles', () {
      var s = status(cycleIndex: 1, cyclesSinceDeload: 0);
      final deloadIndices = <int>[];

      for (var i = 0; i < 20; i++) {
        final next = planNextCycle(s);
        if (next.isDeload) deloadIndices.add(next.cycleIndex);
        s = s.copyWith(
          cycleIndex: next.cycleIndex,
          isDeload: next.isDeload,
          cyclesSinceDeload: next.cyclesSinceDeload,
        );
      }

      // Deload on cycle 7, then every 7th thereafter (6 normal + 1 deload).
      expect(deloadIndices, [7, 14, 21]);
    });
  });

  test('an empty regime has no next session and never completes', () {
    const s = CycleStatus(
      cycleId: 'cycle-1',
      cycleIndex: 1,
      isDeload: false,
      sessionIds: [],
      completedSessionIds: {},
      cyclesSinceDeload: 0,
      deloadEnabled: true,
      deloadAfterCycles: 6,
    );
    expect(s.nextSessionId, isNull);
    expect(s.isComplete, isFalse);
    expect(s.progress, 0);
  });
}
