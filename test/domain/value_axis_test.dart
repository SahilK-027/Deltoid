import 'package:deltoid/domain/value_axis.dart';
import 'package:flutter_test/flutter_test.dart';

/// The value axis every chart draws, held to THEME → Charts and to the chart
/// audit's findings 1, 3, 4, 7, 11, 23 and 24. Every expected band here is
/// worked by hand from the rules in `value_axis.dart`.

/// A label as the bodyweight chart prints it: one decimal, `80` not `80.0`.
String oneDecimal(double v) {
  final rounded = (v * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

String whole(double v) => v.round().toString();

String percent(double v) {
  final r = v.round();
  return '${r > 0 ? '+' : (r < 0 ? '−' : '')}${r.abs()}%';
}

void main() {
  group('trend', () {
    test('is the data plus air, with up to four gridlines on a round step', () {
      // 75 to 131: a step of 10 puts six gridlines in, 20 puts four. The air
      // is half a step and snapped to it: 65 floors to 60, 141 ceils to 150.
      final axis = ValueAxis.trend([
        [75, 90, 105, 120, 131],
      ], format: whole);
      expect(axis.step, 20);
      expect(axis.min, 60);
      expect(axis.max, 150);
      expect(axis.gridlines, [80, 100, 120, 140]);
      expect(axis.labels, ['80', '100', '120', '140']);
    });

    test('five gridlines rather than two when the ladder skips three and '
        'four', () {
      // 77 to 94: a step of 5 puts five gridlines in 72.5 to 97.5, and 10
      // puts two in 70 to 100.
      final axis = ValueAxis.trend([
        [77, 85, 94],
      ], format: whole);
      expect(axis.step, 5);
      expect(axis.gridlines, [75, 80, 85, 90, 95]);
    });

    test('is never anchored at zero unless zero is in the data', () {
      final bodyweight = ValueAxis.trend(
        [
          [80, 82],
        ],
        format: oneDecimal,
        minStep: 0.1,
      );
      expect(bodyweight.min, greaterThan(70));

      final fromZero = ValueAxis.trend([
        [0, 4, 9],
      ], format: whole);
      expect(fromZero.min, 0);
    });

    test('never draws air below zero for values that cannot be negative', () {
      final axis = ValueAxis.trend(
        [
          [0.05, 1.5, 3],
        ],
        format: oneDecimal,
        minStep: 0.1,
      );
      // A step of 1: half a step under 0.05 is below zero, so it stops there.
      expect(axis.min, 0);
      expect(axis.gridlines, [1, 2, 3]);
    });

    test('a narrow band never repeats a label (finding 3)', () {
      // 0.1 kg over a year, with no least span: the step cannot go below the
      // 0.1 the labels print, and no two of them may print the same.
      final axis = ValueAxis.trend(
        [
          [80.0, 80.02, 80.05, 80.08, 80.1],
        ],
        format: oneDecimal,
        minStep: 0.1,
      );
      expect(axis.labels.toSet().length, axis.labels.length);
      expect(axis.gridlines, isNotEmpty);
    });

    test('a label is the value of its gridline, never a rounding of it '
        '(finding 3)', () {
      // A week of weigh-ins between 81.7 and 82.4. A step of 0.25 printed
      // 82.25 as `82.3`; the ladder at a precision of 0.1 skips 0.25, so the
      // steps are 0.1 (eight gridlines) and then 0.2 (four).
      final axis = ValueAxis.trend(
        [
          [81.7, 82.4, 81.9, 82.3, 82.0],
        ],
        format: oneDecimal,
        minStep: 0.1,
      );
      expect(axis.step, 0.2);
      expect(axis.gridlines, [81.8, 82.0, 82.2, 82.4]);
      expect(axis.labels, ['81.8', '82', '82.2', '82.4']);
      for (var i = 0; i < axis.gridlines.length; i++) {
        expect(double.parse(axis.labels[i]), axis.gridlines[i]);
      }
    });

    test('noise under the least span is drawn level, not as a climb', () {
      // 80.0 to 80.1 under a least span of 2 kg is centred: 79.05 to 81.05.
      // A step of 0.5 leaves five gridlines inside the band, 1 leaves three.
      final axis = ValueAxis.trend(
        [
          [80.0, 80.05, 80.1],
        ],
        format: oneDecimal,
        minStep: 0.1,
        minSpan: 2,
      );
      expect(axis.step, 1);
      expect(axis.min, 78.5);
      expect(axis.max, 82);
      expect(axis.labels, ['79', '80', '81']);
    });

    test('a single value has three gridlines and sits on the middle one '
        '(finding 4)', () {
      // 100 kg with a least span of 5%: 97.5 to 102.5. A step of 1 leaves
      // five gridlines, 2 leaves three, and 100 is the middle one.
      final axis = ValueAxis.trend(
        [
          [100],
        ],
        format: whole,
        minStep: 0.5,
        minSpanFraction: 0.05,
      );
      expect(axis.step, 2);
      expect(axis.min, 96);
      expect(axis.max, 104);
      expect(axis.gridlines, [98, 100, 102]);
    });

    test('a flat line with nothing set gets a band of a tenth of its value '
        '(finding 4)', () {
      // 95 to 105: steps of 2 and 2.5 leave five gridlines, 5 leaves three.
      final axis = ValueAxis.trend([
        [100, 100, 100],
      ], format: oneDecimal);
      expect(axis.step, 5);
      expect(axis.gridlines, [95, 100, 105]);
    });

    test('a single bodyweight draws three labelled gridlines (finding 4)', () {
      final axis = ValueAxis.trend(
        [
          [80.3],
        ],
        format: oneDecimal,
        minStep: 0.1,
        minSpan: 2,
      );
      expect(axis.gridlines.length, inInclusiveRange(3, 4));
      expect(axis.min, lessThan(80.3));
      expect(axis.max, greaterThan(80.3));
    });

    test('an empty chart is still an axis with gridlines', () {
      final axis = ValueAxis.trend(const [], format: whole);
      expect(axis.gridlines, isNotEmpty);
      expect(axis.min, 0);
    });

    test('the zero-to-round-number band an untrained movement is drawn on', () {
      final axis = ValueAxis.trend(
        [
          [0, 100],
        ],
        format: whole,
        minStep: 0.5,
      );
      expect(axis.min, 0);
      expect(axis.gridlines, [25, 50, 75, 100]);
    });

    test('two to five gridlines at every data size', () {
      for (final span in [0.3, 1.0, 7.0, 42.0, 180.0, 1300.0]) {
        final axis = ValueAxis.trend(
          [
            [100, 100 + span / 2, 100 + span],
          ],
          format: oneDecimal,
          minStep: 0.1,
        );
        expect(
          axis.gridlines.length,
          inInclusiveRange(2, 4),
          reason: 'a span of $span drew ${axis.labels}',
        );
        expect(axis.labels.toSet().length, axis.labels.length);
        expect(axis.min, lessThanOrEqualTo(100));
        expect(axis.max, greaterThanOrEqualTo(100 + span));
      }
    });
  });

  group('off-scale (finding 23)', () {
    test(
      'one typo goes off the top as a caret, and the band fits the rest',
      () {
        final axis = ValueAxis.trend([
          [100, 101, 102, 260, 103, 104],
        ], format: whole);
        expect(axis.offScale, hasLength(1));
        final off = axis.offScale.single;
        expect(
          (off.series, off.index, off.value, off.edge),
          (0, 3, 260.0, OffScaleEdge.top),
        );
        expect(axis.max, lessThan(120));
        expect(axis.place(0, 3, 260), axis.max);
        expect(axis.place(0, 2, 102), 102);
      },
    );

    test(
      'one typo goes off the bottom, and the axis is not dragged to zero',
      () {
        final axis = ValueAxis.trend([
          [100, 101, 0, 102, 103],
        ], format: whole);
        expect(axis.offScale.single.edge, OffScaleEdge.bottom);
        expect(axis.offScale.single.index, 2);
        expect(axis.min, greaterThan(90));
        expect(axis.place(0, 2, 0), axis.min);
      },
    );

    test('a run of two is a trend and stays on the scale', () {
      final axis = ValueAxis.trend([
        [100, 101, 260, 261, 102, 103],
      ], format: whole);
      expect(axis.offScale, isEmpty);
      expect(axis.max, greaterThanOrEqualTo(261));
    });

    test('the first and last points of a line never go off-scale', () {
      // The newest cycle at the top is where the line is going, not a typo.
      final axis = ValueAxis.trend([
        [100, 101, 102, 260],
        [0, 103, 104],
      ], format: whole);
      expect(axis.offScale, isEmpty);
    });

    test('a chart of two points has no off-scale point', () {
      final axis = ValueAxis.trend([
        [100, 260],
      ], format: whole);
      expect(axis.offScale, isEmpty);
    });

    test('a steady climb is never clipped', () {
      final axis = ValueAxis.trend([
        [for (var i = 0; i <= 12; i++) 100.0 + i * 8],
      ], format: whole);
      expect(axis.offScale, isEmpty);
    });

    test('a point that does not double the band stays on it', () {
      // The rest run 100 to 110, a band of 10, but the least band is a tenth
      // of 110, so 11. 120.8 widens it to 20.8, which does not double 11.
      final axis = ValueAxis.trend([
        [100, 104, 110, 120.8, 105],
      ], format: whole);
      expect(axis.offScale, isEmpty);
    });

    test('a value equal to another series at the same height is not alone', () {
      final axis = ValueAxis.trend([
        [100, 101, 260],
        [102, 260, 103],
      ], format: whole);
      expect(axis.offScale, isEmpty);
    });

    test('the point is found in whichever series holds it', () {
      final axis = ValueAxis.trend([
        [100, 101, 102],
        [103, 260, 104],
      ], format: whole);
      final off = axis.offScale.single;
      expect((off.series, off.index), (1, 1));
      expect(axis.offScaleAt(1, 1), off);
      expect(axis.offScaleAt(0, 1), isNull);
    });

    test('at most one point per edge', () {
      final axis = ValueAxis.trend([
        [100, 0, 101, 102, 103, 260, 104],
      ], format: whole);
      expect([
        for (final o in axis.offScale) o.edge,
      ], unorderedEquals([OffScaleEdge.top, OffScaleEdge.bottom]));
    });

    test('bars never go off-scale', () {
      final axis = ValueAxis.bars(120);
      expect(axis.offScale, isEmpty);
      expect(axis.max, greaterThanOrEqualTo(120));
    });
  });

  group('cycle', () {
    test(
      'every point is inside the band for gains up to +1000% (finding 1)',
      () {
        for (var top = 0.0; top <= 1000; top += 3.7) {
          for (final floor in [0.0, top / 3, top * 0.9]) {
            final values = [floor, (floor + top) / 2, top];
            final axis = ValueAxis.cycle(values, format: percent);
            for (final v in values) {
              expect(
                v,
                inInclusiveRange(axis.min, axis.max),
                reason: '$v drawn on $axis',
              );
            }
          }
        }
      },
    );

    test('a regime at +259% steps past 100 (finding 1)', () {
      // 0 to 259.4: two steps of 100 reach 200, two of 200 reach 400, which
      // is 65% full, so the band stays at two steps.
      final axis = ValueAxis.cycle([0, 60, 120, 190, 259.4], format: percent);
      expect(axis.gridlines, [0, 200, 400]);
      expect(axis.labels, ['0%', '+200%', '+400%']);
    });

    test('every step is a labelled gridline, the bounds included '
        '(finding 11)', () {
      // 6 to 11: steps of 1 and 2 do not reach 11 in two, 4 does from a floor
      // of 4, and 5 of its 8 points are data, so two steps it is.
      final axis = ValueAxis.cycle([6, 8, 11], format: percent);
      expect(axis.min, 4);
      expect(axis.max, 12);
      expect(axis.gridlines, [4, 8, 12]);
      expect(axis.labels, ['+4%', '+8%', '+12%']);
      expect(axis.labelAt(axis.min), '+4%');
      expect(axis.labelAt(axis.max), '+12%');
    });

    test('three steps where two would leave more than 40% empty '
        '(finding 24)', () {
      // 0 to 55: two steps of 50 are 55% full. Three steps of 20 reach 60,
      // and are 92% full.
      final axis = ValueAxis.cycle([0, 30, 55], format: percent);
      expect(axis.gridlines, [0, 20, 40, 60]);
    });

    test('two steps when two leave exactly 40% empty', () {
      final axis = ValueAxis.cycle([0, 30, 60], format: percent);
      expect(axis.gridlines, [0, 50, 100]);
    });

    test('three or four gridlines at every height', () {
      for (var top = 1.0; top <= 1000; top += 1.3) {
        final axis = ValueAxis.cycle([0, top], format: percent);
        expect(axis.gridlines.length, inInclusiveRange(3, 4));
      }
    });

    test('with nothing scored it is the 0 to 2% a new programme has', () {
      final axis = ValueAxis.cycle(const [], format: percent);
      expect(axis.gridlines, [0, 1, 2]);
    });

    test('zero is the floor only when zero is in the data', () {
      expect(ValueAxis.cycle([0, 4], format: percent).min, 0);
      expect(ValueAxis.cycle([13, 17], format: percent).min, greaterThan(0));
    });

    test('one wild cycle goes off-scale and the band fits the others', () {
      final axis = ValueAxis.cycle([
        0,
        1,
        2,
        3,
        4,
        5,
        60,
        6,
        7,
        8,
        9,
        10,
      ], format: percent);
      expect(axis.offScale.single.index, 6);
      expect(axis.offScale.single.edge, OffScaleEdge.top);
      expect(axis.gridlines, [0, 5, 10]);
      expect(axis.place(0, 6, 60), 10);
    });

    test('a run of strong cycles is never clipped', () {
      final axis = ValueAxis.cycle([0, 1, 2, 30, 32, 34], format: percent);
      expect(axis.offScale, isEmpty);
      expect(axis.max, greaterThanOrEqualTo(34));
    });
  });

  group('bars', () {
    test('a heavy week does not pile up eleven labels (finding 7)', () {
      // 120: steps of 1 to 25 need more than four, 50 needs three.
      final axis = ValueAxis.bars(120);
      expect(axis.min, 0);
      expect(axis.max, 150);
      expect(axis.gridlines, [50, 100]);
      expect(axis.labels, ['50', '100']);
    });

    test('a peak of 60 is three steps of 20', () {
      final axis = ValueAxis.bars(60);
      expect(axis.max, 60);
      expect(axis.labels, ['20', '40']);
    });

    test('a fractional peak is rounded up before it is snapped', () {
      final axis = ValueAxis.bars(6.4);
      expect(axis.max, 8);
      expect(axis.labels, ['2', '4', '6']);
    });

    test('an empty or near-empty range keeps a scale', () {
      expect(ValueAxis.bars(0).labels, ['1']);
      expect(ValueAxis.bars(1).labels, ['1']);
      expect(ValueAxis.bars(1).max, 2);
    });

    test('never more than three labels, and the peak under the top', () {
      for (var peak = 0.0; peak <= 5000; peak += 7.3) {
        final axis = ValueAxis.bars(peak);
        expect(axis.labels.length, inInclusiveRange(1, 3), reason: '$peak');
        expect(axis.max, greaterThanOrEqualTo(peak));
        expect(axis.labels.toSet().length, axis.labels.length);
      }
    });
  });
}
