import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every expected figure in this file is worked by hand from Epley, never read
/// back off the implementation. Most cases hold the reps still and move only
/// the load, because `estimated1RM` is linear in load: 100kg × 10 against
/// 110kg × 10 is exactly +10 %, whatever the formula does with the reps.

const bench = LiftId(sessionId: 'push1', exerciseId: 'bench');
const row = LiftId(sessionId: 'pull1', exerciseId: 'row');
const plank = LiftId(sessionId: 'push1', exerciseId: 'plank');
const pullUp = LiftId(sessionId: 'pull1', exerciseId: 'pullUp');

LiftPerformance barbell(
  LiftId lift, {
  required double weight,
  required int reps,
  int dayKey = 20260105,
  List<ScoredSet> extra = const [],
}) =>
    LiftPerformance(
      lift: lift,
      dayKey: dayKey,
      load: LoadMode.total,
      sets: [
        ScoredSet(type: SetType.working, weight: weight, reps: reps),
        ...extra,
      ],
    );

CycleInput cycle(
  int index,
  List<LiftPerformance> performances, {
  bool isDeload = false,
  bool isOpen = false,
}) =>
    CycleInput(
      cycleId: 'c$index',
      index: index,
      isDeload: isDeload,
      isOpen: isOpen,
      performances: performances,
    );

