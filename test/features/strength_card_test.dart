import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/metrics.dart';
import 'package:deltoid/domain/phases.dart';
import 'package:deltoid/features/progress/widgets/strength_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three states of the card, and the line of prose under the figure.
///
/// The arithmetic behind it is proved in `test/domain/cycle_progress_test.dart`;
/// what is held here is that all three states are the same card — THEME →
/// Empty states — and that the readout names a cycle a person can find.

const bench = LiftId(sessionId: 'push1', exerciseId: 'bench');
const row = LiftId(sessionId: 'pull1', exerciseId: 'row');

LiftPerformance lift(LiftId id, double weight, {int dayKey = 20260525}) =>
    LiftPerformance(
      lift: id,
      dayKey: dayKey,
      load: LoadMode.total,
      sets: [ScoredSet(type: SetType.working, weight: weight, reps: 10)],
    );

CycleInput cycle(
  int index,
  List<LiftPerformance> performances, {
  bool isDeload = false,
  bool isOpen = false,
  int? from,
  int? to,
}) =>
    CycleInput(
      cycleId: 'c$index',
      index: index,
      isDeload: isDeload,
      isOpen: isOpen,
      startDayKey: from,
      endDayKey: to,
      performances: performances,
    );

RegimeProgress regimeOf(List<CycleInput> cycles) => RegimeProgress(
      regimeId: 'r',
      regimeName: 'Upper lower',
      identityIndex: 0,
      isActive: true,
      progress: computeCycleProgress(cycles: cycles),
      labels: const {},
    );

/// A regime four cycles in, the third of them a deload.
RegimeProgress trained() => regimeOf([
      cycle(1, [lift(bench, 100), lift(row, 50)], from: 20260525, to: 20260531),
      cycle(2, [lift(bench, 110), lift(row, 50)], from: 20260601, to: 20260607),
      cycle(3, [lift(bench, 60)], isDeload: true, from: 20260608, to: 20260614),
      cycle(4, [lift(bench, 120), lift(row, 55)], from: 20260615, to: 20260621),
    ]);

Widget harness(RegimeProgress regime, {int? planned, VoidCallback? onOpen}) =>
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StrengthCard(
            regime: regime,
            plannedLifts: planned,
            onOpen: onOpen,
          ),
        ),
      ),
    );

