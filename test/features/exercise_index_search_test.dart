import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/history/history_screen.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Searching History for an exercise you have not trained yet used to answer
/// "no such exercise", because the index is built by joining the catalog to
/// completed workouts. An exercise you added this morning is not missing — it
/// is untrained, and those are different sentences.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;

  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  /// Long enough for the queries behind the screen to land, without waiting on
  /// a spinner to stop spinning.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Trains the first slot of the first session once, and returns its name.
  Future<String> logOneDay() async {
    final regime = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
    final session = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..limit(1))
        .getSingle();
    final id =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    final detail = (await repo.workoutDetail(id))!;
    await repo.updateSet(
      detail.entries.first.sets.first.id,
      weight: const Value(60),
      reps: const Value(8),
      isDone: const Value(true),
    );
    await repo.completeWorkout(id);
    return detail.entries.first.exercise.name;
  }

  Future<void> pumpIndex(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const HistoryScreen(),
        ),
      ),
    );
    // Never `pumpAndSettle`: this screen holds a `CircularProgressIndicator`
    // while its queries land, and a spinner is an animation that never ends.
    await settle(tester);
    await tester.tap(find.text('Exercises'));
    await settle(tester);

  }

  /// Unmounts the screen and lets the disposal land. Riverpod cancels drift's
  /// query streams when the scope goes, and those close on a timer the test has
  /// to let fire — a teardown is too late, the framework checks for pending
  /// timers the moment the body returns.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  /// A row in the index, rather than the same text sitting in the search field.
  Finder row(String name) => find.descendant(
        of: find.byType(ListView),
        matching: find.text(name),
      );

  testWidgets('an exercise you own but have never trained is still findable',
      (tester) async {
    await logOneDay();
    await pumpIndex(tester);

    // Not in the list at rest: this is an index of what you have trained,
    // ordered by when, and the whole catalog would bury it.
    expect(find.text('Never logged'), findsNothing);

    final untrained = await (db.select(db.exercises)
          ..where((t) => t.name.like('Face Pull%'))
          ..limit(1))
        .getSingleOrNull();
    expect(untrained, isNotNull, reason: 'the starter catalog changed');

    await tester.enterText(find.byType(TextField), untrained!.name);
    await settle(tester);

    expect(row(untrained.name), findsOneWidget);
    expect(find.text('Never logged'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a trained match is listed above the untrained ones',
      (tester) async {
    final trained = await logOneDay();
    await pumpIndex(tester);

    // The word both a trained and an untrained exercise have in their name.
    final word = trained.split(' ').last;
    await tester.enterText(find.byType(TextField), word);
    await settle(tester);

    expect(row(trained), findsOneWidget);
    if (find.text('Never logged').evaluate().isNotEmpty) {
      expect(find.text('Not yet logged'), findsOneWidget);
      expect(
        tester.getTopLeft(row(trained)).dy,
        lessThan(tester.getTopLeft(find.text('Not yet logged')).dy),
      );
    }
    await unmount(tester);
  });

  testWidgets('a name nothing is called says so rather than looking broken',
      (tester) async {
    await logOneDay();
    await pumpIndex(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await settle(tester);

    expect(find.text('No matches'), findsOneWidget);
    await unmount(tester);
  });
}
