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

/// The tick guard, asserted through the screen rather than through the rule.
///
/// `missingBeforeDone` is well covered as a function, and that covers the rule.
/// It does not cover the **wiring**, and the wiring is where this bug lived:
/// the guard was a private method of `_LogScreenState`, the box called it and
/// the keypad's Next never did, so one of the two ways of completing a set
/// wrote a done row with reps and no load. A unit test of the rule would have
/// been green throughout.
///
/// So these drive the widget. What they assert is not the arithmetic — it is
/// that both paths ask, on a first-ever movement where there is no ghost to
/// borrow a load from, which is the only situation in which the question has a
/// real answer.
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

  /// The first set of the first exercise on the page, read back from disk.
  Future<SetLog> firstSet() async {
    final detail = await repo.workoutDetail(workoutId);
    return detail!.entries.first.sets.first;
  }

  /// Which cell the keypad is pointing at, taken from the row that is drawing
  /// it. This is the observable half of "the thumb was sent to what is
  /// missing": the guard's whole job is to move the caret rather than tick.
  SetField? editingField(WidgetTester tester, String setId) {
    for (final row in tester.widgetList<SetRow>(find.byType(SetRow))) {
      if (row.set.id == setId) return row.editing?.field;
    }
    return null;
  }

  SetRow rowOf(WidgetTester tester, SetLog set) => tester.widget<SetRow>(
        find.byWidgetPredicate((w) => w is SetRow && w.set.id == set.id),
      );

  /// Opens a cell the way the screen opens one: through the callback the cell's
  /// tap fires.
  ///
  /// Not `tester.tap` on the cell. The cells are private widgets inside the
  /// row, so the only handle on them is a position in a list of
  /// `GestureDetector`s, and that list is an implementation detail of a layout
  /// this test has no opinion about — a wrapper added for a swipe or a scroll
  /// silently re-points it at something else. The callback is the row's actual
  /// contract with the screen, and it is what this test is about: the subject
  /// is what `_advance` does once a cell is open, not whether a tap lands.
  Future<void> openField(
    WidgetTester tester,
    SetLog set,
    SetField field,
  ) async {
    rowOf(tester, set).onEdit(set, field);
    await settle(tester);
    expect(editingField(tester, set.id), field,
        reason: 'the cell did not open');
  }

  SetKeypad keypad(WidgetTester tester) {
    expect(find.byType(SetKeypad), findsOneWidget,
        reason: 'the keypad is not up');
    return tester.widget<SetKeypad>(find.byType(SetKeypad));
  }

  /// A digit, through the keypad's own callback for the same reason
  /// [openField] uses the row's.
  Future<void> typeDigit(WidgetTester tester, String digit) async {
    keypad(tester).onKey(digit);
    await settle(tester);
  }

  /// The action key, whatever it currently says. What it says is asserted
  /// separately where it matters — it is the screen telling you why it will not
  /// tick, and "Reps?" is a different refusal from the one under test.
  Future<void> pressNext(WidgetTester tester) async {
    final pad = keypad(tester);
    expect(pad.nextLabel, isNot('Reps?'),
        reason: 'the count did not reach the keypad, so Next was never the '
            'key under test');
    pad.onNext();
    await settle(tester);
  }

  testWidgets('Next refuses a set with reps and no load', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpLog(tester);
    final set = await firstSet();
    expect(set.weight, isNull, reason: 'the fixture must start with no load');

    await openField(tester, set, SetField.reps);
    await typeDigit(tester, '8');
    await pressNext(tester);

    final after = await firstSet();
    expect(
      after.isDone,
      isFalse,
      reason: 'a set with no load was ticked by the keypad path',
    );
    expect(after.reps, 8, reason: 'the count typed must still be kept');
    expect(
      editingField(tester, set.id),
      SetField.weight,
      reason: 'the thumb was not sent to the blank load',
    );
  });

  testWidgets('Next completes the set once the load is there', (tester) async {
    // The guard on the test above: the refusal must narrow the path, not close
    // it. Without this, deleting the whole `_advance` tick block passes.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpLog(tester);
    final set = await firstSet();
    await repo.updateSet(set.id, weight: const Value(60));
    await settle(tester);

    await openField(tester, set, SetField.reps);
    await typeDigit(tester, '8');
    await pressNext(tester);

    final after = await firstSet();
    expect(after.isDone, isTrue, reason: 'a complete set was not ticked');
    expect(after.reps, 8);
    expect(after.weight, 60);
  });

  testWidgets('the box refuses the same set the keypad refuses',
      (tester) async {
    // The other of the two paths, asserted here rather than assumed: the rule
    // exists because these two disagreed once already.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpLog(tester);
    final set = await firstSet();

    rowOf(tester, set).onToggleDone(set, true);
    await settle(tester);

    final after = await firstSet();
    expect(after.isDone, isFalse, reason: 'the box ticked an empty set');
  });
}
