/// Bulk, cut and maintenance, read off the rows that declare them.
///
/// Every answer here is derived, never stored
/// ([SYNC.md § 4](SYNC.md#4-what-the-server-holds)): which phase a day ran in,
/// which phase is current, which phase a cycle is tinted by, and whether the
/// Phase card asks what comes next. Both phones hold the same rows, so both
/// reach the same answer however the rows arrived, and none of it is sent.
///
/// Day keys are compared directly, which `yyyyMMdd` allows because it sorts
/// in calendar order. Spans between them go through [daysBetweenKeys], because
/// a key is not a day count.
library;

import 'dart:math' as math;

import '../core/ids.dart';
import 'chart_buckets.dart';
import 'enums.dart';
import 'metrics.dart';

/// One declared phase, as plain values.
///
/// The repository maps a `phases` row onto this so nothing in `domain/` reads
/// a drift row ([RULES § 4](RULES.md#4-code)).
class PhaseEntry {
  const PhaseEntry({
    required this.id,
    required this.kind,
    required this.startKey,
    this.plannedWeeks,
    this.endKey,
    this.keptKey,
  });

  final String id;
  final PhaseKind kind;

  /// The day the phase starts.
  final int startKey;

  /// 8, 12 or 16, or null for open-ended.
  final int? plannedWeeks;

  /// The last day of a cleared phase, or null while nothing has cleared it.
  final int? endKey;

  /// The day `Keep going` last answered the weigh-in prompt, or null.
  final int? keptKey;
}

/// A phase and the days it actually covers, once its successor is known.
class PhaseSpan {
  const PhaseSpan(this.phase, {required this.lastKey});

  final PhaseEntry phase;

  /// The last day covered, inclusive, or null for a phase still running.
  final int? lastKey;

  PhaseKind get kind => phase.kind;
  int get startKey => phase.startKey;

  /// Whether [dayKey] falls inside the span.
  bool covers(int dayKey) =>
      dayKey >= startKey && (lastKey == null || dayKey <= lastKey!);
}

/// Every live phase as the stretch of days it covers, oldest first.
///
/// A phase runs from its start until the day before the next phase starts, or
/// to its own end day if a `Clear phase` came first. The end is never read off
/// the next row's columns and never written to this one, which is what lets
/// two phones that each started a phase merge into one sequence without
/// either row being edited ([SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does),
/// row 20).
///
/// Two phases on one start day cannot both be live — `idx_phases_start_live`
/// refuses it — but this is also handed rows the schema did not vet, so the
/// case is decided rather than assumed away: ordered by id, the later one
/// covers the day and the earlier covers nothing. Ids are UUID v7, so that is
/// the later declaration on every phone.
List<PhaseSpan> phaseSpans(Iterable<PhaseEntry> phases) {
  final ordered = [...phases]..sort((a, b) {
      final byStart = a.startKey.compareTo(b.startKey);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });

  final spans = <PhaseSpan>[];
  for (var i = 0; i < ordered.length; i++) {
    final phase = ordered[i];
    final nextStart = i + 1 < ordered.length ? ordered[i + 1].startKey : null;
    final beforeNext = nextStart == null
        ? null
        : dayKeyOf(daysBefore(dateFromDayKey(nextStart), 1));
    final ownEnd = phase.endKey;
    final last = switch ((beforeNext, ownEnd)) {
      (null, null) => null,
      (final int a, null) => a,
      (null, final int b) => b,
      (final int a, final int b) => math.min(a, b),
    };
    if (last != null && last < phase.startKey) continue;
    spans.add(PhaseSpan(phase, lastKey: last));
  }
  return spans;
}

/// The phase [dayKey] ran in, or null for a day no phase covers.
PhaseSpan? phaseOn(int dayKey, List<PhaseSpan> spans) {
  for (final span in spans.reversed) {
    if (span.startKey <= dayKey) return span.covers(dayKey) ? span : null;
  }
  return null;
}

/// The phase the Phase card shows: the one today falls in, or null.
///
/// A cleared phase is not current from the day after its end, which is how
/// Home returns to the card's empty state.
PhaseSpan? currentPhase(List<PhaseSpan> spans, {required int todayKey}) =>
    phaseOn(todayKey, spans);

/// The week of its phase [todayKey] falls in, counting the start day's week
/// as week 1.
///
/// What the pill reads, `Week 7 of 12`. Calendar days, so a phase started on a
/// Thursday turns its week on Thursdays rather than on Mondays.
int phaseWeek(PhaseSpan span, {required int todayKey}) =>
    daysBetweenKeys(span.startKey, todayKey) ~/ 7 + 1;

