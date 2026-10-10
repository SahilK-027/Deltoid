import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/history/logged_set_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet that corrects one set of a finished session.
///
/// What it hands back is the contract: only the fields that were retyped, so a
/// corrected rep count cannot move the weight beside it, and nothing at all
/// until something has changed and every field holds a number.
void main() {
  late List<Exercise> catalog;

  setUpAll(() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await ensureStarterCatalog(db);
    catalog = await db.select(db.exercises).get();
    await db.close();
  });

  Exercise exerciseWith({LoadMode? load, MeasureMode? measure}) =>
      catalog.firstWhere(
        (e) =>
            (load == null || e.loadMode == load) &&
            e.measureMode == (measure ?? MeasureMode.reps),
      );

  SetLog setLog({
    double? weight,
    double? addedWeight,
    int? reps,
    int? partialReps,
    SetType type = SetType.working,
  }) => SetLog(
    id: 's1',
    updatedAt: 0,
    deviceId: 'test',
    dirty: false,
    workoutExerciseId: 'we1',
    setIndex: 0,
    setType: type,
    weight: weight,
    addedWeight: addedWeight,
    reps: reps,
    partialReps: partialReps,
    isDone: true,
  );

  /// Opens the sheet and returns a reader for what it came back with.
  Future<LoggedSetEdit? Function()> open(
    WidgetTester tester, {
    required SetLog set,
    required Exercise exercise,
    WeightUnit unit = WeightUnit.kg,
    int deleteCount = 1,
  }) async {
    LoggedSetEdit? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showLoggedSetSheet(
                  context,
                  set: set,
                  exercise: exercise,
                  unit: unit,
                  label: '2',
                  deleteCount: deleteCount,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  Finder field(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
    matching: find.byType(TextField),
  );

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet opens on the set as it was logged', (tester) async {
    await open(
      tester,
      set: setLog(weight: 22.5, reps: 8, partialReps: 3),
      exercise: exerciseWith(load: LoadMode.total),
    );

    expect(find.text('Set 2'), findsOneWidget);
    expect(find.text('22.5'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
  });

  testWidgets('nothing is saved until something has changed', (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 60, reps: 8),
      exercise: exerciseWith(load: LoadMode.total),
    );

    await save(tester);

    // Still open: the button is off, so the tap went nowhere.
    expect(find.text('Save'), findsOneWidget);
    expect(result(), isNull);
  });

  testWidgets('only the field that was retyped comes back', (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 60, reps: 8),
      exercise: exerciseWith(load: LoadMode.total),
    );

    await tester.enterText(field('Reps'), '10');
    await tester.pump();
    await save(tester);

    final edit = result()!;
    expect(edit.delete, isFalse);
    expect(edit.count, 10);
    expect(edit.load, isNull);
    expect(edit.partial, isNull);
    expect(edit.setType, isNull);
  });

  testWidgets('a load typed in pounds comes back in kilograms', (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 100, reps: 5),
      exercise: exerciseWith(load: LoadMode.total),
      unit: WeightUnit.lb,
    );

    await tester.enterText(field('Weight (lb)'), '225');
    await tester.pump();
    await save(tester);

    expect(result()!.load!.kg, closeTo(102.058, 0.001));
    expect(result()!.count, isNull);
  });

  testWidgets('clearing the partials records that the set had none',
      (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 60, reps: 8, partialReps: 3),
      exercise: exerciseWith(load: LoadMode.total),
    );

    await tester.enterText(field('Partial reps'), '');
    await tester.pump();
    await save(tester);

    final partial = result()!.partial;
    expect(partial, isNotNull);
    expect(partial!.reps, isNull);
  });

  testWidgets('a set cannot be saved without a count', (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 60, reps: 8),
      exercise: exerciseWith(load: LoadMode.total),
    );

    await tester.enterText(field('Reps'), '');
    await tester.pump();
    await save(tester);

    expect(find.text('Save'), findsOneWidget);
    expect(result(), isNull);
  });

  testWidgets('a load past the ceiling is refused', (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 60, reps: 8),
      exercise: exerciseWith(load: LoadMode.total),
    );

    await tester.enterText(field('Weight (kg)'), '1000.5');
    await tester.pump();
    await save(tester);

    expect(result(), isNull);
  });

  testWidgets('a bodyweight movement has no load to correct', (tester) async {
    await open(
      tester,
      set: setLog(reps: 12),
      exercise: exerciseWith(load: LoadMode.bodyweight),
    );

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Reps'), findsOneWidget);
    expect(find.text('Partial reps'), findsOneWidget);
  });

  testWidgets('a hold is corrected in seconds and has no partials',
      (tester) async {
    final hold = exerciseWith(measure: MeasureMode.hold);
    final result = await open(tester, set: setLog(reps: 45), exercise: hold);

    expect(find.text('Partial reps'), findsNothing);
    await tester.enterText(field('Seconds'), '90');
    await tester.pump();
    await save(tester);

    expect(result()!.count, 90);
  });

  testWidgets('a set type is chosen from a list and saved with the rest',
      (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 20, reps: 10),
      exercise: exerciseWith(load: LoadMode.total),
    );

    await tester.tap(find.text('Set type'));
    await tester.pumpAndSettle();
    // No drop on the list: it would need a leg nothing can fill.
    expect(find.text('Drop'), findsNothing);
    await tester.tap(find.text('Warm-up'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(result()!.setType, SetType.warmup);
    expect(result()!.load, isNull);
  });

  testWidgets('deleting asks first, and says what goes', (tester) async {
    final result = await open(
      tester,
      set: setLog(weight: 60, reps: 8, type: SetType.drop),
      exercise: exerciseWith(load: LoadMode.total),
      deleteCount: 3,
    );

    await tester.tap(find.text('Delete this drop set'));
    await tester.pumpAndSettle();
    expect(find.textContaining('All 3 legs'), findsOneWidget);
    expect(result(), isNull);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result()!.delete, isTrue);
  });
}
