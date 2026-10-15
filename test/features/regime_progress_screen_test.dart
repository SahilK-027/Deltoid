import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/home/regime_progress_screen.dart';
import 'package:deltoid/features/home/widgets/strength_card.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The regime screen, pumped against a real database and real training.
///
/// The harness rules are the ones `regime_screen_test.dart` learned: never
/// `pumpAndSettle` against a watched query, and own the container so its
/// stream-closing timers outlive the widget tree.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

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

  /// Trains every session of the regime once, at [weight] on every set, and
  /// closes the cycle the way the log screen does.
  Future<void> trainCycle(double weight, {bool close = true}) async {
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
    if (close) await repo.closeCycleIfSatisfied(regime.id);
  }

  /// Trains only the first session, leaving cycle 1 part way through.
  Future<void> trainOneSession(double weight) async {
    final regime = await activeRegime();
    final session = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
          ..limit(1))
        .getSingle();
    final id = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: session.id,
    );
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

  Future<void> pump(WidgetTester tester, String regimeId) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: RegimeProgressScreen(regimeId: regimeId),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Drags the page until [target] is built and on screen.
  ///
  /// `scrollUntilVisible` pumps until it settles, which a watched query never
  /// does, so this drags a fixed number of times instead.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      for (var f = 0; f < 5; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
  }

  testWidgets('a measured regime lists its lifts by what they did',
      (tester) async {
    await trainCycle(50);
    await trainCycle(55);
    final regime = await activeRegime();

    await pump(tester, regime.id);

    expect(find.text(regime.name), findsOneWidget);
    expect(find.byType(StrengthCard), findsOneWidget);
    // The card on this screen has no name of its own: the app bar carries it.
    expect(find.text('Cycle progress'), findsNothing);
    // Everything went up ten per cent, so there is one group and it is that one.
    expect(find.text('Stronger'), findsOneWidget);
    expect(find.text('No change'), findsNothing);
    expect(find.text('Weaker'), findsNothing);
    // A lift row names the movement, its session and the two sets behind it.
    // A lift row names the movement, its session and the two sets behind it.
    // The list is long, so the row is scrolled to rather than assumed on
    // screen — a `ListView` builds only what is visible.
    await scrollTo(tester, find.textContaining('50 kg × 10 to 55 kg × 10'));
    expect(find.textContaining('50 kg × 10 to 55 kg × 10'), findsWidgets);
    // The gain in kilograms, which is what a lift row prints: 50 kg × 10
    // estimates 66.7 and 55 kg × 10 estimates 73.3, so the row reads +6.5
    // against the plate increment.
    expect(find.text('+6.5'), findsWidgets);
    expect(find.text('kg'), findsWidgets);
  });

  testWidgets('a lift that stood still is its own group', (tester) async {
    await trainCycle(50);
    await trainCycle(50);
    final regime = await activeRegime();

    await pump(tester, regime.id);

    expect(find.text('No change'), findsOneWidget);
    expect(find.text('Stronger'), findsNothing);
    // One set, printed once rather than as a range to itself.
    expect(find.textContaining('50 kg × 10 to'), findsNothing);
  });

  testWidgets('the method is folded away until it is asked for',
      (tester) async {
    await trainCycle(50);
    await trainCycle(55);
    final regime = await activeRegime();

    await pump(tester, regime.id);

    expect(find.text('How is this measured?'), findsOneWidget);
    expect(find.text('Deload cycles are left out'), findsNothing);

    await tester.tap(find.text('How is this measured?'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('Every cycle is compared with cycle 1'), findsOneWidget);
    expect(find.text('Deload cycles are left out'), findsOneWidget);
  });

  testWidgets('a first cycle shows what is recorded and what is left',
      (tester) async {
    await trainOneSession(50);
    final regime = await activeRegime();

    await pump(tester, regime.id);

    expect(find.text('Starting point'), findsOneWidget);
    expect(find.text('Recorded'), findsOneWidget);
    await scrollTo(tester, find.text('Still to train'));
    expect(find.text('Still to train'), findsOneWidget);
    expect(find.textContaining('Not yet'), findsWidgets);
    // Nothing claims a comparison that does not exist.
    expect(find.text('Stronger'), findsNothing);
    expect(find.text('How is this measured?'), findsNothing);
  });
}
