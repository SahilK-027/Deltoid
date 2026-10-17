import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/home/home_screen.dart';
import 'package:deltoid/features/home/history_heatmap_screen.dart';
import 'package:deltoid/features/home/weigh_ins_screen.dart';
import 'package:deltoid/features/home/widgets/habit_tile.dart';
import 'package:deltoid/features/log/log_screen.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Workouts resolves in one frame rather than assembling itself from a dozen
/// watched queries in dependency layers, which reveals the screen in stages and
/// flashes an empty state on the way. These tests are about *what the user sees
/// between frames*, not about the final tree — pump one frame at a time rather
/// than `pumpAndSettle`.

/// The blank template is first in the list and has no sessions in it, which is
/// Today's *other* empty state, so these tests build a real split.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ensureStarterCatalog(db);
  });

  tearDown(() => db.close());

  Future<void> pumpWorkouts(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const HomeScreen(),
        ),
      ),
    );
  }

  /// Every frame until the screen stops changing, so a state that appears for
  /// one frame and vanishes is still caught.
  Future<List<String>> frames(WidgetTester tester) async {
    final seen = <String>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('|'),
      );
    }
    return seen;
  }

  testWidgets('never flashes "no sessions" at a regime that has them',
      (tester) async {
    await createRegimeFromTemplate(db, ppl);
    await pumpWorkouts(tester);

    final seen = await frames(tester);

    expect(
      seen.where((f) => f.contains('No sessions in')),
      isEmpty,
      reason: 'the frame before sessions arrived used to render the empty '
          'state for a regime with six of them',
    );
    expect(seen.last, contains('Cycle 1'));
  });

  testWidgets('arrives in one frame, not in layers', (tester) async {
    await createRegimeFromTemplate(db, ppl);
    await pumpWorkouts(tester);

    final seen = await frames(tester);
    final populated = seen.where((f) => f.contains('Cycle 1'));

    // The cycle status and the session it names land together — no frame has
    // one without the other. (The consistency grid may still be below the fold,
    // so a lazy ListView has not built it yet; the snapshot it reads is the
    // same one.)
    for (final frame in populated) {
      expect(frame, contains('Push 1'));
    }
    expect(populated, isNotEmpty);
  });

  testWidgets('the in-progress clock moves', (tester) async {
    final regimeId = await createRegimeFromTemplate(db, ppl);
    final repo = TrainingRepository(db);
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    final id = await repo.startWorkout(
      regimeId: regimeId,
      sessionId: sessions.first.id,
    );
    // Two minutes in, so the reading is unambiguous and not a rounding artefact
    // of the first second. Written straight to the row: `startWorkout(at:)`
    // backdates the *day* and deliberately keeps the current clock time.
    await (db.update(db.workouts)..where((t) => t.id.equals(id))).write(
      WorkoutsCompanion(
        startedAt: Value(nowMs() - const Duration(minutes: 2, seconds: 5).inMilliseconds),
      ),
    );

    await pumpWorkouts(tester);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    String clock() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => RegExp(r'^\d+:\d\d$').hasMatch(s));

    final first = clock();
    expect(first, startsWith('02:'));

    // This is the whole point: `DateTime.now()` read once during build, with
    // nothing to rebuild the card, says "0m" for the entire session.
    //
    // Both clocks have to move. `pump` advances the fake one the ticker runs
    // on; `runAsync` lets the real one — the one the card reads — advance too,
    // so a ticker that fires and recomputes the same number still fails here.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(clock(), isNot(first));
  });

  testWidgets('the in-progress tile counts one set as one set',
      (tester) async {
    final regimeId = await createRegimeFromTemplate(db, ppl);
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    final id = await TrainingRepository(db).startWorkout(
      regimeId: regimeId,
      sessionId: sessions.first.id,
    );
    // Every set but one is deleted, so the workout's total is exactly one.
    await db.customStatement(
      'UPDATE set_logs SET deleted_at = ? WHERE workout_exercise_id IN '
      '(SELECT id FROM workout_exercises WHERE workout_id = ?) AND id <> '
      '(SELECT s.id FROM set_logs s JOIN workout_exercises e '
      'ON e.id = s.workout_exercise_id WHERE e.workout_id = ? LIMIT 1)',
      [nowMs(), id, id],
    );

    await pumpWorkouts(tester);
    await frames(tester);

    expect(find.text('0 of 1 set'), findsOneWidget);
    expect(find.text('0 of 1 sets'), findsNothing);
  });

  testWidgets('the habit grids clear the fold on a six-session split',
      (tester) async {
    // A cycle drawn twice — a row of labelled bars in the hero card and then
    // the same sessions again as a list — pushes the grids off the bottom of
    // the screen on every phone.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await createRegimeFromTemplate(db, ppl);
    await pumpWorkouts(tester);
    await frames(tester);

    for (final grid in find.byType(HabitGrid).evaluate()) {
      expect(
        tester.getRect(find.byWidget(grid.widget)).bottom,
        lessThanOrEqualTo(844),
        reason: 'six sessions is the widest split the templates ship; if the '
            'grids do not fit that, they fit nothing',
      );
    }
    expect(find.byType(HabitGrid), findsNWidgets(2));
  });

  testWidgets('a fresh install offers a regime instead of a blank page',
      (tester) async {
    await pumpWorkouts(tester);

    final seen = await frames(tester);

    expect(seen.last, contains('Create a regime'));
    // And it never claimed a regime existed on the way there.
    expect(seen.where((f) => f.contains('Cycle 1')), isEmpty);

    // The screen keeps its own shape with nothing in it: the habits are the
    // page's second section on a fresh install exactly as on a full one.
    expect(find.text('Habits'), findsOneWidget);
    expect(find.byType(HabitTile), findsNWidgets(2));

    // The empty state is still this screen: the masthead survives it. It is the
    // date and the rest gap, not the screen's name — on a fresh install there
    // is nothing to count from, and it says so.
    expect(
      find.text('Nothing logged'),
      findsOneWidget,
      reason: 'the zero state carries the header like every other state',
    );
    // No cog up here: Settings is a nav destination, so a fresh install
    // restoring a backup reaches it in one tap from everywhere, this screen
    // included.
    expect(find.byTooltip('Settings'), findsNothing);
  });

  testWidgets('a regime with no sessions keeps the page it will have',
      (tester) async {
    // THEME: a thing with no data still has a page, and it is the page it will
    // have once there is some. A lone centred card here — Habits and the
    // masthead's count both gone — would make adding the first session look
    // like it built a section when all it did was fill one.
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'blank'),
    );
    await pumpWorkouts(tester);
    final seen = await frames(tester);

    expect(seen.last, contains('Add a session'));

    // The sections are read off logged work, not off the regime, so a split
    // with no days in it says nothing about whether they should be here.
    expect(find.text('Habits'), findsOneWidget);
    expect(find.byType(HabitTile), findsNWidgets(2));
    // Read rather than entered, so on Progress whatever state Home is in.
    expect(find.text('Weekly volume'), findsNothing);
    expect(find.text('Cycle progress'), findsNothing);

    // Same masthead as every other state on this screen.
    expect(find.text('Nothing logged'), findsOneWidget);
  });

  group('past sessions', () {
    testWidgets('a row under the habits replaces the masthead calendar',
        (tester) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);

      // THEME § 8: the calendar glyph in the band said what it did only
      // through a tooltip. The row says it in words, so the glyph is gone.
      expect(find.byIcon(Icons.edit_calendar_outlined), findsNothing);
      expect(find.byTooltip('Log a past session'), findsNothing);

      final row = find.text('Log a past session');
      await tester.ensureVisible(row);
      await tester.pump();
      expect(find.text('Past sessions'), findsOneWidget);
      expect(
        find.text('For a day you trained without the app'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(tester.getTopLeft(find.byType(HabitGrid).last).dy),
        reason: 'the row sits under the Workouts tile, where the gap it fills '
            'is seen',
      );
    });

    testWidgets('the row opens the backfill sheet', (tester) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);

      final row = find.text('Log a past session');
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await frames(tester);

      // The sheet the calendar icon opened: the day, defaulting to
      // yesterday, over the sessions of the active regime.
      expect(find.textContaining('Yesterday'), findsOneWidget);
      expect(find.text('Which session'), findsOneWidget);
      expect(find.text('Push 1'), findsWidgets);
    });

    testWidgets('is absent while there is nothing to log against',
        (tester) async {
      await pumpWorkouts(tester);
      await frames(tester);
      expect(find.text('Past sessions'), findsNothing);

      await createRegimeFromTemplate(
        db,
        regimeTemplates.firstWhere((t) => t.key == 'blank'),
      );
      await frames(tester);
      expect(find.text('Add a session'), findsOneWidget);
      expect(find.text('Past sessions'), findsNothing);
    });
  });

  testWidgets('cycle progress and weekly volume are on Progress, not here',
      (tester) async {
    await createRegimeFromTemplate(db, ppl);
    await pumpWorkouts(tester);
    await frames(tester);

    // THEME → The destinations: Home is where things are entered, and the two
    // cards that are read rather than entered moved to Progress.
    expect(find.text("Today's session"), findsOneWidget);
    expect(find.text('Habits'), findsOneWidget);
    await tester.ensureVisible(find.text('Log a past session'));
    await tester.pump();
    expect(find.text('Past sessions'), findsOneWidget);
    expect(find.text('Cycle progress'), findsNothing);
    expect(find.text('Weekly volume'), findsNothing);
    expect(find.text('All time'), findsNothing);
  });

  group('habits', () {
    /// The ppl split's sessions, in cycle order.
    Future<List<Session>> sessionsOf(String regimeId) =>
        (db.select(db.sessions)
              ..where((t) => t.regimeId.equals(regimeId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();

    /// A finished session today, with every set of the first exercise ticked.
    Future<void> trainToday(String regimeId) async {
      final repo = TrainingRepository(db);
      final id = await repo.startWorkout(
        regimeId: regimeId,
        sessionId: (await sessionsOf(regimeId)).first.id,
      );
      final detail = await repo.workoutDetail(id);
      for (final set in detail!.entries.first.sets) {
        await repo.updateSet(
          set.id,
          weight: const Value(40),
          reps: const Value(8),
          isDone: const Value(true),
        );
      }
      await repo.completeWorkout(id);
    }

    /// The figure under a tile's hairline, by the tile's name.
    String figureOf(WidgetTester tester, String title) {
      final tile = find.ancestor(
        of: find.text(title),
        matching: find.byType(HabitTile),
      );
      return tester
          .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .firstWhere((s) => s.endsWith('/7'));
    }

    /// A widget test that unmounts the screen before it ends, so drift's
    /// stream-closing timers run out before the harness checks for pending
    /// timers. These tests leave a weigh-in query and a pushed screen open,
    /// and without this one of them trips that check about one run in three.
    void habitTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    Future<void> reveal(WidgetTester tester) async {
      await tester.ensureVisible(find.byType(HabitTile).first);
      await tester.pump();
    }

    habitTest('two tiles take the place of the Consistency card', (
      tester,
    ) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('Weigh-ins'), findsOneWidget);
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Last 30 days'), findsNWidgets(2));
      expect(find.text('Consistency'), findsNothing);
      // Weigh-ins on the left, Workouts on the right.
      expect(
        tester.getCenter(find.text('Weigh-ins')).dx,
        lessThan(tester.getCenter(find.text('Workouts')).dx),
      );
      // Nothing logged yet: a dash, not a zero.
      expect(figureOf(tester, 'Weigh-ins'), '—/7');
      expect(figureOf(tester, 'Workouts'), '—/7');
    });

    habitTest('count days kept this week, not entries', (tester) async {
      final regimeId = await createRegimeFromTemplate(db, ppl);
      final repo = TrainingRepository(db);
      // Two weigh-ins and two sessions, all today: one day each.
      await repo.logBodyweight(DateTime.now(), 77.0);
      await repo.logBodyweight(DateTime.now(), 76.8);
      await trainToday(regimeId);
      await trainToday(regimeId);

      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      expect(figureOf(tester, 'Weigh-ins'), '1/7');
      expect(figureOf(tester, 'Workouts'), '1/7');
    });

    habitTest('the tile updates when a weight is logged', (tester) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);
      expect(figureOf(tester, 'Weigh-ins'), '—/7');

      await TrainingRepository(db).logBodyweight(DateTime.now(), 77.0);
      await frames(tester);

      expect(figureOf(tester, 'Weigh-ins'), '1/7');
    });

    habitTest('+ opens the weigh-in sheet and not the screen', (
      tester,
    ) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      await tester.tap(find.byTooltip('Log weight'));
      await frames(tester);

      expect(find.text('Log bodyweight'), findsOneWidget);
      expect(find.byType(WeighInsScreen), findsNothing);

    });

    habitTest('+ over a weight logged today opens it for correcting', (
      tester,
    ) async {
      await createRegimeFromTemplate(db, ppl);
      await TrainingRepository(db).logBodyweight(DateTime.now(), 76.5);
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      await tester.tap(find.byTooltip('Log weight'));
      await frames(tester);

      expect(find.text('Edit bodyweight'), findsOneWidget);
    });

    habitTest('the Weigh-ins tile opens the Weigh-ins screen', (
      tester,
    ) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      await tester.tap(find.text('Weigh-ins'));
      await frames(tester);

      expect(find.byType(WeighInsScreen), findsOneWidget);
    });

    habitTest('the Workouts tile opens Consistency', (tester) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      await tester.tap(find.text('Workouts'));
      await frames(tester);

      expect(find.byType(HistoryHeatmapScreen), findsOneWidget);
    });

    habitTest('play starts the session that is due', (tester) async {
      final regimeId = await createRegimeFromTemplate(db, ppl);
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      await tester.tap(find.byTooltip('Start Push 1'));
      await frames(tester);

      // The hero's own path: the workout is created and the log opens on it.
      final open = await (db.select(db.workouts)
            ..where((t) => t.endedAt.isNull()))
          .get();
      expect(open, hasLength(1));
      expect(open.single.regimeId, regimeId);
      expect(open.single.sessionId, (await sessionsOf(regimeId)).first.id);
      expect(find.byType(LogScreen), findsOneWidget);
    });

    habitTest('with a session open, play resumes it', (tester) async {
      final regimeId = await createRegimeFromTemplate(db, ppl);
      await TrainingRepository(db).startWorkout(
        regimeId: regimeId,
        sessionId: (await sessionsOf(regimeId)).first.id,
      );
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);

      expect(find.byTooltip('Start Push 1'), findsNothing);
      await tester.tap(find.byTooltip('Resume session'));
      await frames(tester);

      // Resumed, not a second session alongside the first.
      final open = await (db.select(db.workouts)
            ..where((t) => t.endedAt.isNull()))
          .get();
      expect(open, hasLength(1));
      expect(find.byType(LogScreen), findsOneWidget);
    });

    habitTest('with nothing to start, play is absent', (tester) async {
      await pumpWorkouts(tester);
      await frames(tester);
      await reveal(tester);
      expect(find.byType(HabitTile), findsNWidgets(2));
      expect(find.byType(HabitAction), findsOneWidget, reason: 'only +');

      await createRegimeFromTemplate(
        db,
        regimeTemplates.firstWhere((t) => t.key == 'blank'),
      );
      await frames(tester);
      expect(find.text('Add a session'), findsOneWidget);
      await reveal(tester);
      expect(find.byType(HabitAction), findsOneWidget, reason: 'only +');
    });
  });
}
