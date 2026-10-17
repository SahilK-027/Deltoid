import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/domain/chart_legend.dart';

/// THEME → Charts, the legend: two rows at most with the rest named as
/// `and 3 more`, and one entry for lines drawn on top of each other.
void main() {
  group('legendFit', () {
    double more(int hidden) => 60;

    test('prints every entry where every entry fits in two rows', () {
      // 3 × 100 + 2 × 12 = 324 on a row of 330, and two more on the next.
      expect(
        legendFit([100, 100, 100, 100, 100], 330, moreWidth: more),
        5,
      );
    });

    test('never takes a third row, and leaves room to name the rest', () {
      // Nine sessions at 70 each, four to a row of 330. All nine need three
      // rows; seven and `and 2 more` fill two.
      final shown = legendFit(List.filled(9, 70.0), 330, moreWidth: more);
      expect(shown, 7);
      expect(shown, lessThan(9));
    });

    test('an entry wider than the legend takes a row of its own', () {
      expect(legendFit([500, 40], 330, moreWidth: more), 2);
      expect(legendFit([500, 500, 40], 330, moreWidth: more), 1);
    });

    test('at most two rows for any count and width', () {
      for (var n = 1; n <= 20; n++) {
        for (final width in [120.0, 200.0, 330.0]) {
          final widths = [for (var i = 0; i < n; i++) 40.0 + (i * 17) % 50];
          final shown = legendFit(widths, width, moreWidth: (h) => 64);
          final row = <double>[
            ...widths.take(shown),
            if (shown < n) 64,
          ];
          var rows = 0;
          var used = 0.0;
          for (final w in row) {
            if (rows == 0 || used + legendSpacing + w > width) {
              rows++;
              used = w;
            } else {
              used += legendSpacing + w;
            }
          }
          expect(rows, lessThanOrEqualTo(legendMaxRows),
              reason: '$n entries in $width');
        }
      }
    });

    test('names the rest in words', () {
      expect(legendMore(3), 'and 3 more');
    });
  });

  group('identicalSeries', () {
    List<(double, double?)> flat(double y, {int from = 0, int to = 10}) =>
        [for (var x = from; x <= to; x++) (x.toDouble(), y)];

    test('two lines held at one value are one line', () {
      expect(identicalSeries([flat(100), flat(100)]), [
        [0, 1],
      ]);
    });

    test('lines a value apart are two', () {
      expect(identicalSeries([flat(100), flat(101)]), [
        [0],
        [1],
      ]);
    });

    test('within a pixel of each other they are one', () {
      expect(identicalSeries([flat(100), flat(100.2)], tolerance: 0.25), [
        [0, 1],
      ]);
    });

    test('an earlier line under a longer later one is hidden', () {
      // Push 2 started a week later than Push 1 and has held the same weight.
      expect(identicalSeries([flat(100, from: 2), flat(100)]), [
        [0, 1],
      ]);
    });

    test('an earlier line longer than the later one is still seen', () {
      // Drawn first and reaching further: its first weeks are visible.
      expect(identicalSeries([flat(100), flat(100, from: 2)]), [
        [0],
        [1],
      ]);
    });

    test('a line seen across the other one\'s break is still seen', () {
      final broken = [...flat(100, to: 4), (5.0, null), ...flat(100, from: 6)];
      expect(identicalSeries([flat(100), broken]), [
        [0],
        [1],
      ]);
      // The other way round, the broken one lies on the whole one.
      expect(identicalSeries([broken, flat(100)]), [
        [0, 1],
      ]);
    });

    test('a reading between two of the other\'s is read off its segment', () {
      final rising = [(0.0, 0.0), (10.0, 10.0)];
      final between = [(0.0, 0.0), (5.0, 5.0), (10.0, 10.0)];
      expect(identicalSeries([between, rising]), [
        [0, 1],
      ]);
    });

    test('three lines on top of each other key once, in the top colour', () {
      final groups = identicalSeries([flat(100), flat(100), flat(100), flat(90)]);
      expect(groups, [
        [0, 1, 2],
        [3],
      ]);
      expect(groups.first.last, 2, reason: 'the last is the one on top');
    });

    test('a series with nothing drawn is not a line', () {
      expect(identicalSeries([const [], flat(100)]), [
        [0],
        [1],
      ]);
    });
  });

  test('joinNames lists names as a sentence does', () {
    expect(joinNames(['Push 1']), 'Push 1');
    expect(joinNames(['Push 1', 'Push 2']), 'Push 1 and Push 2');
    expect(
      joinNames(['Push 1', 'Push 2', 'Push 3']),
      'Push 1, Push 2 and Push 3',
    );
  });
}
