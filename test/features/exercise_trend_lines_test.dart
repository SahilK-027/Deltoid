import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/history/exercise_trend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// An exercise's trend draws one line per session, and each line has a colour
/// of its own. Past seven there are no colours left, so the oldest sessions are
/// left out and the chart says how many — rather than repeating a colour, which
/// would draw two progressions as one.
void main() {
  // One performance per session, a day apart, all inside the default year.
  List<ProgressPoint> sessions(int n) => [
        for (var i = 0; i < n; i++)
          ProgressPoint(
            dayKey: dayKeyOf(DateTime.now().subtract(Duration(days: 30 - i))),
            sessionId: 's$i',
            sessionName: 'Session $i',
            isDeload: false,
            topSetLoad: 80.0 + i,
            topSetReps: 5,
            best1RM: 90.0 + i,
            volume: 400,
          ),
      ];

  Future<void> pump(WidgetTester tester, List<ProgressPoint> points) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseProgressProvider('bench')
              .overrideWith((ref) => Stream.value(points)),
          weightUnitProvider.overrideWith((ref) => Stream.value(WeightUnit.kg)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(
            body: SingleChildScrollView(child: ExerciseTrend(exerciseId: 'bench')),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  List<TrendSeries> drawn(WidgetTester tester) =>
      tester.widget<TrendChart>(find.byType(TrendChart)).series;

  testWidgets('nine sessions draw the seven most recent and say so',
      (tester) async {
    await pump(tester, sessions(9));

    final series = drawn(tester);
    expect(series, hasLength(7));
    expect(series.first.name, 'Session 8', reason: 'newest is the blue line');
    expect(series.last.name, 'Session 2');
    expect(find.text('Showing 7 of 9 sessions.'), findsOneWidget);
  });

  testWidgets('every drawn line has its own colour, blue first',
      (tester) async {
    await pump(tester, sessions(9));

    final colours = [for (final s in drawn(tester)) s.color];
    expect(colours.toSet(), hasLength(colours.length));
    expect(colours.first, DeltoidColors.dark.progress);
  });

  testWidgets('three sessions draw all three and say nothing', (tester) async {
    await pump(tester, sessions(3));

    expect(drawn(tester), hasLength(3));
    expect(find.textContaining('Showing'), findsNothing);
  });
}
