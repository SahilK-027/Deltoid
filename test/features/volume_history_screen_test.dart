import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:deltoid/features/today/region_volume_screen.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/features/today/volume_history_screen.dart';
import 'package:deltoid/features/today/volume_providers.dart';
import 'package:deltoid/features/today/widgets/volume_history_bars.dart';
import 'package:deltoid/features/today/widgets/volume_chart.dart';
import 'package:deltoid/features/today/widgets/volume_tile.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ensureStarterCatalog(db);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {Widget? home}) async {
    // Tall enough that six tiles are laid out rather than half of them being
    // below a lazy list's fold.
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: home ?? const VolumeHistoryScreen(),
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<String> logSession() async {
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
    return regimeId;
  }

  testWidgets('a fresh install says so rather than drawing empty bars',
      (tester) async {
    await pump(tester);

    expect(find.text('Nothing counted yet'), findsOneWidget);
    expect(find.byType(VolumeTile), findsNothing);
  });

  testWidgets('every region gets a tile, including the untrained ones',
      (tester) async {
    await logSession();
    await pump(tester);

    expect(find.byType(VolumeTile), findsNWidgets(MuscleRegion.values.length));
    for (final region in MuscleRegion.values) {
      expect(
        find.text(region.label),
        findsOneWidget,
        reason: 'a muscle you skipped has to keep its place or its absence '
            'is invisible',
      );
    }
  });

  testWidgets('the caption names the week under the finger', (tester) async {
    await logSession();
    await pump(tester);

    final tile = find.byType(VolumeTile).first;
    final caption = find.descendant(of: tile, matching: find.byType(Text));
    String captionText() => tester.widget<Text>(caption.at(1)).data ?? '';

    expect(captionText(), contains('weeks'));

    // Press the bars: the caption becomes the week, not a tooltip over the
    // chart it is describing.
    final bars = find.descendant(of: tile, matching: find.byType(WeeklyBars));
    final gesture = await tester.startGesture(tester.getCenter(bars));
    // Moved sideways rather than merely pressed, and past `kTouchSlop`: under
    // it the drag recogniser has not claimed the arena, which is also why a
    // scrub does not fight the list scrolling underneath.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();

    expect(captionText(), contains('·'));
    expect(captionText(), anyOf(contains('set'), contains('sets')));

    await gesture.up();
    await tester.pump();
    expect(captionText(), contains('weeks'));
  });

  testWidgets('a region opens onto its own muscles', (tester) async {
    await logSession();
    await pump(tester, home: const RegionVolumeScreen(region: MuscleRegion.legs));

    expect(find.text('By muscle'), findsOneWidget);
    // The region itself is the full chart at the top; the tiles are its parts.
    expect(find.byType(VolumeChart), findsOneWidget);
    expect(
      find.byType(VolumeTile),
      findsNWidgets(MuscleRegion.legs.parts.length),
    );
  });

  testWidgets('a region with one muscle still has more than a chart',
      (tester) async {
    await logSession();
    await pump(
      tester,
      home: const RegionVolumeScreen(region: MuscleRegion.chest),
    );

    // Nothing to split, so no split — but the page is not one chart and a
    // screenful of nothing.
    expect(find.text('By muscle'), findsNothing);
    expect(find.byType(VolumeTile), findsNothing);

    expect(find.byType(VolumeChart), findsOneWidget);
    expect(find.text('hard sets'), findsOneWidget);
    expect(find.text('best week'), findsOneWidget);
    expect(
      find.text('Where the sets came from'),
      findsOneWidget,
      reason: 'the question a region with one muscle has instead of a split',
    );
  });

  testWidgets('a year of weeks draws without overflowing anything',
      (tester) async {
    // 52 bars in half a phone's width is where a fixed gap left hairlines on a
    // grey band, and where twelve month labels collided under the plot.
    await logSession();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.read(volumeWindowProvider.notifier).state =
        const TrendWindow.rolling(ChartRange.year);

    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const RegionVolumeScreen(region: MuscleRegion.chest),
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(VolumeChart), findsOneWidget);
    expect(tester.takeException(), isNull);
    // A year of Mondays, and the fold kept all of them.
    final series = container
        .read(volumeHistoryProvider)
        .value!
        .byRegion[MuscleRegion.chest]!;
    expect(series.weeks.length, inInclusiveRange(52, 54));
  });

  testWidgets('changing the range zooms rather than cutting', (tester) async {
    await logSession();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const VolumeHistoryScreen(),
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    container.read(volumeWindowProvider.notifier).state =
        const TrendWindow.rolling(ChartRange.year);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Mid-flight and after: the widget survives its own animation, and the
    // frames in between are the zoom rather than a rebuild.
    await tester.pump(const Duration(milliseconds: 110));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(WeeklyBars), findsWidgets);
  });

  testWidgets('ticking a set does not zoom the chart', (tester) async {
    // The zoom is a *range* change. A set logged mid-session rewrites the weeks
    // list and moves one bar, and animating that would make logging a set look
    // like navigating somewhere.
    final regimeId = await logSession();
    await pump(tester);

    final before = tester.state<State>(find.byType(WeeklyBars).first);

    final repo = TrainingRepository(db);
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    final id = await repo.startWorkout(
      regimeId: regimeId,
      sessionId: sessions[1].id,
    );
    final detail = await repo.workoutDetail(id);
    await repo.updateSet(
      detail!.entries.first.sets.first.id,
      weight: const Value(40),
      reps: const Value(8),
      isDone: const Value(true),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Same state object: the chart updated in place rather than being rebuilt,
    // and nothing threw on the way.
    expect(
      tester.state<State>(find.byType(WeeklyBars).first),
      same(before),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chart states its scale, and the movements add up',
      (tester) async {
    await logSession();
    await pump(
      tester,
      home: const RegionVolumeScreen(region: MuscleRegion.chest),
    );

    // Three ticked sets of one movement: the axis rounds up to a readable
    // step, and the breakdown accounts for all of them.
    expect(find.text('3'), findsWidgets);
    expect(find.text('100% of chest'), findsOneWidget);
  });
}
