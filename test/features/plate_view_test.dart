import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/widgets/plate_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wrapper between the keypad and the best-covered function in the app.
///
/// `solvePlateLoad` is proved to the plate in `plates_test.dart`. This is the
/// four decisions made *before* it is called — and the one that matters is the
/// unit, because a kilogram breakdown drawn for a pounds user is a picture of
/// plates no gym can load.
void main() {
  test('no plate diagram in pounds, and none without a bar', () {
    // A movement with no bar: a dumbbell press has nothing to draw plates on.
    expect(
      plateLoadFor(buffer: '100', barKg: null, unit: WeightUnit.kg),
      isNull,
      reason: 'there is no bar to hang them on',
    );

    // Pounds. The rack in this app is metric — 25s and 20s, not 45s and 35s —
    // so the only honest answer is to draw nothing.
    expect(
      plateLoadFor(buffer: '225', barKg: 20, unit: WeightUnit.lb),
      isNull,
      reason: 'a kilo breakdown under a pounds number is a diagram of plates '
          'the gym does not have',
    );

    // Nothing typed yet, and a buffer that is not a number.
    expect(plateLoadFor(buffer: '', barKg: 20, unit: WeightUnit.kg), isNull);
    expect(plateLoadFor(buffer: '.', barKg: 20, unit: WeightUnit.kg), isNull);

    // Under the bar: `solvePlateLoad`'s own null, passed through rather than
    // turned into an empty diagram.
    expect(plateLoadFor(buffer: '15', barKg: 20, unit: WeightUnit.kg), isNull);
  });

  test('the bar weight exactly draws a bare bar, not nothing', () {
    // Both doc comments on this path said null for a weight "at or under the
    // bar". The code has always drawn a bare bar at exactly the bar, and
    // `plates_test.dart` has always asserted it. The comments were the ones
    // that were wrong, and this is what stops them being written that way
    // again.
    final load = plateLoadFor(buffer: '20', barKg: 20, unit: WeightUnit.kg)!;

    expect(load.isBarOnly, isTrue);
    expect(load.perSide, isEmpty);
    expect(load.loadedKg, 20);
  });

  test('a kilogram number reaches the solver with the number that was typed',
      () {
    // 100 on a 20 bar: 80kg of plates, 40 a side, which the rack makes as a
    // 25 and a 15. Nothing left over.
    final load = plateLoadFor(buffer: '100', barKg: 20, unit: WeightUnit.kg)!;

    expect(load.barKg, 20);
    expect(load.perSide, [(kg: 25.0, count: 1), (kg: 15.0, count: 1)]);
    expect(load.perSideKg, 40);
    expect(load.loadedKg, 100);
    expect(load.remainderKg, 0);
  });

  test('a fractional buffer is parsed rather than truncated', () {
    // 62.5 on a 20 bar: 42.5 of plates, 21.25 a side. The rack cannot make a
    // quarter kilo, so it loads a 20 a side and reports 2.5 short — the
    // keypad's every-other-press case, and the reason `remainderKg` exists.
    final load = plateLoadFor(buffer: '62.5', barKg: 20, unit: WeightUnit.kg)!;

    expect(load.perSide, [(kg: 20.0, count: 1)]);
    expect(load.loadedKg, 60);
    expect(load.remainderKg, 2.5);
  });
}
