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
  int? minSlots,
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
          minSlots: minSlots,
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
    // And the line between blocks is solid: under blocks a gap is what every
    // segment has, so dashing them says "broken" about the normal case.
    final segments = data.lineBarsData.where((b) => b.barWidth > 0);
    expect(segments, isNotEmpty);
    expect(segments.every((b) => b.dashArray == null), isTrue);
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

  testWidgets('a window with nothing scored in it is an empty axis, not an '
      'empty box', (tester) async {
    await tester.pumpWidget(harness([point(1, isDeload: true)]));

    // The axis this regime will have, with nothing on it: a band from zero,
    // gridlines, and no marker anywhere.
    final data = dataOf(tester);
    expect(data.minY, 0);
    expect(data.maxY, greaterThan(0));
    expect(data.lineBarsData.last.spots, isEmpty);
  });

  testWidgets('an axis numbers the positions no cycle has reached yet',
      (tester) async {
    // A regime one cycle in opens on the axis it will fill: four positions,
    // numbered 1 to 4, with the one dot there is on the first of them.
    await tester.pumpWidget(
      harness([point(1, value: 0)], minSlots: 4),
    );

    for (final label in ['1', '2', '3', '4']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  test('a percentage is printed with a sign and a real minus', () {
    expect(formatCyclePercent(9.84), '+9.8%');
    expect(formatCyclePercent(0), '0.0%');
    expect(formatCyclePercent(-2.5), '−2.5%');
    expect(formatCyclePercent(0.04), '0.0%');
    expect(formatCycleTick(10), '+10%');
    expect(formatCycleTick(0), '0%');
  });
  group('label thinning', () {
    test('counts the room a label needs, not the slots', () {
      // Twelve slots, a slot 26px wide: `1` fits every slot, `36` does not.
      expect(
        CycleAxisChart.labelEvery(12, labelWidth: 8, slotWidth: 26),
        1,
      );
      expect(
        CycleAxisChart.labelEvery(12, labelWidth: 20, slotWidth: 26),
        2,
      );
      // A 1.3 system font on the same axis: wider still, so wider apart.
      expect(
        CycleAxisChart.labelEvery(12, labelWidth: 28, slotWidth: 26),
        2,
      );
    });

    test('rounds up a ladder a person can count in', () {
      // Never `every 3rd` or `every 7th`: 1, 2, 5, 10, then tens.
      for (final width in [10.0, 20.0, 30.0, 40.0, 60.0, 100.0, 200.0]) {
        final every = CycleAxisChart.labelEvery(
          40,
          labelWidth: width,
          slotWidth: 12,
        );
        expect(
          every == 1 || every == 2 || every == 5 || every % 10 == 0,
          isTrue,
          reason: 'a $width label produced every $every',
        );
      }
    });

    test('falls back to the slot count when nothing has been measured', () {
      expect(CycleAxisChart.labelEvery(12), 1);
      expect(CycleAxisChart.labelEvery(20), 2);
      expect(CycleAxisChart.labelEvery(40), 10);
    });
  });

  testWidgets('a crowded axis prints fewer numbers, not narrower ones',
      (tester) async {
    // Cycles 36 to 47 in the width of a phone card: two-digit labels in a slot
    // sized for one is how `36 37 38` closed up into a grey band.
    final points = [for (var i = 36; i <= 47; i++) point(i, value: i.toDouble())];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: SizedBox(
              width: 360,
              child: CycleAxisChart(
                points: points,
                plotted: {for (final p in points) p.cycleId},
                formatValue: formatCycleTick,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final printed = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => int.tryParse(t) != null)
        .toList();

    expect(printed, isNotEmpty);
    expect(
      printed.length,
      lessThan(points.length),
      reason: 'every cycle was numbered into a card too narrow for them',
    );
  });
  testWidgets('a thinned axis keeps one rhythm all the way across',
      (tester) async {
    // `44 46 47` — the last cycle printed half a step after the one before it
    // — reads as a mistake in the spacing. The ladder holds; the readout above
    // is where the selected cycle is named.
    final points = [for (var i = 36; i <= 47; i++) point(i, value: i.toDouble())];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CycleAxisChart(
              points: points,
              plotted: {for (final p in points) p.cycleId},
              formatValue: formatCycleTick,
              selected: 'c47',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final printed = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .map(int.tryParse)
        .whereType<int>()
        .toList()
      ..sort();

    expect(printed.length, greaterThan(2));
    final gaps = {
      for (var i = 1; i < printed.length; i++) printed[i] - printed[i - 1],
    };
    expect(gaps.length, 1, reason: 'the axis printed $printed');
  });
}