/// A phase's name as the app writes it: `Bulk`, `Cut` or `Maintenance`.
extension PhaseKindName on PhaseKind {
  String get label => switch (this) {
        PhaseKind.bulk => 'Bulk',
        PhaseKind.cut => 'Cut',
        PhaseKind.maintenance => 'Maintenance',
      };
}

/// The shortest stretch the Phase card's sparkline covers: twelve weeks.
///
/// A phase younger than that is drawn with the weeks before it, so a cut a
/// fortnight old is seen against the bulk it followed rather than as two
/// points ([THEME → Phase card](THEME.md#phase-card)).
const phaseSparklineMinimumDays = 84;

/// What the Phase card's sparkline draws, as plain values.
///
/// Positions are in days from [fromKey], so the painter maps one number to
/// one pixel column and never reads a calendar. [weeks] are means of each
/// week's weigh-ins in kilograms, oldest first, placed at the middle of the
/// days the week shares with the window. A single week with no weigh-in is
/// absent and the line crosses it; a null is a break, where two or more weeks
/// in a row had none, as every line chart folds them ([lineBuckets]).
/// [bands] are the stretches each phase covers, `toDay` exclusive.
class PhaseSparklineData {
  const PhaseSparklineData({
    required this.fromKey,
    required this.toKey,
    required this.weeks,
    required this.bands,
  });

  final int fromKey;
  final int toKey;
  final List<({double day, double weightKg})?> weeks;
  final List<({PhaseKind kind, int fromDay, int toDay})> bands;

  /// Days the window covers, both ends included.
  int get days => daysBetweenKeys(fromKey, toKey) + 1;

  /// The phases the sparkline shows, in the order they appear, each once:
  /// what its legend names.
  List<PhaseKind> get kinds => [
        for (final band in bands) band.kind,
      ].fold(<PhaseKind>[], (seen, k) => seen.contains(k) ? seen : [...seen, k]);
}

/// The Phase card's sparkline for [current]: bodyweight from the phase's
/// start, or over the last [phaseSparklineMinimumDays] when the phase is
/// younger, folded into weeks, over the phases each stretch ran in.
///
/// Weeks are Monday weeks, as every chart in the app folds them, and a week is
/// the mean of its weigh-ins because the mean of a week of weigh-ins is a
/// weigh-in. Days no phase covered carry no band.
PhaseSparklineData phaseSparkline(
  PhaseSpan current,
  List<PhaseSpan> spans,
  List<({int dayKey, double weightKg})> log, {
  required int todayKey,
}) {
  final today = dateFromDayKey(todayKey);
  final floor = dayKeyOf(daysBefore(today, phaseSparklineMinimumDays - 1));
  final fromKey = math.min(current.startKey, floor);
  final from = dateFromDayKey(fromKey);

  // Broken where the full charts break: a straight line across a month with
  // no weigh-in draws a trend nobody measured.
  final weeks = [
    for (final bucket in lineBuckets(bucketize(
      rows: [for (final e in log) (dayKey: e.dayKey, value: e.weightKg)],
      by: Granularity.weekly,
      from: from,
      to: today,
    )))
      if (bucket == null)
        null
      else
        (
          // The middle of the days the week shares with the window: the
          // first week may start before it, and the last runs past today.
          day: (math.max(0, daysBetween(from, bucket.start)) +
                  math.min(
                    daysBetween(from, bucket.end),
                    daysBetween(from, today),
                  ) +
                  1) /
              2,
          weightKg: bucket.value!,
        ),
  ];

  final bands = [
    for (final span in spans)
      if (span.startKey <= todayKey && (span.lastKey ?? todayKey) >= fromKey)
        (
          kind: span.kind,
          fromDay: daysBetweenKeys(fromKey, math.max(span.startKey, fromKey)),
          toDay: daysBetweenKeys(
                fromKey,
                math.min(span.lastKey ?? todayKey, todayKey),
              ) +
              1,
        ),
  ];

  return PhaseSparklineData(
    fromKey: fromKey,
    toKey: todayKey,
    weeks: weeks,
    bands: bands,
  );
}

