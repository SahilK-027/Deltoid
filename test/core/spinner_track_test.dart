import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';

/// A spinner that does not visibly move has said nothing.
///
/// Material 3 draws `circularTrackColor` as a full ring behind the arc, so a
/// track turns `RowSpinner` — 16 logical pixels at `strokeWidth: 2` — into a
/// circle with a sliver moving inside it, and it reads as static. That is the
/// one thing a spinner on a control may not do: THEME allows it only where the
/// app is genuinely waiting on somebody else, and only because a moving thing
/// is what says it is still happening.
void main() {
  for (final brightness in Brightness.values) {
    test('no circular track in the ${brightness.name} theme', () {
      expect(
        buildTheme(brightness).progressIndicatorTheme.circularTrackColor,
        isNull,
        reason: 'a full ring behind a 2px arc reads as a static circle — the '
            'sign-in spinner looked like it had stopped',
      );
    });
  }

  testWidgets('RowSpinner paints an arc and no ring behind it', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(body: Center(child: RowSpinner())),
    ));

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.backgroundColor, isNull);
    // Indeterminate: a `value` would make it a fixed arc that never sweeps,
    // which is the same failure by a different route.
    expect(indicator.value, isNull);
  });
}
