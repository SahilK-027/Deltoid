import 'package:deltoid/core/theme/theme.dart';
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

    expect(find.text('March 2026'), findsOneWidget);
    // A full March, and no stray day from the month either side.
    expect(find.text('31'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
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

    // The 3rd is on screen — the month keeps its shape — and does nothing.
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('August 2026'), findsOneWidget);
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

    expect(find.text('June 2026'), findsOneWidget);
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
                    20260802: const Color(0xFFFF8B66), // deload
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
    expect(ringOn('2')?.top.color, const Color(0xFFFF8B66));
    // A day with nothing logged and no reason to be marked has no ring.
    expect(ringOn('5'), isNull);
  });

  testWidgets('the month name opens a year grid, newest first', (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 14),
      first: DateTime(2024),
      last: DateTime(2026, 8, 2),
    );

    await tester.tap(find.text('March 2026'));
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsWidgets);
    expect(find.text('2024'), findsOneWidget);

    await tester.tap(find.text('2024').last);
    await tester.pumpAndSettle();
    expect(find.text('March 2024'), findsOneWidget);
  });
}
