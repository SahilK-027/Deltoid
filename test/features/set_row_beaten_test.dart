import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/prefill.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/widgets/set_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The done mark on a bodyweight movement is scored on the real bodyweight.
///
/// The plates are a small part of a weighted dip's load, so whether five more
/// kilograms for one rep fewer is a better set depends on the person under
/// them. A fixed stand-in figure answered for somebody else.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double bodyweightKg,
    int bodyweightPct = 100,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SetRow(
            set: const SetLog(
              id: 's1',
              updatedAt: 0,
              deviceId: 'test',
              dirty: false,
              workoutExerciseId: 'we1',
              setIndex: 0,
              setType: SetType.working,
              addedWeight: 15,
              reps: 8,
              isDone: true,
            ),
            loadMode: LoadMode.bodyweightPlus,
            unit: WeightUnit.kg,
            ghost: const PastSet(
              type: SetType.working,
              addedWeight: 10,
              reps: 9,
            ),
            bodyweightKg: bodyweightKg,
            bodyweightPct: bodyweightPct,
            editing: null,
            buffer: ValueNotifier<String>(''),
            onEdit: (_, _) {},
            onEditPartial: (_) {},
            onToggleDone: (_, _) {},
          ),
        ),
      ),
    );
  }

  testWidgets('BW+10 × 9 → BW+15 × 8 is a win at 70kg', (tester) async {
    // 80 * 1.3 = 104.0 against 85 * (1 + 8/30) = 107.7, 3.5% better.
    await pump(tester, bodyweightKg: 70);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
  });

  testWidgets('the same two sets are a wash at 100kg', (tester) async {
    // 110 * 1.3 = 143.0 against 115 * (1 + 8/30) = 145.7, 1.9% better and
    // inside the margin.
    await pump(tester, bodyweightKg: 100);
    expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('the share of bodyweight the movement moves is read', (
    tester,
  ) async {
    // At 100kg and a 60% share the body contributes 60kg: 70 * 1.3 = 91.0
    // against 75 * (1 + 8/30) = 95.0, 4.4% better.
    await pump(tester, bodyweightKg: 100, bodyweightPct: 60);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
  });
}
