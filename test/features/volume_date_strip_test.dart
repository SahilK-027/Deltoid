import 'dart:io';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/progress/widgets/volume_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The strip under the volume bars, which had all four of the faults a date
/// axis can have at once: the wrong number of labels, labels clipped to
/// fragments (`2024` printing as `2`), labels drifting off the bars they name,
/// and labels hanging past the ends of the plot.
void main() {
  // The strip measures what it prints, so it is tested in the font it prints
  // in. The test font draws every glyph a full em across, twice Inter's width.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
      inter.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await inter.load();
  });

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

  /// The date labels only: the ones under the plot, which is the card height
  /// less its strip, `Space.sm` and a 16 line at 1.0. The value axis sits
  /// beside it, and a date label may be a bare number too (`2024`, `9`).
  List<({String label, Rect rect})> stripOf(WidgetTester tester) => [
        for (final e in find.byType(Text).evaluate())
          if ((e.widget as Text).data case final d?)
            if (tester.getRect(find.byWidget(e.widget)).top >=
                chartHeightCard - 24)
              (label: d, rect: tester.getRect(find.byWidget(e.widget))),
      ];

  testWidgets('a month of weekly bars labels every bar, not two of them',
      (tester) async {
    await pump(tester, 5, Granularity.weekly);

    // Five bars, five labels — never "Jul, Aug" because that is how the months
    // happened to fall. The last is the last day the bars stand for, not the
    // Monday its week began on.
    final dates = [for (final l in stripOf(tester)) l.label];
    expect(dates, hasLength(5));
    expect(dates.first, contains('Jul'));
    expect(dates.last, anyOf('16', '16 Aug'));
  });

  testWidgets('a year of weekly bars keeps to seven, and to distinct ones',
      (tester) async {
    await pump(tester, 52, Granularity.weekly);
    final months = [for (final l in stripOf(tester)) l.label];

    expect(months.length, lessThanOrEqualTo(7));
    expect(months.length, greaterThanOrEqualTo(4));
    expect(months.last, startsWith('Aug'));
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
    // The labels step in whole weeks, or at the average month, so they are
    // evenly spaced. The two at the ends may be pulled in flush with the plot,
    // so the gaps are compared between the labels inside them.
    for (final weeks in [13, 26, 52, 52 * 3]) {
      await pump(tester, weeks, Granularity.weekly);
      final strip = stripOf(tester);
      final centres = [for (final l in strip) l.rect.center.dx]..sort();
      expect(centres.length, greaterThanOrEqualTo(3),
          reason: '$weeks weeks drew ${centres.length} date labels');
      if (centres.length < 4) continue;

      final inner = centres.sublist(1, centres.length - 1);
      final gaps = [
        for (var i = 1; i < inner.length; i++) inner[i] - inner[i - 1],
      ];
      if (gaps.isEmpty) continue;
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
