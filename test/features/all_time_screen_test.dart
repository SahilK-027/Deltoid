import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/workouts/all_time_screen.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The All time screen against a real database. Harness rules as
/// `regime_screen_test.dart`: never `pumpAndSettle` on a watched query, and own
/// the container so its stream-closing timers outlive the tree.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
final blank = regimeTemplates.firstWhere((t) => t.key == 'blank');

void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<Regime> activeRegime() =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
          .getSingle();

  Future<void> trainCycle(double weight) async {
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    for (final s in sessions) {
      final id = await repo.startWorkout(regimeId: regime.id, sessionId: s.id);
      final detail = await repo.workoutDetail(id);
      for (final entry in detail!.entries) {
        for (final set in entry.sets) {
          await repo.updateSet(
            set.id,
            weight: Value(weight),
            reps: const Value(10),
            isDone: const Value(true),
          );
        }
      }
      await repo.completeWorkout(id);
    }
    await repo.closeCycleIfSatisfied(regime.id);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const AllTimeScreen(),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Drags the page until [target] is built and on screen. `scrollUntilVisible`
  /// pumps until it settles, which a watched query never does.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      for (var f = 0; f < 5; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
  }

  testWidgets('the timeline names this year and the regime trained in it',
      (tester) async {
    await trainCycle(50);
    await trainCycle(55);
    final regime = await activeRegime();
    final year = DateTime.now().year;

    await pump(tester);

    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('$year'), findsOneWidget);
    // Two legends, never one: a regime's colour and a week's state are
    // different kinds of fact.
    expect(find.text('Regimes'), findsWidgets);
    expect(find.text('Week off'), findsOneWidget);
    expect(find.text(regime.name), findsWidgets);
  });

  testWidgets('the year\'s spells are folded away until asked for',
      (tester) async {
    await trainCycle(50);
    final year = DateTime.now().year;

    await pump(tester);

    expect(find.text('Regimes in $year'), findsOneWidget);
    expect(find.textContaining('Cycle 1'), findsNothing);

    await tester.tap(find.text('Regimes in $year'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.textContaining('Cycle 1'), findsWidgets);
    expect(find.textContaining(' to now'), findsWidgets);
  });

  testWidgets('every live regime gets a card, and the active one says so',
      (tester) async {
    await trainCycle(50);
    await trainCycle(55);
    // A second programme, which becomes the active one.
    await createRegimeFromTemplate(db, blank);
    final regimes = await repo.liveRegimes();

    await pump(tester);

    expect(find.text('Strength by regime'), findsOneWidget);
    for (final r in regimes) {
      expect(find.text(r.name), findsWidgets);
    }
    expect(find.text('Active'), findsOneWidget);
    // The trained one carries a sparkline and its figures; the new one has
    // nothing to draw and says so with dashes rather than an empty chart.
    await scrollTo(tester, find.byType(CycleAxisChart));
    expect(find.byType(CycleAxisChart), findsOneWidget);
    expect(find.text('——'), findsWidgets);
    expect(find.text('Stronger overall'), findsWidgets);
  });

  testWidgets('a log with nothing in it draws no timeline at all',
      (tester) async {
    await pump(tester);

    expect(find.text('Timeline'), findsNothing);
    expect(find.text('Strength by regime'), findsOneWidget);
  });
}
