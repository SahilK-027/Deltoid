import 'dart:io';

import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/chart_legend.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/chart_legend.dart';
import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/value_axis.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/progress/widgets/volume_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Inter, as `y_axis_gutter_test.dart` loads it: the test font draws every
/// glyph a full em wide, so whether words fit is only answered in the real
/// face.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// The spacing THEME → Charts gives every chart card, and the polish findings
/// 27 to 33 of the chart audit: two line-chart heights, one legend that never
/// passes two rows, one gutter and one label strip for line and bar alike,
/// figures 12 apart, and the year chip naming no year it is not showing.
void main() {
  setUpAll(_loadInter);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1.0,
    double width = 358,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: width, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  final today = DateTime.now();
  double x(int daysAgo) => trendX(dayKeyOf(
        DateTime(today.year, today.month, today.day - daysAgo),
      ));

  TrendSeries line(String name, Color color, double y, {int from = 300}) =>
      TrendSeries(
        name: name,
        color: color,
        spots: [for (var d = from; d >= 0; d -= 30) FlSpot(x(d), y)],
      );

  group('the legend', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('never passes two rows, and names the rest, at $scale',
          (tester) async {
        await pump(
          tester,
          ChartLegend(
            entries: [
              for (var i = 1; i <= 9; i++)
                LegendEntry('Push $i', Colors.blue, mark: LegendMark.line),
            ],
          ),
          scale: scale,
          width: 240,
        );
        final tops = {
          for (final e in find.textContaining('Push').evaluate())
            tester.getTopLeft(find.byWidget(e.widget)).dy.round(),
        };
        expect(tops.length, lessThanOrEqualTo(legendMaxRows));
        final more = find.textContaining(RegExp(r'^and \d+ more$'));
        expect(more, findsOneWidget);
        final shown = find.textContaining('Push').evaluate().length;
        expect(
          (tester.widget<Text>(more).data!),
          'and ${9 - shown} more',
        );
      });
    }

    testWidgets('keys two lines on top of each other once', (tester) async {
      await pump(
        tester,
        TrendChart(
          series: [
            line('Push 2', Colors.blue, 100),
            line('Push 1', Colors.pink, 100),
          ],
          formatValue: (v) => v.toStringAsFixed(0),
          window: const TrendWindow.rolling(ChartRange.year),
        ),
      );
      expect(find.text('Push 2 and Push 1'), findsOneWidget);
      expect(find.text('Push 1'), findsNothing);
    });

    testWidgets('keys two lines apart twice', (tester) async {
      await pump(
        tester,
        TrendChart(
          series: [
            line('Push 2', Colors.blue, 100),
            line('Push 1', Colors.pink, 110),
          ],
          formatValue: (v) => v.toStringAsFixed(0),
          window: const TrendWindow.rolling(ChartRange.year),
        ),
      );
      expect(find.text('Push 2'), findsOneWidget);
      expect(find.text('Push 1'), findsOneWidget);
    });
  });

  group('two heights', () {
    testWidgets('a trend chart, drawn or empty, is the full height',
        (tester) async {
      await pump(
        tester,
        Column(
          children: [
            TrendChart(
              key: const Key('drawn'),
              series: [line('Bodyweight', Colors.blue, 80)],
              formatValue: (v) => v.toStringAsFixed(0),
              window: const TrendWindow.rolling(ChartRange.year),
            ),
            const EmptyTrendChart(
              key: Key('empty'),
              window: TrendWindow.rolling(ChartRange.year),
            ),
          ],
        ),
      );
      for (final key in ['drawn', 'empty']) {
        final chart = find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(LineChart),
        );
        expect(tester.getSize(chart).height, chartHeightFull, reason: key);
      }
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('the volume chart is the card height with its strip, at '
          '$scale', (tester) async {
        final series = VolumeSeries(
          label: 'Chest',
          weeks: [
            for (var i = 0; i < 13; i++)
              VolumeWeek(
                start: weekStartOf(today).subtract(Duration(days: 7 * (12 - i))),
                sets: 8 + i,
              ),
          ],
        );
        await pump(
          tester,
          VolumeChart(
            series: series,
            by: Granularity.weekly,
            hue: Colors.pink,
          ),
          scale: scale,
        );
        final chart = find.byType(VolumeChart);
        expect(tester.getSize(chart).height, chartHeightCard);
        final box = tester.getRect(chart);
        // Every label inside the chart's own box: the date strip did not
        // overflow its row, and the value labels fit their gutter on the
        // right, where they are left-aligned.
        for (final e in find
            .descendant(of: chart, matching: find.byType(Text))
            .evaluate()) {
          final rect = tester.getRect(find.byWidget(e.widget));
          expect(rect.bottom, lessThanOrEqualTo(box.bottom + 0.01),
              reason: '"${(e.widget as Text).data}" below the chart');
          expect(rect.right, lessThanOrEqualTo(box.right + 0.01),
              reason: '"${(e.widget as Text).data}" past the gutter');
        }
      });
    }
  });

  testWidgets('the volume gutter is measured over the axis it draws',
      (tester) async {
    late double expected;
    final series = VolumeSeries(
      label: 'Chest',
      weeks: [
        for (var i = 0; i < 13; i++)
          VolumeWeek(
            start: weekStartOf(today).subtract(Duration(days: 7 * (12 - i))),
            sets: i == 12 ? 105 : 40,
          ),
      ],
    );
    await pump(
      tester,
      Builder(builder: (context) {
        expected = axisGutter(
          context,
          ValueAxis.bars(series.peakPerWeek(Granularity.weekly)).labels,
        );
        return VolumeChart(
          series: series,
          by: Granularity.weekly,
          hue: Colors.pink,
        );
      }),
    );
    final gutter = find
        .descendant(
          of: find.byType(VolumeChart),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width != null && w.height != null,
          ),
        )
        .evaluate()
        .map((e) => (e.widget as SizedBox).width!)
        .toList();
    expect(gutter, contains(expected));
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('the top value label stays inside the trend chart at $scale',
        (tester) async {
      await pump(
        tester,
        TrendChart(
          series: [
            TrendSeries(
              name: 'Bodyweight',
              color: Colors.blue,
              spots: [for (var d = 300; d >= 0; d -= 30) FlSpot(x(d), 70.0 + d / 10)],
            ),
          ],
          formatValue: (v) => v.toStringAsFixed(0),
          window: const TrendWindow.rolling(ChartRange.year),
        ),
        scale: scale,
      );
      final chart = tester.getRect(find.byType(LineChart));
      final values = find.byWidgetPredicate(
        (w) => w is Text && int.tryParse(w.data ?? '') != null,
      );
      expect(values, findsWidgets);
      for (final e in values.evaluate()) {
        expect(
          tester.getRect(find.byWidget(e.widget)).top,
          greaterThanOrEqualTo(chart.top - 0.01),
          reason: '"${(e.widget as Text).data}" rises out of the chart',
        );
      }
    });
  }

  testWidgets('an empty chart draws the band of a drawn one on the same values',
      (tester) async {
    String format(double v) => v.toStringAsFixed(0);
    await pump(
      tester,
      Column(
        children: [
          TrendChart(
            key: const Key('drawn'),
            series: [
              TrendSeries(
                name: 'Bodyweight',
                color: Colors.blue,
                spots: [FlSpot(x(200), 62), FlSpot(x(10), 141)],
              ),
            ],
            formatValue: format,
            window: const TrendWindow.rolling(ChartRange.year),
            minStep: 0.5,
            minSpanFraction: 0.05,
          ),
          EmptyTrendChart(
            key: const Key('empty'),
            window: const TrendWindow.rolling(ChartRange.month),
            scale: (62, 141),
            formatValue: format,
            minStep: 0.5,
            minSpanFraction: 0.05,
          ),
        ],
      ),
    );
    LineChartData data(String key) => tester
        .widget<LineChart>(find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(LineChart),
        ))
        .data;
    final drawn = data('drawn');
    final empty = data('empty');
    expect(empty.minY, drawn.minY);
    expect(empty.maxY, drawn.maxY);
    expect(
      empty.gridData.horizontalInterval,
      drawn.gridData.horizontalInterval,
    );
  });

  testWidgets('figures in a row stand 12 apart', (tester) async {
    await pump(
      tester,
      const StatRow(
        children: [
          StatTile(value: '140.5', unit: 'kg', label: 'Best est. 1RM'),
          StatTile(value: '+60.2%', label: 'Change in Push 2'),
          StatTile(value: '1', label: 'Session since best'),
        ],
      ),
      scale: 1.3,
    );
    final tiles = find.byType(StatTile);
    for (var i = 1; i < 3; i++) {
      expect(
        tester.getTopLeft(tiles.at(i)).dx - tester.getTopRight(tiles.at(i - 1)).dx,
        Space.md,
      );
    }
  });

  group('the year chip', () {
    Future<String> chip(WidgetTester tester, TrendWindow window) async {
      await pump(
        tester,
        TrendRangeBar(
          window: window,
          years: const [2026, 2025],
          onChanged: (_) {},
        ),
      );
      return tester
          .widget<Text>(find.descendant(
            of: find.byType(AppChip),
            matching: find.byType(Text),
          ))
          .data!;
    }

    testWidgets('names no year while a rolling range is in force',
        (tester) async {
      expect(await chip(tester, const TrendWindow.rolling(ChartRange.month)),
          'Year');
      expect(await chip(tester, const TrendWindow.all()), 'Year');
    });

    testWidgets('names the year it is showing', (tester) async {
      expect(await chip(tester, const TrendWindow.calendar(2025)), '2025');
    });
  });

  testWidgets('a selected open cycle keeps its open grey', (tester) async {
    CyclePoint point(int index, double value, {bool isOpen = false}) =>
        CyclePoint(
          cycleId: 'c$index',
          index: index,
          isDeload: false,
          isOpen: isOpen,
          value: value,
          lifts: const [],
          sessions: const [],
        );
    final points = [point(1, 0), point(2, 3), point(3, 5, isOpen: true)];
    await pump(
      tester,
      CycleAxisChart(
        points: points,
        plotted: {for (final p in points) p.cycleId},
        formatValue: formatCycleTick,
        selected: 'c3',
      ),
    );
    final c = DeltoidColors.dark;
    final markers = tester.widget<LineChart>(find.byType(LineChart)).data
        .lineBarsData
        .last;
    final open = markers.spots.last;
    final painter = markers.dotData.getDotPainter(open, 0, markers, 2)
        as FlDotCirclePainter;
    expect(painter.color, c.textTertiary, reason: 'filled, in its own grey');
    expect(painter.strokeColor, c.textTertiary);
    expect(painter.radius, 4.5, reason: 'and still drawn as selected');
  });
}
