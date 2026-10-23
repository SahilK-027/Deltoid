import 'dart:io';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/features/home/widgets/habit_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Inter, as `y_axis_gutter_test.dart` loads it: the test font draws every
/// glyph a full em wide, so a question about whether words fit is only
/// answered in the real face.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// The tile's own layout, at the width it has on a phone: half of a 393dp
/// screen less the gutters and the gap between the two tiles.
void main() {
  setUpAll(_loadInter);

  Future<void> pumpTile(WidgetTester tester, {Widget? action}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 174,
              child: HabitTile(
                title: 'Weigh-ins',
                fill: (_) => null,
                thisWeek: 3,
                onTap: () {},
                action: action,
                today: DateTime(2026, 10, 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('says this week in full in half a phone', (tester) async {
    await pumpTile(tester);

    final words = tester.renderObject<RenderParagraph>(find.text('this week'));
    expect(words.didExceedMaxLines, isFalse,
        reason: 'two Flexibles split the row in half and cut it short');
    expect(find.text('3/7'), findsOneWidget);
  });

  testWidgets('draws thirty days, filled down each column', (tester) async {
    // 15 October is the last day, so the window opens on 16 September.
    const second = Color(0xFFFF0000);
    const today = Color(0xFF00FF00);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 174,
              child: HabitGrid(
                fill: (key) => switch (key) {
                  20260917 => second,
                  20261015 => today,
                  _ => null,
                },
                today: DateTime(2026, 10, 15),
              ),
            ),
          ),
        ),
      ),
    );

    final cells = find.descendant(
      of: find.byType(HabitGrid),
      matching: find.byType(Container),
    );
    expect(cells, findsNWidgets(30));
    Rect cellIn(Color colour) => tester.getRect(find.byWidgetPredicate(
          (w) =>
              w is Container &&
              (w.decoration as BoxDecoration?)?.color == colour,
        ));

    final first = tester.getRect(cells.first);
    expect(first.width, closeTo(first.height, 0.01), reason: 'square');
    // The second day sits under the first, as on the year map, not beside it.
    expect(cellIn(second).left, closeTo(first.left, 0.01));
    expect(cellIn(second).top, greaterThan(first.bottom));
    // Today closes the grid at the bottom right: the last column's last cell,
    // flush with the right edge.
    final last = tester.getRect(cells.last);
    expect(cellIn(today), last);
    expect(last.right, closeTo(174, 0.01));
    expect(last.bottom, greaterThan(cellIn(second).bottom));
  });

  testWidgets('a tap on the button does not also open the tile', (
    tester,
  ) async {
    var opened = 0;
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 174,
            child: HabitTile(
              title: 'Weigh-ins',
              fill: (_) => null,
              thisWeek: null,
              onTap: () => opened++,
              action: HabitAction(
                icon: Icons.add_rounded,
                tooltip: 'Log weight',
                onTap: () => pressed++,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Log weight'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pressed, 1);
    expect(opened, 0);
    // Nothing logged ever: a dash rather than a zero.
    expect(find.text('—/7'), findsOneWidget);

    await tester.tap(find.text('Last 30 days'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, 1);
  });
}
