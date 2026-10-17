import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/chart_density.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Density decided by pixels rather than counts, the audit's findings 15, 17
/// and 18: a series keeps its markers while its neighbours stand far enough
/// apart on screen, a bar never grows into a slab, and a chart too narrow for
/// its weeks folds them coarser.
void main() {
  group('markers', () {
    /// The plot of the exercise trend on a 390 phone, and a year and six
    /// months of it in days.
    const plot = 300.0;
    const year = plot / 365;
    const halfYear = plot / 182;

    List<double> weekly(int count, {double from = 0}) =>
        [for (var i = 0; i < count; i++) from + 7.0 * i];

    test('thirteen weeks squeezed into a year give way to the bare line', () {
      // Finding 15: three months on 1Y, about six pixels between neighbours.
      expect(markersFit(weekly(13, from: 270), year), isFalse);
    });

    test('a series with room keeps its markers whatever the others hold', () {
      // Two series of twenty-six on 6M: fifty-two points, which the old count
      // dropped, though each line has about eleven pixels between points.
      expect(markersFit(weekly(26), halfYear), isTrue);
    });

    test('the closest pair decides, at about ten pixels', () {
      expect(markersFit([0, 10, 40], 1), isTrue);
      expect(markersFit([0, 9.9, 40], 1), isFalse);
      // Unsorted input is read in order of x.
      expect(markersFit([40, 0, 9.9], 1), isFalse);
    });

    test('one reading or none has nothing to touch', () {
      expect(markersFit(const [], year), isTrue);
      expect(markersFit(const [12], year), isTrue);
    });

    test('a pinch spreads the points and brings the markers back', () {
      final points = weekly(52);
      expect(markersFit(points, year), isFalse);
      expect(markersFit(points, year * 2), isTrue);
    });
  });

  group('bars', () {
    test('one week is a bar, not a slab across the plot', () {
      // Finding 17: one bar the full width of a 300 plot. The slot still spans
      // the plot, so a short range is spread across it; only the ink is held.
      expect(barSlot(300, 1), 300);
      expect(barWidth(barSlot(300, 1)), barMaxWidth);
      expect(barWidth(barSlot(300, 5)), barMaxWidth);
    });

    test('many bars share the width evenly, below the cap', () {
      expect(barSlot(300, 52), closeTo(300 / 52, 1e-9));
      expect(barWidth(barSlot(300, 52)), lessThan(barMaxWidth));
    });

    test('no bar is wider than the cap or its slot, and none has no ink', () {
      for (final count in [1, 2, 5, 13, 52, 261, 2600]) {
        for (final width in [44.0, 138.0, 300.0]) {
          final slot = barSlot(width, count);
          final ink = barWidth(slot);
          expect(ink, lessThanOrEqualTo(barMaxWidth));
          expect(ink, lessThanOrEqualTo(slot));
          expect(ink, greaterThan(0));
          expect(slot * count, closeTo(width, 1e-9));
        }
      }
    });

    test('the gap is a share of the slot, and gone below four pixels', () {
      expect(barGap(10), 2);
      expect(barGap(5), 1);
      expect(barGap(barMinSlot - 0.1), 0);
    });

    test('nothing to draw has no slot', () {
      expect(barSlot(300, 0), 0);
      expect(barSlot(0, 12), 0);
    });
  });

  group('folding by width', () {
    List<VolumeWeek> weeks(int count) => [
          for (var i = 0; i < count; i++)
            VolumeWeek(
              start: DateTime(2025, 10, 20).add(Duration(days: 7 * i)),
              sets: 10,
            ),
        ];

    test('a tile at a year draws months, the chart it opens keeps weeks', () {
      // Finding 18: fifty-two weeks in a 138 tile is a slot of 2.7 pixels.
      expect(foldForWidth(weeks(52), Granularity.weekly, 138),
          Granularity.monthly);
      expect(foldForWidth(weeks(52), Granularity.weekly, 300),
          Granularity.weekly);
    });

    test('the finest fold whose slot is at least four pixels', () {
      // Twenty-six weeks in 138 is 5.3 pixels a bar, which is still a bar.
      expect(foldForWidth(weeks(26), Granularity.weekly, 138),
          Granularity.weekly);
      // Thirty-five weeks in 138 is 3.9.
      expect(foldForWidth(weeks(35), Granularity.weekly, 138),
          Granularity.monthly);
    });

    test('never finer than the fold chosen or the weeks allow', () {
      expect(foldForWidth(weeks(13), Granularity.monthly, 300),
          Granularity.monthly);
      // Fifty years of weeks, yearly at any width.
      expect(foldForWidth(weeks(2600), Granularity.weekly, 300),
          Granularity.yearly);
    });

    test('too narrow for months is years', () {
      // Five years is sixty-one months: 1.6 pixels a bar in a 100 tile.
      expect(foldForWidth(weeks(261), Granularity.weekly, 100),
          Granularity.yearly);
    });

    test('nothing in hand keeps the chosen fold', () {
      expect(foldForWidth(const [], Granularity.weekly, 138),
          Granularity.weekly);
    });
  });
}
