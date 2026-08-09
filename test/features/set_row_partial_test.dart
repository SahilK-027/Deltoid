import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/prefill.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/log_screen.dart';
import 'package:deltoid/features/log/widgets/set_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The count cell is one field until there are two numbers in it.
///
/// Partials are the exception rather than the shape of every set, so an empty
/// second box on every row is five boxes an exercise that say nothing, bought
/// by making the reps — the number the row exists for — narrower.
void main() {
  SetLog setLog({int? reps, int? partialReps}) => SetLog(
    id: 's1',
    updatedAt: 0,
    deviceId: 'test',
    dirty: false,
    workoutExerciseId: 'we1',
    setIndex: 0,
    setType: SetType.working,
    reps: reps,
    partialReps: partialReps,
    isDone: false,
  );

  /// Stands in for "the partial half was asked for" in [edits], which is
  /// otherwise a list of fields.
  const partialAsk = SetField.added;

  final edits = <(String, SetField)>[];

  setUp(edits.clear);

  Future<void> pump(
    WidgetTester tester, {
    required SetLog set,
    PastSet? ghost,
    MeasureMode measure = MeasureMode.reps,
    EditTarget? editing,
    String? partialShownFor,
    String? partialClosedFor,
    bool partialEditing = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SetRow(
            set: set,
            loadMode: LoadMode.total,
            unit: WeightUnit.kg,
            measure: measure,
            ghost: ghost,
            editing: editing,
            partialShownFor: partialShownFor,
            partialClosedFor: partialClosedFor,
            partialEditing: partialEditing,
            buffer: ValueNotifier<String>(''),
            onEdit: (s, f) => edits.add((s.id, f)),
            onEditPartial: (s) => edits.add((s.id, partialAsk)),
            onToggleDone: (_, _) {},
          ),
        ),
      ),
    );
  }

  /// The partial half is always in the tree — clipped to nothing while it is
  /// shut — so whether it is *open* is a question about its width.
  double halfWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(SetRow.partialHalfKey)).width;

  testWidgets('a set with no partials is a single count cell', (tester) async {
    await pump(tester, set: setLog(reps: 8));
    expect(halfWidth(tester), 0);
  });

  testWidgets('a set that has partials shows them', (tester) async {
    await pump(tester, set: setLog(reps: 8, partialReps: 3));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // Half the column each: the partial count is the other half of what the
    // set was, not a sliver stuck on the end of the reps. On the default test
    // surface that half is ~176 wide, so this only fails if it has gone back
    // to being a fixed narrow column.
    expect(halfWidth(tester), greaterThan(60));
  });

  testWidgets('asking for P splits the cell before anything is typed', (
    tester,
  ) async {
    await pump(
      tester,
      set: setLog(reps: 8),
      editing: const EditTarget('s1', SetField.reps),
      partialShownFor: 's1',
      partialEditing: true,
    );
    await tester.pumpAndSettle();
    expect(halfWidth(tester), greaterThan(0));
    expect(find.text('–'), findsOneWidget);
  });

  testWidgets('F closes the half again', (tester) async {
    // `F` / `P` is a toggle: nothing was typed into the partial half, so
    // switching back to the reps takes the empty box away rather than leaving
    // it standing on a row that has no partials.
    await pump(
      tester,
      set: setLog(reps: 8),
      editing: const EditTarget('s1', SetField.reps),
      partialEditing: false,
    );
    await tester.pumpAndSettle();
    expect(halfWidth(tester), 0);
  });

  testWidgets('tapping the reps half leaves the partial box open', (
    tester,
  ) async {
    // Mid-entry: `P` opened the half, the reps side is the live one because it
    // was tapped, and nothing has been typed into the partials yet. The box
    // has to still be there — it is what the next digits were opened for.
    await pump(
      tester,
      set: setLog(reps: 8),
      editing: const EditTarget('s1', SetField.reps),
      partialShownFor: 's1',
      partialEditing: false,
    );
    await tester.pumpAndSettle();
    expect(halfWidth(tester), greaterThan(60));
  });

  testWidgets('F drops a recorded partial and closes the box', (tester) async {
    // Going back to full is a statement about the set. The row still carries
    // the old `3` — the clearing write has not come back through the stream —
    // and last week's ghost carries one too, and neither may re-open a box the
    // user has just said does not apply.
    await pump(
      tester,
      set: setLog(reps: 8, partialReps: 3),
      ghost: const PastSet(type: SetType.working, reps: 8, partialReps: 2),
      editing: const EditTarget('s1', SetField.reps),
      partialClosedFor: 's1',
    );
    await tester.pumpAndSettle();
    expect(halfWidth(tester), 0);
  });

  testWidgets('P on another row does not split this one', (tester) async {
    await pump(
      tester,
      set: setLog(reps: 8),
      editing: const EditTarget('other', SetField.reps),
      partialShownFor: 'other',
      partialEditing: true,
    );
    expect(halfWidth(tester), 0);
  });

  testWidgets('last time\'s partials show as a ghost and open the half', (
    tester,
  ) async {
    await pump(
      tester,
      set: setLog(),
      ghost: const PastSet(type: SetType.working, reps: 8, partialReps: 3),
    );
    await tester.pumpAndSettle();
    // Open, and holding last week's number in ghost text — a row that showed
    // `8` where the week before read `8+3` claims a set that did not happen.
    expect(halfWidth(tester), greaterThan(60));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('both halves take focus on their own tap', (tester) async {
    // A field you can see and cannot type into is a broken field. What a tap
    // must not do is *close* the half — that is the pad's `F`, and only its.
    await pump(
      tester,
      set: setLog(reps: 8, partialReps: 3),
      editing: const EditTarget('s1', SetField.reps),
      partialShownFor: 's1',
      partialEditing: true,
    );
    await tester.pumpAndSettle();

    // The live half renders the keypad buffer, which is empty here.
    await tester.tap(find.text('–'));
    await tester.tap(find.text('8'));
    expect(edits, [('s1', partialAsk), ('s1', SetField.reps)]);
  });

  testWidgets('a hold never splits — there is no half-second', (tester) async {
    await pump(
      tester,
      set: setLog(reps: 145, partialReps: 3),
      measure: MeasureMode.hold,
      editing: const EditTarget('s1', SetField.reps),
      partialShownFor: 's1',
      partialEditing: true,
    );
    expect(find.text('2:25'), findsOneWidget);
    expect(halfWidth(tester), 0);
    expect(find.text('3'), findsNothing);
  });
}
