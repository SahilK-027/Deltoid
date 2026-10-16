import 'dart:io';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/progress/widgets/volume_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The volume chart's value gutter fits every label it prints — the bar-chart
/// half of `test/core/y_axis_gutter_test.dart`.
///
/// The gutter was measured on the axis maximum alone. The maximum is never
/// printed, and Inter's figures are proportional, so an axis topping out at
/// 110 printed `100` — wider, having two zeros where 110 has one — into a box
/// sized for the narrower number, and the `Stack` it sits in clipped it.
///
/// **Only meaningful with Inter loaded**: the test font puts every glyph on one
/// advance, and every label then measures the same.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  testWidgets('every value label fits the gutter it is printed in',
      (tester) async {
    // A peak of 105 sets a week: an axis of 110, labelled 10 to 100.
    final series = VolumeSeries(
      label: 'Chest',
      weeks: [
        for (var i = 0; i < 8; i++)
          VolumeWeek(
            start: DateTime(2026, 8, 10).subtract(Duration(days: 7 * (7 - i))),
            sets: i == 7 ? 105 : 40,
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: VolumeChart(
              series: series,
              by: Granularity.weekly,
              hue: const Color(0xFF00E5FF),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final values = find.byWidgetPredicate(
      (w) => w is Text && int.tryParse(w.data ?? '') != null,
    );
    final printed = [
      for (final w in tester.widgetList<Text>(values)) int.parse(w.data!),
    ];
    expect(printed, contains(100), reason: 'the band has to print 100');
    expect(printed, isNot(contains(110)), reason: 'the maximum is not printed');

    double widthOf(String label, TextStyle? style) => (TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
        )..layout())
            .width;

    final style = tester.widget<Text>(values.first).style;
    // Without this the band proves nothing: it is the case where the maximum
    // is narrower than a label under it.
    expect(widthOf('100', style), greaterThan(widthOf('110', style)));

    for (final element in values.evaluate()) {
      final label = find.byWidget(element.widget);
      final gutter = find.ancestor(of: label, matching: find.byType(Stack)).first;
      expect(
        tester.getRect(label).left,
        greaterThanOrEqualTo(tester.getRect(gutter).left - 0.01),
        reason: '"${(element.widget as Text).data}" runs out of the left of its '
            'gutter, where the stack clips it',
      );
    }
  });
}
