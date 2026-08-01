import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The day tabs lay out inside a horizontal scroll, where the cross axis is
/// unbounded. A stretching column in unbounded space asks for an infinite
/// width, and the device answered with one `BoxConstraints forces an infinite
/// width` followed by a hundred `RenderBox was not laid out` — the Regime tab
/// rendered as nothing at all.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: Column(children: [child])),
      );

  testWidgets('lay out in a horizontal scroll without an infinite width',
      (tester) async {
    await tester.pumpWidget(
      host(
        UnderlineTabs(
          labels: const ['Push 1', 'Pull 1', 'Legs and a very long day name'],
          index: 1,
          onSelect: (_) {},
          trailingLabel: 'Add day  +',
          onTrailing: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Push 1'), findsOneWidget);
    expect(find.text('Add day  +'), findsOneWidget);
  });

  testWidgets('a single tab still lays out', (tester) async {
    await tester.pumpWidget(
      host(
        UnderlineTabs(labels: const ['Full body'], index: 0, onSelect: (_) {}),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Full body'), findsOneWidget);
  });
}