void main() {
  testWidgets('a trained regime prints its figure, its trend and its ranges',
      (tester) async {
    await tester.pumpWidget(harness(trained(), planned: 15, onOpen: () {}));
    await tester.pumpAndSettle();

    expect(find.text('Upper lower'), findsOneWidget);
    // Bench +20 %, row +10 %: the latest cycle is +15 %.
    expect(find.text('+15.0'), findsOneWidget);
    expect(find.text('%'), findsWidgets);
    expect(find.text('Progressing'), findsOneWidget);
    for (final label in ['Last 12', 'Last 24', 'All']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(CycleAxisChart), findsOneWidget);
    // Both lifts beat their baseline, out of the two the regime has scored —
    // the same set the row opens onto.
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('lifts improved'), findsOneWidget);
  });

  testWidgets('the deload in the window is legended, and only then',
      (tester) async {
    await tester.pumpWidget(harness(trained()));
    await tester.pumpAndSettle();
    expect(find.text('Deload'), findsOneWidget);

    await tester.pumpWidget(
      harness(
        regimeOf([
          cycle(1, [lift(bench, 100)], from: 20260525, to: 20260531),
          cycle(2, [lift(bench, 110)], from: 20260601, to: 20260607),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Deload'), findsNothing);
  });

  group('phases', () {
    final spans = phaseSpans(const [
      PhaseEntry(id: 'a', kind: PhaseKind.maintenance, startKey: 20260525),
      PhaseEntry(id: 'b', kind: PhaseKind.bulk, startKey: 20260601),
    ]);

    CycleInput phased(int index, double weight, int day, {bool isDeload = false}) =>
        CycleInput(
          cycleId: 'c$index',
          index: index,
          isDeload: isDeload,
          startDayKey: day,
          endDayKey: day,
          sessionDays: [day],
          performances: [lift(bench, weight, dayKey: day)],
        );

    RegimeProgress phasedRegime(List<CycleInput> cycles) => RegimeProgress(
          regimeId: 'r',
          regimeName: 'Upper lower',
          identityIndex: 0,
          isActive: true,
          progress: computeCycleProgress(cycles: cycles, phases: spans),
          labels: const {},
        );

    testWidgets('the legend names the phases on screen, in order, and no '
        'others', (tester) async {
      await tester.pumpWidget(
        harness(
          phasedRegime([
            phased(1, 100, 20260526),
            phased(2, 110, 20260602),
            phased(3, 60, 20260609, isDeload: true),
            phased(4, 120, 20260616),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Maintenance'), findsOneWidget);
      expect(find.text('Bulk'), findsOneWidget);
      expect(find.text('Cut'), findsNothing);
      expect(find.text('Deload'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Maintenance')).dx,
        lessThan(tester.getTopLeft(find.text('Bulk')).dx),
      );
      // The readout opens on the latest cycle and names its phase.
      expect(
        find.textContaining('Bulk  ·  +20.0%', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a regime trained with no phase has no phase in its legend',
        (tester) async {
      await tester.pumpWidget(harness(trained()));
      await tester.pumpAndSettle();

      for (final name in ['Maintenance', 'Bulk', 'Cut']) {
        expect(find.text(name), findsNothing);
      }
    });

    testWidgets('a phase only off screen has no swatch', (tester) async {
      // Twenty cycles: the maintenance cycle is the first, outside Last 12.
      await tester.pumpWidget(
        harness(
          phasedRegime([
            phased(1, 100, 20260526),
            for (var i = 2; i <= 20; i++) phased(i, 100.0 + i, 20260600 + i),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bulk'), findsOneWidget);
      expect(find.text('Maintenance'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Maintenance'), findsOneWidget);
    });
  });

  testWidgets('the open cycle is named in the legend', (tester) async {
    await tester.pumpWidget(
      harness(
        regimeOf([
          cycle(1, [lift(bench, 100)], from: 20260525, to: 20260531),
          cycle(2, [lift(bench, 110)], from: 20260601, to: 20260607),
          cycle(3, [lift(bench, 120)], isOpen: true, from: 20260608),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cycle 3 so far'), findsOneWidget);
  });

  testWidgets('a first cycle has lifts recorded and nothing to compare',
      (tester) async {
    await tester.pumpWidget(
      harness(
        regimeOf([
          cycle(1, [lift(bench, 100), lift(row, 50)], from: 20260525),
        ]),
        planned: 15,
        onOpen: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('——'), findsOneWidget);
    expect(find.text('Stronger overall'), findsOneWidget);
    expect(find.text('2 of 15'), findsOneWidget);
    expect(find.text('Lifts recorded'), findsOneWidget);
    // One cycle is a chart with one dot on it — the starting point.
    expect(find.byType(CycleAxisChart), findsOneWidget);
    // No comparison exists yet, so nothing claims one.
    expect(find.text('Progressing'), findsNothing);
  });

  testWidgets('nothing trained keeps the card and prints dashes',
      (tester) async {
    await tester.pumpWidget(harness(regimeOf(const []), planned: 15));
    await tester.pumpAndSettle();

    expect(find.text('——'), findsOneWidget);
    expect(find.text('— of 15'), findsOneWidget);
    expect(find.text('Lifts improved'), findsOneWidget);
    // The axis the regime will have, with nothing on it yet.
    expect(find.byType(CycleAxisChart), findsOneWidget);
  });

  testWidgets('changing the range redraws the same card', (tester) async {
    await tester.pumpWidget(harness(trained()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.byType(CycleAxisChart), findsOneWidget);
    expect(find.text('+15.0'), findsOneWidget);
  });

  group('the readout', () {
    CyclePoint point(
      int index, {
      double? value,
      bool isDeload = false,
      bool isOpen = false,
      int? from,
      int? to,
      PhaseKind? phase,
    }) =>
        CyclePoint(
          cycleId: 'c$index',
          index: index,
          isDeload: isDeload,
          isOpen: isOpen,
          value: value,
          lifts: const [],
          startDayKey: from,
          endDayKey: to,
          sessions: [
            if (from != null) (dayKey: from, kind: phase),
          ],
        );

    test('names the cycle, its dates and its score', () {
      expect(
        cycleReadout(point(9, value: 9.8, from: 20260824, to: 20260830)),
        'Cycle 9  ·  24 Aug to 30 Aug 2026  ·  +9.8%',
      );
    });

    test('prints both years on a cycle that crosses one', () {
      expect(
        cycleSpan(point(1, value: 0, from: 20251229, to: 20260104)),
        '29 Dec 2025 to 4 Jan 2026',
      );
    });

    test('a cycle trained on one day names that day once', () {
      expect(cycleSpan(point(1, value: 0, from: 20260824, to: 20260824)),
          '24 Aug 2026');
    });

    test('the open cycle runs to now', () {
      expect(
        cycleReadout(point(10, value: 11.2, from: 20260907, isOpen: true)),
        'Cycle 10  ·  7 Sep 2026 to now  ·  +11.2%',
      );
    });

    test('a deload says so instead of scoring', () {
      expect(
        cycleReadout(point(5, from: 20260622, to: 20260628, isDeload: true)),
        'Cycle 5  ·  22 Jun to 28 Jun 2026  ·  Deload',
      );
    });

    test('the baseline cycle claims no percentage of its own', () {
      expect(
        cycleReadout(
          point(1, value: 0, from: 20260525, to: 20260531),
          isBaseline: true,
        ),
        'Cycle 1  ·  25 May to 31 May 2026',
      );
    });

    test('a cycle that ran in a phase names it after the days', () {
      expect(
        cycleReadout(
          point(6, value: 6.4, from: 20260903, to: 20260909, phase: PhaseKind.cut),
        ),
        'Cycle 6  ·  3 Sep to 9 Sep 2026  ·  Cut  ·  +6.4%',
      );
    });

    test('a cycle with no phase says nothing extra', () {
      expect(
        cycleReadout(point(6, value: 6.4, from: 20260903, to: 20260909)),
        'Cycle 6  ·  3 Sep to 9 Sep 2026  ·  +6.4%',
      );
    });

    test('a deload names no phase, whatever it ran in', () {
      expect(
        cycleReadout(
          point(
            5,
            from: 20260622,
            to: 20260628,
            isDeload: true,
            phase: PhaseKind.cut,
          ),
        ),
        'Cycle 5  ·  22 Jun to 28 Jun 2026  ·  Deload',
      );
    });

    test('a cycle with nothing dated is still named', () {
      expect(cycleReadout(point(3, value: 4)), 'Cycle 3  ·  +4.0%');
    });
  });
}
