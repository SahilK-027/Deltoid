import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/features/home/home_providers.dart';
import 'package:deltoid/features/home/weigh_ins_screen.dart';
import 'package:deltoid/features/home/widgets/heatmap.dart';
import 'package:deltoid/features/home/widgets/year_heatmap.dart';
import 'package:deltoid/features/more/more_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Weigh-ins screen, behind the habit tile on Home: the trend, the count,
/// a year map per year, the correction calendar and `Log weight`.
///
/// Harness rules are `more_screen_test.dart`'s: never `pumpAndSettle` while a
/// watched query may still be answering, and the container outlives the tree
/// so drift's stream-closing timer lands outside the pending-timer check.
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

  Future<void> settle(WidgetTester tester, [int frames = 40]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
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
    await settle(tester, 60);
  }

  Future<void> log(DateTime day, double kg) =>
      TrainingRepository(db).logBodyweight(day, kg);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('with no entries: the empty state and its one button', (
    tester,
  ) async {
    await pump(tester, const WeighInsScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('Weigh-ins'), findsOneWidget);
    expect(find.text('No weights logged'), findsOneWidget);
    // The empty state's button is the floating one's action, so the floating
    // one is hidden rather than offered twice.
    expect(find.text('Log weight'), findsOneWidget);
  });

  testWidgets('the trend, the count and its legend, then a map per year', (
    tester,
  ) async {
    await log(DateTime(now.year - 1, 3, 4), 80);
    await log(DateTime(now.year - 1, 3, 9), 79.5);
    await log(today, 78);
    await pump(tester, const WeighInsScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('Trend'), findsOneWidget);
    expect(
      find.text('3 weigh-ins since March ${now.year - 1}'),
      findsOneWidget,
    );
    expect(find.byType(HeatmapLegend), findsOneWidget);
    expect(find.text('No weigh-in'), findsOneWidget);
    expect(find.text('Weighed'), findsOneWidget);

    Finder heading(int year) => find.widgetWithText(SectionHeader, '$year');
    await tester.scrollUntilVisible(
      heading(now.year - 1),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(find.text('2 weigh-ins'), findsOneWidget);
    expect(heading(now.year), findsOneWidget);
    expect(find.text('1 weigh-in'), findsOneWidget);

    // Every map draws weigh-in days, not training days.
    for (final map in tester.widgetList<YearHeatmap>(find.byType(YearHeatmap))) {
      expect(map.days, isA<WeighInYearDays>());
    }
    // And no list of entries by month: the calendar corrects instead.
    expect(find.textContaining('By month'), findsNothing);
  });

  testWidgets('a weight logged here lands on the map', (tester) async {
    await log(DateTime(now.year - 1, 6, 1), 80);
    await pump(tester, const WeighInsScreen());
    expect(find.text('1 weigh-in since June ${now.year - 1}'), findsOneWidget);

    await tester.tap(find.text('Log weight'));
    await settle(tester);
    expect(find.text('Log bodyweight'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '77.4');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('2 weigh-ins since June ${now.year - 1}'), findsOneWidget);
    expect(container.read(weighInDaysProvider).value, contains(dayKeyOf(today)));
  });

  testWidgets('Log weight over a weight already logged today corrects it', (
    tester,
  ) async {
    await log(today, 76.5);
    await pump(tester, const WeighInsScreen());

    await tester.tap(find.text('Log weight'));
    await settle(tester);

    // A blank field here would replace today's weight without showing it.
    expect(find.text('Edit bodyweight'), findsOneWidget);
    expect(find.text('Delete this weight'), findsOneWidget);
  });

  group('the correction calendar', () {
    Future<void> openCalendar(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Correct a weigh-in'));
      await settle(tester);
    }

    Finder cell(DateTime day) => find.byKey(ValueKey(dayKeyOf(day)));

    testWidgets('opens a weighed day as its entry, with delete', (
      tester,
    ) async {
      await log(today, 76.5);
      await pump(tester, const WeighInsScreen());

      await openCalendar(tester);
      expect(find.text('Correct a weigh-in'), findsWidgets);
      await tester.tap(cell(today));
      await settle(tester);

      expect(find.text('Edit bodyweight'), findsOneWidget);
      expect(find.text('Delete this weight'), findsOneWidget);
      expect(find.widgetWithText(TextField, '76.5'), findsOneWidget);
    });

    testWidgets('opens a day without one as a new entry on that day', (
      tester,
    ) async {
      // Yesterday has to be in the month the calendar opens on.
      if (today.day == 1) return;
      final yesterday = today.subtract(const Duration(days: 1));
      await log(today, 76.5);
      await pump(tester, const WeighInsScreen());

      await openCalendar(tester);
      await tester.tap(cell(yesterday));
      await settle(tester);

      // Nothing to delete on a day with no weigh-in.
      expect(find.text('Log bodyweight'), findsOneWidget);
      expect(find.text('Delete this weight'), findsNothing);

      await tester.enterText(find.byType(TextField), '77');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);

      final series = await TrainingRepository(db).bodyweightSeries();
      expect(series.map((p) => p.dayKey), contains(dayKeyOf(yesterday)));
    });
  });

  testWidgets('the chart range survives leaving the screen', (tester) async {
    // The range lived in the route's `State`, so picking 1M and coming back
    // later drew 3M again: the widget had been rebuilt from its initialiser
    // and nothing remembered the answer.
    await log(today, 76.5);
    await pump(tester, const WeighInsScreen());

    expect(
      container.read(bodyweightWindowProvider).range,
      ChartRange.threeMonths,
    );

    container.read(bodyweightWindowProvider.notifier).state =
        const TrendWindow.rolling(ChartRange.month);

    // Leave, and come back to a screen built from scratch.
    await pump(tester, const MoreScreen());
    await pump(tester, const WeighInsScreen());

    expect(container.read(bodyweightWindowProvider).range, ChartRange.month);
  });

  group('the queries behind it', () {
    Future<void> logKey(int dayKey, double kg) =>
        log(dateFromDayKey(dayKey), kg);

    test('the weigh-in days are one per day, deletions left out', () async {
      await logKey(20260801, 76.6);
      // A second weigh-in on the same day replaces the first.
      await logKey(20260801, 76.2);
      await logKey(20260803, 76.4);
      await logKey(20260805, 76.0);
      await TrainingRepository(db).deleteBodyweight(20260805);

      final days = await container.read(weighInDaysProvider.future);
      expect(days, {20260801, 20260803});
    });

    test('the chart reads the whole log, and cuts the window itself', () async {
      await log(today.subtract(const Duration(days: 2)), 76);
      await log(today.subtract(const Duration(days: 200)), 80);

      final all = await container.read(bodyweightRangeProvider.future);

      // Oldest first, and nothing dropped: the range chips are a zoom over
      // one provider, not a query per range.
      expect(all.map((p) => p.weightKg).toList(), [80, 76]);

      const month = TrendWindow.rolling(ChartRange.month);
      final window = [for (final p in all) if (month.contains(p.dayKey)) p];
      expect(window.single.weightKg, 76);
    });

    test('an empty log has no summary and no days', () async {
      final summary = await container.read(bodyweightSummaryProvider.future);
      expect(summary.latest, isNull);
      expect(summary.count, 0);
      expect(await container.read(weighInDaysProvider.future), isEmpty);
    });

    test('the summary is the newest weight and how many there are', () async {
      await logKey(20260801, 76.6);
      await logKey(20260803, 76.4);

      final summary = await container.read(bodyweightSummaryProvider.future);
      expect(summary.latest?.dayKey, 20260803);
      expect(summary.count, 2);
    });
  });
}