/// The phase most of a cycle's sessions ran in, or null for no tint.
///
/// [sessionDays] holds the day of each session the cycle holds so far, so the
/// open cycle is tinted by the sessions it has. Counted by kind rather than by
/// row, because the tint is the kind's: a bulk declared again after a bulk is
/// still one colour. A session on a day no phase covers counts towards having
/// no phase, and it can win: a cycle mostly trained before any phase was set
/// is a cycle the chart cannot honestly tint.
///
/// A tie goes to the phase the cycle ended in
/// ([THEME → The cycle axis](THEME.md#the-cycle-axis)): of the tied answers,
/// the one held by the latest session. A cycle straddling a change therefore
/// reads as the phase it finished in, which is the phase its last reading was
/// taken under. A day falls in one phase only, so two tied answers never
/// share a latest day and the tie always resolves.
PhaseKind? dominantPhase(Iterable<int> sessionDays, List<PhaseSpan> spans) =>
    mostCommonPhase(sessionPhases(sessionDays, spans));

/// One session's day and the phase it ran in.
typedef SessionPhase = ({int dayKey, PhaseKind? kind});

/// Each of [sessionDays] with the phase it ran in, or null where none did.
///
/// What a cycle keeps of the phases, so a run of cycles can be tinted by the
/// sessions of all of them together without the spans travelling with it.
List<SessionPhase> sessionPhases(
  Iterable<int> sessionDays,
  List<PhaseSpan> spans,
) =>
    [
      for (final day in sessionDays)
        (dayKey: day, kind: phaseOn(day, spans)?.kind),
    ];

/// The phase most of [sessions] ran in, with a tie going to the one the
/// latest session held, as [dominantPhase] describes.
///
/// Separate so a block under `All` is tinted by the same count over every
/// session of its cycles ([THEME → The cycle axis](THEME.md#the-cycle-axis)).
PhaseKind? mostCommonPhase(Iterable<SessionPhase> sessions) {
  final ordered = [...sessions]..sort((a, b) => a.dayKey.compareTo(b.dayKey));
  if (ordered.isEmpty) return null;

  final counts = <PhaseKind?, int>{};
  final latest = <PhaseKind?, int>{};
  for (final session in ordered) {
    counts[session.kind] = (counts[session.kind] ?? 0) + 1;
    latest[session.kind] = session.dayKey;
  }

  final most = counts.values.reduce(math.max);
  final tied = [
    for (final entry in counts.entries)
      if (entry.value == most) entry.key,
  ];
  if (tied.length == 1) return tied.single;

  tied.sort((a, b) => latest[a]!.compareTo(latest[b]!));
  return tied.last;
}

/// The fewest days between the first and last reading before a weekly rate
/// is stated.
///
/// A rate drawn over three days is a scale's daily noise multiplied by seven.
/// THEME's Phase card prints `——` below it: `Each week` needs weigh-ins at
/// least a week apart since the start.
const phaseRateMinimumDays = 7;

/// How bodyweight has moved during a phase: in total, and per week.
///
/// [sinceStart] is the latest weigh-in inside the phase less the bodyweight on
/// the phase's first day. That first-day figure is [bodyweightOn] the start,
/// interpolated between the readings either side, whenever some reading falls
/// on or before the start; with none, the first reading inside the phase
/// stands in for it and is dated by its own day. Either way the baseline is a
/// weight that was actually logged or lies between two that were, never the
/// assumed 60 kg.
///
/// [perWeek] is that change over the days from the baseline to the latest
/// reading, scaled to seven, and null below [phaseRateMinimumDays].
///
/// Null altogether when the phase holds no weigh-in up to [todayKey].
({double sinceStart, double? perWeek})? phaseBodyweightChange(
  PhaseSpan span,
  List<({int dayKey, double weightKg})> log, {
  required int todayKey,
}) {
  final ordered = orderedByDay(log);
  final last = span.lastKey == null ? todayKey : math.min(span.lastKey!, todayKey);
  final inside = [
    for (final entry in ordered)
      if (entry.dayKey >= span.startKey && entry.dayKey <= last) entry,
  ];
  if (inside.isEmpty) return null;

  final hasEarlier = ordered.first.dayKey <= span.startKey;
  final baselineDay = hasEarlier ? span.startKey : inside.first.dayKey;
  final baselineKg = hasEarlier
      ? bodyweightOnOrdered(span.startKey, ordered)
      : inside.first.weightKg;

  final latest = inside.last;
  final change = latest.weightKg - baselineKg;
  final days = daysBetweenKeys(baselineDay, latest.dayKey);
  return (
    sinceStart: change,
    perWeek: days >= phaseRateMinimumDays ? change / days * 7 : null,
  );
}

