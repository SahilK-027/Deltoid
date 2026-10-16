import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/metrics.dart';
import 'package:deltoid/domain/phases.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phase each cycle on the cycle axis is tinted by
/// ([THEME → The cycle axis](THEME.md#the-cycle-axis)): the phase most of its
/// sessions ran in, never on a deload, and under blocks the phase most of the
/// block's sessions ran in.
void main() {
  const bench = LiftId(sessionId: 'push1', exerciseId: 'bench');

  // A bulk from 1 Sep to 13 Sep, then a cut from 14 Sep.
  final spans = phaseSpans(const [
    PhaseEntry(id: 'a', kind: PhaseKind.bulk, startKey: 20260901),
    PhaseEntry(id: 'b', kind: PhaseKind.cut, startKey: 20260914),
  ]);

  CycleInput cycle(
    int index,
    List<int> days, {
    bool isDeload = false,
    bool isOpen = false,
  }) =>
      CycleInput(
        cycleId: 'c$index',
        index: index,
        isDeload: isDeload,
        isOpen: isOpen,
        sessionDays: days,
        performances: [
          for (final day in days)
            LiftPerformance(
              lift: bench,
              dayKey: day,
              load: LoadMode.total,
              sets: [
                ScoredSet(
                  type: SetType.working,
                  weight: isDeload ? 60 : 100.0 + index,
                  reps: 10,
                ),
              ],
            ),
        ],
      );

  CyclePoint point(
    int index,
    List<(int, PhaseKind?)> sessions, {
    bool isDeload = false,
  }) =>
      CyclePoint(
        cycleId: 'c$index',
        index: index,
        isDeload: isDeload,
        isOpen: false,
        value: isDeload ? null : 1,
        lifts: const [],
        sessions: [for (final (day, kind) in sessions) (dayKey: day, kind: kind)],
      );

  group('a cycle', () {
    test('takes the phase most of its sessions ran in', () {
      final p = computeCycleProgress(
        phases: spans,
        cycles: [
          cycle(1, [20260902, 20260904, 20260906]),
          // Two sessions in the cut, one in the bulk.
          cycle(2, [20260912, 20260914, 20260916]),
        ],
      );

      expect(p.cycles[0].phase, PhaseKind.bulk);
      expect(p.cycles[1].phase, PhaseKind.cut);
    });

    test('trained with no phase set has no tint', () {
      final p = computeCycleProgress(
        phases: spans,
        cycles: [cycle(1, [20260820, 20260822, 20260902])],
      );

      expect(p.cycles.single.phase, isNull);
    });

    test('with no phases at all has no tint', () {
      final p = computeCycleProgress(cycles: [cycle(1, [20260902])]);

      expect(p.cycles.single.phase, isNull);
    });

    test('still open is tinted by the sessions it has so far', () {
      final p = computeCycleProgress(
        phases: spans,
        cycles: [
          cycle(1, [20260902, 20260904]),
          cycle(2, [20260915], isOpen: true),
        ],
      );

      expect(p.cycles[1].phase, PhaseKind.cut);
    });

    test('that is a deload is never tinted, whatever it ran in', () {
      final p = computeCycleProgress(
        phases: spans,
        cycles: [
          cycle(1, [20260902]),
          cycle(2, [20260908, 20260910], isDeload: true),
        ],
      );

      expect(p.cycles[1].sessions.map((s) => s.kind), [
        PhaseKind.bulk,
        PhaseKind.bulk,
      ]);
      expect(p.cycles[1].phase, isNull);
      expect(cycleTints(p.cycles), [PhaseKind.bulk, null]);
    });
  });

  group('under blocks', () {
    test('every cycle of a block wears the phase most of its sessions ran in',
        () {
      final points = [
        // Block one: four bulk sessions to two cut.
        point(1, [(1, PhaseKind.bulk), (2, PhaseKind.bulk)]),
        point(2, [(3, PhaseKind.bulk), (4, PhaseKind.bulk)]),
        point(3, [(5, PhaseKind.cut), (6, PhaseKind.cut)]),
        point(4, [(7, PhaseKind.cut)], isDeload: true),
        // Block two: all cut.
        point(5, [(8, PhaseKind.cut)]),
        point(6, [(9, PhaseKind.cut)]),
      ];

      expect(cycleTints(points, isBlocks: true), [
        PhaseKind.bulk,
        PhaseKind.bulk,
        PhaseKind.bulk,
        null,
        PhaseKind.cut,
        PhaseKind.cut,
      ]);
      // Cycle by cycle, the third cycle of block one is a cut.
      expect(cycleTints(points)[2], PhaseKind.cut);
    });

    test('a block split evenly takes the phase it ended in', () {
      final points = [
        point(1, [(1, PhaseKind.maintenance), (2, PhaseKind.maintenance)]),
        point(2, [(3, PhaseKind.bulk), (4, PhaseKind.bulk)]),
      ];

      expect(
        cycleTints(points, isBlocks: true),
        [PhaseKind.bulk, PhaseKind.bulk],
      );
    });

    test('a block trained mostly with no phase has no tint', () {
      final points = [
        point(1, [(1, null), (2, null)]),
        point(2, [(3, null), (4, PhaseKind.bulk)]),
      ];

      expect(cycleTints(points, isBlocks: true), [null, null]);
    });
  });

  group('mostCommonPhase', () {
    test('counts every session, and breaks a tie by the latest', () {
      expect(mostCommonPhase(const []), isNull);
      expect(
        mostCommonPhase(const [
          (dayKey: 3, kind: PhaseKind.cut),
          (dayKey: 1, kind: PhaseKind.bulk),
        ]),
        PhaseKind.cut,
      );
    });

    test('agrees with dominantPhase', () {
      const days = [20260910, 20260912, 20260914, 20260916];
      expect(
        mostCommonPhase(sessionPhases(days, spans)),
        dominantPhase(days, spans),
      );
    });
  });
}
