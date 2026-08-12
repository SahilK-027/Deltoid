import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:deltoid/features/today/today_screen.dart';
import 'package:deltoid/features/today/widgets/volume_bars.dart';
import 'package:deltoid/features/today/widgets/heatmap.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Today used to assemble itself from a dozen watched queries in dependency
/// layers, so it revealed itself in stages and flashed an empty state on the
/// way. These tests are about *what the user sees between frames*, not about
/// the final tree — pump one frame at a time rather than `pumpAndSettle`.

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

  Future<void> pumpToday(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const TodayScreen(),
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
    await pumpToday(tester);

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
    await pumpToday(tester);

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

    await pumpToday(tester);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    String clock() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => RegExp(r'^\d+:\d\d$').hasMatch(s));

    final first = clock();
    expect(first, startsWith('02:'));

    // This is the whole point: the old card read `DateTime.now()` once during
    // build with nothing to rebuild it, so it said "0m" for the entire session.
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

  testWidgets('the consistency grid clears the fold on a six-session split',
      (tester) async {
    // The grid used to sit under a cycle drawn twice — a row of labelled bars in
    // the hero card and then the same sessions again as a list — which put it
    // off the bottom of the screen on every phone.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await createRegimeFromTemplate(db, ppl);
    await pumpToday(tester);
    await frames(tester);

    final grid = tester.getRect(find.byType(ConsistencyHeatmap));

    expect(
      grid.bottom,
      lessThanOrEqualTo(844),
      reason: 'six sessions is the widest split the templates ship; if the '
          'grid does not fit that, it fits nothing',
    );
  });

  testWidgets('a fresh install offers a regime instead of a blank page',
      (tester) async {
    await pumpToday(tester);

    final seen = await frames(tester);

    expect(seen.last, contains('Create a regime'));
    // And it never claimed a regime existed on the way there.
    expect(seen.where((f) => f.contains('Cycle 1')), isEmpty);

    // The screen keeps its own shape with nothing in it: the record is the
    // page's second section on a fresh install exactly as it is on a full one.
    expect(find.byType(ConsistencyHeatmap), findsOneWidget);

    // The empty state is still this screen: the masthead survives it. It is the
    // date and the rest gap, not the screen's name — on a fresh install there
    // is nothing to count from, and it says so.
    expect(
      find.text('Nothing logged'),
      findsOneWidget,
      reason: 'the zero state used to drop the header entirely',
    );
    // Settings used to be a cog up here, and this test guarded it because a
    // fresh install restoring a backup had no other route in. It is a nav
    // destination now, so the cog is gone and the route is one tap from
    // everywhere — including this screen.
    expect(find.byTooltip('Settings'), findsNothing);
  });

  group('this week', () {
    /// A finished session with every set of the first exercise ticked.
    Future<void> logSession(String regimeId) async {
      final repo = TrainingRepository(db);
      final sessions = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regimeId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      final id = await repo.startWorkout(
        regimeId: regimeId,
        sessionId: sessions.first.id,
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

    testWidgets('is there on a fresh install, at zero', (tester) async {
      await createRegimeFromTemplate(db, ppl);
      await pumpToday(tester);
      await frames(tester);

      // It used to be held back until something was logged, on the grounds
      // that six empty tracks is a chart of nothing. What that cost was the
      // section appearing from nowhere on the day of the first workout, which
      // moved everything under it. The page keeps its shape instead.
      expect(find.text('Weekly volume'), findsOneWidget);
      expect(find.byType(VolumeBars), findsOneWidget);
    });

    testWidgets('draws all six rows once there is history, zeros included', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final regimeId = await createRegimeFromTemplate(db, ppl);
      await logSession(regimeId);
      await pumpToday(tester);
      await frames(tester);

      expect(find.text('Weekly volume'), findsOneWidget);
      for (final region in MuscleRegion.values) {
        expect(
          find.text(region.label),
          findsOneWidget,
          reason: 'a muscle trained zero times is still a row',
        );
      }
      // The session logged is a chest opener, so chest is the only row with
      // anything in it — and the untrained ones say so out loud.
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('a compound row opens onto its own muscles', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final regimeId = await createRegimeFromTemplate(db, ppl);
      await logSession(regimeId);
      await pumpToday(tester);
      await frames(tester);

      expect(find.text('Quads'), findsNothing);

      await tester.tap(find.text('Legs'));
      await frames(tester);

      // `Legs 18` is a number you cannot act on; `Quads 12 · Hamstrings 0` is
      // the same week saying something you would train differently over.
      for (final m in MuscleRegion.legs.parts) {
        expect(find.text(m.label), findsOneWidget);
      }
      // Chest is not compound, so it has nothing to open and does not offer to.
      expect(find.text('Chest'), findsOneWidget);
    });
  });
}
