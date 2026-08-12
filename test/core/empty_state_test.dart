import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';

Widget _harness(double height) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: height,
            child: EmptyState(
              icon: Icons.tune_rounded,
              title: 'Nothing set up yet',
              message: 'Build your training split — any number of sessions, in '
                  'any order. One pass through all of them is a cycle.',
              action:
                  PrimaryButton(label: 'Create a regime', onPressed: () {}),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('roomy viewport: fills the space, centred, nothing clipped',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(700));
    final view = tester.getRect(find.byType(SingleChildScrollView));
    final btn = tester.getRect(find.byType(PrimaryButton));
    expect(view.height, 700, reason: 'viewport must fill the space given');
    expect(btn.bottom, lessThanOrEqualTo(view.bottom));

    final state = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(state.position.maxScrollExtent, 0,
        reason: 'content fits, so there is nothing to scroll');
  });

  testWidgets('cramped viewport: overflow scrolls instead of being clipped',
      (tester) async {
    await tester.pumpWidget(_harness(240));
    final view = tester.getRect(find.byType(SingleChildScrollView));
    expect(view.height, 240, reason: 'viewport must fill the space given');

    final state = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(state.position.maxScrollExtent, greaterThan(0),
        reason: 'overflow must be reachable, not cut off at a fixed edge');

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final btn = tester.getRect(find.byType(PrimaryButton));
    expect(btn.bottom, lessThanOrEqualTo(view.bottom + 0.5),
        reason: 'button must be fully visible once scrolled to the end');
  });
}
