import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/progress/widgets/volume_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every chart draws the value axis `ValueAxis` gives it: the chart half of
/// `test/domain/value_axis_test.dart`, for the audit's findings 1, 3, 4, 7, 11
/// and 23.

Widget _app(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

Widget _trend(
  List<double> values, {
  String Function(double)? format,
  double minStep = 0,
  double minSpan = 0,
  double minSpanFraction = 0,
}) =>
    _app(
      TrendChart(
        series: [
          TrendSeries(
            name: 'Push 1',
            color: const Color(0xFF4C8DFF),
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i * 7.0, values[i]),
            ],
          ),
        ],
        formatValue: format ?? (v) => v.round().toString(),
        tooltip: (v) => '${v.round()} kg',
        minStep: minStep,
        minSpan: minSpan,
        minSpanFraction: minSpanFraction,
      ),
    );

CyclePoint _cycle(int index, double value) => CyclePoint(
      cycleId: 'c$index',
      index: index,
      isDeload: false,
      isOpen: false,
      value: value,
      lifts: const [],
      sessions: const [],
    );

Widget _cycles(List<double> values, {bool small = false}) {
  final points = [
    for (var i = 0; i < values.length; i++) _cycle(i + 1, values[i]),
  ];
  return _app(
    CycleAxisChart(
      points: points,
      plotted: {for (final p in points) p.cycleId},
      formatValue: formatCycleTick,
      small: small,
    ),
  );
}

LineChartData _data(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

/// The value labels the chart printed, top to bottom.
List<String> _printed(WidgetTester tester, bool Function(String) isValue) {
  final texts = [
    for (final e in find.byType(Text).evaluate())
      if ((e.widget as Text).data case final d? when isValue(d))
        (d, tester.getCenter(find.byWidget(e.widget)).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final t in texts) t.$1];
}

bool _number(String s) => double.tryParse(s) != null;
bool _percent(String s) => s.endsWith('%');

void main() {
  group('trend chart', () {
    testWidgets('a single value draws three labelled gridlines (finding 4)',
        (tester) async {
      await tester.pumpWidget(
        _trend([100], minStep: 0.5, minSpanFraction: 0.05),
      );
      await tester.pumpAndSettle();
      expect(_printed(tester, _number), ['102', '100', '98']);
    });

    testWidgets('a narrow band never repeats a label (finding 3)',
        (tester) async {
      String oneDecimal(double v) {
        final r = (v * 10).round() / 10;
        return r == r.roundToDouble()
            ? r.toStringAsFixed(0)
            : r.toStringAsFixed(1);
      }

      await tester.pumpWidget(
        _trend([80.0, 80.03, 80.06, 80.1], format: oneDecimal, minStep: 0.1),
      );
      await tester.pumpAndSettle();
      final labels = _printed(tester, _number);
      expect(labels, isNotEmpty);
      expect(labels.toSet().length, labels.length, reason: '$labels');
    });

    testWidgets('one typo is a caret on the top edge, read at its real value '
        '(finding 23)', (tester) async {
      await tester.pumpWidget(_trend([100, 101, 102, 260, 103, 104]));
      await tester.pumpAndSettle();

      final data = _data(tester);
      final line = data.lineBarsData.single;
      expect(data.maxY, lessThan(120));
      expect(line.spots[3].y, data.maxY,
          reason: 'the line runs to the edge and back');
      expect(line.spots[2].y, 102);

      final caret = line.dotData.getDotPainter(line.spots[3], 0, line, 3);
      expect(caret, isA<OffScaleCaret>());
      expect((caret as OffScaleCaret).pointsUp, isTrue);
      expect(
        line.dotData.getDotPainter(line.spots[2], 0, line, 2),
        isA<FlDotCirclePainter>(),
      );

      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(line, 0, line.spots[3]),
      ]);
      expect(items.single!.text, '260 kg');
    });

    testWidgets('no gridline is drawn without a label', (tester) async {
      await tester.pumpWidget(_trend([75, 90, 105, 120, 131]));
      await tester.pumpAndSettle();
      final grid = _data(tester).gridData;
      final drawn = [
        for (var v = 0.0; v <= 200; v += grid.horizontalInterval!)
          if (grid.checkToShowHorizontalLine(v)) '${v.round()}',
      ];
      expect(drawn, ['80', '100', '120', '140']);
      expect(_printed(tester, _number), ['140', '120', '100', '80']);
    });
  });

  group('cycle axis', () {
    testWidgets('a regime at +259% stays inside the plot (finding 1)',
        (tester) async {
      final values = [for (var i = 0; i < 12; i++) i * 259.4 / 11];
      await tester.pumpWidget(_cycles(values));
      await tester.pumpAndSettle();
      final data = _data(tester);
      for (final bar in data.lineBarsData) {
        for (final spot in bar.spots) {
          expect(spot.y, inInclusiveRange(data.minY, data.maxY));
        }
      }
      expect(_printed(tester, _percent), ['+400%', '+200%', '0%']);
    });

    testWidgets('three gridlines, all of them drawn and labelled '
        '(finding 11)', (tester) async {
      await tester.pumpWidget(_cycles([6, 8, 11]));
      await tester.pumpAndSettle();
      final data = _data(tester);
      expect((data.minY, data.maxY), (4.0, 12.0));
      // `fl_chart` draws the one between the bounds, and the bounds are drawn
      // as extra lines.
      expect(data.gridData.checkToShowHorizontalLine(8), isTrue);
      expect(
        [for (final l in data.extraLinesData.horizontalLines) l.y],
        [4, 12],
      );
      expect(_printed(tester, _percent), ['+12%', '+8%', '+4%']);
    });

    testWidgets('one wild cycle is a caret, and the readout still gets its '
        'value (finding 23)', (tester) async {
      await tester.pumpWidget(
        _cycles([0, 1, 2, 3, 4, 5, 60, 6, 7, 8, 9, 10]),
      );
      await tester.pumpAndSettle();
      final data = _data(tester);
      expect(data.maxY, 10);
      final markers = data.lineBarsData.last;
      final wild = markers.spots[6];
      expect(wild.y, 10);
      expect(
        markers.dotData.getDotPainter(wild, 0, markers, 6),
        isA<OffScaleCaret>(),
      );
    });

    testWidgets('the sparkline keeps the caret and no other marker',
        (tester) async {
      await tester.pumpWidget(
        _cycles([0, 1, 2, 3, 4, 5, 60, 6, 7, 8, 9, 10], small: true),
      );
      await tester.pumpAndSettle();
      final markers = _data(tester).lineBarsData.last;
      expect(markers.dotData.checkToShowDot(markers.spots[6], markers), isTrue);
      expect(markers.dotData.checkToShowDot(markers.spots[5], markers), isFalse);
      expect(_data(tester).extraLinesData.horizontalLines, isEmpty,
          reason: 'a sparkline states no scale');
    });
  });

  testWidgets('a heavy week labels the volume axis twice, not eleven times '
      '(finding 7)', (tester) async {
    final series = VolumeSeries(
      label: 'Chest',
      weeks: [
        for (var i = 0; i < 13; i++)
          VolumeWeek(
            start: DateTime(2026, 8, 10).subtract(Duration(days: 7 * (12 - i))),
            sets: i == 6 ? 120 : 10,
          ),
      ],
    );
    await tester.pumpWidget(
      _app(
        VolumeChart(
          series: series,
          by: Granularity.weekly,
          hue: const Color(0xFF00E5FF),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_printed(tester, (s) => int.tryParse(s) != null), ['100', '50']);
  });
}
