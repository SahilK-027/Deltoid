import 'dart:io';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/metrics.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/home/widgets/year_heatmap.dart';
import 'package:deltoid/features/progress/widgets/strength_card.dart';
import 'package:deltoid/features/progress/widgets/volume_bars.dart';
import 'package:deltoid/features/progress/widgets/volume_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Inter, as `y_axis_gutter_test.dart` loads it: the test font draws every
/// glyph a full em wide, so a question about whether words fit is only
/// answered in the real face.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// The chart cards at the largest system font the app allows, 1.3 (see
/// `app.dart`), on a phone 390 wide: nothing overflows, no unit or name is
/// cut short, and no label touches what sits over it. The chart audit's
/// findings 6, 21, 22 and 26.
void main() {
  setUpAll(_loadInter);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1.3,
    double width = 358,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: width, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  /// Whether the text was drawn whole, rather than clipped or ellipsized.
  bool whole(WidgetTester tester, Finder text) =>
      !tester.renderObject<RenderParagraph>(text).didExceedMaxLines;

  group('the bar list', () {
    final big = computeWeeklyVolume(
      setsByMuscle: {for (final m in MuscleGroup.values) m: 95 + m.index},
    );

    testWidgets('fits three-digit counts', (tester) async {
      await pump(tester, AppCard(child: VolumeBars(volume: big)));
      await tester.tap(find.text('Legs'));
      await tester.pump(const Duration(seconds: 1));

      // A fixed 64 overflowed by 8 pixels at `140 sets`.
      expect(tester.takeException(), isNull);
      expect(find.text('410'), findsOneWidget);
    });

    testWidgets('prints every region and muscle name in full', (tester) async {
      await pump(tester, AppCard(child: VolumeBars(volume: big)));
      await tester.tap(find.text('Arms'));
      await tester.tap(find.text('Legs'));
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      for (final name in ['Shoulders', 'Hamstrings', 'Forearms', 'Calves']) {
        expect(whole(tester, find.text(name)), isTrue, reason: name);
      }
    });

    testWidgets('ends every bar at the same x', (tester) async {
      await pump(
        tester,
        AppCard(
          child: VolumeBars(
            volume: computeWeeklyVolume(
              setsByMuscle: {MuscleGroup.chest: 140, MuscleGroup.back: 3},
            ),
          ),
        ),
      );
      final right = {
        for (final n in ['140', '3', '0'])
          tester.getRect(find.text(n).first).right,
      };
      expect(right, hasLength(1));
    });
  });

  testWidgets('a volume tile prints its whole unit', (tester) async {
    final monday = weekStartOf(DateTime.now());
    final series = VolumeSeries(label: 'Shoulders', weeks: [
      for (var i = 0; i < 52; i++)
        VolumeWeek(
          start: DateTime(monday.year, monday.month, monday.day - 7 * (51 - i)),
          sets: 10 + i % 3,
        ),
    ]);
    // Half a phone, as two tiles sit in a row.
    await pump(
      tester,
      Builder(
        builder: (context) => VolumeTile(
          series: series,
          by: Granularity.weekly,
          hue: context.c.forRegion(MuscleRegion.shoulders),
          onTap: () {},
        ),
      ),
      width: 171,
    );

    // It was `sets/...` at 1.3.
    expect(tester.takeException(), isNull);
    expect(whole(tester, find.text('sets/wk')), isTrue);
  });

  group('the year map', () {
    Size sizeAt(WidgetTester tester) => tester.getSize(
          find.descendant(
            of: find.byType(YearHeatmap),
            matching: find.byType(CustomPaint),
          ),
        );

    testWidgets('makes room for its month strip at the system font', (
      tester,
    ) async {
      const map = YearHeatmap(year: 2025, days: TrainingYearDays({}));
      await pump(tester, map, scale: 1.0);
      final small = sizeAt(tester).height;
      await pump(tester, map);
      final large = sizeAt(tester).height;

      // A line of 14 at 1.3 is 18.2, 4.2 taller than at 1.0. The labels were
      // painted without the system font, at as little as 7 sp.
      expect(large - small, closeTo(14 * 0.3, 0.01));
    });
  });

  testWidgets('the cycle chart keeps its top value inside its own box', (
    tester,
  ) async {
    const bench = LiftId(sessionId: 'push1', exerciseId: 'bench');
    LiftPerformance lift(double kg) => LiftPerformance(
          lift: bench,
          dayKey: 20260601,
          load: LoadMode.total,
          sets: [ScoredSet(type: SetType.working, weight: kg, reps: 8)],
        );
    final regime = RegimeProgress(
      regimeId: 'r',
      regimeName: 'Upper lower',
      identityIndex: 0,
      isActive: true,
      progress: computeCycleProgress(cycles: [
        CycleInput(
          cycleId: 'c1',
          index: 1,
          isDeload: false,
          isOpen: false,
          performances: [lift(100)],
        ),
        CycleInput(
          cycleId: 'c2',
          index: 2,
          isDeload: false,
          isOpen: true,
          performances: [lift(101)],
        ),
      ]),
      labels: const {},
    );
    await pump(tester, StrengthCard(regime: regime));

    // The top value sits on the top gridline, so half of it is over the plot.
    // `fl_chart` gave no room for that half, and at 1.3 the label met the
    // readout over the chart.
    final chart = tester.getRect(find.byType(CycleAxisChart));
    final labels = find.descendant(
      of: find.byType(CycleAxisChart),
      matching: find.byType(Text),
    );
    final top = tester
        .widgetList<Text>(labels)
        .map((t) => tester.getRect(find.byWidget(t)).top)
        .reduce((a, b) => a < b ? a : b);
    expect(top, greaterThanOrEqualTo(chart.top));
  });
}
