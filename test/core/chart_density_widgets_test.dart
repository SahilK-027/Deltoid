import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/progress/widgets/volume_chart.dart';
import 'package:deltoid/features/progress/widgets/volume_history_bars.dart';
import 'package:deltoid/features/progress/widgets/volume_tile.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Density decided by pixels rather than counts, as the charts draw it: the
/// audit's findings 15, 17 and 18. The thresholds themselves are tested in
/// `test/domain/chart_density_test.dart`.

Widget _app(Widget child, {double width = 358}) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

TrendSeries _series(String name, List<double> xs) => TrendSeries(
      name: name,
      color: const Color(0xFF4C8DFF),
      spots: [for (final x in xs) FlSpot(x, 100 + x / 10)],
    );

/// [count] weeks of Mondays, the last holding 12 October 2026.
List<VolumeWeek> _weeks(int count) => [
      for (var i = 0; i < count; i++)
        VolumeWeek(
          start: DateTime(2026, 10, 12 - 7 * (count - 1 - i)),
          sets: 6 + i % 7,
        ),
    ];

void main() {
  const hint = 'Pinch to zoom and drag to pan.';

  group('trend markers', () {
    Future<List<bool>> markersOf(
      WidgetTester tester,
      List<TrendSeries> series,
    ) async {
      await tester.pumpWidget(_app(TrendChart(
        series: series,
        formatValue: (v) => v.round().toString(),
      )));
      await tester.pumpAndSettle();
      final bars =
          tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      return [
        for (final b in bars)
          b.spots.every((s) => b.dotData.checkToShowDot(s, b)),
      ];
    }

    testWidgets('are decided for each series on its own', (tester) async {
      // Finding 15. Sixty-four points across two series, which the old count
      // dropped from both: the weekly series is six pixels apart and goes bare,
      // the monthly one is twenty-five apart and keeps its circles.
      final marked = await markersOf(tester, [
        _series('Weekly', [for (var i = 0; i < 52; i++) 7.0 * i]),
        _series('Monthly', [for (var i = 0; i < 12; i++) 30.0 * i]),
      ]);
      expect(marked, [false, true]);
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets('stay on fifty-two points that have room for them',
        (tester) async {
      // Two series of twenty-six, a week apart over six months: about eleven
      // pixels between neighbours.
      final marked = await markersOf(tester, [
        _series('Push 1', [for (var i = 0; i < 26; i++) 7.0 * i]),
        _series('Push 2', [for (var i = 0; i < 26; i++) 7.0 * i + 3]),
      ]);
      expect(marked, [true, true]);
      expect(find.text(hint), findsNothing);
    });
  });

  group('volume bars', () {
    testWidgets('five weeks are spread across the plot, each still touchable',
        (tester) async {
      // Finding 17. The ink is capped, but the slots keep the whole width, so a
      // touch anywhere in a bar's fifth of the plot picks that bar.
      VolumeBar? picked;
      final bars = foldWeeks(_weeks(5), Granularity.weekly);
      await tester.pumpWidget(_app(
        WeeklyBars(
          bars: bars,
          hue: const Color(0xFF00E5FF),
          height: 100,
          onSelected: (b) => picked = b ?? picked,
        ),
        width: 300,
      ));
      final box = tester.getRect(find.byType(WeeklyBars));

      await tester.tapAt(Offset(box.left + 2, box.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked, bars[0]);
      await tester.tapAt(Offset(box.left + 150, box.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked, bars[2]);
      await tester.tapAt(Offset(box.right - 2, box.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked, bars[4]);
    });

    testWidgets('a tile at a year draws months, its chart keeps weeks',
        (tester) async {
      // Finding 18: fifty-two weeks in half a phone merge into texture.
      final series = VolumeSeries(label: 'Chest', weeks: _weeks(52));
      await tester.pumpWidget(_app(
        VolumeTile(
          series: series,
          by: Granularity.weekly,
          hue: const Color(0xFF00E5FF),
        ),
        width: 170,
      ));
      final tile = tester.widget<WeeklyBars>(find.byType(WeeklyBars)).bars;
      expect(tile, hasLength(foldWeeks(series.weeks, Granularity.monthly).length));

      // Scrubbed, the caption names the month the bar is, not a week.
      final box = tester.getRect(find.byType(WeeklyBars));
      final gesture =
          await tester.startGesture(Offset(box.right - 4, box.center.dy));
      // Past the press timeout, where a press that is not yet a drag lands.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(weekReadout(tile.last, Granularity.monthly)),
          findsOneWidget);
      expect(weekReadout(tile.last, Granularity.monthly),
          startsWith('October 2026 · '));
      await gesture.up();

      await tester.pumpWidget(_app(
        VolumeChart(
          series: series,
          by: Granularity.weekly,
          hue: const Color(0xFF00E5FF),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<WeeklyBars>(find.byType(WeeklyBars)).bars,
          hasLength(52));
    });
  });
}
