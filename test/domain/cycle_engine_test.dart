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

  group('days that alternate', () {
    // Leg 1 and Leg 2 share the third position; everything else is trained
    // every cycle.
    const legs = {'leg1': 'legs', 'leg2': 'legs'};
    const order = ['push1', 'pull1', 'leg1', 'leg2', 'push2', 'pull2'];

    CycleStatus alternating({
      Set<String> done = const {},
      String? lastLeg,
    }) =>
        CycleStatus(
          cycleId: 'cycle-1',
          cycleIndex: 1,
          isDeload: false,
          sessionIds: order,
          completedSessionIds: done,
          cyclesSinceDeload: 0,
          deloadEnabled: true,
          deloadAfterCycles: 6,
          rotations: legs,
          lastTrainedInRotation: {'legs': ?lastLeg},
        );

    test('two days in one rotation are one position', () {
      expect(cyclePositions(order, legs), [
        ['push1'],
        ['pull1'],
        ['leg1', 'leg2'],
        ['push2'],
        ['pull2'],
      ]);
      expect(alternating().total, 5);
    });

    test('a position stands where its earliest member does', () {
      // Leg 2 sits last in the programme, and the pair is still third.
      expect(
        cyclePositions(
            ['push1', 'pull1', 'leg1', 'push2', 'pull2', 'leg2'], legs),
        [
          ['push1'],
          ['pull1'],
          ['leg1', 'leg2'],
          ['push2'],
          ['pull2'],
        ],
      );
    });

    test('a rotation left with one member is a day of its own', () {
      // What deleting Leg 2 leaves behind: Leg 1 still carrying the rotation.
      expect(
        cyclePositions(['push1', 'leg1'], {'leg1': 'legs'}),
        [
          ['push1'],
          ['leg1'],
        ],
      );
    });

    test('a rotation nobody has trained starts from its first member', () {
      expect(alternating().positions[2].dueSessionId, 'leg1');
    });

    test('the member after the one last trained is due, and it wraps', () {
      expect(alternating(lastLeg: 'leg1').positions[2].dueSessionId, 'leg2');
      expect(alternating(lastLeg: 'leg2').positions[2].dueSessionId, 'leg1');
    });

    test('a last-trained member since deleted starts the rotation again', () {
      expect(alternating(lastLeg: 'leg3').positions[2].dueSessionId, 'leg1');
    });

    test('a member trained this cycle is the one the position holds', () {
      // Leg 1 was due, and Leg 2 was trained instead.
      final s = alternating(done: {'leg2'});
      expect(s.positions[2].dueSessionId, 'leg2');
      expect(s.done, 1);
      expect(s.remainingSessionIds, ['push1', 'pull1', 'push2', 'pull2']);
    });

    test('the cycle completes on one of the two, never needing both', () {
      final s = alternating(done: {'push1', 'pull1', 'leg1', 'push2', 'pull2'});
      expect(s.isComplete, isTrue);
      expect(s.done, 5);
      expect(s.remainingSessionIds, isEmpty);
    });

    test('the day not due is never the next session, nor owed', () {
      final s = alternating(done: {'push1', 'pull1'}, lastLeg: 'leg1');
      expect(s.nextSessionId, 'leg2');
      expect(s.remainingSessionIds, ['leg2', 'push2', 'pull2']);
    });

    test('training both in one cycle still counts the position once', () {
      final s = alternating(done: {'leg1', 'leg2'});
      expect(s.done, 1);
    });

    test('a finished cycle whose first position alternates wraps to the next '
        'member', () {
      const s = CycleStatus(
        cycleId: 'cycle-1',
        cycleIndex: 1,
        isDeload: false,
        sessionIds: ['leg1', 'leg2', 'push1'],
        completedSessionIds: {'leg1', 'push1'},
        cyclesSinceDeload: 0,
        deloadEnabled: true,
        deloadAfterCycles: 6,
        rotations: legs,
      );
      expect(s.isComplete, isTrue);
      expect(s.nextSessionId, 'leg2');
    });

    test('the turn order starts with the day due', () {
      final p = alternating(lastLeg: 'leg1').positions[2];
      expect(p.turnOrder, ['leg2', 'leg1']);
      expect(alternating().positions[0].turnOrder, ['push1']);
    });

    test('the cycles ahead step a rotation and repeat everything else', () {
      final positions = alternating().positions;
      expect(cyclesAhead(positions, 3), [
        ['push1', 'pull1', 'leg1', 'push2', 'pull2'],
        ['push1', 'pull1', 'leg2', 'push2', 'pull2'],
        ['push1', 'pull1', 'leg1', 'push2', 'pull2'],
      ]);
    });

    test('the order repeats after one cycle, two, or the cap', () {
      expect(cyclesBeforeRepeat(status().positions), 1);
      expect(cyclesBeforeRepeat(alternating().positions), 2);
      // A pair and a trio meet every six cycles, and three rows are drawn.
      final mixed = buildPositions(
        ['a1', 'a2', 'b1', 'b2', 'b3'],
        rotations: {'a1': 'a', 'a2': 'a', 'b1': 'b', 'b2': 'b', 'b3': 'b'},
      );
      expect(cyclesBeforeRepeat(mixed), 3);
    });

    test('a regime with no rotations reads exactly as it did', () {
      final s = status(done: {'push1', 'pull1'});
      expect(s.total, 6);
      expect(s.done, 2);
      expect(s.nextSessionId, 'leg1');
      expect(s.remainingSessionIds, ['leg1', 'push2', 'pull2', 'leg2']);
      expect(s.positions.every((p) => !p.alternates), isTrue);
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
