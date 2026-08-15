import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/set_format.dart';
import 'package:deltoid/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// The set that [heaviestLogged] ranks, without a database row in sight.
({SetType setType, double? weight, double? addedWeight, int? reps}) s({
  SetType type = SetType.working,
  double? weight,
  double? added,
  int? reps,
}) =>
    (setType: type, weight: weight, addedWeight: added, reps: reps);

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

    test('says × 2 for a pair of dumbbells, because two are moving', () {
      expect(
        loadLabel(
          loadMode: LoadMode.perSide,
          weight: 22.5,
          addedWeight: null,
          unit: WeightUnit.kg,
        ),
        '22.5 kg × 2',
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

  group('loadWithCount', () {
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

    test('an unloaded rep set says reps rather than printing a bare number', () {
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
    });
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

  group('heaviestLogged', () {
    test('picks the heaviest, not the last', () {
      final sets = [
        s(weight: 60, reps: 8),
        s(weight: 80, reps: 5),
        s(weight: 70, reps: 6),
      ];
      expect(heaviestLogged(sets: sets, measureMode: MeasureMode.reps, loadMode: LoadMode.total), 1);
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
      expect(heaviestLogged(sets: sets, measureMode: MeasureMode.hold, loadMode: LoadMode.bodyweight), 1);
    });

    test('warm-ups are not what the day was about', () {
      final sets = [
        s(type: SetType.warmup, weight: 100, reps: 5),
        s(weight: 80, reps: 5),
      ];
      expect(heaviestLogged(sets: sets, measureMode: MeasureMode.reps, loadMode: LoadMode.total), 1);
    });

    test('unless warm-ups are all there is', () {
      final sets = [
        s(type: SetType.warmup, weight: 40, reps: 10),
        s(type: SetType.warmup, weight: 60, reps: 8),
      ];
      expect(heaviestLogged(sets: sets, measureMode: MeasureMode.reps, loadMode: LoadMode.total), 1);
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
      // no belt, so `addedWeight` is not load on it — but the old ranking read
      // `weight ?? addedWeight`, so the second set here sorted as 100 kg while
      // the chart scored it as having no weight at all. One set, two answers.
      //
      // Ranked by effectiveLoad, set 1 has no load and set 0 has 50 kg.
      final sets = [
        s(weight: 50, reps: 5),
        s(added: 100, reps: 5),
      ];
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
      expect(heaviestLogged(sets: [], measureMode: MeasureMode.reps, loadMode: LoadMode.total), isNull);
    });
  });
}
