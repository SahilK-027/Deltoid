import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/log/log_screen.dart';
import 'package:deltoid/features/log/widgets/set_row.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Last week was `8+2`; this week is eight clean reps.
///
/// The row splits the count cell on last week's partials so the ghost reads
/// as the whole set it was. That is right while the set is a plan, and wrong
/// once it is a result: a ticked set with no partials of its own was all full
/// reps, and the pad's `F` has to be able to say so before the tick as well.
/// Asserted through the screen, because the bug was in the wiring between the
/// row and the pad: each half was consistent with itself.
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

    final regime = await (db.select(
      db.regimes,
    )..where((t) => t.isActive.equals(true))).getSingle();
    final session = await (db.select(
      db.sessions,
    )..where((t) => t.name.equals('Push 1'))).getSingle();

    // Last week: every set `8+2` at 60 kg.
    final last = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: session.id,
    );
    final detail = await repo.workoutDetail(last);
    for (final entry in detail!.entries) {
      for (final set in entry.sets) {
        await repo.updateSet(
          set.id,
          weight: const Value(60),
          reps: const Value(8),
          partialReps: const Value(2),
          isDone: const Value(true),
        );
      }
    }
    await repo.completeWorkout(last);

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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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

  Future<SetLog> firstSet() async {
    final detail = await repo.workoutDetail(workoutId);
    return detail!.entries.first.sets.first;
  }

  Finder rowFinder(SetLog set) =>
      find.byWidgetPredicate((w) => w is SetRow && w.set.id == set.id);

  SetRow rowOf(WidgetTester tester, SetLog set) =>
      tester.widget<SetRow>(rowFinder(set));

  /// Whether this set's partial half is open, measured as the row draws it.
  double halfWidth(WidgetTester tester, SetLog set) => tester
      .getSize(
        find.descendant(
          of: rowFinder(set),
          matching: find.byKey(SetRow.partialHalfKey),
        ),
      )
      .width;

  SetKeypad keypad(WidgetTester tester) =>
      tester.widget<SetKeypad>(find.byType(SetKeypad));

  Future<void> openField(
    WidgetTester tester,
    SetLog set,
    SetField field,
  ) async {
    rowOf(tester, set).onEdit(set, field);
    await settle(tester);
  }

  Future<void> typeAndNext(WidgetTester tester, String digit) async {
    keypad(tester).onKey(digit);
    await settle(tester);
    keypad(tester).onNext();
    await settle(tester);
  }

  testWidgets('the ghost opens the half and the key says so', (tester) async {
    await pumpLog(tester);
    final set = await firstSet();
    expect(
      rowOf(tester, set).ghost?.partialReps,
      2,
      reason: 'the fixture must ghost last week\'s partials',
    );

    await openField(tester, set, SetField.reps);
    expect(halfWidth(tester, set), greaterThan(0));
    expect(
      keypad(tester).partial,
      isTrue,
      reason: 'the key read F beside an open partial box',
    );
  });

  testWidgets('one press of F closes a box the ghost opened', (tester) async {
    await pumpLog(tester);
    final set = await firstSet();

    await openField(tester, set, SetField.reps);
    keypad(tester).onTogglePartial!();
    await settle(tester);

    expect(keypad(tester).partial, isFalse);
    expect(halfWidth(tester, set), 0);

    // The weight beside it is the same set: the box stays shut.
    await openField(tester, set, SetField.weight);
    expect(
      halfWidth(tester, set),
      0,
      reason: 'last week\'s partials re-opened a box F had closed',
    );
  });

  testWidgets('a set ticked without partials is a full set', (tester) async {
    await pumpLog(tester);
    final set = await firstSet();

    // No F: type the reps and move on, which is what happens at the gym.
    await openField(tester, set, SetField.reps);
    await typeAndNext(tester, '8');

    final after = await firstSet();
    expect(after.isDone, isTrue);
    expect(after.reps, 8);
    expect(after.partialReps, isNull);
    expect(
      halfWidth(tester, after),
      0,
      reason: 'a full set still showed last week\'s partials',
    );
  });

  testWidgets('partials typed this week are still recorded', (tester) async {
    // The guard on the tests above: the fix must narrow the ghost, not take
    // partial entry away.
    await pumpLog(tester);
    final set = await firstSet();

    await openField(tester, set, SetField.reps);
    keypad(tester).onKey('8');
    await settle(tester);
    rowOf(tester, set).onEditPartial(set);
    await settle(tester);
    await typeAndNext(tester, '3');

    final after = await firstSet();
    expect(after.isDone, isTrue);
    expect(after.reps, 8);
    expect(after.partialReps, 3);
    expect(halfWidth(tester, after), greaterThan(0));
  });
}
