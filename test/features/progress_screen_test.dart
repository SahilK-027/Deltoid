import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:deltoid/features/progress/all_time_screen.dart';
import 'package:deltoid/features/progress/cycle_progress_providers.dart';
import 'package:deltoid/features/progress/progress_screen.dart';
import 'package:deltoid/features/progress/volume_history_screen.dart';
import 'package:deltoid/features/progress/widgets/strength_card.dart';
import 'package:deltoid/features/progress/widgets/volume_bars.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Progress against a real database: Cycle progress and Weekly volume, moved
/// from Home unchanged (THEME → The destinations). Harness rules as
/// `all_time_screen_test.dart`: never `pumpAndSettle` on a watched query, and
/// own the container so its stream-closing timers outlive the tree.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
final blank = regimeTemplates.firstWhere((t) => t.key == 'blank');

void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<Session>> sessionsOf(String regimeId) =>
      (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();

  /// One finished session with every set of [exercises] entries ticked.
  Future<void> logSession(
    String regimeId,
    String sessionId, {
    double weight = 40,
    int? exercises,
  }) async {
    final id = await repo.startWorkout(regimeId: regimeId, sessionId: sessionId);
    final detail = await repo.workoutDetail(id);
    for (final entry in detail!.entries.take(exercises ?? 1 << 30)) {
      for (final set in entry.sets) {
        await repo.updateSet(
          set.id,
          weight: Value(weight),
          reps: const Value(8),
          isDone: const Value(true),
        );
      }
    }
    await repo.completeWorkout(id);
  }

  /// Every session of the split, then the cycle closed.
  ///
  /// One exercise a session, to keep the fixture small.
  Future<void> trainCycle(String regimeId, double weight) async {
    for (final s in await sessionsOf(regimeId)) {
      await logSession(regimeId, s.id, weight: weight, exercises: 1);
    }
    await repo.closeCycleIfSatisfied(regimeId);
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// A tall phone, so both sections are built without scrolling.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const ProgressScreen(),
        ),
      ),
    );
    await frames(tester);
  }

  /// Unmounts the screen before the test ends, so drift's stream-closing
  /// timers run out before the harness checks for pending timers.
  void progressTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  /// The `All time` link under the section heading [title].
  Finder allTimeOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
    matching: find.text('All time'),
  );

  progressTest('the masthead names the page and its inventory', (
    tester,
  ) async {
    await createRegimeFromTemplate(db, ppl);
    await pump(tester);

    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('CYCLES AND VOLUME'), findsOneWidget);
  });

  progressTest('Cycle progress comes first, then Weekly volume', (
    tester,
  ) async {
    await createRegimeFromTemplate(db, ppl);
    await pump(tester);

    expect(find.byType(StrengthCard), findsOneWidget);
    expect(find.byType(VolumeBars), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Cycle progress')).dy,
      lessThan(tester.getTopLeft(find.text('Weekly volume')).dy),
    );
  });

  progressTest('a fresh install keeps both sections, with nothing to open', (
    tester,
  ) async {
    await pump(tester);

    // THEME → Empty states: the page is the page it will be, with the
    // figures as dashes and the bars at zero.
    expect(find.text('Cycle progress'), findsOneWidget);
    expect(find.byType(StrengthCard), findsOneWidget);
    expect(find.text('Weekly volume'), findsOneWidget);
    expect(find.byType(VolumeBars), findsOneWidget);
    // A link to an empty screen is a control that does nothing.
    expect(find.text('All time'), findsNothing);
  });

  progressTest('a regime with no sessions keeps both sections', (
    tester,
  ) async {
    await createRegimeFromTemplate(db, blank);
    await pump(tester);

    expect(find.byType(StrengthCard), findsOneWidget);
    expect(find.byType(VolumeBars), findsOneWidget);
    expect(find.text('All time'), findsNothing);
  });

  progressTest('a regime with nothing trained offers no All time link', (
    tester,
  ) async {
    await createRegimeFromTemplate(db, ppl);
    await pump(tester);

    expect(find.byType(StrengthCard), findsOneWidget);
    expect(find.text('All time'), findsNothing);
  });

  progressTest('a first session opens the week but scores no cycle yet', (
    tester,
  ) async {
    final regimeId = await createRegimeFromTemplate(db, ppl);
    await logSession(regimeId, (await sessionsOf(regimeId)).first.id);
    await pump(tester);

    // The week has a set in it, so its link is there.
    expect(allTimeOf('Weekly volume'), findsOneWidget);
    // Cycle progress is gated on a scored point, not on a row existing.
    final scored = container
        .read(activeRegimeProgressProvider)
        .valueOrNull
        ?.progress
        .latest;
    expect(
      allTimeOf('Cycle progress'),
      scored == null ? findsNothing : findsOneWidget,
    );
  });

  progressTest('Cycle progress opens All time', (tester) async {
    final regimeId = await createRegimeFromTemplate(db, ppl);
    await trainCycle(regimeId, 40);
    await trainCycle(regimeId, 45);
    // A fortnight ago, out of the volume window: two cycles in one week print
    // counts wider than the test font fits in a bar's count box.
    const fortnight = 14 * 24 * 60 * 60 * 1000;
    await db.customStatement(
      'UPDATE workouts SET started_at = started_at - $fortnight, '
      'ended_at = ended_at - $fortnight, '
      "day_key = CAST(strftime('%Y%m%d', "
      "(started_at - $fortnight) / 1000 + tz_offset_minutes * 60, "
      "'unixepoch') AS INTEGER)",
    );
    await pump(tester);

    expect(allTimeOf('Cycle progress'), findsOneWidget);
    await tester.tap(allTimeOf('Cycle progress'));
    await frames(tester);

    expect(find.byType(AllTimeScreen), findsOneWidget);
  });

  progressTest('Weekly volume opens its history, by link or by card', (
    tester,
  ) async {
    final regimeId = await createRegimeFromTemplate(db, ppl);
    await logSession(regimeId, (await sessionsOf(regimeId)).first.id);
    await pump(tester);

    await tester.tap(allTimeOf('Weekly volume'));
    await frames(tester);
    expect(find.byType(VolumeHistoryScreen), findsOneWidget);

    await tester.pageBack();
    await frames(tester);
    expect(find.byType(VolumeHistoryScreen), findsNothing);
  });

  group('weekly volume', () {
    progressTest('is there with a regime and nothing logged, at zero', (
      tester,
    ) async {
      await createRegimeFromTemplate(db, ppl);
      await pump(tester);

      // Not held back until something is logged, on the grounds that six empty
      // tracks is a chart of nothing: that costs the section appearing from
      // nowhere on the day of the first workout, moving everything under it.
      // The page keeps its shape instead.
      expect(find.text('Weekly volume'), findsOneWidget);
      expect(find.byType(VolumeBars), findsOneWidget);
    });

    progressTest('draws all six rows once there is history, zeros included', (
      tester,
    ) async {
      final regimeId = await createRegimeFromTemplate(db, ppl);
      await logSession(
        regimeId,
        (await sessionsOf(regimeId)).first.id,
        exercises: 1,
      );
      await pump(tester);

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

    progressTest('a compound row opens onto its own muscles', (tester) async {
      final regimeId = await createRegimeFromTemplate(db, ppl);
      await logSession(
        regimeId,
        (await sessionsOf(regimeId)).first.id,
        exercises: 1,
      );
      await pump(tester);

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
