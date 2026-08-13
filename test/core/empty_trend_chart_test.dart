import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';

Widget _harness(
  TrendWindow window, {
  String? message,
  (double, double)? scale,
}) =>
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: EmptyTrendChart(
          window: window,
          message: message,
          scale: scale,
          formatValue: scale == null ? null : (v) => v.round().toString(),
        ),
      ),
    );

void main() {
  testWidgets('a range with nothing in it still draws its own time axis',
      (tester) async {
    await tester.pumpWidget(_harness(const TrendWindow.calendar(2024)));

    // Dated inside the year that was asked for, not the year we happen to be
    // in: the axis belongs to the window, which is what makes the range chips
    // still mean something with no data under them.
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(labels, isNotEmpty, reason: 'the time axis is still drawn');
    for (final l in labels) {
      expect(DateFormat('MMM').parse(l), isNotNull);
    }
  });

  testWidgets('an empty range keeps the y axis of the whole history',
      (tester) async {
    await tester.pumpWidget(
      _harness(const TrendWindow.rolling(ChartRange.month), scale: (60, 100)),
    );

    // The numbers stay where they were, so a month you did not train reads as
    // an empty stretch of the same chart rather than as a chart with no scale.
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    expect(labels, isNotEmpty, reason: 'the value axis is labelled');
    expect(labels.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(100));
    expect(labels.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(60));
  });

  testWidgets('the plot is the height it always is', (tester) async {
    await tester.pumpWidget(_harness(const TrendWindow.rolling(ChartRange.year),
        message: 'Only deload weeks in this range.'));

    // A plot shorter than the chart it stands in for moves the page under your
    // thumb every time you change range. The caption is below it, not in it.
    expect(tester.getSize(find.byType(LineChart)).height, 220);
    final caption = tester.getRect(find.text('Only deload weeks in this range.'));
    expect(caption.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(LineChart)).bottom));
  });

  testWidgets('with nothing loaded yet it says nothing at all', (tester) async {
    await tester
        .pumpWidget(_harness(const TrendWindow.rolling(ChartRange.month)));

    // No caption without a message: "nothing logged" is a claim about the log,
    // and a frame that has not read it is not entitled to make it.
    expect(find.textContaining('Nothing'), findsNothing);
    expect(find.textContaining('Never'), findsNothing);
  });

  testWidgets('one session is a chart with one dot on it', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: TrendChart(
          series: [
            TrendSeries(
              name: 'Push 1',
              color: const Color(0xFF00E5FF),
              spots: [FlSpot(trendX(20260210), 102.5)],
            ),
          ],
          formatValue: (v) => v.round().toString(),
        ),
      ),
    ));

    // A single point has a span of zero days, and an axis from a day to itself
    // has no width to divide — the chart pads it rather than refusing to draw.
    expect(tester.takeException(), isNull);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('a chart with no history at all is still labelled',
      (tester) async {
    // The never-logged case. Dropping the numbers reads as a chart that failed
    // to draw, and a scale under a plot with no line on it claims nothing.
    await tester.pumpWidget(
      _harness(const TrendWindow.rolling(ChartRange.year), scale: (0, 100)),
    );

    final numbers = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    expect(numbers, isNotEmpty);
    expect(numbers.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(75));
  });
}
