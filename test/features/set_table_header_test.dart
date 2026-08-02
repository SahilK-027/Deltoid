import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/widgets/set_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The heading is the only place the second column's unit is said, so a hold's
/// table is read correctly or not at all off this one word: `45` under `Reps`
/// is a claim nobody makes.
void main() {
  Future<void> pump(WidgetTester tester, MeasureMode measure) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SetTableHeader(
            loadMode: LoadMode.bodyweight,
            measure: measure,
            unit: WeightUnit.kg,
          ),
        ),
      ),
    );
  }

  testWidgets('a hold counts seconds, and says so', (tester) async {
    await pump(tester, MeasureMode.hold);
    expect(find.text('Secs'), findsOneWidget);
    expect(find.text('Reps'), findsNothing);
  });

  testWidgets('everything else counts reps', (tester) async {
    await pump(tester, MeasureMode.reps);
    expect(find.text('Reps'), findsOneWidget);
  });
}
