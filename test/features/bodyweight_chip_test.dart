import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/log_providers.dart';
import 'package:deltoid/features/log/widgets/bodyweight_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chip under a bodyweight movement's name on the log.
///
/// It prints the bodyweight the lift is scored against, and the two cases it
/// exists for are the ones nothing else on the log shows: a figure that was
/// never weighed, and one that was weighed too long ago.
void main() {
  const today = 20260120;

  Future<void> pump(
    WidgetTester tester, {
    required List<({int dayKey, double weightKg})> series,
    LoadMode load = LoadMode.bodyweight,
    MeasureMode measure = MeasureMode.reps,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weightUnitProvider.overrideWith((ref) => Stream.value(unit)),
          bodyweightSeriesProvider.overrideWith((ref) async => series),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: BodyweightChip(
              loadMode: load,
              measureMode: measure,
              dayKey: today,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing logged shows the assumed figure', (tester) async {
    await pump(tester, series: const []);
    expect(find.text('Bodyweight 60 kg assumed'), findsOneWidget);
  });

  testWidgets('a recent weigh-in shows the figure alone', (tester) async {
    await pump(tester, series: const [(dayKey: 20260118, weightKg: 73.2)]);
    expect(find.text('Bodyweight 73.2 kg'), findsOneWidget);
  });

  testWidgets('an old weigh-in says how old it is', (tester) async {
    await pump(tester, series: const [(dayKey: 20260108, weightKg: 73.2)]);
    expect(find.text('Bodyweight 73.2 kg · 12 days old'), findsOneWidget);
  });

  testWidgets('a movement that takes a load has no chip', (tester) async {
    await pump(tester, series: const [], load: LoadMode.total);
    expect(find.byType(AppChip), findsNothing);
  });

  testWidgets('a hold has no chip, because nothing scores its load',
      (tester) async {
    await pump(tester, series: const [], measure: MeasureMode.hold);
    expect(find.byType(AppChip), findsNothing);
  });

  testWidgets('the sheet asks for a weight when none is logged',
      (tester) async {
    await pump(tester, series: const [], load: LoadMode.bodyweightPlus);

    await tester.tap(find.byType(AppChip));
    await tester.pumpAndSettle();

    expect(find.text('Bodyweight'), findsOneWidget);
    expect(
      find.text(
        'No bodyweight is logged, so 60 kg is assumed. Log your weight for an '
        'accurate strength trend.',
      ),
      findsOneWidget,
    );
    expect(find.text('Assumed until a weight is logged'), findsOneWidget);
    expect(find.text('Your bodyweight plus the weight you add'), findsOneWidget);
    expect(find.text('Log bodyweight'), findsOneWidget);
  });

  testWidgets('the sheet asks for a newer weight when the last one is old',
      (tester) async {
    await pump(tester, series: const [(dayKey: 20260108, weightKg: 73.2)]);

    await tester.tap(find.byType(AppChip));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Your last weigh-in was 12 days ago. Log your latest weight for an '
        'accurate strength trend.',
      ),
      findsOneWidget,
    );
    expect(find.text('73.2 kg'), findsOneWidget);
    expect(find.text('Weighed 8 Jan 2026'), findsOneWidget);
  });

  testWidgets('a recent weigh-in opens a sheet with nothing to ask',
      (tester) async {
    await pump(tester, series: const [(dayKey: 20260118, weightKg: 73.2)]);

    await tester.tap(find.byType(AppChip));
    await tester.pumpAndSettle();

    expect(find.byType(NoticeBox), findsNothing);
    expect(find.text('Your bodyweight'), findsOneWidget);
    expect(find.text('Log bodyweight'), findsOneWidget);
  });
}
