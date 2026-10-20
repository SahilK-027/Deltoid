import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Changing range is a zoom of one frame, not a line re-plotted point by point
/// (THEME → Charts). `fl_chart` interpolates two spot lists of different
/// lengths index by index, which sent every point across the plot to wherever
/// the same index fell in the new list, so the chart being left and the chart
/// being arrived at are drawn together and cross-faded instead.

Widget _app(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 358, child: child),
        ),
      ),
    );

/// Today, in the chart's units of days since the epoch.
double get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch /
      86400000;
}

/// One point every [every] days for the last [days] days, ending today.
TrendChart _chart(TrendWindow window, {required int days, required int every}) {
  final today = _today;
  return TrendChart(
    window: window,
    formatValue: (v) => v.round().toString(),
    series: [
      TrendSeries(
        name: 'Push 1',
        color: const Color(0xFF4C8DFF),
        spots: [
          for (var d = days; d >= 0; d -= every)
            FlSpot(today - d, 100 + (days - d) / 10),
        ],
      ),
    ],
  );
}

List<LineChart> _charts(WidgetTester tester) =>
    tester.widgetList<LineChart>(find.byType(LineChart)).toList();

void main() {
  const threeMonths = TrendWindow.rolling(ChartRange.threeMonths);
  const year = TrendWindow.rolling(ChartRange.year);

  testWidgets('both ranges are drawn in one frame while it travels',
      (tester) async {
    await tester.pumpWidget(_app(_chart(threeMonths, days: 90, every: 1)));
    await tester.pumpAndSettle();
    final before = _charts(tester).single.data;

    await tester.pumpWidget(_app(_chart(year, days: 365, every: 7)));
    await tester.pump();
    await tester.pump(Motion.slow ~/ 4);

    final mid = _charts(tester);
    expect(mid, hasLength(2), reason: 'the old range under the new one');
    final (held, live) = (mid.first.data, mid.last.data);
    // One frame for both, so a date stays where it is on screen whichever
    // line it belongs to.
    expect(held.minX, live.minX);
    expect(held.maxX, live.maxX);
    expect(held.minY, live.minY);
    expect(held.maxY, live.maxY);
    // Part way from three months to a year, widening leftwards.
    expect(live.minX, lessThan(before.minX));
    expect(live.minX, greaterThan(_today - 366));
    // Each line keeps its own points: nothing is interpolated between them.
    expect(held.lineBarsData.first.spots, hasLength(91));
    expect(live.lineBarsData.first.spots, hasLength(53));
    // Neither chart animates on its own while the frame is carried.
    expect(mid.first.duration, Duration.zero);
    expect(mid.last.duration, Duration.zero);

    await tester.pumpAndSettle();
    final after = _charts(tester);
    expect(after, hasLength(1), reason: 'the old range is gone once arrived');
    expect(after.single.data.lineBarsData.first.spots, hasLength(53));
    expect(after.single.duration, Motion.base);
  });

  testWidgets('new data in the same range moves a point and nothing else',
      (tester) async {
    await tester.pumpWidget(_app(_chart(year, days: 365, every: 7)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_app(_chart(year, days: 364, every: 7)));
    await tester.pump();
    await tester.pump(Motion.slow ~/ 4);

    expect(_charts(tester), hasLength(1));
  });
}
