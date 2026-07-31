import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/plates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('solvePlateLoad', () {
    test('splits the load over both ends, heaviest plate first', () {
      final load = solvePlateLoad(totalKg: 100, barKg: 20)!;

      expect(load.perSide, [(kg: 25.0, count: 1), (kg: 15.0, count: 1)]);
      expect(load.perSideKg, 40);
      expect(load.loadedKg, 100);
      expect(load.remainderKg, 0);
    });

    test('stacks the same plate rather than reaching for a lighter one', () {
      final load = solvePlateLoad(totalKg: 140, barKg: 20)!;

      expect(load.perSide, [(kg: 25.0, count: 2), (kg: 10.0, count: 1)]);
      expect(load.loadedKg, 140);
    });

    test('an empty bar loads nothing', () {
      final load = solvePlateLoad(totalKg: 20, barKg: 20)!;

      expect(load.isBarOnly, isTrue);
      expect(load.perSide, isEmpty);
      expect(load.loadedKg, 20);
    });

    test('under the bar has no diagram at all', () {
      expect(solvePlateLoad(totalKg: 15, barKg: 20), isNull);
      expect(solvePlateLoad(totalKg: 0, barKg: 20), isNull);
    });

    test('no bar, no plate maths', () {
      expect(solvePlateLoad(totalKg: 100, barKg: 0), isNull);
    });

    test('reports what the rack cannot make instead of rounding it away', () {
      // 2.5 is the lightest plate, so the bar moves in 5kg steps. The keypad's
      // 2.5kg step lands between two of them every other press.
      final load = solvePlateLoad(totalKg: 62.5, barKg: 20)!;

      expect(load.remainderKg, 2.5);
      expect(load.loadedKg, 60);
      expect(load.perSide, [(kg: 20.0, count: 1)]);
    });

    test('an odd bar weight still lands on whole plates', () {
      // The EZ is 9kg, so every loadable total on it is odd-ish: 29 = a 10 a
      // side. Worth pinning because a subtraction loop in doubles leaves a
      // remainder small enough to print as "0.0000000000000004 kg short"
      // under a correctly loaded bar.
      final load = solvePlateLoad(totalKg: 29, barKg: BarKind.ez.kg!)!;

      expect(load.perSide, [(kg: 10.0, count: 1)]);
      expect(load.remainderKg, 0);
      expect(load.loadedKg, 29);
    });

    test('the bars are the ones in this gym, not the catalogue ones', () {
      expect(BarKind.olympic.kg, 20);
      expect(BarKind.womens.kg, 16);
      expect(BarKind.ez.kg, 9);
      expect(BarKind.trap.kg, 25);
      expect(BarKind.none.kg, isNull);
    });

    test('every bar kind but none carries a weight', () {
      for (final kind in BarKind.values) {
        expect(
          kind.kg,
          kind == BarKind.none ? isNull : isNonZero,
          reason: '${kind.name} has the wrong idea of an empty bar',
        );
      }
    });
  });
}
