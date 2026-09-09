import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';

/// The value gutter has to fit every label the axis prints, not just the two on
/// the bounds.
///
/// **This test only means anything with Inter loaded.** The figures in Inter are
/// proportional — `1` is 833 units against `0` at 1292 — so a label is not as
/// wide as its digit count, and an axis running 185 to 215 sizes its gutter on
/// two bounds that both contain a `1`, then prints `200` and `205`, which do
/// not. A side title is clipped rather than reported as overflowing, so the axis
/// reads `20` and nothing anywhere raises a word about it.
///
/// A widget test loads no fonts of its own: the fallback puts every glyph on one
/// advance, every label measures the same, and the defect cannot reproduce. The
/// first version of this test passed against the unfixed chart for exactly that
/// reason. So the real font is loaded here, and the band below is the one the
/// bug was found on — 200 kg on the leg press, at a five-kilogram step.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _harness(Brightness brightness, (double, double) scale) => MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: EmptyTrendChart(
          window: const TrendWindow.rolling(ChartRange.year),
          scale: scale,
          formatValue: (v) => v.round().toString(),
        ),
      ),
    );

void main() {
  setUpAll(_loadInter);

  for (final brightness in Brightness.values) {
    testWidgets(
      'the value gutter fits every label the axis draws — ${brightness.name}',
      (tester) async {
        await tester.pumpWidget(_harness(brightness, (192, 208)));
        await tester.pumpAndSettle();

        final data = tester.widget<LineChart>(find.byType(LineChart)).data;
        final sideTitles = data.titlesData.rightTitles.sideTitles;
        final step = sideTitles.interval!;
        final gutter = sideTitles.reservedSize;

        // The style the axis actually labels in, read off the built tree rather
        // than restated here, so a change of type role moves this with it.
        final style = tester
            .widget<Text>(
              find
                  .byWidgetPredicate(
                    (w) => w is Text && int.tryParse(w.data ?? '') != null,
                  )
                  .first,
            )
            .style;

        double widthOf(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: TextDirection.ltr,
          )..layout();
          return painter.width;
        }

        var ticks = 0;
        var sawLabelWiderThanItsBounds = false;
        final bounds = [data.minY, data.maxY]
            .map((v) => widthOf(v.round().toString()))
            .reduce((a, b) => a > b ? a : b);

        for (var v = data.minY; v <= data.maxY + 0.0001; v += step) {
          final label = v.round().toString();
          // `SideTitleWidget` spends `Space.xs` of the reserved size on the gap
          // before the text, so the label is laid out in what is left. Comparing
          // against the whole gutter is what let the first version of this test
          // pass over a chart that was visibly clipping.
          expect(
            gutter - Space.xs,
            greaterThanOrEqualTo(widthOf(label)),
            reason: '"$label" needs ${widthOf(label).toStringAsFixed(2)}px and '
                'is laid out in ${(gutter - Space.xs).toStringAsFixed(2)}px, '
                'so the axis prints it a glyph short',
          );
          ticks += 1;
          if (widthOf(label) > bounds) sawLabelWiderThanItsBounds = true;
        }

        expect(ticks, greaterThan(2), reason: 'the axis has interior ticks');

        // Without this the assertions above could all pass on a band where the
        // bounds happen to be the widest labels — which is the case the broken
        // gutter got right, and proves nothing.
        expect(
          sawLabelWiderThanItsBounds,
          isTrue,
          reason: 'the band must contain a label wider than either bound, '
              'or it does not exercise the defect',
        );
      },
    );
  }
}
