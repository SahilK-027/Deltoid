import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/rest.dart';
import 'package:deltoid/domain/units.dart';
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

  /// What the database says the unit is, which is the only thing a confirmed
  /// switch is allowed to have changed.
  Future<WeightUnit> savedUnit() async {
    final rows = await (db.select(db.appSettings)
      ..where((t) => t.key.equals(unitsKey))).get();
    return WeightUnitX.parse(rows.isEmpty ? null : rows.first.value);
  }

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

      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('Default rest'), findsOneWidget);
      expect(find.text('Between exercises'), findsOneWidget);
      expect(find.text('Rest sound'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.text('Units'), findsOneWidget);
      expect(find.text('Kilograms'), findsOneWidget);
      expect(find.text('Pounds'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('rest ships at two minutes, and the steps are quarter-minutes',
        (tester) async {
      await pump(tester, const SettingsScreen());
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      // Both numbers, before anything has been stored: the shipped default.
      expect(find.text('2:00'), findsNWidgets(2));

      // The + belonging to `Default rest` — the first stepper in the section.
      final plus = find.descendant(
        of: find.ancestor(
          of: find.text('Default rest'),
          matching: find.byType(Row),
        ),
        matching: find.byIcon(Icons.add_rounded),
      );
      await tester.tap(plus.first);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('2:15'), findsOneWidget);
      final rows = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(restDefaultKey)))
          .get();
      expect(rows.single.value, '135');
    });

    testWidgets('the tone can be turned off; the buzz is not part of it',
        (tester) async {
      await pump(tester, const SettingsScreen());
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(
        find.text('The tone at 0:00. The phone still buzzes either way.'),
        findsOneWidget,
      );

      // The switch belonging to `Rest sound`, not "whatever switch is last".
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Rest sound'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Switch),
        ).first,
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final rows = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(restSoundKey)))
          .get();
      expect(rows.single.value, 'off');
      final prefs = container.read(restPrefsProvider).valueOrNull;
      expect(
        prefs?.sound,
        isFalse,
        reason: 'the log screen reads this at the moment a rest ends',
      );
      // And the switch is about the tone alone: the two durations are
      // untouched, and the between-exercises one still reads through the
      // provider that is its only reader.
      expect(prefs?.defaultSeconds, 120);
      expect(prefs?.betweenExercises, 120);

      await setRestBetweenExercisesSeconds(db, 210);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final moved = container.read(restPrefsProvider).valueOrNull;
      expect(moved?.betweenExercises, 210);
      expect(moved?.defaultSeconds, 120);
    });

    testWidgets('the unit asks before it restates every number in the app', (
      tester,
    ) async {
      await pump(tester, const SettingsScreen());
      // Two drags: Rest sits between Data and Units.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      await tester.tap(find.text('Pounds'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('Show weights in pounds?'), findsOneWidget);

      await tester.tap(find.text('Go back').last);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // A radio is one tap, and this one is on the way past to a backup.
      expect(await savedUnit(), WeightUnit.kg);

      await tester.tap(find.text('Pounds'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.tap(find.text('Switch to pounds').last);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(await savedUnit(), WeightUnit.lb);
    });
  });

  group('Bodyweight screen', () {
    testWidgets('with no entries: the full-page empty state', (tester) async {
      await pump(tester, const BodyweightScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('No weights logged'), findsOneWidget);
    });

    testWidgets('months are summaries; the newest one is open', (
      tester,
    ) async {
      final repo = TrainingRepository(db);
      await repo.logBodyweight(DateTime(2026, 7, 28), 75.0);
      await repo.logBodyweight(DateTime(2026, 8, 1), 76.0);
      await pump(tester, const BodyweightScreen());

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('August 2026'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('July 2026'), findsOneWidget);

      // The current month is open, so its days are on screen.
      expect(find.text('Sat 1 Aug'), findsOneWidget);
      // Every older month is one row until it is asked for — this is the whole
      // point of the screen: a year is twelve rows, not 365.
      expect(find.text('Tue 28 Jul'), findsNothing);

      // The chart leads the screen, so the older months are below the fold.
      await tester.scrollUntilVisible(find.text('July 2026'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('July 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Tue 28 Jul'), findsOneWidget);
    });

    testWidgets('a month row states what it averaged and which way it went', (
      tester,
    ) async {
      final repo = TrainingRepository(db);
      // Chosen so the month's own figure is one no entry row can produce:
      // July averages 75, August averages 78, and the change between the two
      // averages (+3) is neither of August's entry-to-entry steps (+2 and +1).
      // With numbers that collide, this passed on the entry row alone and
      // proved nothing about the month.
      await repo.logBodyweight(DateTime(2026, 7, 14), 74.0);
      await repo.logBodyweight(DateTime(2026, 7, 20), 75.0);
      await repo.logBodyweight(DateTime(2026, 7, 28), 76.0);
      await repo.logBodyweight(DateTime(2026, 8, 1), 77.0);
      await repo.logBodyweight(DateTime(2026, 8, 3), 79.0);
      await pump(tester, const BodyweightScreen());

      // `.builder`: a month below the fold is not built until it is scrolled
      // to, which is the point of the change.
      await tester.scrollUntilVisible(find.text('July 2026'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('3 weigh-ins'), findsOneWidget);
      expect(find.text('2 weigh-ins'), findsOneWidget);
      // August averaged 78 against July's 75 — the month row's own figure.
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('a month of one weigh-in claims no trend of its own', (
      tester,
    ) async {
      final repo = TrainingRepository(db);
      // July averages 76.0 while *ending* at 77.0, so the two comparisons
      // available here point opposite ways: August's single weigh-in is 0.5
      // above July's average and 0.5 below the weigh-in before it.
      await repo.logBodyweight(DateTime(2026, 7, 20), 75.0);
      await repo.logBodyweight(DateTime(2026, 7, 28), 77.0);
      await repo.logBodyweight(DateTime(2026, 8, 1), 76.5);
      await pump(tester, const BodyweightScreen());
      await tester.pumpAndSettle();

      // The month row printed `+0.5` directly above its only entry printing
      // `−0.5`, against the identical weight. Both were arithmetically right
      // and the pair was unreadable, so the summary of a month that has no
      // shape yet says nothing at all.
      expect(find.text('1 weigh-in'), findsOneWidget);
      expect(find.text('+0.5'), findsNothing);
      // The entry keeps the comparison it can make honestly.
      expect(find.text('−0.5'), findsOneWidget);
    });

    testWidgets('a row opens the sheet that corrects and deletes it', (
      tester,
    ) async {
      await TrainingRepository(db).logBodyweight(DateTime(2026, 8, 1), 76.0);
      await pump(tester, const BodyweightScreen());

      await tester.scrollUntilVisible(find.text('Sat 1 Aug'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
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

  /// The log is summarised in SQLite and read a month at a time, so what used
  /// to be a grouping function is now four queries. Fifty years of daily
  /// weighing is 18 250 rows: holding them all to show eight month rows was
  /// what made this screen slow to open.
  group('the log is summarised, not loaded', () {
    Future<void> log(int dayKey, double kg) => TrainingRepository(db)
        .logBodyweight(dateFromDayKey(dayKey), kg);

    test('an empty log has no months', () async {
      expect(await container.read(bodyweightMonthsProvider.future), isEmpty);
      final summary = await container.read(bodyweightSummaryProvider.future);
      expect(summary.latest, isNull);
      expect(summary.count, 0);
    });

    test('a month is its count and its average, newest first', () async {
      await log(20260803, 76.4);
      await log(20260801, 76.6);
      await log(20260728, 77.0);

      final months = await container.read(bodyweightMonthsProvider.future);

      expect(months.map((m) => m.label), ['August 2026', 'July 2026']);
      expect(months.first.ym, 202608);
      expect(months.first.count, 2);
      expect(months.first.averageKg, closeTo(76.5, 1e-9));
      expect(months.last.count, 1);
    });

    test('the same month a year apart is two months, not one', () async {
      await log(20260801, 76);
      await log(20250801, 78);

      final months = await container.read(bodyweightMonthsProvider.future);
      expect(months.map((m) => m.label), ['August 2026', 'August 2025']);
    });

    test('a month loads only its own days, and the one before them', () async {
      await log(20260803, 76.4);
      await log(20260801, 76.6);
      await log(20260728, 77.0);

      final august = await container.read(bodyweightMonthProvider(202608).future);

      expect(august.entries.map((e) => e.dayKey), [20260803, 20260801]);
      // The seam: August's oldest row still has something to read against.
      expect(august.before?.dayKey, 20260728);

      final july = await container.read(bodyweightMonthProvider(202607).future);
      expect(july.entries.single.dayKey, 20260728);
      expect(july.before, isNull);
    });

    test('the chart reads the whole log, and cuts the window itself', () async {
      final today = DateTime.now();
      await TrainingRepository(db)
          .logBodyweight(today.subtract(const Duration(days: 2)), 76);
      await TrainingRepository(db)
          .logBodyweight(today.subtract(const Duration(days: 200)), 80);

      final all = await container.read(bodyweightRangeProvider.future);

      // Oldest first, and nothing dropped: the range chips are a zoom over
      // one provider, not a query per range.
      expect(all.map((p) => p.weightKg).toList(), [80, 76]);

      const month = TrendWindow.rolling(ChartRange.month);
      final window = [for (final p in all) if (month.contains(p.dayKey)) p];
      expect(window.single.weightKg, 76);
    });

    test('the summary is the newest weight and how many there are', () async {
      await log(20260801, 76.6);
      await log(20260803, 76.4);

      final summary = await container.read(bodyweightSummaryProvider.future);
      expect(summary.latest?.dayKey, 20260803);
      expect(summary.count, 2);
    });
  });
}
