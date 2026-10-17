import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/metrics.dart';
import 'package:deltoid/domain/set_format.dart';
import 'package:deltoid/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// The set that [heaviestLogged] ranks, without a database row in sight.
({SetType setType, double? weight, double? addedWeight, int? reps}) s({
  SetType type = SetType.working,
  double? weight,
  double? added,
  int? reps,
}) => (setType: type, weight: weight, addedWeight: added, reps: reps);

void main() {
  group('loadLabel', () {
    test('states the unit beside a plain weight', () {
      expect(
        loadLabel(
          loadMode: LoadMode.total,
          weight: 82.5,
          addedWeight: null,
          unit: WeightUnit.kg,
        ),
        '82.5 kg',
      );
    });

    test('says each for a pair of dumbbells, because two are moving', () {
      expect(
        loadLabel(
          loadMode: LoadMode.perSide,
          weight: 22.5,
          addedWeight: null,
          unit: WeightUnit.kg,
        ),
        '22.5 kg each',
      );
    });

    test('a bodyweight lift names itself and carries no number', () {
      expect(
        loadLabel(
          loadMode: LoadMode.bodyweight,
          weight: null,
          addedWeight: null,
          unit: WeightUnit.kg,
        ),
        'Bodyweight',
      );
    });

    test('added weight of zero is bodyweight, not "BW + 0"', () {
      expect(
        loadLabel(
          loadMode: LoadMode.bodyweightPlus,
          weight: null,
          addedWeight: 0,
          unit: WeightUnit.kg,
        ),
        'Bodyweight',
      );
    });

    test('added weight prints as a sum', () {
      expect(
        loadLabel(
          loadMode: LoadMode.bodyweightPlus,
          weight: null,
          addedWeight: 10,
          unit: WeightUnit.kg,
        ),
        'BW + 10 kg',
      );
    });

    test('nothing recorded is a dash, never a zero (rule 4)', () {
      expect(
        loadLabel(
          loadMode: LoadMode.total,
          weight: null,
          addedWeight: null,
          unit: WeightUnit.kg,
        ),
        '—',
      );
    });

    test('converts to the display unit, rounded to that unit\'s increment', () {
      // A pound is the granularity in pounds, so 100 kg reads as a weight a
      // gym actually has rather than as 220.46.
      expect(
        loadLabel(
          loadMode: LoadMode.total,
          weight: 100,
          addedWeight: null,
          unit: WeightUnit.lb,
        ),
        '220 lb',
      );
    });
  });

  test('a pair is spelled out unless the surface has already said so', () {
    // The default, for a list that stands alone: what you picked up, and that
    // there are two of them.
    expect(
      loadLabel(
        loadMode: LoadMode.perSide,
        weight: 20,
        addedWeight: null,
        unit: WeightUnit.kg,
      ),
      '20 kg each',
    );
    // Off where the load mode is stated beside the list. The suffix would
    // repeat it, using an `×` that means reps in the format next to it.
    expect(
      loadLabel(
        loadMode: LoadMode.perSide,
        weight: 20,
        addedWeight: null,
        unit: WeightUnit.kg,
        pair: false,
      ),
      '20 kg',
    );
    // Nothing else changes: the flag is about the pair and only the pair.
    expect(
      loadLabel(
        loadMode: LoadMode.total,
        weight: 60,
        addedWeight: null,
        unit: WeightUnit.kg,
        pair: false,
      ),
      '60 kg',
    );
  });

  group('loadWithCount', () {
    test('one multiplication sign, and it means reps', () {
      // `20 kg × 2 × 10` is what this printed for a pair of dumbbells: two
      // multiplication signs in one string, the first meaning "a pair" and the
      // second "for ten reps", with nothing to tell them apart. `×` means reps
      // here, on the exercise's history, and in the compressed form, so the
      // pair says itself in words instead.
      final line = loadWithCount(
        loadMode: LoadMode.perSide,
        measureMode: MeasureMode.reps,
        weight: 20,
        addedWeight: null,
        reps: 10,
        unit: WeightUnit.kg,
      );
      expect(line, '20 kg each × 10');
      expect('×'.allMatches(line).length, 1);
    });

    test('appends what was done against the load', () {
      expect(
        loadWithCount(
          loadMode: LoadMode.total,
          measureMode: MeasureMode.reps,
          weight: 82.5,
          addedWeight: null,
          reps: 8,
          unit: WeightUnit.kg,
        ),
        '82.5 kg × 8',
      );
    });

    test('an unloaded hold is its clock alone', () {
      expect(
        loadWithCount(
          loadMode: LoadMode.total,
          measureMode: MeasureMode.hold,
          weight: null,
          addedWeight: null,
          reps: 90,
          unit: WeightUnit.kg,
        ),
        '1:30',
      );
    });

    test(
      'an unloaded rep set says reps rather than printing a bare number',
      () {
        expect(
          loadWithCount(
            loadMode: LoadMode.total,
            measureMode: MeasureMode.reps,
            weight: null,
            addedWeight: null,
            reps: 12,
            unit: WeightUnit.kg,
          ),
          '12 reps',
        );
      },
    );
  });

  group('setLabel', () {
    test('compresses to fit a dense row, with no unit', () {
      expect(
        setLabel(
          loadMode: LoadMode.total,
          measureMode: MeasureMode.reps,
          setType: SetType.working,
          weight: 82.5,
          addedWeight: null,
          reps: 8,
          unit: WeightUnit.kg,
        ),
        '82.5×8',
      );
    });

    test('a warm-up carries its letter so it is not read as a working set', () {
      expect(
        setLabel(
          loadMode: LoadMode.total,
          measureMode: MeasureMode.reps,
          setType: SetType.warmup,
          weight: 40,
          addedWeight: null,
          reps: 10,
          unit: WeightUnit.kg,
        ),
        '40×10 W',
      );
    });
  });

  group('setsOfTotal', () {
    test('the unit agrees with the total', () {
      expect(setsOfTotal(0, 1), '0 of 1 set');
      expect(setsOfTotal(1, 1), '1 of 1 set');
      expect(setsOfTotal(1, 2), '1 of 2 sets');
      expect(setsOfTotal(3, 12), '3 of 12 sets');
      expect(setsOfTotal(0, 0), '0 of 0 sets');
    });

    test('a kind qualifies the unit without changing its number', () {
      expect(setsOfTotal(1, 1, kind: 'working'), '1 of 1 working set');
      expect(setsOfTotal(2, 3, kind: 'working'), '2 of 3 working sets');
    });
  });

  group('heaviestLogged', () {
    test('picks the heaviest, not the last', () {
      final sets = [
        s(weight: 60, reps: 8),
        s(weight: 80, reps: 5),
        s(weight: 70, reps: 6),
      ];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.total,
        ),
        1,
      );
    });

    test('a hold is ranked by its clock, not by the load on it', () {
      // The bug this function exists to close: workout detail ranked a plank by
      // weight, so five sets at zero resolved to whichever came first, while the
      // session summary ranked the same five by duration. Two screens, one day,
      // two different "top sets".
      final sets = [
        s(weight: 0, reps: 45),
        s(weight: 0, reps: 90),
        s(weight: 0, reps: 60),
      ];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.hold,
          loadMode: LoadMode.bodyweight,
        ),
        1,
      );
    });

    test('warm-ups are not what the day was about', () {
      final sets = [
        s(type: SetType.warmup, weight: 100, reps: 5),
        s(weight: 80, reps: 5),
      ];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.total,
        ),
        1,
      );
    });

    test('unless warm-ups are all there is', () {
      final sets = [
        s(type: SetType.warmup, weight: 40, reps: 10),
        s(type: SetType.warmup, weight: 60, reps: 8),
      ];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.total,
        ),
        1,
      );
    });

    test('added weight ranks a weighted chin above an unweighted one', () {
      final sets = [s(added: 0, reps: 10), s(added: 20, reps: 5)];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.bodyweightPlus,
        ),
        1,
      );
    });

    test('a set with no load does not outrank one that has a load', () {
      // The one real disagreement between the two rankers. A `total` exercise has
      // no belt, so `addedWeight` is not load on it — but a ranking reading
      // `weight ?? addedWeight` sorts the second set here as 100 kg while the
      // chart scores it as having no weight at all. One set, two answers.
      //
      // Ranked by effectiveLoad, set 1 has no load and set 0 has 50 kg.
      final sets = [s(weight: 50, reps: 5), s(added: 100, reps: 5)];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.total,
        ),
        0,
      );
    });

    test('a dumbbell day is ranked on the total, and orders the same', () {
      // 22.5 a side is 45 kg. Doubling is monotonic so the order never changes
      // — pinned so that ranking by the typed figure cannot creep back in as
      // an equivalent simplification.
      final sets = [s(weight: 20, reps: 8), s(weight: 22.5, reps: 6)];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.perSide,
        ),
        1,
      );
    });

    test('a back-off day still names what was lifted', () {
      // The card describes the session; the chart decides what counts as
      // progress. On a deliberately light day the chart correctly draws
      // nothing and this correctly says 60 kg. Two questions, two answers.
      final sets = [
        s(type: SetType.warmup, weight: 40, reps: 10),
        s(type: SetType.backoff, weight: 60, reps: 8),
      ];
      expect(
        heaviestLogged(
          sets: sets,
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.total,
        ),
        1,
      );
    });

    test('nothing logged has no top set', () {
      expect(
        heaviestLogged(
          sets: [],
          measureMode: MeasureMode.reps,
          loadMode: LoadMode.total,
        ),
        isNull,
      );
    });
  });

  group('the bodyweight pill', () {
    BodyweightBasis basis(
      BodyweightTrust trust, {
      double kg = 73.2,
      int? days,
    }) => (
      kg: kg,
      trust: trust,
      lastDayKey: days == null ? null : 20260101,
      daysOld: days,
    );

    test('a recent weigh-in is the figure and nothing else', () {
      final recent = basis(BodyweightTrust.logged, days: 2);
      expect(bodyweightBasisLabel(recent, WeightUnit.kg), '73.2 kg');
      expect(bodyweightPillDetail(recent, 95, WeightUnit.kg), '+69.5 kg (95%)');
      expect(
        bodyweightRecordedLine(
          recent,
          WeightUnit.kg,
          lastRecorded: '8 Jan 2026',
        ),
        'Last recorded on 8 Jan 2026',
      );
    });

    test('an old weigh-in says how old', () {
      final stale = basis(BodyweightTrust.stale, days: 12);
      expect(bodyweightBasisLabel(stale, WeightUnit.kg), '73.2 kg');
      expect(bodyweightPillDetail(stale, 95, WeightUnit.kg), '12 days old');
      expect(
        bodyweightRecordedLine(
          stale,
          WeightUnit.kg,
          lastRecorded: '8 Jan 2026',
        ),
        'Last recorded on 8 Jan 2026, 12 days ago. Log your latest weight for '
        'an accurate strength trend.',
      );
    });

    test('nothing logged says the figure is assumed', () {
      final assumed = basis(BodyweightTrust.assumed, kg: 60);
      expect(bodyweightBasisLabel(assumed, WeightUnit.kg), '60 kg');
      expect(bodyweightPillDetail(assumed, 95, WeightUnit.kg), 'assumed');
      expect(
        bodyweightRecordedLine(assumed, WeightUnit.kg, lastRecorded: null),
        'No weight is recorded, so 60 kg is assumed. Log your weight for an '
        'accurate strength trend.',
      );
    });

    test('the assumed figure is printed in the unit the phone shows', () {
      final assumed = basis(BodyweightTrust.assumed, kg: 60);
      expect(bodyweightBasisLabel(assumed, WeightUnit.lb), startsWith('132'));
    });

    test('the second line is what the movement takes from it', () {
      // 95 per cent of 72.5 kg is 68.875 kg.
      expect(bodyweightMovedLabel(72.5, 95, WeightUnit.kg), '+68.9 kg (95%)');
      expect(bodyweightMovedLabel(75, 64, WeightUnit.kg), '+48 kg (64%)');
      expect(bodyweightMovedLabel(73.2, 100, WeightUnit.kg), '+73.2 kg (100%)');
    });

    test('the sentence under the resistance names the share', () {
      expect(
        bodyweightLoadBlurb(LoadMode.bodyweight, 64),
        'This is the part of your bodyweight that counts as resistance on '
        'this movement, 64% of it. It is what your charts, volume and cycle '
        'progress are worked out from.',
      );
      expect(
        bodyweightLoadBlurb(LoadMode.bodyweightPlus, 95),
        endsWith('The weight you add is counted on top.'),
      );
    });
  });
}
