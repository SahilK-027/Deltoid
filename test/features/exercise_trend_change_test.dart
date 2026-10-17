import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/history/exercise_trend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The figures under an exercise's trend: `Change` is read along one
/// session's own line, never from one session to the other (RULES § 1), a drop
/// is not painted red, and a flat line is `0%` at its best. The chart audit's
/// finding 20.
void main() {
  ProgressPoint point(int daysAgo, String session, double e1rm) =>
      ProgressPoint(
        dayKey: dayKeyOf(DateTime.now().subtract(Duration(days: daysAgo))),
        sessionId: session,
        sessionName: session,
        isDeload: false,
        topSetLoad: e1rm * 0.85,
        topSetReps: 5,
        best1RM: e1rm,
        volume: 400,
      );

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
            body: SingleChildScrollView(
              child: ExerciseTrend(exerciseId: 'bench'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('reads the change along the latest session, in the text colour',
      (tester) async {
    // Push 1 is the heavier day. First Push 1 against last Push 2 read −22%.
    await pump(tester, [
      point(6, 'Push 1', 100),
      point(4, 'Push 2', 80),
      point(2, 'Push 1', 102),
      point(0, 'Push 2', 78),
    ]);

    expect(find.text('Change in Push 2'), findsOneWidget);
    final figure = tester.widget<Text>(find.text('−2.5%'));
    expect(figure.style?.color, isNot(DeltoidColors.dark.negative));
    expect(figure.style?.color, isNot(DeltoidColors.dark.positive));
  });

  testWidgets('a gain is green', (tester) async {
    await pump(tester, [point(4, 'Push 1', 100), point(0, 'Push 1', 104)]);

    expect(find.text('Change'), findsOneWidget);
    final figure = tester.widget<Text>(find.text('+4.0%'));
    expect(figure.style?.color, DeltoidColors.dark.positive);
  });

  testWidgets('a flat line is 0% and at its best', (tester) async {
    await pump(tester, [
      for (var d = 30; d >= 0; d -= 3) point(d, 'Push 1', 100),
    ]);

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('+0.0%'), findsNothing);
    expect(find.text('Peak'), findsOneWidget);
    expect(find.textContaining('since best'), findsNothing);
  });
}
