import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The day picker is ours now, not Material's dialog. What has to hold: it
/// opens on the month of the day handed to it, it never returns a day outside
/// the range, and paging stops at the ends rather than running off into 2043.
/// The cell for one exact date. Day numbers are no longer unique on screen —
/// the months either side of the one on show are drawn too — so a test names
/// the day it means rather than the number it wears.
Finder cell(int year, int month, int day) =>
    find.byKey(ValueKey(dayKeyOf(DateTime(year, month, day))));

DateTime _midnightOf(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  Future<DateTime?> open(
    WidgetTester tester, {
    required DateTime initial,
    DateTime? first,
    DateTime? last,
    Map<int, Color> marks = const {},
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
                    marks: marks,
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
    // A full March, with the months either side drawn in around it.
    expect(cell(2026, 3, 1), findsOneWidget);
    expect(cell(2026, 3, 31), findsOneWidget);
    expect(cell(2026, 2, 28), findsOneWidget, reason: "February's tail");
  });

  testWidgets('an inverted range opens on a grid rather than throwing', (
    tester,
  ) async {
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

    await tester.tap(cell(2026, 3, 9));
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
    expect(cell(2026, 8, 3), findsOneWidget);
    await tester.tap(cell(2026, 8, 3));
    await tester.pump();
    expect(
      find.text('A day that has not happened cannot be logged.'),
      findsOneWidget,
    );
    expect(result, isNull);
    expect(find.text('August'), findsOneWidget);
  });

  testWidgets('the card is the same height in a 4-week month and a 6-week one', (
    tester,
  ) async {
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

    Border? ringOn(Finder day) {
      final box = tester.widget<Container>(
        find.descendant(of: day, matching: find.byType(Container)).first,
      );
      return (box.decoration as BoxDecoration?)?.border as Border?;
    }

    expect(ringOn(cell(2026, 8, 1))?.top.color, const Color(0xFF689FFA));
    // The 2nd is also the selected day: the ring survives the fill, because
    // the ring is the only thing saying it was a deload.
    expect(ringOn(cell(2026, 8, 2))?.top.color, const Color(0xFFFF8660));
    // A day inside the range with nothing logged wears the empty ring, so
    // logged and unlogged are read against each other rather than one of them
    // being read against nothing.
    expect(
      ringOn(cell(2026, 8, 5)),
      isNull,
      reason: 'the 5th is past the range',
    );
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

    Border? ringOn(Finder day) {
      final box = tester.widget<Container>(
        find.descendant(of: day, matching: find.byType(Container)).first,
      );
      return (box.decoration as BoxDecoration?)?.border as Border?;
    }

    expect(
      ringOn(cell(2026, 8, 1))?.top.color,
      const Color(0xFF689FFA),
      reason: 'logged',
    );
    expect(
      ringOn(cell(2026, 8, 5))?.top.color,
      DeltoidColors.dark.heatEmpty,
      reason: 'unlogged, and inside the range',
    );
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
    Iterable<Color?> dotsIn(Finder day) => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: day, matching: find.byType(DecoratedBox)),
        )
        .map((b) => (b.decoration as BoxDecoration).color);

    expect(
      dotsIn(cell(today.year, today.month, today.day)),
      isNot(contains(Colors.transparent)),
    );
    final other = daysBefore(_midnightOf(today), 1);
    expect(
      dotsIn(cell(other.year, other.month, other.day)),
      contains(Colors.transparent),
    );
  });

  testWidgets('the grid holds together at twice the type size', (tester) async {
    // Every day is a circle of a fixed size holding a number, a dot and a ring,
    // and the weekday strip under them is text that scales. Both were reserved
    // as flat figures once, and a phone set to 2.0 overflowed the column.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
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

    // The card opens on the range's own end, so the pills read May 2027. The
    // bar sits above the grid, so its own pill is the first match in the tree
    // and anything a list draws comes after it.
    expect(find.text('May'), findsOneWidget);

    await tester.tap(find.text('2027'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('2027'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.text('May').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('May').first);
    await tester.pumpAndSettle();

    // Back on the days, and every one of them refuses rather than returning a
    // day from outside the range.
    await tester.tap(cell(2027, 5, 14));
    await tester.pump();
    expect(find.textContaining('log'), findsOneWidget);
  });

  testWidgets('a year picked from outside the range lands inside it', (
    tester,
  ) async {
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

  testWidgets('a day before the range says so in its own words', (
    tester,
  ) async {
    await open(
      tester,
      initial: DateTime(2026, 8, 10),
      first: DateTime(2026, 8, 5),
      last: DateTime(2026, 8, 20),
    );

    await tester.tap(cell(2026, 8, 1));
    await tester.pump();
    expect(
      find.text('There is nothing in the log this far back.'),
      findsOneWidget,
    );
  });

  testWidgets('the refusal goes when the month it named is paged away', (
    tester,
  ) async {
    await open(
      tester,
      initial: DateTime(2026, 8, 10),
      first: DateTime(2026),
      last: DateTime(2026, 8, 20),
    );

    await tester.tap(cell(2026, 8, 25));
    await tester.pump();
    expect(find.textContaining('cannot be logged'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be logged'), findsNothing);
  });

  testWidgets('the refusal outlives neither the dialog nor its timer', (
    tester,
  ) async {
    await open(
      tester,
      initial: DateTime(2026, 8, 2),
      last: DateTime(2026, 8, 2),
    );

    await tester.tap(cell(2026, 8, 3));
    await tester.pump();
    expect(find.textContaining('cannot be logged'), findsOneWidget);

    // Closed while the message is still up, then run past its dwell: the timer
    // must not call setState on a card that has left the tree.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the month keeps its whole name on a 384dp phone', (
    tester,
  ) async {
    // A OnePlus Nord is 1080px at 450dpi, which is 384dp — nine narrower than
    // the emulator this bar was drawn on, and enough to cut `September` to
    // `Septem…` there while it fit here. The bar is measured at the real width.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 450 / 160;
    addTearDown(tester.view.reset);

    await open(
      tester,
      initial: DateTime(2026, 9, 8),
      first: DateTime(2026),
      last: DateTime(2026, 9, 8),
    );

    expect(find.text('September'), findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('September'),
        matching: find.byType(RichText),
      ),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'the month is scaled to fit, never cut',
    );
  });

  testWidgets('with no floor named it reaches back to 2015', (tester) async {
    // The session picker used to pass the first day ever logged as its floor,
    // which made the log its own boundary: a session done before the app was
    // installed could not be backfilled. A picker with marks only in 2026 must
    // still open 2015.
    await open(
      tester,
      initial: DateTime(2026, 9, 8),
      last: DateTime(2026, 9, 8),
      marks: {20260901: const Color(0xFF689FFA)},
    );

    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(find.text('2015'), findsOneWidget);
  });

  testWidgets('a mark before 2015 pushes the floor back to it', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 9, 8),
      last: DateTime(2026, 9, 8),
      marks: {20090714: const Color(0xFF689FFA)},
    );

    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(
      find.text('2009'),
      findsOneWidget,
      reason: 'a history older than the default floor is still reachable',
    );
  });

  testWidgets('a future day wears no ring the frame after paging onto it', (
    tester,
  ) async {
    // August is wholly in range, so all of it is ringed; September's days after
    // the 8th are in the future and ringless. Paging between them reuses the
    // same cells, and an animated ring tweened the old grey away rather than
    // never being there — a ring flickering on days that have not happened.
    await open(
      tester,
      initial: DateTime(2026, 8, 20),
      first: DateTime(2026),
      last: DateTime(2026, 9, 8),
    );

    Border? ringOn(Finder day) {
      final box = tester.widget<Container>(
        find.descendant(of: day, matching: find.byType(Container)).first,
      );
      return (box.decoration as BoxDecoration?)?.border as Border?;
    }

    expect(
      ringOn(cell(2026, 8, 20)),
      isNotNull,
      reason: 'August 20 is in range',
    );

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();

    expect(
      ringOn(cell(2026, 9, 20)),
      isNull,
      reason: 'no ring is left over from the month paged away from',
    );
  });

  testWidgets('every month is six full rows, neighbours included', (
    tester,
  ) async {
    // June 2026 starts on a Monday and its own days fill five rows exactly.
    // The ragged sixth was the whole reason one month looked unlike another.
    await open(
      tester,
      initial: DateTime(2026, 6, 15),
      first: DateTime(2015),
      last: DateTime(2026, 8, 2),
    );

    // The 1st is a Monday, so June leads the grid and July fills the rest of
    // it: six rows of forty-two days either way.
    expect(cell(2026, 6, 1), findsOneWidget);
    expect(cell(2026, 6, 30), findsOneWidget);
    expect(cell(2026, 7, 12), findsOneWidget, reason: 'July fills the tail');
  });

  testWidgets('a neighbouring month is drawn back, not drawn out', (
    tester,
  ) async {
    // September 2026 opens on a Tuesday, so the 31st of August leads the grid.
    await open(
      tester,
      initial: DateTime(2026, 9, 15),
      first: DateTime(2015),
      last: DateTime(2026, 9, 30),
    );

    double opacityOf(Finder day) => tester
        .widget<Opacity>(
          find.descendant(of: day, matching: find.byType(Opacity)).first,
        )
        .opacity;

    expect(opacityOf(cell(2026, 9, 15)), 1, reason: 'the month on show');
    expect(
      opacityOf(cell(2026, 8, 31)),
      lessThan(0.5),
      reason: 'August, seen past the edge of September',
    );
  });

  testWidgets('the month is turned by dragging the grid', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 6, 15),
      first: DateTime(2015),
      last: DateTime(2026, 8, 2),
    );

    expect(find.text('June'), findsOneWidget);

    // A flick leftwards is the next month, the way a month turns everywhere.
    await tester.fling(cell(2026, 6, 15), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('July'), findsOneWidget);

    await tester.fling(cell(2026, 7, 15), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('June'), findsOneWidget);
  });

  testWidgets('a drag stops at the end of the range', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 8, 2),
      first: DateTime(2026, 8),
      last: DateTime(2026, 8, 2),
    );

    await tester.fling(cell(2026, 8, 2), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(
      find.text('August'),
      findsOneWidget,
      reason: 'there is no month after the range to turn to',
    );
  });
}
