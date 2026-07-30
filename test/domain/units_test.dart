import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/prefill.dart';
import 'package:deltoid/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeightUnit', () {
    test('kilograms are the identity, because storage is kilograms', () {
      expect(WeightUnit.kg.toKg(22.5), 22.5);
      expect(WeightUnit.kg.display(22.5), 22.5);
      expect(formatInUnit(22.5, WeightUnit.kg), '22.5');
    });

    test('pounds convert both ways without drifting', () {
      final kg = WeightUnit.lb.toKg(225);
      expect(kg, closeTo(102.058, 0.001));
      expect(WeightUnit.lb.display(kg), 225);
    });

    test('a displayed weight is snapped to what a gym actually has', () {
      // 100 kg is 220.462… lb, and no rack has that plate.
      expect(WeightUnit.lb.display(100), 220);
      expect(formatInUnit(100, WeightUnit.lb), '220');
      // Half a kilo is the smallest microplate in normal use.
      expect(WeightUnit.kg.display(74.4), 74.5);
    });

    test('the plate step is a pair of plates in each unit', () {
      expect(WeightUnit.kg.step, 2.5);
      expect(WeightUnit.lb.step, 5);
    });

    test('an unknown or missing setting means kilograms', () {
      expect(WeightUnitX.parse(null), WeightUnit.kg);
      expect(WeightUnitX.parse('stones'), WeightUnit.kg);
      expect(WeightUnitX.parse('lb'), WeightUnit.lb);
    });
  });

  group('roundLoadIn', () {
    test('snaps to a half kilo in kg', () {
      expect(roundLoadIn(74.4, WeightUnit.kg), 74.5);
      expect(roundLoadIn(17.6, WeightUnit.kg), 17.5);
    });

    test('snaps to a whole pound in lb, still stored as kg', () {
      final kg = roundLoadIn(WeightUnit.lb.toKg(180.4), WeightUnit.lb);
      expect(WeightUnit.lb.display(kg), 180);
    });
  });

  test('a deload in pounds lands on a weight you can load', () {
    // 225 lb at 80% is 180 lb, not 81.65 kg rendered as 180.0000001.
    final sets = [
      PastSet(
        type: SetType.working,
        weight: WeightUnit.lb.toKg(225),
        reps: 5,
      ),
    ];

    final out = applyDeload(
      sets,
      setDelta: 0,
      weightPct: 80,
      unit: WeightUnit.lb,
    );

    expect(WeightUnit.lb.display(out.single.weight!), 180);
  });
}
