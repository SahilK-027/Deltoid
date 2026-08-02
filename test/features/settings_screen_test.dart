import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/features/settings/bodyweight_screen.dart';
import 'package:deltoid/features/settings/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings and the bodyweight log, pumped against a real database.
///
/// Bodyweight had never once been logged through the UI, so nothing here had
/// ever been exercised outside the repository — the screens could have been
/// rendering anything.
///
/// Harness rules are `regime_screen_test.dart`'s: never `pumpAndSettle` (a
/// watched query that has not answered yet renders a spinner, which never
/// settles), and the container outlives the tree so drift's stream-closing
/// timer lands outside the harness's pending-timer check.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: screen,
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('Settings', () {
    testWidgets('with nothing logged: the masthead, and an invitation', (
      tester,
    ) async {
      await pump(tester, const SettingsScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Not logged'), findsOneWidget);
      // Nothing to look back at yet, so no link to the past.
      expect(find.text('History'), findsNothing);
    });

    testWidgets('a weight logged today reads as today, and offers the edit', (
      tester,
    ) async {
      await TrainingRepository(db).logBodyweight(DateTime.now(), 76.5);
      await pump(tester, const SettingsScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('76.5 kg'), findsOneWidget);
      expect(find.text('Logged today  ·  1 entries'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('the figure is one tap from the sheet that logs it', (
      tester,
    ) async {
      await pump(tester, const SettingsScreen());

      await tester.tap(find.text('Not logged'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.takeException(), isNull);
      expect(find.text('Log bodyweight'), findsOneWidget);
    });

    testWidgets('every section renders, top to bottom', (tester) async {
      await pump(tester, const SettingsScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('Bodyweight'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Export backup'), findsOneWidget);

      // A `ListView` builds what is on screen, so the tail of the page has to
      // be scrolled to before it exists at all.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.text('Units'), findsOneWidget);
      expect(find.text('Kilograms'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });
  });

  group('Bodyweight screen', () {
    testWidgets('with no entries: the full-page empty state', (tester) async {
      await pump(tester, const BodyweightScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('No weights logged'), findsOneWidget);
    });

    testWidgets('entries sit under their month, newest first, with deltas', (
      tester,
    ) async {
      final repo = TrainingRepository(db);
      await repo.logBodyweight(DateTime(2026, 7, 28), 75.0);
      await repo.logBodyweight(DateTime(2026, 8, 1), 76.0);
      await pump(tester, const BodyweightScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('July 2026'), findsOneWidget);
      expect(find.text('Sat 1 Aug'), findsOneWidget);
      // Against the entry before it in time, across the month boundary.
      expect(find.text('+1'), findsOneWidget);
      // The oldest entry has nothing to compare against.
      expect(find.textContaining('−'), findsNothing);
    });

    testWidgets('a row opens the sheet that corrects and deletes it', (
      tester,
    ) async {
      await TrainingRepository(db).logBodyweight(DateTime(2026, 8, 1), 76.0);
      await pump(tester, const BodyweightScreen());

      await tester.tap(find.text('Sat 1 Aug'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.takeException(), isNull);
      expect(find.text('Edit bodyweight'), findsOneWidget);
      // Delete lives in the sheet, not on eighty rows.
      expect(find.text('Delete this weight'), findsOneWidget);
    });
  });

  group('groupByMonth', () {
    BodyweightLog entry(int dayKey) => BodyweightLog(
          id: '$dayKey',
          updatedAt: 0,
          deviceId: 'test',
          dirty: false,
          dayKey: dayKey,
          weightKg: 76,
        );

    test('an empty log has no months', () {
      expect(groupByMonth(const []), isEmpty);
    });

    test('a month keeps its entries in the order it was given them', () {
      final months = groupByMonth([
        entry(20260803),
        entry(20260801),
        entry(20260728),
      ]);

      expect(months.map((m) => m.label), ['August 2026', 'July 2026']);
      expect(months.first.entries.map((e) => e.dayKey), [20260803, 20260801]);
      expect(months.last.entries.single.dayKey, 20260728);
    });

    test('the same month a year apart is two months, not one', () {
      final months = groupByMonth([entry(20260801), entry(20250801)]);

      expect(months.map((m) => m.label), ['August 2026', 'August 2025']);
    });
  });
}
