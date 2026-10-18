import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/progress/widgets/volume_chart.dart';
import 'package:deltoid/features/progress/widgets/volume_history_bars.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gaps and jumps, the audit's findings 2 and 12: a line breaks at a bucket
/// with nothing in it and a faint dotted line bridges the break, a bar chart
/// keeps its zero, and the cycle line is dashed across a spell on another
/// regime as it is across a deload.

Widget _app(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

/// One series, a week apart, with a null wherever [values] has one.
Widget _trend(List<double?> values) => _app(
      TrendChart(
        series: [
          TrendSeries(
            name: 'Push 1',
            color: const Color(0xFF4C8DFF),
            spots: [
              for (var i = 0; i < values.length; i++)
                values[i] == null
                    ? FlSpot.nullSpot
                    : FlSpot(i * 7.0, values[i]!),
            ],
          ),
        ],
        formatValue: (v) => v.round().toString(),
        tooltip: (v) => '${v.round()} kg',
      ),
    );

LineChartData _data(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

CyclePoint _cycle(int index, {bool isDeload = false}) => CyclePoint(
      cycleId: 'c$index',
      index: index,
      isDeload: isDeload,
      isOpen: false,
      value: isDeload ? null : index.toDouble(),
      lifts: const [],
    );

Widget _cycles(List<CyclePoint> points, {bool isBlocks = false}) => _app(
      CycleAxisChart(
        points: points,
        plotted: {
          for (final p in points)
            if (p.value != null) p.cycleId,
        },
        formatValue: formatCycleTick,
        isBlocks: isBlocks,
      ),
    );

List<LineChartBarData> _segments(WidgetTester tester) =>
    _data(tester).lineBarsData.where((b) => b.barWidth > 0).toList();

void main() {
  group('a trend line', () {
    testWidgets('breaks at an empty bucket instead of crossing it',
        (tester) async {
      await tester.pumpWidget(_trend([100, 102, null, 110, 112]));
      await tester.pumpAndSettle();

      final line = _data(tester).lineBarsData.first;
      expect(line.spots.length, 5);
      expect(line.spots[2].isNull(), isTrue,
          reason: 'fl_chart breaks the line at a null spot');
      expect([for (final s in line.spots) if (s.isNotNull()) s.y],
          [100, 102, 110, 112]);
    });

    testWidgets('bridges the break with a faint dotted line', (tester) async {
      await tester.pumpWidget(_trend([100, 102, null, 110, 112]));
      await tester.pumpAndSettle();

      final bars = _data(tester).lineBarsData;
      expect(bars.length, 2, reason: 'the line, then one bridge');
      final line = bars.first;
      final bridge = bars.last;
      expect(line.dashArray, isNull);
      expect(bridge.dashArray, softLineDash);
      expect(bridge.color!.a, closeTo(softLineAlpha, 0.01));
      expect([for (final s in bridge.spots) (s.x, s.y)],
          [(line.spots[1].x, 102), (line.spots[3].x, 110)]);
      expect(bridge.dotData.show, isFalse);
    });

    testWidgets('a bridge names nothing when touched', (tester) async {
      await tester.pumpWidget(_trend([100, 102, null, 110, 112]));
      await tester.pumpAndSettle();

      final data = _data(tester);
      final bridge = data.lineBarsData.last;
      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(bridge, 1, bridge.spots.first),
      ]);
      expect(items.single, isNull);
      expect(
        data.lineTouchData.getTouchedSpotIndicator(bridge, [0]).single,
        isNull,
      );
    });

    testWidgets('a line with no break has no bridge', (tester) async {
      await tester.pumpWidget(_trend([100, 102, 104, 110]));
      await tester.pumpAndSettle();

      expect(_data(tester).lineBarsData.length, 1);
    });

    testWidgets('scales its axis to the readings, not to the break',
        (tester) async {
      await tester.pumpWidget(_trend([100, 102, null, 110, 112]));
      await tester.pumpAndSettle();

      final data = _data(tester);
      expect(data.minY.isFinite && data.maxY.isFinite, isTrue);
      expect(data.minY, lessThanOrEqualTo(100));
      expect(data.maxY, greaterThanOrEqualTo(112));
    });

    testWidgets('keeps the off-scale caret on the right point across a break',
        (tester) async {
      await tester
          .pumpWidget(_trend([100, 101, null, 102, 260, 103, 104]));
      await tester.pumpAndSettle();

      final data = _data(tester);
      final line = data.lineBarsData.first;
      expect(line.spots[4].y, data.maxY,
          reason: 'the wild point is drawn on the top edge');
      expect(
        line.dotData.getDotPainter(line.spots[4], 0, line, 4),
        isA<OffScaleCaret>(),
      );
      expect(
        line.dotData.getDotPainter(line.spots[3], 0, line, 3),
        isA<FlDotCirclePainter>(),
      );
      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(line, 0, line.spots[4]),
      ]);
      expect(items.single!.text, '260 kg');
    });

    testWidgets('keeps the marker on a lone reading when the rest are dropped',
        (tester) async {
      // Neighbours closer than about ten pixels lose their markers: three
      // hundred weeks across this plot are under three apart. A reading with a
      // break either side is a line of no length, so without its marker it is
      // not drawn at all.
      final values = <double?>[
        for (var i = 0; i < 150; i++) 100 + i.toDouble(),
        null,
        140,
        null,
        for (var i = 0; i < 150; i++) 150 + i.toDouble(),
      ];
      await tester.pumpWidget(_trend(values));
      await tester.pumpAndSettle();

      final line = _data(tester).lineBarsData.first;
      final show = line.dotData.checkToShowDot;
      expect(show(line.spots[151], line), isTrue);
      expect(show(line.spots[10], line), isFalse);
      expect(show(line.spots[200], line), isFalse);
    });
  });

  testWidgets('a bar chart keeps an untrained month as a zero in its place',
      (tester) async {
    final series = VolumeSeries(
      label: 'Chest',
      weeks: [
        for (var i = 0; i < 13; i++)
          VolumeWeek(
            start: DateTime(2026, 6, 1).add(Duration(days: 7 * i)),
            // July has no training at all.
            sets: DateTime(2026, 6, 1).add(Duration(days: 7 * i)).month == 7
                ? 0
                : 10,
          ),
      ],
    );
    await tester.pumpWidget(
      _app(
        VolumeChart(
          series: series,
          by: Granularity.monthly,
          hue: const Color(0xFF00E5FF),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bars = tester.widget<WeeklyBars>(find.byType(WeeklyBars)).bars;
    expect([for (final b in bars) b.start.month], [6, 7, 8]);
    expect(bars[1].isEmpty, isTrue);
    expect(bars[1].totalSets, 0);
  });

  group('the cycle line', () {
    testWidgets('is dashed across a spell on another regime', (tester) async {
      await tester.pumpWidget(_cycles([
        _cycle(1),
        _cycle(2),
        _cycle(3),
        _cycle(9),
        _cycle(10),
      ]));
      await tester.pumpAndSettle();

      final segments = _segments(tester);
      expect(segments.length, 4);
      expect([for (final s in segments) s.dashArray != null],
          [false, false, true, false],
          reason: '3 to 9 sit side by side but six cycles lie between them');
      final jump = segments[2];
      expect(jump.color!.a, closeTo(segments.first.color!.a * 0.6, 0.01));
    });

    testWidgets('is dashed the same way across a deload', (tester) async {
      await tester.pumpWidget(_cycles([
        _cycle(1),
        _cycle(2),
        _cycle(3, isDeload: true),
        _cycle(4),
      ]));
      await tester.pumpAndSettle();

      final segments = _segments(tester);
      expect([for (final s in segments) s.dashArray != null], [false, true]);
    });

    testWidgets('is solid under blocks, where every segment spans a block',
        (tester) async {
      await tester.pumpWidget(_cycles(
        [_cycle(1), _cycle(2), _cycle(3), _cycle(9), _cycle(10)],
        isBlocks: true,
      ));
      await tester.pumpAndSettle();

      expect(_segments(tester).every((s) => s.dashArray == null), isTrue);
    });
  });
}
