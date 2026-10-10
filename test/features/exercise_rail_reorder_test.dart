import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/features/log/widgets/exercise_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dragging a tab must land it where the finger left it and keep it there.
///
/// The rail is built off a database stream, so the frame after a drop still
/// carries the order the database last emitted, which is the order before the
/// drop. Without an optimistic order the tab snaps home and jumps again when
/// the write lands:
/// two movements to express one, the first of them backwards.
void main() {
  ExerciseEntry entry(String id, String name, int order) => ExerciseEntry(
        workoutExercise: WorkoutExercise(
          id: id,
          updatedAt: 0,
          deviceId: 'test',
          dirty: false,
          workoutId: 'w',
          exerciseId: 'e$id',
          orderIndex: order,
          targetSets: 3,
          skipReason: SkipReason.none,
        ),
        exercise: Exercise(
          id: 'e$id',
          updatedAt: 0,
          deviceId: 'test',
          dirty: false,
          name: name,
          muscle: MuscleGroup.chest,
          equipment: Equipment.barbell,
          loadMode: LoadMode.total,
          barKind: BarKind.none,
          measureMode: MeasureMode.reps,
          bodyweightPct: 100,
          archived: false,
          formVideoUrls: const [],
        ),
        sets: const [],
      );

  /// `Bench Press` → `BP`, which is what the rail actually renders.
  List<String> visibleTabs(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.length == 2)
      .toList();

  testWidgets('a dropped tab stays where it was dropped', (tester) async {
    final entries = [
      entry('1', 'Bench Press', 0),
      entry('2', 'Cable Row', 1),
      entry('3', 'Front Squat', 2),
    ];
    List<String>? reordered;

    Widget rail(List<ExerciseEntry> data) => MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: ExerciseRail(
              entries: data,
              current: 0,
              onSelect: (_) {},
              onAdd: () {},
              onReorder: (ids) => reordered = ids,
            ),
          ),
        );

    await tester.pumpWidget(rail(entries));
    expect(visibleTabs(tester), ['BP', 'CR', 'FS']);

    // Long-press the first tab, drag it one slot right, drop it.
    final start = tester.getCenter(find.text('BP'));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    // The very next frame, before any animation settles and long before the
    // database has heard about it.
    await tester.pump(const Duration(milliseconds: 16));
    expect(visibleTabs(tester), ['CR', 'FS', 'BP'],
        reason: 'the drop must not play back through the old order');
    await tester.pumpAndSettle();

    expect(reordered, isNotNull, reason: 'the drag should report a new order');
    expect(reordered, ['2', '3', '1']);

    // The database has not caught up yet: the widget is rebuilt with exactly
    // the order it had before the drag. The rail must not snap back to it.
    await tester.pumpWidget(rail(entries));
    await tester.pump();
    expect(visibleTabs(tester), ['CR', 'FS', 'BP']);

    // The write lands and the stream finally agrees.
    await tester.pumpWidget(rail([entries[1], entries[2], entries[0]]));
    await tester.pumpAndSettle();
    expect(visibleTabs(tester), ['CR', 'FS', 'BP']);
  });
}
