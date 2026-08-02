import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/widgets/set_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The heading names what the second column holds, and the clock in the cells
/// under it does the rest: `2:25` under `Time` cannot be misread as a rep
/// count.
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

  testWidgets('a hold is measured in time, and says so', (tester) async {
    await pump(tester, MeasureMode.hold);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Reps'), findsNothing);
  });

  testWidgets('everything else counts reps', (tester) async {
    await pump(tester, MeasureMode.reps);
    expect(find.text('Reps'), findsOneWidget);
  });
}
