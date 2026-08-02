import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('effectiveLoad', () {
    test('doubles per-side dumbbell entries', () {
      expect(
        effectiveLoad(mode: LoadMode.perSide, weight: 22.5),
        45,
      );
    });

    test('takes machine and barbell entries at face value', () {
      expect(effectiveLoad(mode: LoadMode.total, weight: 73), 73);
    });

    test('bodyweight lifts use logged bodyweight', () {
      expect(
        effectiveLoad(mode: LoadMode.bodyweight, bodyweightKg: 72),
        72,
      );
    });

    test('bodyweight-plus adds the belt load', () {
      expect(
        effectiveLoad(
          mode: LoadMode.bodyweightPlus,
          addedWeight: 10,
          bodyweightKg: 72,
        ),
        82,
      );
    });

    test('bodyweight-plus without a bodyweight log falls back to added only', () {
      expect(
        effectiveLoad(mode: LoadMode.bodyweightPlus, addedWeight: 10),
        10,
      );
    });
  });

  group('sessionVolume', () {
    List<({LoadMode mode, MeasureMode measure, List<ScoredSet> sets})> one(
      LoadMode mode,
      List<ScoredSet> sets, {
      MeasureMode measure = MeasureMode.reps,
    }) =>
        [(mode: mode, measure: measure, sets: sets)];

    test('a bodyweight session is not a session of nothing', () {
      // The bug: volume read `weight` off the row, which is null on every
      // bodyweight set, so a day of chins and dips reported 0 kg moved.
      final volume = sessionVolume(
        bodyweightKg: 72,
        exercises: one(LoadMode.bodyweight, const [
          ScoredSet(type: SetType.working, reps: 8),
          ScoredSet(type: SetType.working, reps: 6),
        ]),
      );
      expect(volume, 72 * 14);
    });

    test('dumbbells count both of them', () {
      expect(
        sessionVolume(
          exercises: one(LoadMode.perSide, const [
            ScoredSet(type: SetType.working, weight: 22.5, reps: 10),
          ]),
        ),
        450,
      );
    });

    test('bodyweight-plus adds the belt to the body', () {
      expect(
        sessionVolume(
          bodyweightKg: 72,
          exercises: one(LoadMode.bodyweightPlus, const [
            ScoredSet(type: SetType.working, addedWeight: 10, reps: 5),
          ]),
        ),
        410,
      );
    });

    test('warm-ups count — this is work done, not a progression score', () {
      expect(
        sessionVolume(
          exercises: one(LoadMode.total, const [
            ScoredSet(type: SetType.warmup, weight: 40, reps: 10),
            ScoredSet(type: SetType.working, weight: 60, reps: 5),
          ]),
        ),
        700,
      );
    });

    test('with no bodyweight ever logged it is zero, for the caller to dash', () {
      expect(
        sessionVolume(
          exercises: one(LoadMode.bodyweight, const [
            ScoredSet(type: SetType.working, reps: 8),
          ]),
        ),
        0,
      );
    });
  });

  group('estimated1RM', () {
    test('matches Epley', () {
      expect(estimated1RM(load: 100, reps: 6), closeTo(120, 1e-9));
    });

    test('caps reps so high-rep sets cannot masquerade as strength', () {
      final at12 = estimated1RM(load: 50, reps: 12);
      final at20 = estimated1RM(load: 50, reps: 20);
      expect(at20, at12);
    });

    test('rejects incomplete or nonsensical sets', () {
      expect(estimated1RM(load: null, reps: 5), isNull);
      expect(estimated1RM(load: 100, reps: null), isNull);
      expect(estimated1RM(load: 100, reps: 0), isNull);
      expect(estimated1RM(load: 0, reps: 5), isNull);
    });
  });

  group('scorePerformance', () {
    test('excludes warmups, drops and rest-pause from the score', () {
      final score = scorePerformance(
        mode: LoadMode.total,
        sets: const [
          ScoredSet(type: SetType.warmup, weight: 40, reps: 8),
          ScoredSet(type: SetType.working, weight: 100, reps: 6),
          ScoredSet(type: SetType.drop, weight: 60, reps: 10),
          ScoredSet(type: SetType.restPause, weight: 100, reps: 2),
        ],
      );

      expect(score.workingSets, 1);
      expect(score.topSetLoad, 100);
      expect(score.totalReps, 6);
      expect(score.volume, 600);
    });

    test('counts AMRAP sets toward progress', () {
      final score = scorePerformance(
        mode: LoadMode.total,
        sets: const [
          ScoredSet(type: SetType.working, weight: 60, reps: 8),
          ScoredSet(type: SetType.amrap, weight: 60, reps: 14),
        ],
      );

      expect(score.workingSets, 2);
      expect(score.totalReps, 22);
    });

    test('top set is by load, and reports that set\'s reps', () {
      final score = scorePerformance(
        mode: LoadMode.perSide,
        sets: const [
          ScoredSet(type: SetType.working, weight: 20, reps: 12),
          ScoredSet(type: SetType.working, weight: 22.5, reps: 8),
        ],
      );

      expect(score.topSetLoad, 45); // 22.5 per side
      expect(score.topSetReps, 8);
    });

    test('a warmup-only performance scores as empty', () {
      final score = scorePerformance(
        mode: LoadMode.total,
        sets: const [ScoredSet(type: SetType.warmup, weight: 40, reps: 8)],
      );
      expect(score.isEmpty, isTrue);
      expect(score.best1RM, isNull);
    });
  });

  group('a hold is scored on the clock', () {
    List<ScoredSet> plank() => const [
          ScoredSet(type: SetType.working, reps: 45),
          ScoredSet(type: SetType.working, reps: 62),
          ScoredSet(type: SetType.working, reps: 50),
        ];

    test('the top set is the longest, not the heaviest', () {
      final score = scorePerformance(
        mode: LoadMode.bodyweight,
        measure: MeasureMode.hold,
        bodyweightKg: 80,
        sets: plank(),
      );
      // Every set carries the same 80kg of body, so "heaviest" picks one at
      // random — the 62-second hold is the performance.
      expect(score.topSetReps, 62);
      expect(score.totalReps, 157);
    });

    test('a plank has no estimated 1RM', () {
      final score = scorePerformance(
        mode: LoadMode.bodyweight,
        measure: MeasureMode.hold,
        bodyweightKg: 80,
        sets: plank(),
      );
      expect(score.best1RM, isNull);
      // Epley on seconds would answer anyway, and loudly: 80 × (1 + 12/30).
      expect(estimated1RM(load: 80, reps: 62), isNotNull);
    });

    test('kg × seconds is not volume', () {
      final score = scorePerformance(
        mode: LoadMode.bodyweight,
        measure: MeasureMode.hold,
        bodyweightKg: 80,
        sets: plank(),
      );
      expect(score.volume, 0);
    });

    test('a session total leaves holds out of it', () {
      final total = sessionVolume(
        bodyweightKg: 80,
        exercises: [
          (
            mode: LoadMode.total,
            measure: MeasureMode.reps,
            sets: const [ScoredSet(type: SetType.working, weight: 60, reps: 5)],
          ),
          (
            mode: LoadMode.bodyweight,
            measure: MeasureMode.hold,
            sets: plank(),
          ),
        ],
      );
      // The squat, and nothing from three minutes of plank: 80 × 157 would
      // have been eleven times the day's real tonnage.
      expect(total, 300);
    });

    test('a hold reads as a clock and reps read as a count', () {
      // The number the stopwatch was showing when it stopped, not a figure to
      // convert standing up from a plank.
      expect(formatCount(45, MeasureMode.hold), '0:45');
      expect(formatCount(145, MeasureMode.hold), '2:25');
      expect(formatCount(8, MeasureMode.reps), '8');
      expect(formatCount(null, MeasureMode.hold), '0:00');
    });
  });

  group('humanizeEnum', () {
    test('splits camelCase and capitalises', () {
      expect(humanizeEnum('bodyweightPlus'), 'Bodyweight plus');
      expect(humanizeEnum('perSide'), 'Per side');
      expect(humanizeEnum('chest'), 'Chest');
    });

    test('every enum value renders without throwing', () {
      for (final v in MuscleGroup.values) {
        expect(v.label, isNotEmpty);
      }
      for (final v in Equipment.values) {
        expect(v.label, isNotEmpty);
      }
    });
  });

  group('beatsPrevious', () {
    test('more reps at the same load is a win', () {
      expect(
        beatsPrevious(load: 45, reps: 13, previousLoad: 45, previousReps: 12),
        isTrue,
      );
    });

    test('the rep cap in e1RM does not hide a 12 to 13 improvement', () {
      // estimated1RM caps at 12, so both sides score identically there.
      expect(estimated1RM(load: 45, reps: 13), estimated1RM(load: 45, reps: 12));
      expect(
        beatsPrevious(load: 45, reps: 13, previousLoad: 45, previousReps: 12),
        isTrue,
      );
    });

    test('more load at no cost in reps is a win', () {
      expect(
        beatsPrevious(load: 47.5, reps: 8, previousLoad: 45, previousReps: 8),
        isTrue,
      );
    });

    test('heavier for fewer reps is a trade-off, not a win', () {
      expect(
        beatsPrevious(load: 50, reps: 8, previousLoad: 45, previousReps: 12),
        isFalse,
      );
    });

    test('matching or regressing is not a win', () {
      expect(
        beatsPrevious(load: 45, reps: 12, previousLoad: 45, previousReps: 12),
        isFalse,
      );
      expect(
        beatsPrevious(load: 40, reps: 12, previousLoad: 45, previousReps: 12),
        isFalse,
      );
    });

    test('an incomplete set never counts', () {
      expect(
        beatsPrevious(load: null, reps: 12, previousLoad: 45, previousReps: 8),
        isFalse,
      );
      expect(
        beatsPrevious(load: 45, reps: 12, previousLoad: null, previousReps: 8),
        isFalse,
      );
    });
  });

  group('bodyweightOn', () {
    final log = [
      (dayKey: 20260101, weightKg: 70.0),
      (dayKey: 20260201, weightKg: 72.0),
    ];

    test('interpolates between entries', () {
      // Roughly halfway through January.
      final w = bodyweightOn(20260116, log)!;
      expect(w, greaterThan(70));
      expect(w, lessThan(72));
    });

    test('clamps outside the logged range instead of extrapolating', () {
      expect(bodyweightOn(20251201, log), 70);
      expect(bodyweightOn(20260601, log), 72);
    });

    test('returns null with no log at all', () {
      expect(bodyweightOn(20260101, const []), isNull);
    });

    test('handles unsorted input', () {
      final unsorted = [
        (dayKey: 20260201, weightKg: 72.0),
        (dayKey: 20260101, weightKg: 70.0),
      ];
      expect(bodyweightOn(20260101, unsorted), 70);
    });
  });

  group('stalledSessions', () {
    test('is zero while the most recent session is the best', () {
      expect(stalledSessions([100, 105, 110]), 0);
    });

    test('counts sessions since the best result', () {
      expect(stalledSessions([100, 120, 110, 115]), 2);
    });

    test('ignores sessions with no scoreable sets', () {
      expect(stalledSessions([100, null, 120, null]), 0);
    });

    test('needs at least two data points', () {
      expect(stalledSessions([100]), 0);
      expect(stalledSessions([]), 0);
    });
  });

  test('roundLoad snaps to the nearest half kilo', () {
    expect(roundLoad(74.4), 74.5);
    expect(roundLoad(18.0), 18.0);
    expect(roundLoad(17.6), 17.5);
  });
}
