import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('effectiveLoad', () {
    test('doubles per-side dumbbell entries', () {
      expect(effectiveLoad(mode: LoadMode.perSide, weight: 22.5), 45);
    });

    test('takes machine and barbell entries at face value', () {
      expect(effectiveLoad(mode: LoadMode.total, weight: 73), 73);
    });

    test('bodyweight lifts use logged bodyweight', () {
      expect(effectiveLoad(mode: LoadMode.bodyweight, bodyweightKg: 72), 72);
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

    test(
      'bodyweight-plus without a bodyweight log falls back to added only',
      () {
        expect(
          effectiveLoad(mode: LoadMode.bodyweightPlus, addedWeight: 10),
          10,
        );
      },
    );
  });

  group('sessionVolume', () {
    List<
      ({
        LoadMode mode,
        MeasureMode measure,
        int bodyweightPct,
        List<ScoredSet> sets,
      })
    >
    one(
      LoadMode mode,
      List<ScoredSet> sets, {
      MeasureMode measure = MeasureMode.reps,
      int bodyweightPct = 100,
    }) => [
      (mode: mode, measure: measure, bodyweightPct: bodyweightPct, sets: sets),
    ];

    test('a push-up day counts the part of the body a push-up moves', () {
      final volume = sessionVolume(
        bodyweightKg: 75,
        exercises: one(LoadMode.bodyweight, const [
          ScoredSet(type: SetType.working, reps: 10),
        ], bodyweightPct: 64),
      );
      expect(volume, closeTo(480, 1e-9));
    });

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

    test(
      'with no bodyweight ever logged it is zero, for the caller to dash',
      () {
        expect(
          sessionVolume(
            exercises: one(LoadMode.bodyweight, const [
              ScoredSet(type: SetType.working, reps: 8),
            ]),
          ),
          0,
        );
      },
    );
  });

  group('estimated1RM', () {
    test('matches Epley', () {
      expect(estimated1RM(load: 100, reps: 6), closeTo(120, 1e-9));
    });

    test('caps reps so high-rep sets cannot masquerade as strength', () {
      // Epley at the cap: 50 * (1 + 12/30) = 50 * 1.4 = 70.
      expect(estimated1RM(load: 50, reps: 12), closeTo(70, 1e-9));
      // 20 reps is scored as 12, so it lands on the same 70 rather than on
      // 50 * (1 + 20/30) = 83.333…, which is the number the cap exists to
      // refuse.
      expect(estimated1RM(load: 50, reps: 20), closeTo(70, 1e-9));
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
            bodyweightPct: 100,
            sets: const [ScoredSet(type: SetType.working, weight: 60, reps: 5)],
          ),
          (
            mode: LoadMode.bodyweight,
            measure: MeasureMode.hold,
            bodyweightPct: 100,
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

    test('partials ride alongside the count and never inside it', () {
      expect(formatCount(8, MeasureMode.reps, partial: 3), '8+3');
      // None to speak of reads exactly as it did before partials existed.
      expect(formatCount(8, MeasureMode.reps, partial: 0), '8');
      expect(formatCount(8, MeasureMode.reps, partial: null), '8');
      // A hold has no half-second, so a stray value cannot reach the clock.
      expect(formatCount(145, MeasureMode.hold, partial: 3), '2:25');
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
      // estimated1RM caps at 12, so both sides score identically there:
      // 45 * (1 + 12/30) = 45 * 1.4 = 63, at 12 reps and at 13.
      expect(estimated1RM(load: 45, reps: 12), closeTo(63, 1e-9));
      expect(estimated1RM(load: 45, reps: 13), closeTo(63, 1e-9));
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

    test('heavier for fewer reps is a wash when the estimate says so', () {
      // 45 * 1.4 = 63.0 against 50 * (1 + 8/30) = 63.3. Half a percent apart:
      // the same set, as far as a formula can tell, and the strict rule was
      // written to keep exactly this unlit.
      expect(estimated1RM(load: 45, reps: 12), closeTo(63, 1e-9));
      expect(estimated1RM(load: 50, reps: 8), closeTo(63.333, 1e-3));
      expect(
        beatsPrevious(load: 50, reps: 8, previousLoad: 45, previousReps: 12),
        isFalse,
      );
    });

    test('heavier for fewer reps is a win when the estimate is clear', () {
      // 72 * 1.4 = 100.8 against 100 * (1 + 8/30) = 126.7 — a quarter better.
      // Four reps were given up and it is still unambiguously the better set.
      expect(
        beatsPrevious(load: 100, reps: 8, previousLoad: 72, previousReps: 12),
        isTrue,
      );
    });

    test('the gain has to clear the margin, not merely exist', () {
      // 2.4% up: inside the noise, and not lit.
      expect(
        beatsPrevious(
          load: 46.05,
          reps: 12,
          previousLoad: 45,
          previousReps: 13,
        ),
        isFalse,
      );
      // 2.7% up, same shape of set: lit.
      expect(
        beatsPrevious(load: 46.2, reps: 12, previousLoad: 45, previousReps: 13),
        isTrue,
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
      // Lighter and fewer reps: neither rule has anything to say for it.
      expect(
        beatsPrevious(load: 40, reps: 8, previousLoad: 45, previousReps: 12),
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

  group('the share of bodyweight a movement moves', () {
    test('a push-up moves 64 per cent of the body', () {
      expect(bodyweightMoved(75, 64), closeTo(48, 1e-9));
      expect(
        effectiveLoad(
          mode: LoadMode.bodyweight,
          bodyweightKg: 75,
          bodyweightPct: 64,
        ),
        closeTo(48, 1e-9),
      );
    });

    test('added weight is added whole, on top of the share', () {
      // A 10 kg plate on a push-up is 10 kg, not 64 per cent of it.
      expect(
        effectiveLoad(
          mode: LoadMode.bodyweightPlus,
          bodyweightKg: 75,
          bodyweightPct: 64,
          addedWeight: 10,
        ),
        closeTo(58, 1e-9),
      );
    });

    test('a movement with no share stated moves the whole body', () {
      expect(effectiveLoad(mode: LoadMode.bodyweight, bodyweightKg: 75), 75);
    });

    test('a loaded movement does not read the share', () {
      expect(
        effectiveLoad(mode: LoadMode.total, weight: 100, bodyweightPct: 64),
        100,
      );
      expect(
        effectiveLoad(mode: LoadMode.perSide, weight: 20, bodyweightPct: 64),
        40,
      );
    });

    test('the same plate is a bigger step on a push-up than on a pull-up', () {
      double? best(int pct, double added) => scorePerformance(
        mode: LoadMode.bodyweightPlus,
        bodyweightKg: 75,
        bodyweightPct: pct,
        sets: [ScoredSet(type: SetType.working, addedWeight: added, reps: 5)],
      ).best1RM;

      // 48 → 58 kg on the push-up, 71.25 → 81.25 on the pull-up.
      final pushUp = best(64, 10)! / best(64, 0)! - 1;
      final pullUp = best(95, 10)! / best(95, 0)! - 1;
      expect(pushUp, closeTo(10 / 48, 1e-9));
      expect(pullUp, closeTo(10 / 71.25, 1e-9));
      expect(pushUp, greaterThan(pullUp));
    });
  });

  group('bodyweightBasis', () {
    const log = [
      (dayKey: 20260101, weightKg: 70.0),
      (dayKey: 20260110, weightKg: 72.0),
    ];

    test('nothing logged is the assumed figure, and says so', () {
      final basis = bodyweightBasis(20260115, const []);
      expect(basis.kg, 60);
      expect(basis.trust, BodyweightTrust.assumed);
      expect(basis.lastDayKey, isNull);
      expect(basis.daysOld, isNull);
    });

    test('a weigh-in a week old is still current', () {
      final basis = bodyweightBasis(20260117, log);
      expect(basis.kg, 72);
      expect(basis.trust, BodyweightTrust.logged);
      expect(basis.lastDayKey, 20260110);
      expect(basis.daysOld, 7);
    });

    test('a weigh-in eight days old is stale', () {
      final basis = bodyweightBasis(20260118, log);
      expect(basis.kg, 72);
      expect(basis.trust, BodyweightTrust.stale);
      expect(basis.daysOld, 8);
    });

    test('age is counted in days across a month end, not in keys', () {
      // 28 January to 4 February is 7 days and 76 key units.
      final basis = bodyweightBasis(20260204, const [
        (dayKey: 20260128, weightKg: 71.0),
      ]);
      expect(basis.daysOld, 7);
      expect(basis.trust, BodyweightTrust.logged);
    });

    test('a day before the newest weigh-in is not stale', () {
      // A session backfilled to a day between two entries, or before the
      // first, is scored on real entries taken around it.
      final between = bodyweightBasis(20260105, log);
      expect(between.kg, closeTo(70.8889, 1e-4));
      expect(between.trust, BodyweightTrust.logged);
      expect(between.daysOld, 0);

      final before = bodyweightBasis(20251201, log);
      expect(before.kg, 70);
      expect(before.trust, BodyweightTrust.logged);
    });
  });

  group('a weighted bodyweight lift with nothing logged', () {
    test('is scored on the assumed bodyweight plus the added weight', () {
      final kg = bodyweightOn(20260101, const []);
      expect(
        effectiveLoad(
          mode: LoadMode.bodyweightPlus,
          addedWeight: 10,
          bodyweightKg: kg,
        ),
        70,
      );
      // 10 kg to 12.5 kg added is 70 to 72.5, not a quarter more.
      expect(
        effectiveLoad(
          mode: LoadMode.bodyweightPlus,
          addedWeight: 12.5,
          bodyweightKg: kg,
        ),
        72.5,
      );
    });
  });

  group('bodyweightOn', () {
    final log = [
      (dayKey: 20260101, weightKg: 70.0),
      (dayKey: 20260201, weightKg: 72.0),
    ];

    test('interpolates in days, not in date keys', () {
      // 1 Jan = 70.0, 1 Feb = 72.0. 16 Jan is 15 of the 31 days between them.
      // 70 + 2 * (15 / 31) = 70.967741935…
      //
      // A dayKey is not a day count. Interpolating on the key reads the gap as
      // 100 units and 16 Jan as 15 of them, which lands on 70.3 — the whole of
      // the error, and it is worst across a month or a year boundary, which is
      // exactly where a monthly weigh-in habit puts it.
      expect(bodyweightOn(20260116, log), closeTo(70.9677, 1e-4));
    });

    test('interpolates across a year boundary in days', () {
      // 1 Dec 2025 = 70.0, 31 Jan 2026 = 74.0, asked for 1 Jan 2026.
      // 61 days apart, 1 Jan is day 31. 70 + 4 * (31 / 61) = 72.032786885…
      //
      // On the keys the gap reads as 8 930 and 1 Jan as 8 900 of them — 73.99,
      // nearly two kilograms out, because the key jumps a year in one day.
      final acrossNewYear = [
        (dayKey: 20251201, weightKg: 70.0),
        (dayKey: 20260131, weightKg: 74.0),
      ];
      expect(bodyweightOn(20260101, acrossNewYear), closeTo(72.0328, 1e-4));
    });

    test('interpolates across a month end in days', () {
      // 28 Jan = 70.0, 4 Feb = 71.0, asked for 1 Feb: 4 of 7 days.
      // 70 + 1 * (4 / 7) = 70.571428571…
      final acrossMonthEnd = [
        (dayKey: 20260128, weightKg: 70.0),
        (dayKey: 20260204, weightKg: 71.0),
      ];
      expect(bodyweightOn(20260201, acrossMonthEnd), closeTo(70.5714, 1e-4));
    });

    test('clamps outside the logged range instead of extrapolating', () {
      expect(bodyweightOn(20251201, log), 70);
      expect(bodyweightOn(20260601, log), 72);
    });

    test('assumes a bodyweight when none has ever been logged', () {
      expect(bodyweightOn(20260101, const []), 60);
      expect(assumedBodyweightKg, 60);
    });

    test('handles unsorted input', () {
      final unsorted = [
        (dayKey: 20260201, weightKg: 72.0),
        (dayKey: 20260101, weightKg: 70.0),
      ];
      expect(bodyweightOn(20260101, unsorted), 70);
    });

    test('lands on an entry rather than interpolating past it', () {
      final three = [
        (dayKey: 20260101, weightKg: 70.0),
        (dayKey: 20260201, weightKg: 72.0),
        (dayKey: 20260301, weightKg: 80.0),
      ];
      expect(bodyweightOn(20260201, three), 72);
    });

    test('two entries on one day take the later reading', () {
      final sameDay = [
        (dayKey: 20260101, weightKg: 70.0),
        (dayKey: 20260201, weightKg: 72.0),
        (dayKey: 20260201, weightKg: 73.0),
        (dayKey: 20260301, weightKg: 80.0),
      ];
      expect(bodyweightOn(20260201, sameDay), 73);
    });

    test('interpolates the same whatever order the entries arrive in', () {
      final ordered = [
        (dayKey: 20260101, weightKg: 70.0),
        (dayKey: 20260201, weightKg: 72.0),
        (dayKey: 20260301, weightKg: 80.0),
      ];
      final shuffled = [ordered[2], ordered[0], ordered[1]];
      for (final day in [20260115, 20260220, 20260301, 20251101]) {
        expect(bodyweightOn(day, shuffled), bodyweightOn(day, ordered));
      }

      // Both sides of the loop above are the same function, so it proves the
      // sort and nothing about the value. The literals are what pin that:
      //   15 Jan — 14 of the 31 days from 1 Jan to 1 Feb: 70 + 2 * 14/31
      //   20 Feb — 19 of the 28 days from 1 Feb to 1 Mar: 72 + 8 * 19/28
      expect(bodyweightOn(20260115, shuffled), closeTo(70.9032, 1e-4));
      expect(bodyweightOn(20260220, shuffled), closeTo(77.4286, 1e-4));
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

    test('counts a session that equals the best as the best', () {
      // A year of identical sessions printed `98 sessions since best`.
      expect(stalledSessions([100, 100, 100, 100]), 0);
      expect(stalledSessions([100, 120, 110, 120]), 0);
      expect(stalledSessions([100, 120, 120, 110, 115]), 2);
    });
  });

  group('latestSessionChange', () {
    test('compares the latest session with itself, never with the other', () {
      // Push 1 is heavier than Push 2. First Push 1 against last Push 2 was a
      // drop of 20%; Push 2 itself went from 80 to 82, which is +2.5%.
      final change = latestSessionChange([
        (session: 'Push 1', value: 100),
        (session: 'Push 2', value: 80),
        (session: 'Push 1', value: 102),
        (session: 'Push 2', value: 82),
      ]);
      expect(change?.session, 'Push 2');
      expect(change?.percent, closeTo(2.5, 1e-9));
    });

    test('reads the session the last entry belongs to', () {
      final change = latestSessionChange([
        (session: 'Push 2', value: 80),
        (session: 'Push 1', value: 100),
        (session: 'Push 2', value: 84),
        (session: 'Push 1', value: 95),
      ]);
      expect(change?.session, 'Push 1');
      expect(change?.percent, closeTo(-5, 1e-9));
    });

    test('skips entries it cannot score', () {
      final change = latestSessionChange([
        (session: 'Push 1', value: null),
        (session: 'Push 1', value: 100),
        (session: 'Push 1', value: 110),
        (session: 'Push 2', value: null),
      ]);
      expect(change?.session, 'Push 1');
      expect(change?.percent, closeTo(10, 1e-9));
    });

    test('is null with one performance of that session, or none', () {
      expect(
        latestSessionChange([
          (session: 'Push 1', value: 100),
          (session: 'Push 1', value: 104),
          (session: 'Push 2', value: 80),
        ]),
        isNull,
      );
      expect(latestSessionChange([]), isNull);
      expect(latestSessionChange([(session: 'Push 1', value: null)]), isNull);
    });

    test('is null on a base of zero', () {
      expect(
        latestSessionChange([
          (session: 'Plank', value: 0),
          (session: 'Plank', value: 30),
        ]),
        isNull,
      );
    });
  });

  group('formatChangePercent', () {
    test('signs a gain and a loss, with a true minus', () {
      expect(formatChangePercent(3.44), '+3.4%');
      expect(formatChangePercent(-2.2), '−2.2%');
    });

    test('prints a change that rounds to nothing as 0%, with no sign', () {
      expect(formatChangePercent(0), '0%');
      expect(formatChangePercent(0.04), '0%');
      expect(formatChangePercent(-0.04), '0%');
    });
  });

  test('roundLoad snaps to the nearest half kilo', () {
    expect(roundLoad(74.4), 74.5);
    expect(roundLoad(18.0), 18.0);
    expect(roundLoad(17.6), 17.5);
  });
}
