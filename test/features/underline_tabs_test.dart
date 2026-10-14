import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
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

  testWidgets('a single tab still lays out, and stays on the gutter',
      (tester) async {
    await tester.pumpWidget(
      host(
        UnderlineTabs(labels: const ['Full body'], index: 0, onSelect: (_) {}),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Full body'), findsOneWidget);
    // The strip is full width whatever is in it. Left to shrink-wrap, a column
    // centres it, and one day's tabs floated into the middle of the band while
    // six days' sat against the gutter.
    expect(
      tester.getTopLeft(find.text('Full body')).dx,
      Space.gutter + Space.md,
    );
  });

  testWidgets('a leading tab is drawn selected instead of the indexed one',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      host(
        UnderlineTabs(
          labels: const ['Push 1', 'Pull 1'],
          index: 0,
          onSelect: (_) {},
          leadingLabel: 'Cycle',
          leadingIcon: Icons.sync_rounded,
          leadingSelected: true,
          onLeading: () => opened++,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    const c = DeltoidColors.dark;
    Color? colourOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;
    // One tab reads as open, and it is the leading one although `index` still
    // names the first day.
    expect(colourOf('Cycle'), c.textPrimary);
    expect(colourOf('Push 1'), c.textSecondary);
    // It is told apart by its glyph.
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);

    await tester.tap(find.text('Cycle'));
    expect(opened, 1);
  });
}