/// Whether the current phase has run its planned length.
///
/// True from the day after the last day of the planned weeks: a 12-week phase
/// started on 3 September is up on 26 November, its 85th day. False for an
/// open-ended phase, which is what `Keep going` makes of it so the question is
/// answered once, and false for any phase that is not current, since only the
/// Phase card asks and it asks about today.
bool plannedLengthPassed(PhaseSpan span, {required int todayKey}) {
  final weeks = span.phase.plannedWeeks;
  if (weeks == null || !span.covers(todayKey)) return false;
  return daysBetweenKeys(span.startKey, todayKey) >= weeks * 7;
}

/// Which way the weigh-ins are moving when they run against the phase.
enum WeightDirection { rising, falling }

/// How far back the weigh-in prompt looks: three weeks.
const againstPhaseWindowDays = 21;

/// How many of those days the readings must actually span.
///
/// Three weeks "or about": nobody weighs in on exactly the first and last day
/// of a window, and a person weighing every third or fourth day would
/// otherwise rarely qualify at all. Eighteen days leaves room for one missed
/// weigh-in at either end and still covers more than two and a half weeks.
const againstPhaseMinimumSpanDays = 18;

/// How many readings the window needs, so two noisy mornings cannot decide it.
const againstPhaseMinimumReadings = 3;

/// The weekly change, in kilograms, past which a bulk is losing or a cut is
/// gaining.
///
/// Not zero, because a fitted line over a few readings is never exactly flat:
/// a tenth of a kilogram a week is under half a kilogram over the window,
/// inside a single morning's water.
const againstPhaseNoiseKgPerWeek = 0.1;

/// The weekly change, in kilograms, past which maintenance is drifting.
///
/// Wider than the noise floor, because maintenance is a band rather than a
/// direction: a quarter of a kilogram a week is about a kilogram a month,
/// which is no longer maintaining.
const maintenanceDriftKgPerWeek = 0.25;

/// Whether the weigh-ins have run against the current phase for about three
/// weeks, and which way.
///
/// Losing on a bulk, gaining on a cut, or drifting either way on maintenance.
/// The readings considered are the current phase's, within the last
/// [againstPhaseWindowDays] to [todayKey], and only those after `Keep going`
/// was last tapped: that answer stands until three more weeks of weigh-ins
/// run against the phase. They must number [againstPhaseMinimumReadings] and
/// span [againstPhaseMinimumSpanDays].
///
/// The direction is the slope of a least-squares line through those readings
/// rather than the last less the first, so a single heavy morning at either
/// end cannot raise or silence the question.
///
/// Null when the phase is not current, when the readings are too few or too
/// close together, or when they agree with the phase.
WeightDirection? weighInsAgainstPhase(
  PhaseSpan span,
  List<({int dayKey, double weightKg})> log, {
  required int todayKey,
}) {
  if (!span.covers(todayKey)) return null;

  final windowStart =
      dayKeyOf(daysBefore(dateFromDayKey(todayKey), againstPhaseWindowDays));
  final kept = span.phase.keptKey;
  final from = [
    span.startKey,
    windowStart,
    ?kept,
  ].reduce(math.max);

  final readings = [
    for (final entry in orderedByDay(log))
      if (entry.dayKey >= from && entry.dayKey <= todayKey) entry,
  ];
  if (readings.length < againstPhaseMinimumReadings) return null;
  final first = readings.first.dayKey;
  if (daysBetweenKeys(first, readings.last.dayKey) <
      againstPhaseMinimumSpanDays) {
    return null;
  }

  final xs = [for (final r in readings) daysBetweenKeys(first, r.dayKey)];
  final ys = [for (final r in readings) r.weightKg];
  final perWeek = _slope(xs, ys) * 7;

  return switch (span.kind) {
    PhaseKind.bulk =>
      perWeek <= -againstPhaseNoiseKgPerWeek ? WeightDirection.falling : null,
    PhaseKind.cut =>
      perWeek >= againstPhaseNoiseKgPerWeek ? WeightDirection.rising : null,
    PhaseKind.maintenance => perWeek >= maintenanceDriftKgPerWeek
        ? WeightDirection.rising
        : perWeek <= -maintenanceDriftKgPerWeek
            ? WeightDirection.falling
            : null,
  };
}

/// The least-squares slope of [ys] over [xs], per unit of x.
///
/// The caller guarantees the xs are not all equal, since it requires them to
/// span [againstPhaseMinimumSpanDays].
double _slope(List<int> xs, List<double> ys) {
  final n = xs.length;
  final meanX = xs.reduce((a, b) => a + b) / n;
  final meanY = ys.reduce((a, b) => a + b) / n;
  var covariance = 0.0;
  var variance = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - meanX;
    covariance += dx * (ys[i] - meanY);
    variance += dx * dx;
  }
  return covariance / variance;
}
