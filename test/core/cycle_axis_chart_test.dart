import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/domain/cycle_progress.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cycle axis, held to the rules THEME → Charts sets for the one chart in
/// this app: deloads are a band and never a point, the open cycle is drawn as
/// unfinished, and the y band is data plus air rather than a floor at zero.

CyclePoint point(
  int index, {
  double? value,
  bool isDeload = false,
  bool isOpen = false,
}) =>
    CyclePoint(
      cycleId: 'c$index',
      index: index,
      isDeload: isDeload,
      isOpen: isOpen,
      value: value,
      lifts: const [],
    );

Widget harness(
  List<CyclePoint> points, {
  Set<String>? plotted,
  bool isBlocks = false,
  String? selected,
  ValueChanged<CyclePoint>? onSelected,
  bool small = false,
}) =>
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: CycleAxisChart(
          points: points,
          plotted: plotted ??
              {
                for (final p in points)
                  if (p.value != null) p.cycleId,
              },
          formatValue: formatCycleTick,
          isBlocks: isBlocks,
          selected: selected,
          onSelected: onSelected,
          small: small,
        ),
      ),
    );

LineChartData dataOf(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

void main() {
  testWidgets('a deload is a band and never a point', (tester) async {
    await tester.pumpWidget(
      harness([
        point(1, value: 0),
        point(2, value: 5),
        point(3, isDeload: true),
        point(4, value: 10),
      ]),
    );

    final data = dataOf(tester);
    expect(data.rangeAnnotations.verticalRangeAnnotations.length, 1);
    // The band sits over the deload's own position, third of four.
    final band = data.rangeAnnotations.verticalRangeAnnotations.single;
    expect(band.x1, lessThan(2));
    expect(band.x2, greaterThan(2));

    // And nothing is plotted there: three cycles scored, three markers.
    final spots = data.lineBarsData.last.spots;
    expect(spots.map((s) => s.x), [0, 1, 3]);
  });

  testWidgets('a thinned chart draws hairlines rather than bands',
      (tester) async {
    final points = [
      for (var i = 1; i <= 30; i++)
        point(i, value: i % 5 == 0 ? null : i.toDouble(), isDeload: i % 5 == 0),
    ];
    await tester.pumpWidget(
      harness(
        points,
        plotted: {
          for (var i = 4; i <= 30; i += 5) 'c$i',
          'c30',
        },
        isBlocks: true,
      ),
    );

    final data = dataOf(tester);
    expect(data.rangeAnnotations.verticalRangeAnnotations, isEmpty);
    expect(data.extraLinesData.verticalLines.length, 6);
  });

  testWidgets('a cycle the window skips still holds its place', (tester) async {
    // Cycles 1 and 2, then a spell on another regime, then 5 and 6.
    await tester.pumpWidget(
      harness([
        point(1, value: 0),
        point(2, value: 4),
        point(5, value: 9),
        point(6, value: 12),
      ]),
    );

    final data = dataOf(tester);
    // Four positions, evenly spaced: the axis is cycles, not weeks.
    expect(data.lineBarsData.last.spots.map((s) => s.x), [0, 1, 2, 3]);
    // And the numbers printed are the regime's own.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('the open cycle is joined by a dashed segment', (tester) async {
    await tester.pumpWidget(
      harness([
        point(1, value: 0),
        point(2, value: 5),
        point(3, value: 8, isOpen: true),
      ]),
    );

    final segments = dataOf(tester)
        .lineBarsData
        .where((b) => b.barWidth > 0)
        .toList();
    expect(segments.length, 2);
    expect(segments.first.dashArray, isNull);
    expect(segments.last.dashArray, isNotNull);
  });

  testWidgets('the y band is the data plus air, not a floor at zero',
      (tester) async {
    // A window opening at cycle 13: nothing near zero, so the axis must not
    // reach down to it and draw four cycles of work as a flat line.
    await tester.pumpWidget(
      harness([
        point(13, value: 6),
        point(14, value: 8),
        point(15, value: 11),
      ]),
    );

    final data = dataOf(tester);
    expect(data.minY, greaterThan(0));
    expect(data.minY, lessThanOrEqualTo(6));
    expect(data.maxY, greaterThanOrEqualTo(11));
  });

  testWidgets('zero is on the axis when zero is in the data', (tester) async {
    await tester.pumpWidget(
      harness([point(1, value: 0), point(2, value: 4)]),
    );

    expect(dataOf(tester).minY, 0);
  });

  testWidgets('tapping a cycle reports it', (tester) async {
    CyclePoint? tapped;
    await tester.pumpWidget(
      harness(
        [point(1, value: 0), point(2, value: 5), point(3, value: 9)],
        onSelected: (p) => tapped = p,
      ),
    );

    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(LineChart)));
    await tester.pumpAndSettle();

    expect(tapped, isNotNull);
  });

  testWidgets('dragging the page past the chart selects nothing',
      (tester) async {
    // The card sits in a scrolling list. A flick that crosses the plot must
    // scroll the page, not pick whichever cycle the finger went over.
    CyclePoint? tapped;
    await tester.pumpWidget(
      harness(
        [point(1, value: 0), point(2, value: 5), point(3, value: 9)],
        onSelected: (p) => tapped = p,
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(LineChart), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tapped, isNull);
  });

  testWidgets('the small variant drops the axes entirely', (tester) async {
    await tester.pumpWidget(
      harness([point(1, value: 0), point(2, value: 5)], small: true),
    );

    final data = dataOf(tester);
    expect(data.titlesData.rightTitles.sideTitles.showTitles, isFalse);
    expect(data.titlesData.bottomTitles.sideTitles.showTitles, isFalse);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a window with nothing scored in it draws no chart at all',
      (tester) async {
    await tester.pumpWidget(harness([point(1, isDeload: true)]));

    expect(find.byType(LineChart), findsNothing);
  });

  test('a percentage is printed with a sign and a real minus', () {
    expect(formatCyclePercent(9.84), '+9.8%');
    expect(formatCyclePercent(0), '0.0%');
    expect(formatCyclePercent(-2.5), '−2.5%');
    expect(formatCyclePercent(0.04), '0.0%');
    expect(formatCycleTick(10), '+10%');
    expect(formatCycleTick(0), '0%');
  });
}
