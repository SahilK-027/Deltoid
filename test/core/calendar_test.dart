import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The day picker is ours now, not Material's dialog. What has to hold: it
/// opens on the month of the day handed to it, it never returns a day outside
/// the range, and paging stops at the ends rather than running off into 2043.
void main() {
  Future<DateTime?> open(
    WidgetTester tester, {
    required DateTime initial,
    DateTime? first,
    DateTime? last,
  }) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await pickDay(
                    context,
                    initial: initial,
                    first: first,
                    last: last,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('opens on the month of the day it was given', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      last: DateTime(2026, 8, 2),
    );

    expect(find.text('March'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    // A full March, and no stray day from the month either side.
    expect(find.text('31'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an inverted range opens on a grid rather than throwing',
      (tester) async {
    // `first` and `last` are the picker's own computed bounds, and a
    // caller that gets them the wrong way round — a history whose newest
    // workout predates the window it is being offered — would otherwise hand
    // `_CalendarCard` a range it cannot page inside. The picker owns the
    // ordering rather than trusting it.
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      first: DateTime(2026, 8, 2),
      last: DateTime(2026, 1, 1),
    );

    expect(tester.takeException(), isNull);
    // Opened on the range's own end rather than on a month outside it.
    expect(find.text('August'), findsOneWidget);
  });

  testWidgets('picking a day pops it back at midnight', (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await pickDay(
                    context,
                    initial: DateTime(2026, 3, 14, 17, 30),
                    last: DateTime(2026, 8, 2),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();

    expect(result, DateTime(2026, 3, 9));
  });

  testWidgets('a day past the last date is shown but dead', (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await pickDay(
                    context,
                    initial: DateTime(2026, 8, 2),
                    last: DateTime(2026, 8, 2),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The 3rd is on screen — the month keeps its shape — and says why it
    // cannot be picked rather than swallowing the tap.
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.text('A day that has not happened cannot be logged.'),
        findsOneWidget);
    expect(result, isNull);
    expect(find.text('August'), findsOneWidget);
  });

  testWidgets('the card is the same height in a 4-week month and a 6-week one',
      (tester) async {
    // February 2026 starts on a Sunday and needs six rows; June 2026 starts on
    // a Monday and needs five. The dialog must not resize between them.
    await open(
      tester,
      initial: DateTime(2026, 2, 15),
      first: DateTime(2026),
      last: DateTime(2026, 8, 2),
    );

    final six = tester.getSize(find.byType(Dialog));
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    expect(find.text('June'), findsOneWidget);
    expect(tester.getSize(find.byType(Dialog)), six);
  });

  testWidgets('a marked day wears a ring in its own colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => pickDay(
                  context,
                  initial: DateTime(2026, 8, 2),
                  first: DateTime(2026, 8),
                  last: DateTime(2026, 8, 2),
                  marks: {
                    20260801: const Color(0xFF689FFA), // trained
                    20260802: const Color(0xFFFF8660), // deload
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Border? ringOn(String day) {
      final box = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text(day),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration as BoxDecoration?)?.border as Border?;
    }

    expect(ringOn('1')?.top.color, const Color(0xFF689FFA));
    // The 2nd is also the selected day: the ring survives the fill, because
    // the ring is the only thing saying it was a deload.
    expect(ringOn('2')?.top.color, const Color(0xFFFF8660));
    // A day inside the range with nothing logged wears the empty ring, so
    // logged and unlogged are read against each other rather than one of them
    // being read against nothing.
    expect(ringOn('5'), isNull, reason: 'the 5th is past the range');
  });

  testWidgets('a day inside the range wears the empty ring', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => pickDay(
                  context,
                  initial: DateTime(2026, 8, 20),
                  first: DateTime(2026, 8),
                  last: DateTime(2026, 8, 31),
                  marks: {20260801: const Color(0xFF689FFA)},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Border? ringOn(String day) {
      final box = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text(day),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration as BoxDecoration?)?.border as Border?;
    }

    expect(ringOn('1')?.top.color, const Color(0xFF689FFA), reason: 'logged');
    expect(ringOn('5')?.top.color, DeltoidColors.dark.heatEmpty,
        reason: 'unlogged, and inside the range');
  });

  testWidgets('the year pill opens a year grid, newest first', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      first: DateTime(2024),
      last: DateTime(2026, 8, 2),
    );

    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();

    expect(find.text('2024'), findsWidgets);

    await tester.tap(find.text('2024').last);
    await tester.pumpAndSettle();
    expect(find.text('March'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget, reason: 'the pill, not the grid');
  });

  testWidgets('the month pill opens the twelve months', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      first: DateTime(2026),
      last: DateTime(2026, 8, 2),
    );

    await tester.tap(find.text('March'));
    await tester.pumpAndSettle();

    expect(find.text('Jan'), findsOneWidget);
    expect(find.text('Dec'), findsOneWidget);

    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();
    expect(find.text('June'), findsOneWidget, reason: 'back on the days');
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('a month past the range cannot be picked', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      first: DateTime(2026),
      last: DateTime(2026, 8, 2),
    );

    await tester.tap(find.text('March'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dec'));
    await tester.pumpAndSettle();

    // Still on the month list, still on March: a month with nothing in range
    // refuses the tap rather than paging somewhere the days are all dead.
    expect(find.text('March'), findsOneWidget);
    expect(find.text('Jan'), findsOneWidget);
  });

  testWidgets('today carries a dot, logged or not', (tester) async {
    final today = DateTime.now();
    await open(tester, initial: today);

    // The dot is drawn in the foreground colour inside today's circle, and in
    // nothing at all inside every other day's.
    Iterable<Color?> dotsIn(String day) {
      final cell = find.ancestor(
        of: find.text(day),
        matching: find.byType(AnimatedContainer),
      );
      return tester
          .widgetList<DecoratedBox>(
            find.descendant(of: cell, matching: find.byType(DecoratedBox)),
          )
          .map((b) => (b.decoration as BoxDecoration).color);
    }

    expect(dotsIn('${today.day}'), isNot(contains(Colors.transparent)));
    final other = today.day == 1 ? 2 : 1;
    expect(dotsIn('$other'), contains(Colors.transparent));
  });

  testWidgets('the grid holds together at twice the type size', (tester) async {
    // Every day is a circle of a fixed size holding a number, a dot and a ring,
    // and the weekday strip under them is text that scales. Both were reserved
    // as flat figures once, and a phone set to 2.0 overflowed the column.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    pickDay(context, initial: DateTime(2026, 8, 2)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the card is the same height on all three panes', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      first: DateTime(2015),
      last: DateTime(2026, 8, 2),
    );

    final days = tester.getSize(find.byType(Dialog));
    await tester.tap(find.text('March'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Dialog)), days, reason: 'months');
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Dialog)), days, reason: 'years');
  });

  testWidgets('an inverted range opens both lists without throwing',
      (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      first: DateTime(2027, 5),
      last: DateTime(2026),
    );

    // The card opens on the range's own end, so the pills read May 2027.
    expect(find.text('May'), findsOneWidget);
    await tester.tap(find.text('2027'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('May').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('May').last);
    await tester.pumpAndSettle();

    // Every day in it refuses, rather than returning a day out of range.
    await tester.tap(find.text('14'));
    await tester.pump();
    expect(find.textContaining('log'), findsOneWidget);
  });

  testWidgets('a year picked from outside the range lands inside it',
      (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 1, 5),
      first: DateTime(2024, 3),
      last: DateTime(2026, 8, 2),
    );

    expect(find.text('January'), findsOneWidget);
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2024').last);
    await tester.pumpAndSettle();

    // January 2024 is before the range, so the card must not land on a month
    // with nothing live in it.
    expect(find.text('March'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
  });

  testWidgets('a day before the range says so in its own words',
      (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 8, 10),
      first: DateTime(2026, 8, 5),
      last: DateTime(2026, 8, 20),
    );

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('There is nothing in the log this far back.'),
        findsOneWidget);
  });

  testWidgets('the refusal goes when the month it named is paged away',
      (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 8, 10),
      first: DateTime(2026),
      last: DateTime(2026, 8, 20),
    );

    await tester.tap(find.text('25'));
    await tester.pump();
    expect(find.textContaining('cannot be logged'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be logged'), findsNothing);
  });

  testWidgets('the refusal outlives neither the dialog nor its timer',
      (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 8, 2),
      last: DateTime(2026, 8, 2),
    );

    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.textContaining('cannot be logged'), findsOneWidget);

    // Closed while the message is still up, then run past its dwell: the timer
    // must not call setState on a card that has left the tree.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
