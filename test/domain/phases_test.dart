import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/phases.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every answer read off a phase, against hand-worked literals.
///
/// Both phones compute these from the same rows and never send them
/// ([SYNC.md § 4](SYNC.md#4-what-the-server-holds)), so a rule that is wrong
/// here is wrong identically on every phone and nothing downstream notices.
/// The edges are the point: a span ending a day early tints the wrong cycle,
/// and a threshold off by a day asks a question a week early.
void main() {
  PhaseEntry phase(
    String id,
    PhaseKind kind,
    int start, {
    int? weeks,
    int? end,
    int? kept,
  }) =>
      PhaseEntry(
        id: id,
        kind: kind,
        startKey: start,
        plannedWeeks: weeks,
        endKey: end,
        keptKey: kept,
      );

  ({int dayKey, double weightKg}) w(int day, double kg) =>
      (dayKey: day, weightKg: kg);

  group('phaseSpans — where each phase ends', () {
    test('no phases cover nothing', () {
      expect(phaseSpans(const []), isEmpty);
    });

    test('a phase with nothing after it is still running', () {
      final spans = phaseSpans([phase('a', PhaseKind.bulk, 20260903)]);
      expect(spans.single.lastKey, isNull);
    });

    test('a phase ends the day before the next one starts', () {
      final spans = phaseSpans([
        phase('a', PhaseKind.bulk, 20260903),
        phase('b', PhaseKind.cut, 20260917),
      ]);
      expect(spans.first.lastKey, 20260916);
      expect(spans.last.lastKey, isNull);
    });

    test('the day before is a calendar day, across a month end', () {
      final spans = phaseSpans([
        phase('a', PhaseKind.bulk, 20260903),
        phase('b', PhaseKind.cut, 20261001),
      ]);
      expect(spans.first.lastKey, 20260930);
    });

    test('and across a year end', () {
      final spans = phaseSpans([
        phase('a', PhaseKind.cut, 20261201),
        phase('b', PhaseKind.maintenance, 20270101),
      ]);
      expect(spans.first.lastKey, 20261231);
    });

    test('a cleared phase ends on its own end day', () {
      final spans = phaseSpans([
        phase('a', PhaseKind.bulk, 20260903, end: 20260910),
        phase('b', PhaseKind.cut, 20260917),
      ]);
      expect(spans.first.lastKey, 20260910);
    });

    test('the next start wins over an end day after it', () {
      final spans = phaseSpans([
        phase('a', PhaseKind.bulk, 20260903, end: 20260920),
        phase('b', PhaseKind.cut, 20260917),
      ]);
      expect(spans.first.lastKey, 20260916);
    });

    test('a phase cleared on its start day covers that one day', () {
      final spans =
          phaseSpans([phase('a', PhaseKind.cut, 20260903, end: 20260903)]);
      expect(spans.single.lastKey, 20260903);
      expect(spans.single.covers(20260903), isTrue);
      expect(spans.single.covers(20260904), isFalse);
    });

    test('rows arriving in any order are read in calendar order', () {
      final spans = phaseSpans([
        phase('b', PhaseKind.cut, 20260917),
        phase('a', PhaseKind.bulk, 20260903),
      ]);
      expect([for (final s in spans) s.kind], [PhaseKind.bulk, PhaseKind.cut]);
    });

    test('two phases on one day: the later id covers it, on every phone', () {
      final spans = phaseSpans([
        phase('0b', PhaseKind.cut, 20260903),
        phase('0a', PhaseKind.bulk, 20260903),
      ]);
      expect(spans.single.phase.id, '0b');
    });
  });

  group('phaseOn and currentPhase — which phase a day ran in', () {
    final spans = phaseSpans([
      phase('a', PhaseKind.bulk, 20260903, end: 20260910),
      phase('b', PhaseKind.cut, 20260917),
    ]);

    test('a day before any phase ran in none', () {
      expect(phaseOn(20260902, spans), isNull);
    });

    test('the start day and the end day are both inside', () {
      expect(phaseOn(20260903, spans)!.kind, PhaseKind.bulk);
      expect(phaseOn(20260910, spans)!.kind, PhaseKind.bulk);
    });

    test('the days between a clear and the next phase ran in none', () {
      expect(phaseOn(20260911, spans), isNull);
      expect(phaseOn(20260916, spans), isNull);
    });

    test('a running phase covers every day from its start', () {
      expect(phaseOn(20260917, spans)!.kind, PhaseKind.cut);
      expect(phaseOn(20271231, spans)!.kind, PhaseKind.cut);
    });

    test('a phase cleared yesterday is not current today', () {
      final cleared =
          phaseSpans([phase('a', PhaseKind.cut, 20260903, end: 20260930)]);
      expect(currentPhase(cleared, todayKey: 20260930), isNotNull);
      expect(currentPhase(cleared, todayKey: 20261001), isNull);
    });
  });

  group('phaseWeek — the pill', () {
    final span = phaseSpans([phase('a', PhaseKind.cut, 20260903)]).single;

    test('the start day is week 1, and so is the sixth day after it', () {
      expect(phaseWeek(span, todayKey: 20260903), 1);
      expect(phaseWeek(span, todayKey: 20260909), 1);
    });

    test('the seventh day after it is week 2', () {
      expect(phaseWeek(span, todayKey: 20260910), 2);
    });

    test('forty-eight days in is week 7', () {
      expect(phaseWeek(span, todayKey: 20261021), 7);
    });
  });

  group('dominantPhase — the tint a cycle takes', () {
    final spans = phaseSpans([
      phase('a', PhaseKind.bulk, 20260903, end: 20260910),
      phase('b', PhaseKind.cut, 20260914),
    ]);

    test('a cycle with no sessions has no tint', () {
      expect(dominantPhase(const [], spans), isNull);
    });

    test('a cycle trained in one phase takes it', () {
      expect(dominantPhase([20260904, 20260906, 20260908], spans),
          PhaseKind.bulk);
    });

    test('most sessions decide it', () {
      expect(dominantPhase([20260908, 20260909, 20260915], spans),
          PhaseKind.bulk);
    });

    test('most sessions in no phase leave the cycle untinted', () {
      expect(dominantPhase([20260901, 20260902, 20260904], spans), isNull);
    });

    test('a cycle straddling a change and split evenly takes the phase it '
        'ended in', () {
      expect(
        dominantPhase([20260908, 20260909, 20260915, 20260916], spans),
        PhaseKind.cut,
      );
    });

    test('the order sessions arrive in does not move the tie', () {
      expect(
        dominantPhase([20260916, 20260908, 20260915, 20260909], spans),
        PhaseKind.cut,
      );
    });

    test('an even split with no phase at the end has no tint', () {
      expect(dominantPhase([20260909, 20260912], spans), isNull);
    });

    test('an even split with no phase at the start takes the phase', () {
      expect(dominantPhase([20260902, 20260904], spans), PhaseKind.bulk);
    });

    test('a three-way tie takes the phase of the last session', () {
      final three = phaseSpans([
        phase('a', PhaseKind.maintenance, 20260901),
        phase('b', PhaseKind.bulk, 20260905),
        phase('c', PhaseKind.cut, 20260910),
      ]);
      expect(dominantPhase([20260902, 20260906, 20260911], three),
          PhaseKind.cut);
    });

    test('a bulk declared twice is counted as one colour', () {
      final twice = phaseSpans([
        phase('a', PhaseKind.bulk, 20260901),
        phase('b', PhaseKind.bulk, 20260910),
        phase('c', PhaseKind.cut, 20260920),
      ]);
      expect(dominantPhase([20260905, 20260912, 20260921], twice),
          PhaseKind.bulk);
    });

    test('the open cycle is tinted by the sessions it has so far', () {
      expect(dominantPhase([20260915], spans), PhaseKind.cut);
    });
  });

  group('phaseBodyweightChange — since the start, and each week', () {
    final running = phaseSpans([phase('a', PhaseKind.bulk, 20260903)]).single;

    test('a phase with no weigh-in inside it has no figures', () {
      expect(
        phaseBodyweightChange(running, [w(20260901, 80)], todayKey: 20260920),
        isNull,
      );
      expect(phaseBodyweightChange(running, const [], todayKey: 20260920),
          isNull);
    });

    test('the first day is read between the weigh-ins either side of it', () {
      // 80 on 1 Sep and 81 on 11 Sep put 3 Sep at 80.2; 82 on 17 Sep is
      // 1.8 up over the 14 days from the start, 0.9 a week.
      final change = phaseBodyweightChange(
        running,
        [w(20260901, 80), w(20260911, 81), w(20260917, 82)],
        todayKey: 20260920,
      )!;
      expect(change.sinceStart, closeTo(1.8, 1e-9));
      expect(change.perWeek, closeTo(0.9, 1e-9));
    });

    test('with nothing on or before the start, the first weigh-in in the '
        'phase is the baseline and dates the rate', () {
      // 80 on 5 Sep to 79 on 15 Sep: down 1 over 10 days, 0.7 a week.
      final change = phaseBodyweightChange(
        running,
        [w(20260905, 80), w(20260915, 79)],
        todayKey: 20260920,
      )!;
      expect(change.sinceStart, closeTo(-1.0, 1e-9));
      expect(change.perWeek, closeTo(-0.7, 1e-9));
    });

    test('six days is too few for a rate, and the change still stands', () {
      final change = phaseBodyweightChange(
        running,
        [w(20260905, 80), w(20260911, 80.6)],
        todayKey: 20260920,
      )!;
      expect(change.sinceStart, closeTo(0.6, 1e-9));
      expect(change.perWeek, isNull);
    });

    test('seven days is a rate, equal to the change', () {
      final change = phaseBodyweightChange(
        running,
        [w(20260905, 80), w(20260912, 80.6)],
        todayKey: 20260920,
      )!;
      expect(change.perWeek, closeTo(0.6, 1e-9));
    });

    test('a single weigh-in on the first day is no change at all', () {
      final change = phaseBodyweightChange(
        running,
        [w(20260903, 80)],
        todayKey: 20260920,
      )!;
      expect(change.sinceStart, 0);
      expect(change.perWeek, isNull);
    });

    test('a cleared phase stops reading at its end', () {
      final cleared =
          phaseSpans([phase('a', PhaseKind.cut, 20260903, end: 20260910)])
              .single;
      final change = phaseBodyweightChange(
        cleared,
        [w(20260903, 80), w(20260910, 79), w(20260915, 75)],
        todayKey: 20260920,
      )!;
      expect(change.sinceStart, closeTo(-1.0, 1e-9));
    });

    test('a weigh-in dated after today is not read', () {
      final change = phaseBodyweightChange(
        running,
        [w(20260903, 80), w(20260910, 81), w(20260925, 90)],
        todayKey: 20260920,
      )!;
      expect(change.sinceStart, closeTo(1.0, 1e-9));
    });
  });

  group('plannedLengthPassed — the first prompt', () {
    test('twelve weeks from 3 Sep are up on 26 Nov, the 85th day', () {
      final span =
          phaseSpans([phase('a', PhaseKind.cut, 20260903, weeks: 12)]).single;
      expect(plannedLengthPassed(span, todayKey: 20261125), isFalse);
      expect(plannedLengthPassed(span, todayKey: 20261126), isTrue);
    });

    test('eight weeks are up on the 57th day', () {
      final span =
          phaseSpans([phase('a', PhaseKind.bulk, 20260903, weeks: 8)]).single;
      expect(plannedLengthPassed(span, todayKey: 20261028), isFalse);
      expect(plannedLengthPassed(span, todayKey: 20261029), isTrue);
    });

    test('an open-ended phase is never up', () {
      final span = phaseSpans([phase('a', PhaseKind.cut, 20260903)]).single;
      expect(plannedLengthPassed(span, todayKey: 20271231), isFalse);
    });

    test('a phase that is no longer current is never asked about', () {
      final spans = phaseSpans([
        phase('a', PhaseKind.cut, 20260903, weeks: 8),
        phase('b', PhaseKind.maintenance, 20261001),
      ]);
      expect(plannedLengthPassed(spans.first, todayKey: 20261201), isFalse);

      final cleared = phaseSpans(
        [phase('a', PhaseKind.cut, 20260903, weeks: 8, end: 20261001)],
      ).single;
      expect(plannedLengthPassed(cleared, todayKey: 20261201), isFalse);
    });
  });

  group('weighInsAgainstPhase — the second prompt', () {
    PhaseSpan running(PhaseKind kind, {int start = 20260801, int? kept}) =>
        phaseSpans([phase('a', kind, start, kept: kept)]).single;

    /// Weigh-ins on [days] moving by [perWeek] kilograms a week from 80,
    /// day 0 being the first of them.
    List<({int dayKey, double weightKg})> line(
      List<int> days,
      List<int> offsets,
      double perWeek,
    ) =>
        [
          for (var i = 0; i < days.length; i++)
            w(days[i], 80 + perWeek * offsets[i] / 7),
        ];

    // 1 Sep is today; the window opens 21 days back, on 11 Aug.
    const today = 20260901;
    const days = [20260812, 20260819, 20260826, 20260901];
    const offsets = [0, 7, 14, 20];

    test('a bulk losing weight for three weeks is asked about', () {
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk),
          line(days, offsets, -0.2),
          todayKey: today,
        ),
        WeightDirection.falling,
      );
    });

    test('a bulk gaining weight is not', () {
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk),
          line(days, offsets, 0.3),
          todayKey: today,
        ),
        isNull,
      );
    });

    test('a bulk inside the noise floor is not', () {
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk),
          line(days, offsets, -0.09),
          todayKey: today,
        ),
        isNull,
      );
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk),
          line(days, offsets, -0.11),
          todayKey: today,
        ),
        WeightDirection.falling,
      );
    });

    test('a cut gaining weight is asked about, and one losing is not', () {
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.cut),
          line(days, offsets, 0.11),
          todayKey: today,
        ),
        WeightDirection.rising,
      );
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.cut),
          line(days, offsets, -0.5),
          todayKey: today,
        ),
        isNull,
      );
    });

    test('maintenance is asked about past a quarter kilogram a week either '
        'way', () {
      final maintenance = running(PhaseKind.maintenance);
      expect(
        weighInsAgainstPhase(maintenance, line(days, offsets, 0.24),
            todayKey: today),
        isNull,
      );
      expect(
        weighInsAgainstPhase(maintenance, line(days, offsets, 0.26),
            todayKey: today),
        WeightDirection.rising,
      );
      expect(
        weighInsAgainstPhase(maintenance, line(days, offsets, -0.24),
            todayKey: today),
        isNull,
      );
      expect(
        weighInsAgainstPhase(maintenance, line(days, offsets, -0.26),
            todayKey: today),
        WeightDirection.falling,
      );
    });

    test('readings spanning 17 days are too close together, 18 are enough',
        () {
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk),
          line([20260815, 20260822, 20260901], [0, 7, 17], -0.5),
          todayKey: today,
        ),
        isNull,
      );
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk),
          line([20260814, 20260822, 20260901], [0, 8, 18], -0.5),
          todayKey: today,
        ),
        WeightDirection.falling,
      );
    });

    test('two readings are too few, however far apart', () {
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk),
          line([20260812, 20260901], [0, 20], -1),
          todayKey: today,
        ),
        isNull,
      );
    });

    test('readings older than three weeks are not read', () {
      // Falling hard until 10 Aug and flat since: the window sees the flat.
      final log = [
        w(20260720, 84),
        w(20260801, 82),
        w(20260810, 80),
        ...line(days, offsets, 0),
      ];
      expect(
        weighInsAgainstPhase(running(PhaseKind.bulk, start: 20260701), log,
            todayKey: today),
        isNull,
      );
    });

    test('readings from before the phase began are not read', () {
      // A cut that ran until 20 Aug, then a bulk: the bulk has 12 days.
      expect(
        weighInsAgainstPhase(
          running(PhaseKind.bulk, start: 20260820),
          line(days, offsets, -0.5),
          todayKey: today,
        ),
        isNull,
      );
    });

    test('Keep going holds until three more weeks have run against the phase',
        () {
      final kept = running(PhaseKind.bulk, kept: 20260820);
      final log = line(
        [20260812, 20260820, 20260826, 20260901, 20260907],
        [0, 8, 14, 20, 26],
        -0.3,
      );
      expect(weighInsAgainstPhase(kept, log, todayKey: today), isNull,
          reason: 'twelve days since Keep going');
      expect(weighInsAgainstPhase(kept, log, todayKey: 20260907),
          WeightDirection.falling,
          reason: 'eighteen days since Keep going');
    });

    test('a phase that is not current is never asked about', () {
      final cleared =
          phaseSpans([phase('a', PhaseKind.bulk, 20260801, end: 20260831)])
              .single;
      expect(
        weighInsAgainstPhase(cleared, line(days, offsets, -0.5),
            todayKey: today),
        isNull,
      );
    });

    test('one heavy morning at the end does not hide three weeks of loss', () {
      final log = [
        w(20260812, 80),
        w(20260815, 79.8),
        w(20260819, 79.7),
        w(20260822, 79.5),
        w(20260826, 79.3),
        w(20260829, 79.2),
        w(20260901, 80.1),
      ];
      expect(
        weighInsAgainstPhase(running(PhaseKind.bulk), log, todayKey: today),
        WeightDirection.falling,
      );
    });
  });

  group('phaseSparkline — the Phase card\'s graph', () {
    const today = 20261016;
    final spans = phaseSpans([
      phase('a', PhaseKind.bulk, 20260801),
      phase('b', PhaseKind.cut, 20261001),
    ]);
    final cut = spans.last;

    test('a phase younger than twelve weeks is drawn with the weeks before',
        () {
      final data = phaseSparkline(cut, spans, const [], todayKey: today);
      expect(data.fromKey, 20260725);
      expect(data.toKey, today);
      expect(data.days, phaseSparklineMinimumDays);
    });

    test('a phase older than twelve weeks is drawn from its start', () {
      final old = phaseSpans([phase('a', PhaseKind.cut, 20260601)]);
      final data = phaseSparkline(old.single, old, const [], todayKey: today);
      expect(data.fromKey, 20260601);
      expect(data.bands.single.fromDay, 0);
      expect(data.bands.single.toDay, data.days);
    });

    test('each phase is tinted over the days it covered, and no others', () {
      final data = phaseSparkline(cut, spans, const [], todayKey: today);
      expect(data.bands, [
        (kind: PhaseKind.bulk, fromDay: 7, toDay: 68),
        (kind: PhaseKind.cut, fromDay: 68, toDay: 84),
      ]);
      expect(data.kinds, [PhaseKind.bulk, PhaseKind.cut]);
    });

    test('a phase declared twice is named in the legend once', () {
      final again = phaseSpans([
        phase('a', PhaseKind.cut, 20260801),
        phase('b', PhaseKind.maintenance, 20260901),
        phase('c', PhaseKind.cut, 20261001),
      ]);
      final data =
          phaseSparkline(again.last, again, const [], todayKey: today);
      expect(data.kinds, [PhaseKind.cut, PhaseKind.maintenance]);
    });

    test('weeks are Monday weeks, at the middle of their days in the window',
        () {
      final data = phaseSparkline(
        cut,
        spans,
        [w(20261005, 80), w(20261007, 82), w(20261012, 79), w(today, 78)],
        todayKey: today,
      );
      expect(data.weeks, [
        (day: (72 + 78 + 1) / 2, weightKg: 81.0),
        // The current week runs past today, so its middle is today's side.
        (day: (79 + 83 + 1) / 2, weightKg: 78.5),
      ]);
    });

    test('a week with no weigh-in is never drawn at zero', () {
      final data = phaseSparkline(
        cut,
        spans,
        [w(20260803, 80), w(today, 78)],
        todayKey: today,
      );
      expect(data.weeks.nonNulls.map((e) => e.weightKg), [80.0, 78.0]);
    });

    test('a single week with no weigh-in is crossed', () {
      // Weighed the weeks of 28 Sep and 12 Oct; the week of 5 Oct had none.
      final data = phaseSparkline(
        cut,
        spans,
        [w(20260929, 80), w(20261013, 79)],
        todayKey: today,
      );
      expect(data.weeks, hasLength(2));
      expect(data.weeks.every((e) => e != null), isTrue);
    });

    test('two or more weeks in a row with no weigh-in break the line', () {
      final data = phaseSparkline(
        cut,
        spans,
        [w(20260803, 80), w(20260922, 79), w(20261013, 78)],
        todayKey: today,
      );
      expect(data.weeks, hasLength(5));
      expect(data.weeks[1], isNull);
      expect(data.weeks[3], isNull);
      expect(data.weeks.last?.weightKg, 78.0);
    });

    test('empty weeks at either end are trimmed, not breaks', () {
      final data = phaseSparkline(
        cut,
        spans,
        [w(20260901, 80), w(20260908, 79)],
        todayKey: today,
      );
      expect(data.weeks, hasLength(2));
      expect(data.weeks.first, isNotNull);
      expect(data.weeks.last, isNotNull);
    });
  });
}
