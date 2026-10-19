import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/features/home/widgets/year_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The year map Weigh-ins draws its days with: the fill of a day, and the
/// words of a picked one.
void main() {
  final c = DeltoidColors.dark;

  group('weigh-in days', () {
    final days = WeighInYearDays({20250101});

    test('fill a weighed day in the weigh-in colour, never in blue', () {
      expect(days.fill(c, 20250101), c.weighIn);
      expect(days.fill(c, 20250101), isNot(c.progress));
      expect(days.fill(c, 20250102), c.heatEmpty);
    });

    test('read weighed or no weigh-in', () {
      expect(days.describe(20250101, isFuture: false), 'weighed');
      expect(days.describe(20250102, isFuture: false), 'no weigh-in');
    });

    test('say nothing but the date of a day still to come', () {
      expect(days.describe(20250102, isFuture: true), isEmpty);
    });
  });

  test('two wrappers around the same days are the same days', () {
    // The screens build a fresh wrapper on every frame. Unequal, every frame
    // would repaint every year on the page.
    final set = {20250101};
    expect(WeighInYearDays(set), WeighInYearDays(set));
    expect(WeighInYearDays(set), isNot(WeighInYearDays({20250101})));
  });

  group('a tapped day', () {
    Future<void> pumpYear(WidgetTester tester, YearMapDays days) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: YearHeatmap(year: 2025, days: days),
            ),
          ),
        ),
      );
    }

    /// Taps a day of 2025, by its column and its row from Monday.
    ///
    /// 2025 starts on a Wednesday, so its first column holds two days of 2024
    /// and the 1st of January is row 2 of column 0. The geometry is the map's
    /// own: fifty-three weeks across the width, with a gap a fifth of each.
    Future<void> tapDay(WidgetTester tester, {required int column, required int row}) async {
      final box = tester.getRect(find.byType(CustomPaint).last);
      final unit = box.width / 53;
      final gap = (unit * 0.2).clamp(1.0, 3.0);
      final cell = (unit - gap).clamp(2.0, 14.0);
      await tester.tapAt(box.topLeft +
          Offset(column * (cell + gap) + cell / 2, row * (cell + gap) + cell / 2));
      await tester.pump();
    }

    testWidgets('reads weighed on a weigh-in map', (tester) async {
      await pumpYear(tester, WeighInYearDays({20250101}));
      await tapDay(tester, column: 0, row: 2);
      expect(find.bySemanticsLabel('Wed 1 Jan · weighed'), findsOneWidget);
    });

    testWidgets('reads no weigh-in on a day without one', (tester) async {
      await pumpYear(tester, WeighInYearDays({20250101}));
      await tapDay(tester, column: 0, row: 3);
      expect(find.bySemanticsLabel('Thu 2 Jan · no weigh-in'), findsOneWidget);
    });

    testWidgets('a second tap on the same day lets it go', (tester) async {
      await pumpYear(tester, WeighInYearDays({20250101}));
      await tapDay(tester, column: 0, row: 2);
      await tapDay(tester, column: 0, row: 2);
      expect(find.bySemanticsLabel('2025'), findsOneWidget);
    });
  });
}
