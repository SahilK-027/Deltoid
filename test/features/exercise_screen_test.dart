import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/features/regime/exercise_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creating an exercise answers every question, because the defaults it used to
/// ship with were guesses wearing the clothes of answers — a movement filed
/// under chest / machine / total load by nobody, and load mode decides how
/// every set ever logged against it is read.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ensureStarterCatalog(db);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpNew(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const ExerciseScreen(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // Never `pumpAndSettle`: a watched query that has not answered yet renders a
  // spinner, which never settles. Enough frames for a sheet to open or close.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  VoidCallback? createAction(WidgetTester tester) => tester
      .widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Create exercise'),
      )
      .onPressed;

  Future<void> answer(
    WidgetTester tester,
    String row,
    String option,
  ) async {
    await tester.tap(find.text(row));
    await settle(tester);
    await tester.tap(find.text(option).last);
    await settle(tester);
  }

  testWidgets('nothing is created until every field is answered', (
    tester,
  ) async {
    await pumpNew(tester);

    // Each question shows `Choose` rather than a plausible-looking default.
    expect(find.text('Choose'), findsNWidgets(3));
    expect(createAction(tester), isNull);

    await tester.tap(find.text('Name'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Cable fly');
    await settle(tester);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save'));
    await settle(tester);
    expect(createAction(tester), isNull);

    await answer(tester, 'Muscle', 'Chest');
    expect(createAction(tester), isNull);

    await answer(tester, 'Equipment', 'Cable');
    expect(createAction(tester), isNull);

    // A total load is the one that still owes an answer about its bar, so the
    // button stays off through this step and comes on at the next.
    await answer(tester, 'How the weight is entered', 'Total load');
    expect(createAction(tester), isNull);

    await tester.tap(find.text('Bar'));
    await settle(tester);
    await tester.tap(find.text('No bar').last);
    await settle(tester);

    expect(createAction(tester), isNotNull);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Create exercise'));
    await settle(tester);

    final made = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Cable fly')))
        .getSingle();
    expect(made.muscle, MuscleGroup.chest);
    expect(made.equipment, Equipment.cable);
    expect(made.loadMode, LoadMode.total);
    expect(made.barKind, BarKind.none);
  });

  testWidgets('a load that is not a total never asks about a bar', (
    tester,
  ) async {
    await pumpNew(tester);

    // A name the starter catalog does not already hold — the prompt refuses a
    // duplicate, which is its own test in `regime_repository_test`.
    await tester.tap(find.text('Name'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Ring pull-up');
    await settle(tester);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save'));
    await settle(tester);

    await answer(tester, 'Muscle', 'Back');
    await answer(tester, 'Equipment', 'Bodyweight');
    await answer(
        tester, 'How the weight is entered', 'Bodyweight plus added weight');

    // The row is gone, so there is no outstanding question behind it.
    expect(find.text('Bar'), findsNothing);
    expect(createAction(tester), isNotNull);
  });

  group('editing an existing exercise', () {
    Future<Exercise> anExercise() async {
      return (db.select(db.exercises)..where((t) => t.muscle.equalsValue(
        MuscleGroup.chest,
      ))).get().then((rows) => rows.first);
    }

    Future<void> pumpExisting(WidgetTester tester, String id) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: ExerciseScreen(exerciseId: id),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('a mis-tap does not refile a movement with history behind it', (
      tester,
    ) async {
      final exercise = await anExercise();
      await pumpExisting(tester, exercise.id);

      await tester.tap(find.text('Muscle'));
      await settle(tester);
      await tester.tap(find.text('Back').last);
      await settle(tester);

      // Every row here writes the moment the sheet closes, which is right for a
      // screen you came to edit and wrong for one you opened to read.
      expect(find.textContaining('Change ${exercise.name}?'), findsOneWidget);
      // Both values are named, and both are lifted out of the sentence.
      final body = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && (w.textSpan?.toPlainText().contains(
                'changes from Chest to Back',
              ) ?? false),
        ),
      );
      final bold = (body.textSpan! as TextSpan)
          .children!
          .cast<TextSpan>()
          .where((s) => s.style?.fontWeight == FontWeight.w600)
          .map((s) => s.text)
          .toList();
      expect(bold, ['Chest', 'Back']);

      await tester.tap(find.text('Go back').last);
      await settle(tester);

      final after = await (db.select(db.exercises)
        ..where((t) => t.id.equals(exercise.id))).getSingle();
      expect(after.muscle, exercise.muscle);
    });

    testWidgets('confirming writes it', (tester) async {
      final exercise = await anExercise();
      await pumpExisting(tester, exercise.id);

      await tester.tap(find.text('Muscle'));
      await settle(tester);
      await tester.tap(find.text('Back').last);
      await settle(tester);
      await tester.tap(find.text('Change it').last);
      await settle(tester);

      final after = await (db.select(db.exercises)
        ..where((t) => t.id.equals(exercise.id))).getSingle();
      expect(after.muscle, MuscleGroup.back);
    });

    testWidgets('picking the value it already has asks nothing', (
      tester,
    ) async {
      final exercise = await anExercise();
      await pumpExisting(tester, exercise.id);

      await tester.tap(find.text('Muscle'));
      await settle(tester);
      await tester.tap(find.text('Chest').last);
      await settle(tester);

      expect(find.textContaining('Change ${exercise.name}?'), findsNothing);
    });
  });
}
