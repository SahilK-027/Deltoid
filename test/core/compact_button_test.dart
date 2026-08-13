import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';

/// Full width is a commitment — *this is what the screen is for*. An action
/// that adds one more row to a list you are browsing takes the compact form,
/// bottom right (THEME → Buttons).
void main() {
  Widget harness(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: Column(children: [child])),
      );

  testWidgets('a compact primary is the width of its own words',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(harness(Align(
      alignment: Alignment.centerRight,
      child: PrimaryButton(
        compact: true,
        label: 'New exercise',
        icon: Icons.add_rounded,
        onPressed: () {},
      ),
    )));

    final size = tester.getSize(find.byType(PrimaryButton));
    expect(size.height, 46);
    // Its own words plus the 20 either side, not the page. Measured against the
    // label rather than against a number, because the test font is a square per
    // glyph and a hard width here would only be asserting that.
    final label = tester.getSize(find.text('New exercise')).width;
    expect(size.width, lessThan(400));
    expect(size.width, closeTo(label + 20 + 8 + 20 * 2, 1));

    // And parked on the right edge, not centred.
    expect(tester.getRect(find.byType(PrimaryButton)).right, 400);
  });

  testWidgets('the default primary still spans the screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(harness(
      PrimaryButton(label: 'Finish session', onPressed: () {}),
    ));

    final size = tester.getSize(find.byType(PrimaryButton));
    expect(size.width, 400);
    expect(size.height, 54);
  });
}
