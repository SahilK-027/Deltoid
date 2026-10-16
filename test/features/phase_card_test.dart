import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/phase_sparkline.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/phase_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/features/home/home_screen.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// The Phase card on Home and the sheet behind it (THEME → Phase card,
/// Phase sheet): the card's three states, and the sheet setting, changing,
/// correcting and clearing a phase.
void main() {
  late AppDatabase db;
  late PhaseRepository phases;
  late TrainingRepository training;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayKey = dayKeyOf(today);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ensureStarterCatalog(db);
    phases = PhaseRepository(db);
    training = TrainingRepository(db);
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const HomeScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<List<Phase>> live() => (db.select(db.phases)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
      .get();

  /// Unmounts the screen before the test ends, so drift's stream-closing
  /// timers run out before the harness checks for pending timers, as the
  /// habit tests on Home do.
  void phaseTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  String since(DateTime day) => 'Since ${DateFormat('d MMM y').format(day)}';

  group('the card', () {
    phaseTest('with no phase, says what one is for and offers to set it',
        (tester) async {
      await pumpHome(tester);

      expect(find.text('Phase'), findsOneWidget);
      expect(
        find.text('Set a bulk, a cut or maintenance, and Cycle progress shows '
            'which one each cycle ran in.'),
        findsOneWidget,
      );
      expect(find.text('Set a phase'), findsOneWidget);
      // The button says it, so the heading drops its link.
      expect(find.text('Change'), findsNothing);
      expect(find.byType(PhaseSparkline), findsNothing);
    });

    phaseTest('an open-ended phase counts its weeks and no further',
        (tester) async {
      final start = daysBefore(today, 20);
      await phases.startPhase(PhaseKind.maintenance, from: start);
      await pumpHome(tester);

      expect(find.text('Maintenance'), findsWidgets);
      expect(find.text(since(start)), findsOneWidget);
      expect(find.text('Week 3'), findsOneWidget);
      expect(find.textContaining('Week 3 of'), findsNothing);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Set a phase'), findsNothing);
      // No weigh-ins: every figure is a dash rather than a guess.
      expect(find.text('——'), findsNWidgets(3));
    });

    phaseTest('a cut after a bulk: its length, its figures and both tints',
        (tester) async {
      final bulk = daysBefore(today, 40);
      final cut = daysBefore(today, 14);
      await phases.startPhase(PhaseKind.bulk, from: bulk);
      await phases.startPhase(PhaseKind.cut, from: cut, plannedWeeks: 12);
      await training.logBodyweight(daysBefore(today, 30), 80);
      await training.logBodyweight(cut, 82);
      await training.logBodyweight(today, 80.6);
      await pumpHome(tester);

      expect(find.text('Cut'), findsWidgets);
      expect(find.text(since(cut)), findsOneWidget);
      expect(find.text('Week 3 of 12'), findsOneWidget);
      expect(find.byType(PhaseSparkline), findsOneWidget);

      // The legend names the phases the sparkline shows, in order.
      final legend = tester.widget<PhaseLegend>(find.byType(PhaseLegend));
      expect(legend.kinds, [PhaseKind.bulk, PhaseKind.cut]);

      expect(find.text('Bodyweight'), findsOneWidget);
      expect(find.text('80.6'), findsOneWidget);
      expect(find.text('Since start'), findsOneWidget);
      expect(find.text('−1.4'), findsOneWidget);
      expect(find.text('Each week'), findsOneWidget);
      expect(find.text('−0.7'), findsOneWidget);
    });
  });

  group('the sheet', () {
    Future<void> openSheet(WidgetTester tester, String via) async {
      await tester.ensureVisible(find.text(via));
      await tester.tap(find.text(via));
      await settle(tester);
    }

    phaseTest('sets a phase, with Save off until one is chosen',
        (tester) async {
      await pumpHome(tester);
      await openSheet(tester, 'Set a phase');

      expect(find.text('Clear phase'), findsNothing);
      expect(find.text('12 weeks'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect((await tester.runAsync(live))!, isEmpty, reason: 'nothing was chosen');

      await tester.tap(find.text('Cut'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      final rows = (await tester.runAsync(live))!;
      expect(rows.single.kind, PhaseKind.cut);
      expect(rows.single.dayKey, todayKey);
      expect(rows.single.plannedWeeks, 12);
      expect(find.text('Week 1 of 12'), findsOneWidget);
    });

    phaseTest('the start day comes from the day picker', (tester) async {
      await pumpHome(tester);
      await openSheet(tester, 'Set a phase');

      await tester.tap(find.text('Started'));
      await settle(tester);
      expect(find.text('When did it start?'), findsOneWidget);
    });

    phaseTest('a different phase starts a new one and keeps the last',
        (tester) async {
      final bulkStart = daysBefore(today, 30);
      final bulkId = await phases.startPhase(
        PhaseKind.bulk,
        from: bulkStart,
        plannedWeeks: 16,
      );
      await pumpHome(tester);
      await openSheet(tester, 'Change');

      await tester.tap(find.text('Cut'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      final rows = (await tester.runAsync(live))!;
      expect(rows, hasLength(2));
      expect(rows.first.id, bulkId);
      expect(rows.first.dayKey, dayKeyOf(bulkStart));
      expect(rows.last.kind, PhaseKind.cut);
      expect(rows.last.dayKey, todayKey);
      expect(find.text(since(today)), findsOneWidget);
    });

    phaseTest('the same phase is corrected rather than started again',
        (tester) async {
      final start = daysBefore(today, 30);
      final id = await phases.startPhase(
        PhaseKind.bulk,
        from: start,
        plannedWeeks: 12,
      );
      await pumpHome(tester);
      await openSheet(tester, 'Change');

      await tester.tap(find.text('Planned length'));
      await settle(tester);
      await tester.tap(find.text('16 weeks'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      final rows = (await tester.runAsync(live))!;
      expect(rows.single.id, id);
      expect(rows.single.dayKey, dayKeyOf(start));
      expect(rows.single.plannedWeeks, 16);
      expect(find.text('Week 5 of 16'), findsOneWidget);
    });

    phaseTest('an open-ended plan is saved as no planned length',
        (tester) async {
      await phases.startPhase(
        PhaseKind.bulk,
        from: daysBefore(today, 3),
        plannedWeeks: 8,
      );
      await pumpHome(tester);
      await openSheet(tester, 'Change');

      await tester.tap(find.text('Planned length'));
      await settle(tester);
      await tester.tap(find.text('Open-ended'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(((await tester.runAsync(live))!).single.plannedWeeks, isNull);
      expect(find.text('Week 1'), findsOneWidget);
    });

    phaseTest('clearing ends the phase yesterday and empties the card',
        (tester) async {
      final id = await phases.startPhase(
        PhaseKind.cut,
        from: daysBefore(today, 20),
      );
      await pumpHome(tester);
      await openSheet(tester, 'Change');

      await tester.tap(find.text('Clear phase'));
      await settle(tester);

      // Kept, so it goes on tinting the cycles it covered.
      final rows = (await tester.runAsync(live))!;
      expect(rows.single.id, id);
      expect(rows.single.endDayKey, dayKeyOf(daysBefore(today, 1)));
      expect(find.text('Set a phase'), findsOneWidget);
    });

    phaseTest('clearing a phase begun today removes it', (tester) async {
      await phases.startPhase(PhaseKind.bulk, from: today);
      await pumpHome(tester);
      await openSheet(tester, 'Change');

      await tester.tap(find.text('Clear phase'));
      await settle(tester);

      expect((await tester.runAsync(live))!, isEmpty);
      expect(find.text('Set a phase'), findsOneWidget);
    });
  });
}
