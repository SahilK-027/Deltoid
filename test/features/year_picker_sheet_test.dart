import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The year picker on a real phone: a short screen, a gesture bar, and enough
/// years to fill it.
void main() {
  Future<void> openPicker(
    WidgetTester tester, {
    required int years,
    double bottomInset = 48,
  }) async {
    const dpr = 3.0;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = const Size(390 * dpr, 844 * dpr);
    tester.view.padding =
        FakeViewPadding(bottom: bottomInset * dpr);
    tester.view.viewInsets = FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: TrendRangeBar(
              window: const TrendWindow.rolling(ChartRange.year),
              years: [for (var y = 0; y < years; y++) 2026 - y],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    // The chip row is eight choices wide now — six ranges, `All`, the year —
    // so on a 390pt phone the year chip starts off the right edge. That is the
    // strip working as designed (a clipped chip is the scroll affordance), and
    // it means this test has to scroll to it exactly as a thumb would.
    await tester.ensureVisible(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
  }

  testWidgets('a short list clears the gesture bar', (tester) async {
    await openPicker(tester, years: 3);

    expect(find.text('Which year?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The last row has to end above the gesture bar, not under it.
    final last = tester.getRect(find.text('2024'));
    expect(
      last.bottom,
      lessThanOrEqualTo(844 - 48),
      reason: 'the bottom row was sitting behind the system navigation bar',
    );
  });

  testWidgets('a long list scrolls instead of overflowing', (tester) async {
    // Twenty years of training is a list taller than the phone. The sheet has
    // to cap itself and scroll — an uncapped column overflows the screen and
    // the years at the end are unreachable.
    await openPicker(tester, years: 20);

    expect(tester.takeException(), isNull);

    final sheet = tester.getRect(find.byType(AppSheet));
    expect(
      sheet.height,
      lessThanOrEqualTo(844),
      reason: 'the sheet grew taller than the screen',
    );
    expect(sheet.bottom, lessThanOrEqualTo(844));

    // And the far end is reachable rather than drawn off the bottom.
    await tester.dragFrom(const Offset(195, 700), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('2007'), findsOneWidget);
  });
}
