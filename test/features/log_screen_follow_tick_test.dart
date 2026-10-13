import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/log/log_screen.dart';
import 'package:deltoid/features/log/widgets/exercise_rail.dart';
import 'package:deltoid/features/log/widgets/set_row.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the caret goes after a set is completed, asserted through the screen.
///
/// The page turns when an exercise is finished, not when its last row is
/// ticked. The two are the same thing only when the sets are logged in order,
/// and ticking the last set first used to turn the page with two sets still
/// open behind it. Both ways of completing a set are driven here, because the
/// box and the keypad's Next reach the page turn through separate code.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late TrainingRepository repo;
  late String workoutId;

  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    final regime = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
    final session = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();
    // The first workout this database has ever held, so no exercise on it has
    // a previous set to ghost from. A ghosted load is not missing — the tick
    // adopts it — so a fixture with history cannot feel this guard at all.
    workoutId = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: session.id,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // Never `pumpAndSettle`: a watched query that has not answered yet renders a
  // spinner, which never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpLog(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: LogScreen(workoutId: workoutId),
        ),
      ),
    );
    await settle(tester);
  }

  /// The sets of the exercise on a page, read back from disk.
  Future<List<SetLog>> setsOn(int page) async {
    final detail = await repo.workoutDetail(workoutId);
    return detail!.entries[page].sets;
  }

  /// Gives every set on a page a load and a count, so that nothing but the
  /// order of the ticks decides where the caret goes.
  Future<void> fill(WidgetTester tester, int page) async {
    for (final set in await setsOn(page)) {
      await repo.updateSet(
        set.id,
        weight: const Value(60),
        reps: const Value(8),
      );
    }
    await settle(tester);
  }

  int currentPage(WidgetTester tester) =>
      tester.widget<ExerciseRail>(find.byType(ExerciseRail)).current;

  /// The set the keypad is pointing at. Every row is handed the screen's one
  /// target, so any row answers.
  String? editingSetId(WidgetTester tester) =>
      tester.widgetList<SetRow>(find.byType(SetRow)).first.editing?.setId;

  SetRow rowOf(WidgetTester tester, SetLog set) => tester.widget<SetRow>(
        find.byWidgetPredicate((w) => w is SetRow && w.set.id == set.id),
      );

  Future<void> tick(WidgetTester tester, SetLog set) async {
    rowOf(tester, set).onToggleDone(set, true);
    await settle(tester);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('ticking the last set first goes back to the open set above it',
      (tester) async {
    phone(tester);
    await pumpLog(tester);
    await fill(tester, 0);
    final sets = await setsOn(0);
    expect(sets.length, greaterThan(1),
        reason: 'the fixture needs an exercise with more than one set');

    await tick(tester, sets.last);

    expect((await setsOn(0)).last.isDone, isTrue);
    expect(currentPage(tester), 0,
        reason: 'the page turned with sets still open on it');
    expect(editingSetId(tester), sets.first.id,
        reason: 'the caret did not go to the first open set');
  });

  testWidgets('the page turns once every set of the exercise is ticked',
      (tester) async {
    // The guard on the test above: staying on the page must not become never
    // leaving it.
    phone(tester);
    await pumpLog(tester);
    await fill(tester, 0);
    final sets = await setsOn(0);

    for (final set in sets.reversed) {
      expect(currentPage(tester), 0);
      await tick(tester, set);
    }

    expect(currentPage(tester), 1,
        reason: 'the page did not turn on a finished exercise');
  });

  testWidgets('a set ticked in the middle carries on down the table',
      (tester) async {
    phone(tester);
    await pumpLog(tester);
    await fill(tester, 0);
    final sets = await setsOn(0);
    expect(sets.length, greaterThan(2),
        reason: 'the fixture needs an exercise with a middle set');

    await tick(tester, sets[1]);

    expect(editingSetId(tester), sets[2].id,
        reason: 'the caret went back up with a set open below');
  });

  testWidgets('Next on the last set goes back to the open set above it',
      (tester) async {
    phone(tester);
    await pumpLog(tester);
    await fill(tester, 0);
    final sets = await setsOn(0);

    rowOf(tester, sets.last).onEdit(sets.last, SetField.reps);
    await settle(tester);
    tester.widget<SetKeypad>(find.byType(SetKeypad)).onNext();
    await settle(tester);

    expect((await setsOn(0)).last.isDone, isTrue);
    expect(currentPage(tester), 0,
        reason: 'the page turned with sets still open on it');
    expect(editingSetId(tester), sets.first.id,
        reason: 'the caret did not go to the first open set');
  });
}
