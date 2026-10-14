import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/cycle_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );

  List<CycleOrderRow> rows(int positions) => [
        for (final label in const ['This cycle', 'Next cycle'])
          CycleOrderRow(
            label: label,
            days: [
              for (var i = 0; i < positions; i++)
                CycleOrderDay(name: 'Day ${i + 1}', alternates: i == 2),
            ],
          ),
      ];

  testWidgets('five positions share the width and do not scroll',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(CycleOrderCard(rows: rows(5))));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNothing);
    // The last tile ends inside the card rather than past the screen.
    expect(tester.getTopRight(find.text('Day 5').first).dx, lessThan(360));
  });

  testWidgets('six positions keep their width and scroll together',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(CycleOrderCard(rows: rows(6))));

    expect(tester.takeException(), isNull);
    // One scroll view for every row, so the columns stay aligned while moving.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final first = tester.getSize(find.text('Day 1').first);
    final second = tester.getTopLeft(find.text('Day 1').last);
    expect(second.dx, tester.getTopLeft(find.text('Day 1').first).dx);
    expect(first.width, greaterThan(0));
  });

  testWidgets('the tile that alternates is marked, and dimmer in a later cycle',
      (tester) async {
    await tester.pumpWidget(host(CycleOrderCard(rows: rows(5))));

    const c = DeltoidColors.dark;
    Color fillOf(Finder text) {
      final box = tester.widget<Container>(
        find.ancestor(of: text, matching: find.byType(Container)).first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(fillOf(find.text('Day 3').first), c.accent);
    expect(fillOf(find.text('Day 3').last), c.textSecondary);
    expect(fillOf(find.text('Day 1').first), c.surfaceHigh);
  });

  testWidgets('a single cycle is drawn without a name', (tester) async {
    await tester.pumpWidget(
      host(
        const CycleOrderCard(
          rows: [
            CycleOrderRow(days: [CycleOrderDay(name: 'Push 1')]),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Push 1'), findsOneWidget);
    expect(find.text('This cycle'), findsNothing);
  });
}
