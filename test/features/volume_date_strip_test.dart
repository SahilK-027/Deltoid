import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/workouts/widgets/volume_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The strip under the volume bars, which had all four of the faults a date
/// axis can have at once: the wrong number of labels, labels clipped to
/// fragments (`2024` printing as `2`), labels drifting off the bars they name,
/// and labels hanging past the ends of the plot.
void main() {
  /// [weeks] Mondays running back from a fixed date, so the tests do not move
  /// with the calendar.
  VolumeSeries seriesOf(int weeks) => VolumeSeries(
        label: 'Chest',
        weeks: [
          for (var i = 0; i < weeks; i++)
            VolumeWeek(
              start: DateTime(2026, 8, 10)
                  .subtract(Duration(days: 7 * (weeks - 1 - i))),
              sets: 8 + i % 7,
            ),
        ],
      );

  Future<List<Rect>> pump(
    WidgetTester tester,
    int weeks,
    Granularity by, {
    double width = 360,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: VolumeChart(
              series: seriesOf(weeks),
              by: by,
              hue: const Color(0xFF00E5FF),
            ),
          ),
        ),
      ),
    );
    // Settled, not just pumped: the strip lives inside an `AnimatedSwitcher`,
    // which holds the outgoing labels while the new ones fade in — so a single
    // pump measures two strips laid over each other.
    await tester.pumpAndSettle();
    return [
      for (final e in find.byType(Text).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
  }

  List<String> labelsOf(WidgetTester tester) => [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          if (w.data != null) w.data!,
      ];

  /// The date labels only — the value axis is bare integers.
  List<({String label, Rect rect})> stripOf(WidgetTester tester) => [
        for (final e in find.byType(Text).evaluate())
          if ((e.widget as Text).data case final d?)
            if (int.tryParse(d) == null)
              (label: d, rect: tester.getRect(find.byWidget(e.widget))),
      ];

  testWidgets('a month of weekly bars labels every bar, not two of them',
      (tester) async {
    await pump(tester, 5, Granularity.weekly);
    final dates = labelsOf(tester).where((s) => s.contains(' ')).toList();

    // Five bars, five labels — never "Jul, Aug" because that is how the months
    // happened to fall.
    expect(dates, hasLength(5));
    expect(dates.first, contains('Jul'));
  });

  testWidgets('a year of weekly bars keeps to seven, and to distinct ones',
      (tester) async {
    await pump(tester, 52, Granularity.weekly);
    final months = labelsOf(tester)
        .where((s) => RegExp(r'^[A-Z][a-z]{2}').hasMatch(s))
        .toList();

    expect(months.length, lessThanOrEqualTo(7));
    expect(months.length, greaterThanOrEqualTo(5));
    // A year reaching back from August covers thirteen months, so plain `Aug`
    // would land at both ends. The axis says which year each one is rather than
    // printing one of them fewer times and losing an end.
    expect(months.toSet().length, months.length,
        reason: 'a repeated label is a format that is too coarse');
  });

  testWidgets('a whole label is drawn, never a fragment of one',
      (tester) async {
    // Thirty years folded yearly: the case that printed `2` instead of `2024`.
    await pump(tester, 52 * 30, Granularity.yearly);
    final years =
        labelsOf(tester).where((s) => RegExp(r'^\d{4}$').hasMatch(s)).toList();

    expect(years, isNotEmpty, reason: 'years were clipped to fragments');
    expect(years.length, lessThanOrEqualTo(7));
    for (final y in years) {
      expect(y, hasLength(4));
    }
  });

  testWidgets('nothing hangs off either end of the plot', (tester) async {
    const width = 360.0;
    final rects = await pump(tester, 52 * 30, Granularity.yearly, width: width);

    for (final r in rects) {
      expect(r.left, greaterThanOrEqualTo(-0.5),
          reason: 'a label was drawn off the left edge');
      expect(r.right, lessThanOrEqualTo(width + 0.5),
          reason: 'a label was drawn off the right edge');
    }
  });

  testWidgets('the gaps between labels are equal, at every range',
      (tester) async {
    // The complaint that produced this file's second rewrite: the labels were
    // *nearly* evenly spaced, which reads worse than either even or obviously
    // not. They now sit where the line chart's ticks sit — `(k + ½) / count` of
    // the plot — so every gap is the same and the two ends are not special.
    for (final weeks in [13, 26, 52, 52 * 3]) {
      await pump(tester, weeks, Granularity.weekly);
      final strip = stripOf(tester);
      final centres = [for (final l in strip) l.rect.center.dx]..sort();
      expect(centres.length, greaterThanOrEqualTo(5),
          reason: '$weeks weeks drew ${centres.length} date labels');

      final gaps = [
        for (var i = 1; i < centres.length; i++) centres[i] - centres[i - 1],
      ];
      final widest = gaps.reduce((a, b) => a > b ? a : b);
      final narrowest = gaps.reduce((a, b) => a < b ? a : b);
      expect(widest - narrowest, lessThan(1.0),
          reason: '$weeks weeks: gaps ran $narrowest..$widest '
              '(${[for (final l in strip) l.label]})');
    }
  });

  testWidgets('the strip survives a single bar', (tester) async {
    await pump(tester, 1, Granularity.weekly);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the value gutter is sized to its widest number', (tester) async {
    // 34 points were reserved for labels like `12`, and the room came off the
    // plot — and therefore off the date labels under it.
    await pump(tester, 13, Granularity.weekly);
    final strip = stripOf(tester);
    final rightmost =
        strip.map((l) => l.rect.right).reduce((a, b) => a > b ? a : b);

    // 360 wide, 16 of page padding either side: the last date label should
    // reach close to where the plot ends rather than stopping a gutter short.
    expect(rightmost, greaterThan(300),
        reason: 'the date strip is being squeezed by the value gutter');
  });
}
