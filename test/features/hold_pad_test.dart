import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/features/log/widgets/hold_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hold is a number you find out, not one you know. The pad that replaces
/// the keypad on an isometric movement has to be usable with your forearms on
/// the floor: start, stop, done.
void main() {
  Future<int?> pump(
    WidgetTester tester, {
    int? previous,
    int? current,
    VoidCallback? onType,
  }) async {
    int? stopped;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HoldPad(
              previous: previous,
              current: current,
              onStop: (s) => stopped = s,
              onType: onType ?? () {},
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    return stopped;
  }

  testWidgets('last time is a mark to pass, not a target to stop at', (
    tester,
  ) async {
    await pump(tester, previous: 62);
    // Minutes, because this one is watched second by second — the set table
    // still prints the bare seconds it stores.
    expect(find.text('Last time 1:02'), findsOneWidget);
    expect(find.text('Start hold'), findsOneWidget);
  });

  testWidgets('with nothing behind it there is nothing to compare against', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No previous hold to compare against'), findsOneWidget);
    expect(find.textContaining('last time'), findsNothing);
  });

  testWidgets('a logged hold reads as a record, not a clock at zero', (
    tester,
  ) async {
    await pump(tester, current: 75, previous: 62);
    expect(find.text('1:15'), findsOneWidget);
    expect(find.text('Past last time by 13s'), findsOneWidget);
  });

  testWidgets('the digits are one tap away, and gone once it is running', (
    tester,
  ) async {
    var typed = false;
    await pump(tester, onType: () => typed = true);

    expect(find.text('Type it'), findsOneWidget);
    await tester.tap(find.text('Type it'));
    expect(typed, isTrue);

    await tester.tap(find.text('Start hold'));
    await tester.pump();
    // Offering to type it mid-set is offering to throw the running clock away.
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Type it'), findsNothing);
  });

  testWidgets('a stop inside the first second is a mis-tap, not a set', (
    tester,
  ) async {
    // The wall clock does not move inside a widget test, so this is the
    // zero-elapsed case by construction — and it must write nothing.
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HoldPad(
              onStop: (_) => stops++,
              onType: () {},
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start hold'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(stops, 0);
    expect(find.text('Start hold'), findsOneWidget);
  });
}
