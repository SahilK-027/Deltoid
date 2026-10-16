import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/date_axis.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// The date labels every time-based chart draws, held to THEME → Charts and to
/// the chart audit's findings 5, 8, 9, 10 and 19. Today is fixed at Friday
/// 16 October 2026 so nothing moves with the calendar.
void main() {
  final today = DateTime(2026, 10, 16);
  DateTime back(int days) => DateTime(today.year, today.month, today.day - days);

  /// Inter at `label` size runs about seven points a character, digits and
  /// letters alike; [scale] is the system font scale.
  double Function(String) measureAt(double scale) =>
      (s) => s.length * 7.0 * scale;

  /// The plot of a chart in a card on a 390 phone, and of one on the page.
  const card = 296.0;
  const page = 328.0;

  /// What a bar chart's newest label may run on into: the value gutter and
  /// the card's padding beyond it, as `VolumeChart` gives it.
  const gutter = 36.0;

  List<String> textsOf(DateAxis axis) => [for (final l in axis.labels) l.text];

  /// No two labels within the minimum gap, none off either end, and no weekday
  /// or month named twice. A bare day may repeat: `16` of two months.
  /// Every label is centred on its day; none is pulled in from an end.
  void expectReadable(
    DateAxis axis,
    double width,
    double Function(String) measure, {
    String reason = '',
    double rightRoom = 0,
  }) {
    final texts = textsOf(axis);
    final named = [for (final t in texts) if (int.tryParse(t) == null) t];
    expect(named.toSet(), hasLength(named.length),
        reason: '$reason: a label repeats in $texts');
    double? right;
    for (final l in axis.labels) {
      final w = measure(l.text);
      final left = l.at * width - w / 2;
      expect(left, greaterThanOrEqualTo(-0.001),
          reason: '$reason: ${l.text} hangs off the left in $texts');
      expect(left + w, lessThanOrEqualTo(width + rightRoom + 0.001),
          reason: '$reason: ${l.text} hangs off the right in $texts');
      if (right != null) {
        expect(left - right, greaterThanOrEqualTo(DateAxis.minGap - 0.001),
            reason: '$reason: ${l.text} collides in $texts');
      }
      right = left + w;
    }
  }

  /// [opening] allows the first gap of a bar strip to be a bar short: a month
  /// the bars open part way through is labelled on the first bar.
  void expectEvenGaps(
    DateAxis axis, {
    double tolerance = 0.002,
    bool opening = false,
  }) {
    var at = [for (final l in axis.labels) l.at];
    if (opening && at.length > 2) at = at.sublist(1);
    final gaps = [for (var i = 1; i < at.length; i++) at[i] - at[i - 1]];
    for (final g in gaps) {
      expect((g - gaps.first).abs(), lessThan(tolerance),
          reason: 'uneven gaps $gaps in ${textsOf(axis)}');
    }
  }

  group('line', () {
    DateAxis line(int days, {double width = card, double scale = 1}) =>
        DateAxis.line(
          from: back(days),
          to: today,
          width: width,
          measure: measureAt(scale),
        );

    test('a week is its seven weekdays, ending today', () {
      final axis = line(6);
      expect(axis.scale, DateScale.weekdays);
      expect(textsOf(axis), ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
      expect(axis.labels.last.date, today);
      expectEvenGaps(axis);
    });

    test('the last label is today on every rolling range', () {
      for (final days in [6, 30, 90, 182, 365]) {
        for (final scale in [1.0, 1.3]) {
          final axis = line(days, scale: scale);
          expect(axis.labels.last.date, today,
              reason: '$days days at $scale ends on ${axis.labels.last}');
        }
      }
    });

    test('a month does not collide at 1.0 or 1.3 (finding 5)', () {
      for (final scale in [1.0, 1.3]) {
        final axis = line(30, scale: scale);
        expect(axis.scale, DateScale.dates);
        expectReadable(axis, card, measureAt(scale), reason: '1M at $scale');
        expect(axis.labels.length, greaterThanOrEqualTo(4));
      }
    });

    test('every label is worded the same way, in full', () {
      // `16 Oct` seven times is 7 × 42 = 294 points of ink in 296, so a card
      // drops to fewer labels rather than shortening some of them.
      expect(textsOf(line(30)), ['18 Sep', '25 Sep', '2 Oct', '9 Oct', '16 Oct']);
      for (final days in [30, 90]) {
        for (final scale in [1.0, 1.3]) {
          for (final t in textsOf(line(days, scale: scale))) {
            expect(t, matches(RegExp(r'^\d{1,2} [A-Z][a-z]{2}$')),
                reason: '$days days at $scale printed $t');
          }
        }
      }
    });

    test('three months never repeat a month (finding 9)', () {
      for (final scale in [1.0, 1.3]) {
        final axis = line(90, scale: scale);
        expect(axis.scale, DateScale.dates);
        expectReadable(axis, card, measureAt(scale), reason: '3M at $scale');
      }
      // Seven fortnights in a card collide even printed as bare days, so the
      // step widens to a month and the count falls to four.
      expect(textsOf(line(90)), ['18 Jul', '17 Aug', '16 Sep', '16 Oct']);
      // With the room, seven fortnights.
      expect(textsOf(line(90, width: 400)),
          ['18 Jul', '2 Aug', '17 Aug', '1 Sep', '16 Sep', '1 Oct', '16 Oct']);
    });

    test('a year holds October twice, so every month carries its year', () {
      final axis = line(365);
      expect(axis.scale, DateScale.months);
      final texts = textsOf(axis);
      expect(texts.first, "Oct '25");
      expect(texts.last, "Oct '26");
      for (final scale in [1.0, 1.3]) {
        expectReadable(line(365, scale: scale), card, measureAt(scale));
      }
      // Edge to edge: the first label sits on the window's first day.
      expect(axis.labels.first.date, back(365));
    });

    test('a calendar year is its months, with no year on them', () {
      final axis = DateAxis.line(
        from: DateTime(2019),
        to: DateTime(2019, 12, 31),
        width: card,
        measure: measureAt(1),
      );
      expect(textsOf(axis), ['Feb', 'Apr', 'Jun', 'Aug', 'Oct', 'Dec']);
    });

    test('more than a year of months carries the year on every label', () {
      final axis = line(540, scale: 1.3);
      expect(axis.scale, DateScale.months);
      for (final t in textsOf(axis)) {
        expect(t, matches(RegExp(r"^[A-Z][a-z]{2} '\d\d$")));
      }
      expectReadable(axis, card, measureAt(1.3));
    });

    test('a calendar year ends on its own last day', () {
      final axis = DateAxis.line(
        from: DateTime(2019),
        to: DateTime(2019, 12, 31),
        width: card,
        measure: measureAt(1),
      );
      expect(textsOf(axis), ['Feb', 'Apr', 'Jun', 'Aug', 'Oct', 'Dec']);
      expect(axis.labels.last.date, DateTime(2019, 12, 31));
    });

    test('long ranges fall mid-year, evenly, counted back from this year '
        '(finding 10)', () {
      final twenty = DateAxis.line(
        from: DateTime(2006, 10, 2),
        to: today,
        width: page,
        measure: measureAt(1),
      );
      expect(twenty.scale, DateScale.years);
      // 2006 is on the chart from October, so it keeps its label.
      expect(textsOf(twenty), ['2006', '2011', '2016', '2021', '2026']);
      expect(twenty.labels.map((l) => l.date),
          everyElement(predicate<DateTime>((d) => d.month == 7 && d.day == 1)));
      expectEvenGaps(twenty);

      final five = DateAxis.line(
        from: DateTime(2021, 10, 18),
        to: today,
        width: card,
        measure: measureAt(1.3),
      );
      expect(textsOf(five), ['2021', '2022', '2023', '2024', '2025', '2026']);
      expectEvenGaps(five);
    });

    test('six months keep the month they open in', () {
      // Back from 16 October to 17 April: `Apr` is on the chart.
      expect(textsOf(line(182)), ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct']);
    });

    test('the first label stands as far from the left as the last from the '
        'right', () {
      for (final days in [6, 30, 90, 182, 365, 540, 365 * 5, 365 * 20]) {
        final axis = line(days);
        if (axis.labels.length < 2) continue;
        final left = axis.labels.first.at;
        final right = 1 - axis.labels.last.at;
        expect((left - right).abs(), lessThan(1e-6),
            reason: '$days days: $left on the left, $right on the right');
      }
    });

    test('a year before July names today, not a July still to come', () {
      final march = DateTime(2026, 3, 10);
      final axis = DateAxis.line(
        from: DateTime(2016, 3, 10),
        to: march,
        width: page,
        measure: measureAt(1),
      );
      expect(axis.labels.last.date, march);
      expect(axis.labels.last.text, '2026');
    });

    test('nothing collides at any span, width or font scale (finding 5)', () {
      for (final days in [
        6, 13, 30, 45, 60, 90, 120, 182, 250, 365, 500, 731, 800,
        1100, 365 * 3, 365 * 5, 365 * 8, 365 * 12, 365 * 20, 365 * 50,
      ]) {
        for (final width in [card, page, 200.0]) {
          for (final scale in [1.0, 1.3]) {
            final axis = line(days, width: width, scale: scale);
            expect(axis.labels, isNotEmpty);
            expectReadable(axis, width, measureAt(scale),
                reason: '$days days, $width wide, at $scale');
          }
        }
      }
    });

    test('labelAt reads back each label where fl_chart walks to it', () {
      for (final days in [6, 30, 90, 365, 365 * 20]) {
        final axis = line(days);
        final n = axis.labels.length;
        for (var k = 0; k < n; k++) {
          final x = axis.baselineX - k * axis.interval;
          expect(axis.labelAt(x), axis.labels[n - 1 - k].text);
          expect(x, greaterThan(axis.minX));
          expect(x, lessThan(axis.maxX));
        }
        expect(axis.labelAt(axis.baselineX + axis.interval), isNull);
        expect(axis.labelAt(axis.baselineX - n * axis.interval), isNull);
      }
    });

    test('zooming into a decade turns its years into months', () {
      final axis = DateAxis.line(
        from: DateTime(2016, 10, 16),
        to: today,
        width: page,
        measure: measureAt(1),
        zoom: 8,
      );
      expect(axis.scale, DateScale.months);
      // Laid out across the whole window, so a pan finds them.
      expect(axis.labels.first.date.year, 2016);
    });
  });

  group('bars', () {
    /// The row runs flush from the left end of the plot to the right.
    void expectFlush(DateAxis axis, double scale) {
      final m = measureAt(scale);
      final first = axis.labels.first;
      final last = axis.labels.last;
      expect(first.at * card - m(first.text) / 2, closeTo(0, 1e-6),
          reason: '${textsOf(axis)} does not start at the left end');
      expect(last.at * card + m(last.text) / 2, closeTo(card, 1e-6),
          reason: '${textsOf(axis)} does not end at the right end');
    }

    /// [weeks] weekly bars whose last week holds today.
    DateAxis weekly(int weeks, {double scale = 1, double width = card}) {
      final monday = DateTime(2026, 10, 12);
      final first =
          DateTime(monday.year, monday.month, monday.day - 7 * (weeks - 1));
      return DateAxis.bars(
        from: first,
        to: today,
        by: Granularity.weekly,
        count: weeks,
        width: width,
        measure: measureAt(scale),
        rightRoom: gutter,
      );
    }

    test('thirteen weeks end on today, not on the Monday (finding 8)', () {
      for (final scale in [1.0, 1.3]) {
        final axis = weekly(13, scale: scale);
        expect(axis.labels.last.date, today);
        expect(axis.labels.last.text, contains('16'));
        expect(axis.labels.first.text, '24 Jul');
        expectFlush(axis, scale);
        expectReadable(axis, card, measureAt(scale), rightRoom: gutter);
        expectEvenGaps(axis);
      }
    });

    test('a year of weeks ends on this month and names each month once', () {
      // Fifty-two weeks reach back into October of last year, so every month
      // carries its year. Every seventeenth week divides them evenly and the
      // months come out four apart, so a label names both end bars.
      final axis = weekly(52);
      expect(axis.scale, DateScale.months);
      expect(textsOf(axis), ["Oct '25", "Feb '26", "Jun '26", "Oct '26"]);
      expectFlush(axis, 1);
      expectEvenGaps(axis);
    });

    test('five years of monthly bars name every year, end to end', () {
      // 261 weeks from Monday 18 October 2021: 61 monthly bars, sixty months
      // apart, so a label every twelve names October of each year.
      final axis = DateAxis.bars(
        from: DateTime(2021, 10, 18),
        to: today,
        by: Granularity.monthly,
        count: 61,
        width: card,
        measure: measureAt(1.3),
        rightRoom: gutter,
      );
      expect(textsOf(axis),
          ['2021', '2022', '2023', '2024', '2025', '2026']);
      expectFlush(axis, 1.3);
      expectEvenGaps(axis);
    });

    test('twenty years of yearly bars count back from this year', () {
      final axis = DateAxis.bars(
        from: DateTime(2006, 10, 2),
        to: today,
        by: Granularity.yearly,
        count: 21,
        width: card,
        measure: measureAt(1),
        rightRoom: gutter,
      );
      expect(textsOf(axis),
          ['2006', '2010', '2014', '2018', '2022', '2026']);
      expectFlush(axis, 1);
      expectEvenGaps(axis);
    });

    test('a single bar is labelled today', () {
      final axis = weekly(1);
      expect(textsOf(axis), ['16 Oct']);
    });

    test('nothing collides at any count or font scale (finding 8)', () {
      for (final weeks in [1, 2, 5, 8, 13, 26, 39, 52, 60, 104]) {
        for (final scale in [1.0, 1.3]) {
          final axis = weekly(weeks, scale: scale);
          expect(axis.labels, isNotEmpty);
          expectReadable(axis, card, measureAt(scale),
              reason: '$weeks weeks at $scale', rightRoom: gutter);
          expectEvenGaps(axis, opening: true);
          expect(axis.labels.last.date, today);
        }
      }
    });
  });

  group('the five-year cliff (finding 19)', () {
    test('five years of weeks fold monthly, not into six yearly bars', () {
      expect(autoGranularityFor(261, Granularity.weekly), Granularity.monthly);
      expect(autoGranularity(1827), Granularity.monthly);
      // The charts fold the weeks they hold, counted as weeks whatever level
      // was asked for.
      expect(foldForWeeks(261, Granularity.monthly), Granularity.monthly);
      expect(foldForWeeks(261, Granularity.weekly), Granularity.monthly);
      expect(foldForWeeks(52, Granularity.monthly), Granularity.monthly);
      expect(foldForWeeks(1044, Granularity.monthly), Granularity.yearly);
    });

    test('about sixty is a tenth either way, and no more', () {
      expect(autoGranularity(365 * 6), Granularity.yearly);
      expect(autoGranularity(65), Granularity.daily);
      expect(autoGranularity(66), Granularity.weekly);
    });
  });
}