void main() {
  group('cycle points', () {
    test('a cycle is measured against the first cycle of its own regime', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [barbell(bench, weight: 100, reps: 10)]),
          cycle(2, [barbell(bench, weight: 110, reps: 10)]),
          cycle(3, [barbell(bench, weight: 120, reps: 10)]),
        ],
      );

      expect(p.cycles.map((c) => c.value), [
        closeTo(0, 1e-9),
        closeTo(10, 1e-9),
        closeTo(20, 1e-9),
      ]);
      expect(p.percent, closeTo(20, 1e-9));
    });

    test('the point is the mean of the lifts trained in the cycle', () {
      // Bench +10 %, row +20 %, so the cycle is +15 %.
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [
            barbell(bench, weight: 100, reps: 10),
            barbell(row, weight: 50, reps: 10),
          ]),
          cycle(2, [
            barbell(bench, weight: 110, reps: 10),
            barbell(row, weight: 60, reps: 10),
          ]),
        ],
      );

      expect(p.cycles.last.value, closeTo(15, 1e-9));
    });

    test('the best qualifying set of the cycle is the one that counts', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [barbell(bench, weight: 100, reps: 10)]),
          cycle(2, [
            barbell(bench, weight: 90, reps: 10),
            barbell(bench, weight: 110, reps: 10),
          ]),
        ],
      );

      expect(p.cycles.last.value, closeTo(10, 1e-9));
    });

    test('warm-ups and drop sets are not strength', () {
      // A 200kg warm-up would be +100 % if it counted.
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [barbell(bench, weight: 100, reps: 10)]),
          cycle(2, [
            barbell(
              bench,
              weight: 100,
              reps: 10,
              extra: const [
                ScoredSet(type: SetType.warmup, weight: 200, reps: 10),
                ScoredSet(type: SetType.drop, weight: 300, reps: 10),
              ],
            ),
          ]),
        ],
      );

      expect(p.cycles.last.value, closeTo(0, 1e-9));
    });
  });

  group('deloads', () {
    test('a deload scores nothing and does not become a baseline', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [barbell(bench, weight: 100, reps: 10)]),
          cycle(2, [barbell(bench, weight: 110, reps: 10)]),
          cycle(3, [barbell(bench, weight: 60, reps: 10)], isDeload: true),
          cycle(4, [barbell(bench, weight: 120, reps: 10)]),
        ],
      );

      expect(p.cycles[2].value, isNull);
      expect(p.cycles[2].isScored, isFalse);
      // Measured against cycle 1, not against the deload, which would be +100 %.
      expect(p.cycles[3].value, closeTo(20, 1e-9));
    });

    test('a lift first seen in a deload takes its baseline from the next '
        'ordinary cycle', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [barbell(bench, weight: 100, reps: 10)]),
          cycle(2, [
            barbell(bench, weight: 60, reps: 10),
            barbell(row, weight: 40, reps: 10),
          ], isDeload: true),
          cycle(3, [
            barbell(bench, weight: 110, reps: 10),
            barbell(row, weight: 50, reps: 10),
          ]),
        ],
      );

      // Bench +10 %, row at its own baseline and so 0. The mean is +5 %, not
      // the +25 % a deload baseline would have produced for the row.
      expect(p.cycles.last.value, closeTo(5, 1e-9));
      final rowChange = p.cycles.last.lifts.firstWhere((l) => l.lift == row);
      expect(rowChange.baselineCycleIndex, 3);
    });
  });

  test('leaving a regime and coming back carries on from cycle 1', () {
    // Cycles 3 and 4 were trained on another regime, so this regime's numbering
    // resumes at 5 with no cycles of its own in between.
    final p = computeCycleProgress(
      cycles: [
        cycle(1, [barbell(bench, weight: 100, reps: 10)]),
        cycle(2, [barbell(bench, weight: 110, reps: 10)]),
        cycle(5, [barbell(bench, weight: 130, reps: 10)]),
        cycle(6, [barbell(bench, weight: 140, reps: 10)]),
      ],
    );

    expect(p.cycles.map((c) => c.index), [1, 2, 5, 6]);
    expect(p.cycles.map((c) => c.value), [
      closeTo(0, 1e-9),
      closeTo(10, 1e-9),
      closeTo(30, 1e-9),
      closeTo(40, 1e-9),
    ]);
  });

  test('cycles are read in index order however they arrive', () {
    final p = computeCycleProgress(
      cycles: [
        cycle(2, [barbell(bench, weight: 110, reps: 10)]),
        cycle(1, [barbell(bench, weight: 100, reps: 10)]),
      ],
    );

    expect(p.cycles.first.index, 1);
    expect(p.cycles.first.value, closeTo(0, 1e-9));
    expect(p.cycles.last.value, closeTo(10, 1e-9));
  });

  test('a lift added part-way through starts at its own baseline', () {
    final p = computeCycleProgress(
      cycles: [
        cycle(1, [barbell(bench, weight: 100, reps: 10)]),
        cycle(2, [
          barbell(bench, weight: 120, reps: 10),
          barbell(row, weight: 50, reps: 10),
        ]),
        cycle(3, [
          barbell(bench, weight: 130, reps: 10),
          barbell(row, weight: 55, reps: 10),
        ]),
      ],
    );

    // Cycle 2: bench +20 %, row 0 % → +10 %.
    expect(p.cycles[1].value, closeTo(10, 1e-9));
    // Cycle 3: bench +30 %, row +10 % → +20 %.
    expect(p.cycles[2].value, closeTo(20, 1e-9));
  });

  group('days that alternate', () {
    const squat = LiftId(sessionId: 'leg1', exerciseId: 'squat');
    const deadlift = LiftId(sessionId: 'leg2', exerciseId: 'deadlift');
    const legs = {'leg1': 'legs', 'leg2': 'legs'};

    // Bench never moves, the squat is 40 % up and the deadlift 10 % up. Leg 1
    // and Leg 2 are trained in turn from cycle 2.
    final cycles = [
      cycle(1, [
        barbell(bench, weight: 100, reps: 10),
        barbell(squat, weight: 100, reps: 10),
        barbell(deadlift, weight: 100, reps: 10),
      ]),
      cycle(2, [
        barbell(bench, weight: 100, reps: 10),
        barbell(squat, weight: 140, reps: 10),
      ]),
      cycle(3, [
        barbell(bench, weight: 100, reps: 10),
        barbell(deadlift, weight: 110, reps: 10),
      ]),
      cycle(4, [
        barbell(bench, weight: 100, reps: 10),
        barbell(squat, weight: 140, reps: 10),
      ]),
      cycle(5, [
        barbell(bench, weight: 100, reps: 10),
        barbell(deadlift, weight: 110, reps: 10),
      ]),
    ];

    test('the day resting this cycle counts at its last reading', () {
      final p = computeCycleProgress(cycles: cycles, rotations: legs);

      // Cycle 2: bench 0, squat +40, deadlift as it stood in cycle 1, 0.
      expect(p.cycles[1].value, closeTo(40 / 3, 1e-9));
      // Cycle 3: bench 0, deadlift +10, squat as it stood in cycle 2, +40.
      expect(p.cycles[2].value, closeTo(50 / 3, 1e-9));
      // Nothing moved after that, so neither does the figure. Scored on the
      // trained day alone it would read 20, 5, 20, 5.
      expect(p.cycles[3].value, closeTo(50 / 3, 1e-9));
      expect(p.cycles[4].value, closeTo(50 / 3, 1e-9));
    });

    test('a programme standing still is not read as rising and falling', () {
      // Three more cycles of the same weights, so the trend looks back from
      // cycle 8 to cycle 5: a Leg 1 cycle against a Leg 2 one.
      final still = [
        ...cycles,
        for (var i = 6; i <= 8; i++)
          cycle(i, [
            barbell(bench, weight: 100, reps: 10),
            if (i.isEven)
              barbell(squat, weight: 140, reps: 10)
            else
              barbell(deadlift, weight: 110, reps: 10),
          ]),
      ];

      expect(
        computeCycleProgress(cycles: still, rotations: legs).trend,
        ProgressTrend.holdingSteady,
      );
      // Scored on the trained day alone, the same log reads 20 against 5.
      expect(
        computeCycleProgress(cycles: still).trend,
        ProgressTrend.progressing,
      );
    });

    test('nothing is carried into a cycle the position has not reached', () {
      // Two sessions into cycle 6, neither of them a leg day.
      final p = computeCycleProgress(
        cycles: [
          ...cycles,
          cycle(6, [barbell(bench, weight: 110, reps: 10)], isOpen: true),
        ],
        rotations: legs,
      );
      expect(p.cycles[5].lifts.map((l) => l.lift), [bench]);
      expect(p.cycles[5].value, closeTo(10, 1e-9));
    });

    test('a movement the resting day has since dropped is not carried', () {
      const lunge = LiftId(sessionId: 'leg2', exerciseId: 'lunge');
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [
            barbell(squat, weight: 100, reps: 10),
            barbell(deadlift, weight: 100, reps: 10),
            barbell(lunge, weight: 100, reps: 10),
          ]),
          // Leg 2 comes round without the lunge.
          cycle(2, [barbell(deadlift, weight: 110, reps: 10)]),
          cycle(3, [barbell(squat, weight: 120, reps: 10)]),
        ],
        rotations: legs,
      );
      // Squat +20 and the deadlift at +10. The lunge is not on the day any
      // more, so its cycle 1 reading is not brought forward.
      expect(p.cycles[2].lifts.map((l) => l.lift).toSet(), {squat, deadlift});
      expect(p.cycles[2].value, closeTo(15, 1e-9));
    });

    test('a deload reading is never the one carried', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [
            barbell(squat, weight: 100, reps: 10),
            barbell(deadlift, weight: 100, reps: 10),
          ]),
          cycle(2, [barbell(deadlift, weight: 120, reps: 10)]),
          cycle(3, [barbell(deadlift, weight: 60, reps: 10)], isDeload: true),
          cycle(4, [barbell(squat, weight: 110, reps: 10)]),
        ],
        rotations: legs,
      );
      // Squat +10, and the deadlift at the +20 of cycle 2 rather than the
      // light week after it.
      expect(p.cycles[3].value, closeTo(15, 1e-9));
    });

    test('a regime with no rotations is scored on what was trained', () {
      final p = computeCycleProgress(cycles: cycles);
      expect(p.cycles[1].value, closeTo(20, 1e-9));
      expect(p.cycles[2].value, closeTo(5, 1e-9));
    });
  });

  test('a hold is measured in seconds, never in estimated 1RM', () {
    LiftPerformance hold(int seconds) => LiftPerformance(
          lift: plank,
          dayKey: 20260105,
          load: LoadMode.bodyweight,
          measure: MeasureMode.hold,
          sets: [ScoredSet(type: SetType.working, reps: seconds)],
        );

    final p = computeCycleProgress(
      cycles: [
        cycle(1, [hold(60)]),
        cycle(2, [hold(75)]),
      ],
    );

    // 75 / 60 − 1 = +25 %.
    expect(p.cycles.last.value, closeTo(25, 1e-9));
  });

  test('a bodyweight lift resolves through the weigh-in series', () {
    LiftPerformance pull(int dayKey) => LiftPerformance(
          lift: pullUp,
          dayKey: dayKey,
          load: LoadMode.bodyweightPlus,
          sets: const [
            ScoredSet(type: SetType.working, addedWeight: 5, reps: 10),
          ],
        );

    final p = computeCycleProgress(
      cycles: [
        cycle(1, [pull(20260105)]),
        cycle(2, [pull(20260112)]),
      ],
      bodyweightLog: const [
        (dayKey: 20260105, weightKg: 80),
        (dayKey: 20260112, weightKg: 90),
      ],
    );

    // 85kg carried, then 95kg, at the same reps: 95 / 85 − 1 = +11.7647 %.
    expect(p.cycles.last.value, closeTo(11.764705882, 1e-6));
  });

  group('lifts improved', () {
    test('counts the latest cycle against each lift\'s baseline', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [
            barbell(bench, weight: 100, reps: 10),
            barbell(row, weight: 50, reps: 10),
            barbell(pullUp, weight: 40, reps: 10),
          ]),
          cycle(2, [
            barbell(bench, weight: 110, reps: 10),
            barbell(row, weight: 50, reps: 10),
            barbell(pullUp, weight: 38, reps: 10),
          ]),
        ],
      );

      expect(p.liftsImproved, 1);
      expect(p.liftsCompared, 3);
      final lifts = p.latest!.lifts;
      expect(lifts.first.lift, bench);
      expect(lifts.where((l) => l.isUnchanged).single.lift, row);
      expect(lifts.where((l) => l.isWeaker).single.lift, pullUp);
      expect(lifts.last.rounded, closeTo(-5, 1e-9));
    });

    test('a change under half a tenth reads as no change', () {
      final change = LiftChange(
        lift: bench,
        baseline: 100,
        baselineCycleIndex: 1,
        latest: 100.04,
      );

      expect(change.percent, closeTo(0.04, 1e-9));
      expect(change.rounded, 0);
      expect(change.isUnchanged, isTrue);
    });
  });

  group('trend', () {
    CycleProgress fromValues(List<double> loads, {bool openLast = false}) =>
        computeCycleProgress(
          cycles: [
            for (var i = 0; i < loads.length; i++)
              cycle(
                i + 1,
                [barbell(bench, weight: loads[i], reps: 10)],
                isOpen: openLast && i == loads.length - 1,
              ),
          ],
        );

    test('is nothing until two cycles have scored', () {
      expect(fromValues([100]).trend, isNull);
    });

    test('compares the last scored cycle with three scored cycles earlier', () {
      // 0, +2, +5, +8: eight points clear of the first.
      expect(
        fromValues([100, 102, 105, 108]).trend,
        ProgressTrend.progressing,
      );
      // 0, +0.2, +0.3, +0.4: inside the half-point threshold.
      expect(
        fromValues([100, 100.2, 100.3, 100.4]).trend,
        ProgressTrend.holdingSteady,
      );
      // 0, −1, −2, −3.
      expect(
        fromValues([100, 99, 98, 97]).trend,
        ProgressTrend.dropping,
      );
    });

    test('looks no further back than three scored cycles', () {
      // 0, +10, +10.1, +10.2, +10.3: a big early gain, flat since.
      expect(
        fromValues([100, 110, 110.1, 110.2, 110.3]).trend,
        ProgressTrend.holdingSteady,
      );
    });

    test('the open cycle is left out of the reading', () {
      final p = fromValues([100, 100.1, 100.2, 130], openLast: true);

      expect(p.percent, closeTo(30, 1e-9));
      expect(p.latest!.isOpen, isTrue);
      expect(p.trend, ProgressTrend.holdingSteady);
    });

    test('deloads do not interrupt the count of scored cycles', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [barbell(bench, weight: 100, reps: 10)]),
          cycle(2, [barbell(bench, weight: 60, reps: 10)], isDeload: true),
          cycle(3, [barbell(bench, weight: 102, reps: 10)]),
          cycle(4, [barbell(bench, weight: 103, reps: 10)]),
          cycle(5, [barbell(bench, weight: 110, reps: 10)]),
        ],
      );

      // The four scored cycles are 0, +2, +3, +10, so the pill reads +10.
      expect(p.trend, ProgressTrend.progressing);
    });
  });

  group('ranges', () {
    CycleProgress long(int n) => computeCycleProgress(
          cycles: [
            for (var i = 1; i <= n; i++)
              cycle(
                i,
                [barbell(bench, weight: 100 + i.toDouble(), reps: 10)],
                isDeload: i % 5 == 0,
              ),
          ],
        );

    test('a block is the last scored cycle before each deload', () {
      final p = long(10);

      expect(p.blockPoints.map((c) => c.index), [4, 9]);
    });

    test('the latest cycle is a block of its own', () {
      final p = long(12);

      expect(p.blockPoints.map((c) => c.index), [4, 9, 12]);
    });

    test('a window takes the most recent cycles', () {
      final w = cycleWindow(long(30), CycleRange.last12);

      expect(w.isBlocks, isFalse);
      expect(w.points.first.index, 19);
      expect(w.plotted, isNotEmpty);
      expect(w.points.length, 12);
    });

    test('a window shorter than the range draws what there is', () {
      final w = cycleWindow(long(4), CycleRange.last24);

      expect(w.points.length, 4);
    });

    test('All thins to blocks only past twenty-four cycles', () {
      expect(cycleWindow(long(24), CycleRange.all).isBlocks, isFalse);
      expect(cycleWindow(long(24), CycleRange.all).points.length, 24);
      expect(cycleWindow(long(30), CycleRange.all).isBlocks, isTrue);
    });

    test('a thinned chart keeps every cycle on the axis', () {
      final w = cycleWindow(long(30), CycleRange.all);

      // All thirty positions, six of them drawn: the cycles between the blocks
      // hold the spacing open rather than closing it up.
      expect(w.points.length, 30);
      expect(
        [for (final c in w.points) if (w.plotted.contains(c.cycleId)) c.index],
        [4, 9, 14, 19, 24, 29],
      );
    });

    test('an unthinned chart plots every scored cycle', () {
      final w = cycleWindow(long(12), CycleRange.all);

      expect(w.plotted.length, w.points.where((c) => c.isScored).length);
    });
  });

  group('ISO weeks', () {
    test('a week belongs to the year its Thursday falls in', () {
      // 1 January 2026 is a Thursday, so the week beginning 29 December 2025
      // is week 1 of 2026.
      expect(isoWeekOf(DateTime.utc(2025, 12, 29)), (year: 2026, week: 1));
      expect(isoWeekOf(DateTime.utc(2026, 1, 1)), (year: 2026, week: 1));
      expect(isoWeekOf(DateTime.utc(2026, 1, 5)), (year: 2026, week: 2));
      expect(isoWeekStart(2026, 1), DateTime.utc(2025, 12, 29));
      expect(isoWeekStart(2026, 2), DateTime.utc(2026, 1, 5));
    });

    test('a year beginning on a Thursday has fifty-three weeks', () {
      expect(isoWeeksInYear(2026), 53);
      expect(isoWeeksInYear(2025), 52);
    });
  });

  group('timeline', () {
    test('a week belongs to the regime trained most in it', () {
      final weeks = computeTimelineWeeks(
        year: 2026,
        days: const [
          // Week 1: two sessions of upper lower, one of push pull.
          TrainedDay(dayKey: 20260101, regimeId: 'ul'),
          TrainedDay(dayKey: 20260102, regimeId: 'ul'),
          TrainedDay(dayKey: 20260103, regimeId: 'pp'),
          // Week 2: a deload.
          TrainedDay(dayKey: 20260106, regimeId: 'ul', isDeload: true),
        ],
      );

      expect(weeks.length, 53);
      expect(weeks[0].regimeId, 'ul');
      expect(weeks[0].sessions, 2);
      expect(weeks[0].isDeload, isFalse);
      expect(weeks[1].regimeId, 'ul');
      expect(weeks[1].isDeload, isTrue);
    });

    test('an untrained week is a week off, not an absence', () {
      final weeks = computeTimelineWeeks(
        year: 2026,
        days: const [TrainedDay(dayKey: 20260101, regimeId: 'ul')],
      );

      expect(weeks[0].isOff, isFalse);
      expect(weeks[1].isOff, isTrue);
      expect(weeks[1].regimeId, isNull);
      expect(weeks[1].sessions, 0);
      expect(weeks[1].start, DateTime.utc(2026, 1, 5));
    });

    test('a week split evenly goes to the regime moved to', () {
      final weeks = computeTimelineWeeks(
        year: 2026,
        days: const [
          TrainedDay(dayKey: 20260105, regimeId: 'ul'),
          TrainedDay(dayKey: 20260108, regimeId: 'pp'),
        ],
      );

      expect(weeks[1].regimeId, 'pp');
    });

    test('days outside the year are not drawn on its strip', () {
      final weeks = computeTimelineWeeks(
        year: 2026,
        days: const [
          // Week 52 of 2025, despite the date.
          TrainedDay(dayKey: 20251222, regimeId: 'ul'),
          // Week 1 of 2026, despite the date.
          TrainedDay(dayKey: 20251230, regimeId: 'pp'),
        ],
      );

      expect(weeks[0].regimeId, 'pp');
      expect(weeks.where((w) => w.regimeId == 'ul'), isEmpty);
    });
  });

  test('nothing trained is empty rather than zero', () {
    final p = computeCycleProgress(cycles: const []);

    expect(p.isEmpty, isTrue);
    expect(p.percent, isNull);
    expect(p.trend, isNull);
    expect(p.liftsCompared, 0);
  });

  test('the first cycle has nothing to compare itself with', () {
    final p = computeCycleProgress(
      cycles: [
        cycle(1, [barbell(bench, weight: 100, reps: 10)]),
      ],
    );

    expect(p.isFirstCycle, isTrue);
    expect(p.percent, closeTo(0, 1e-9));
    expect(p.trend, isNull);
  });
  group('runs', () {
    TimelineWeek week(int w, String? id, {int? first, int? last}) =>
        TimelineWeek(
          week: w,
          start: isoWeekStart(2026, w),
          regimeId: id,
          isDeload: false,
          sessions: id == null ? 0 : 3,
          firstCycle: first,
          lastCycle: last,
        );

    test('a week off does not end a spell', () {
      final runs = timelineRuns([
        week(1, 'ul', first: 1, last: 1),
        week(2, 'ul', first: 2, last: 2),
        week(3, null),
        week(4, 'ul', first: 3, last: 3),
      ]);

      expect(runs.length, 1);
      expect(runs.single.from.week, 1);
      expect(runs.single.to.week, 4);
      expect(runs.single.firstCycle, 1);
      expect(runs.single.lastCycle, 3);
    });

    test('training something else does', () {
      final runs = timelineRuns([
        week(1, 'ul', first: 1, last: 1),
        week(2, 'pp', first: 7, last: 7),
        week(3, 'ul', first: 2, last: 2),
      ]);

      expect(runs.map((r) => r.regimeId), ['ul', 'pp', 'ul']);
      // The second spell on the regime carries on from where it left off.
      expect(runs.last.firstCycle, 2);
    });

    test('a year with nothing trained has no spells', () {
      expect(timelineRuns([week(1, null), week(2, null)]), isEmpty);
    });
  });

  group('the years a stepper offers', () {
    test('run from the first ISO year to the last', () {
      expect(
        trainedYears(firstDayKey: 20240115, lastDayKey: 20260301),
        [2024, 2025, 2026],
      );
    });

    test('are the week\'s years, not the dates\'', () {
      // 29 December 2025 is in week 1 of 2026, so a log of that one day is a
      // log of 2026 and the stepper must offer it.
      expect(trainedYears(firstDayKey: 20251229, lastDayKey: 20251229), [2026]);
    });

    test('are nothing at all on an empty log', () {
      expect(trainedYears(firstDayKey: null, lastDayKey: null), isEmpty);
    });
  });

  test('a week names the cycles trained in it', () {
    final weeks = computeTimelineWeeks(
      year: 2026,
      days: const [
        TrainedDay(dayKey: 20260105, regimeId: 'ul', cycleIndex: 3),
        TrainedDay(dayKey: 20260108, regimeId: 'ul', cycleIndex: 4),
      ],
    );

    // A cycle closing mid-week leaves the week spanning two of them.
    expect(weeks[1].firstCycle, 3);
    expect(weeks[1].lastCycle, 4);
  });
  group('the lift summary', () {
    test('reads every lift on its most recent cycle, not on the last one', () {
      // Bench in cycle 3, row only in cycle 2 — a cycle part way through holds
      // only the sessions trained so far, and the row is not gone because of
      // it.
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [
            barbell(bench, weight: 100, reps: 10),
            barbell(row, weight: 50, reps: 10),
          ]),
          cycle(2, [
            barbell(bench, weight: 110, reps: 10),
            barbell(row, weight: 55, reps: 10),
          ]),
          cycle(3, [barbell(bench, weight: 120, reps: 10)]),
        ],
      );

      expect(p.latest!.lifts.length, 1, reason: 'the open cycle has one lift');
      expect(p.lifts.length, 2, reason: 'the regime has two');
      expect(p.liftsImproved, 2);
      expect(p.liftsCompared, 2);

      final benchChange = p.lifts.firstWhere((l) => l.lift == bench);
      final rowChange = p.lifts.firstWhere((l) => l.lift == row);
      expect(benchChange.percent, closeTo(20, 1e-9));
      expect(rowChange.percent, closeTo(10, 1e-9));
    });

    test('a deload is not a lift\'s most recent reading', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [barbell(bench, weight: 100, reps: 10)]),
          cycle(2, [barbell(bench, weight: 120, reps: 10)]),
          cycle(3, [barbell(bench, weight: 60, reps: 10)], isDeload: true),
        ],
      );

      expect(p.lifts.single.percent, closeTo(20, 1e-9));
    });

    test('the biggest change is first', () {
      final p = computeCycleProgress(
        cycles: [
          cycle(1, [
            barbell(bench, weight: 100, reps: 10),
            barbell(row, weight: 100, reps: 10),
          ]),
          cycle(2, [
            barbell(bench, weight: 105, reps: 10),
            barbell(row, weight: 130, reps: 10),
          ]),
        ],
      );

      expect(p.lifts.first.lift, row);
      expect(p.lifts.last.lift, bench);
    });
  });
}
