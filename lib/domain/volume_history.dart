/// Weekly set counts over a span, which is the question `muscle_volume.dart`
/// cannot answer.
///
/// That file counts the last seven days and hands Today six bars. This one
/// takes the same counted sets and lays them out week by week, so "have I
/// trained hamstrings enough lately" becomes "have I ever". The rules about
/// *what counts* are not repeated here — [countsAsVolume] and the repository's
/// filters own that, and this only decides which week a counted set lands in.
///
/// Pure, and tested without a database (RULES § 7).
library;

import '../core/ids.dart';
import 'chart_buckets.dart';
import 'chart_density.dart';
import 'enums.dart';
import 'muscle_volume.dart';

/// The Monday of the week containing [date].
///
/// Monday because `Consistency.thisWeek` already draws its week that way, and
/// two week rules in one app means the same Sunday session lands in different
/// weeks on two screens. `weekday` is 1 on Monday, so this goes back nothing on
/// a Monday and six days on a Sunday.
///
/// **The result is a map key**, which is what makes the calendar-named form
/// load-bearing rather than tidy. [computeVolumeHistory] builds `indexOfWeek`
/// by walking Mondays as dates and then looks this up in it; `bucketize` does
/// the same through `bucketStartOf`. Both drop a row whose key is absent, with
/// `if (i == null) continue;` and no complaint. Going back a `Duration` instead
/// returns 23:00 or 01:00 of a neighbouring day whenever a clock change falls
/// inside the week, so the lookup misses and a week of training silently
/// vanishes from the chart.
DateTime weekStartOf(DateTime date) => daysBefore(date, date.weekday - 1);

/// One week of one series.
class VolumeWeek {
  const VolumeWeek({required this.start, required this.sets});

  /// Monday of the week, at midnight local.
  final DateTime start;

  /// The hard sets performed in the week.
  ///
  /// Zero is a value rather than a gap: an untrained week must retain its
  /// position in the list or its absence is not visible.
  final int sets;

  /// The last day the week covers, for a readout that names a span.
  DateTime get end => daysBefore(start, -6);
}

/// One bar: a stretch of weeks folded into the rate they averaged.
///
/// **The value is sets per week at every granularity**, never sets in the
/// bucket. A monthly bar reading `62` and a weekly one reading `14` are the same
/// training drawn twice, and switching between them would rescale the axis by
/// four and read as a different chart rather than as a zoom. Holding the unit
/// still is what makes the granularity control a smoothing control — and it is
/// the unit the whole feature already speaks, because "sets per week" is how a
/// training plan is written.
class VolumeBar {
  const VolumeBar({
    required this.start,
    required this.end,
    required this.weeks,
    required this.totalSets,
  });

  /// Monday of the first week in the bar.
  final DateTime start;

  /// The last day the bar covers.
  final DateTime end;

  /// The number of weeks aggregated into this bar, including untrained weeks,
  /// for the reason given by [VolumeSeries.averagePerWeek]. Never zero: a bar
  /// covering no weeks is not rendered.
  final int weeks;

  final int totalSets;

  /// What the bar's height means.
  double get setsPerWeek => weeks == 0 ? 0 : totalSets / weeks;

  /// Whether any training was recorded in the period.
  ///
  /// An empty bar is still rendered, as its full-height empty track, because an
  /// untrained period that collapses is not visible.
  bool get isEmpty => totalSets == 0;
}

/// The fold a chart draws [weeks] weekly marks at: [chosen], coarsened until
/// the weeks fit (see [autoGranularityFor]) and never refined below it.
///
/// The weeks are counted as weeks whatever was chosen. Counted as months, as
/// the charts used to, five years of weeks read as twenty-one years of months
/// and folded into six yearly bars.
Granularity foldForWeeks(int weeks, Granularity chosen) {
  final fits = autoGranularityFor(weeks, Granularity.weekly);
  return fits.index > chosen.index ? fits : chosen;
}

/// The fold a chart [width] logical pixels wide draws [weeks] at: the finest
/// one from [foldForWeeks] onward whose bars each have at least [barMinSlot]
/// of slot, and yearly when none does.
///
/// Folded by width rather than by span, because the same year is fifty-two
/// legible bars across a full-width chart and a texture across half a phone.
/// A tile at a year therefore draws months while the chart it opens onto
/// keeps weeks.
Granularity foldForWidth(
  List<VolumeWeek> weeks,
  Granularity chosen,
  double width,
) {
  final from = foldForWeeks(weeks.length, chosen);
  for (final g in const [Granularity.weekly, Granularity.monthly]) {
    if (g.index < from.index) continue;
    final bars = foldWeeks(weeks, g).length;
    if (bars == 0 || width / bars >= barMinSlot) return g;
  }
  return Granularity.yearly;
}

/// Folds weeks into the bars a chart draws at [by].
///
/// [Granularity.weekly] is the identity: one bar per week, which is what this
/// feature's base unit already was. [Granularity.daily] is not offered and is
/// treated as weekly — a day is not a unit weekly volume has, and "sets per
/// week" of a single Tuesday is a number about nothing.
///
/// Bars are folded from the weeks rather than re-counted from the sets, so
/// every figure on the screen — the bars, the average, the peak — comes off one
/// list and cannot disagree with itself.
List<VolumeBar> foldWeeks(List<VolumeWeek> weeks, Granularity by) {
  if (weeks.isEmpty) return const [];
  if (by == Granularity.weekly || by == Granularity.daily) {
    return [
      for (final w in weeks)
        VolumeBar(start: w.start, end: w.end, weeks: 1, totalSets: w.sets),
    ];
  }

  final out = <VolumeBar>[];
  DateTime? open;
  var count = 0;
  var total = 0;
  VolumeWeek? last;

  void close() {
    final from = open;
    final to = last;
    if (from == null || to == null) return;
    out.add(VolumeBar(
      start: from,
      end: to.end,
      weeks: count,
      totalSets: total,
    ));
  }

  for (final w in weeks) {
    // A week belongs to the bucket its Monday is in — the same rule the bar
    // itself is counted by, so a label can never sit over a week counted
    // somewhere else.
    final bucket = bucketStartOf(w.start, by);
    final from = open;
    if (from == null || bucket != bucketStartOf(from, by)) {
      close();
      open = w.start;
      count = 0;
      total = 0;
    }
    count++;
    total += w.sets;
    last = w;
  }
  close();
  return out;
}

/// A muscle or a region's weeks, with the figures a card prints.
class VolumeSeries {
  const VolumeSeries({required this.label, required this.weeks});

  /// What the series is of — a [MuscleRegion] or a [MuscleGroup] label. Kept as
  /// a string so this class serves both without knowing which it is holding.
  final String label;

  /// Oldest first, one entry per week in the span, no gaps.
  final List<VolumeWeek> weeks;

  /// Sets per week across the span.
  ///
  /// Divided by every week in the span, including untrained weeks. This is what
  /// makes the figure an average over the period rather than an average over
  /// the weeks that happened to contain training. Excluding zero weeks would
  /// report a muscle trained twice in three months as `6.0 per week`.
  double get averagePerWeek {
    if (weeks.isEmpty) return 0;
    return totalSets / weeks.length;
  }

  int get totalSets => weeks.fold(0, (s, w) => s + w.sets);

  /// Weeks with anything in them.
  ///
  /// The necessary companion to [averagePerWeek]. `4.0 per week` over thirteen
  /// weeks describes a different training block depending on whether it was
  /// distributed across every week or concentrated in three, and the average
  /// alone does not distinguish them.
  int get weeksTrained => weeks.where((w) => w.sets > 0).length;

  /// The most recent week, which is the one currently in progress.
  VolumeWeek? get latest => weeks.isEmpty ? null : weeks.last;

  /// The tallest week, which the bars are drawn against.
  ///
  /// Each series is scaled to its own peak rather than to a figure shared
  /// across the grid: core at three sets a week and back at eighteen on one
  /// scale makes core a row of stubs that says nothing about whether core is
  /// steady. Magnitude is what [averagePerWeek] is printed for; these bars are
  /// for shape.
  int get peakSets => weeks.fold(0, (m, w) => w.sets > m ? w.sets : m);

  bool get isEmpty => totalSets == 0;

  /// The weeks folded into the marks a chart draws at [by] — see [foldWeeks].
  List<VolumeBar> bars(Granularity by) => foldWeeks(weeks, by);

  /// The tallest bar at [by], which is what the axis is scaled against. Coarser
  /// averaging flattens the peaks, so this moves with the granularity and the
  /// axis has to be asked again rather than reusing [peakSets].
  double peakPerWeek(Granularity by) => bars(by)
      .fold<double>(0, (m, b) => b.setsPerWeek > m ? b.setsPerWeek : m);
}

/// Every region's weeks over one span, and the muscles under them.
class VolumeHistory {
  const VolumeHistory({
    required this.weekStarts,
    required this.byRegion,
    required this.byMuscle,
  });

  /// Monday of every week in the span, oldest first. Empty only when the span
  /// itself is.
  final List<DateTime> weekStarts;

  /// All six regions, in [MuscleRegion] order. An untrained region is rendered
  /// as a card reading `0.0` rather than omitted.
  final Map<MuscleRegion, VolumeSeries> byRegion;

  /// Every muscle that rolls into a region, in [MuscleGroup] order.
  /// [MuscleGroup.other] is absent: it belongs to no region, exactly as in
  /// [regionOf].
  final Map<MuscleGroup, VolumeSeries> byMuscle;

  int get weekCount => weekStarts.length;

  /// Sets per week across every region — what the screen prints under its
  /// range control.
  double get averagePerWeek {
    if (weekStarts.isEmpty) return 0;
    final total = byRegion.values.fold(0, (s, r) => s + r.totalSets);
    return total / weekStarts.length;
  }

  bool get isEmpty => byRegion.values.every((r) => r.isEmpty);
}

/// Folds day-level counts into weeks.
///
/// [daily] is what the repository counted — hard sets per muscle per day,
/// in any order, already filtered to the span. Days outside [from]..[to] are
/// dropped rather than trusted, so a caller that widens its query without
/// widening its span cannot silently add a week to the average.
///
/// [from] and [to] are inclusive calendar days. The span is expanded outward to
/// whole weeks — from the Monday on or before [from], to the Sunday on or after
/// [to] — because a bar covering three days is drawn the same height as one
/// covering seven and is not the same fact.
VolumeHistory computeVolumeHistory({
  required List<({int dayKey, MuscleGroup muscle, int sets})> daily,
  required DateTime from,
  required DateTime to,
}) {
  final firstWeek = weekStartOf(from);
  final lastWeek = weekStartOf(to);
  if (lastWeek.isBefore(firstWeek)) {
    return const VolumeHistory(weekStarts: [], byRegion: {}, byMuscle: {});
  }

  // Built by walking Mondays rather than by dividing a day count by seven:
  // adding seven days to a local `DateTime` crosses daylight saving correctly,
  // and `difference(...).inDays` across a clock change is 6 or 8.
  final weekStarts = <DateTime>[];
  final indexOfWeek = <DateTime, int>{};
  for (var w = firstWeek;
      !w.isAfter(lastWeek);
      w = DateTime(w.year, w.month, w.day + 7)) {
    indexOfWeek[w] = weekStarts.length;
    weekStarts.add(w);
  }

  // One row per muscle, allocated once and added into. Rebuilding a list per
  // counted day is where a year of history would go quadratic.
  final counts = <MuscleGroup, List<int>>{
    for (final m in MuscleGroup.values)
      if (regionOf(m) != null) m: List.filled(weekStarts.length, 0),
  };

  final fromKey = dayKeyOf(from);
  final toKey = dayKeyOf(to);
  for (final row in daily) {
    if (row.dayKey < fromKey || row.dayKey > toKey) continue;
    final bucket = counts[row.muscle];
    // `other`, and nothing else: it maps to no region, so it is counted
    // nowhere rather than borrowing a row. See [regionOf].
    if (bucket == null) continue;
    final i = indexOfWeek[weekStartOf(dateFromDayKey(row.dayKey))];
    if (i == null) continue;
    bucket[i] += row.sets;
  }

  VolumeSeries series(String label, List<int> weekly) => VolumeSeries(
        label: label,
        weeks: [
          for (var i = 0; i < weekStarts.length; i++)
            VolumeWeek(start: weekStarts[i], sets: weekly[i]),
        ],
      );

  return VolumeHistory(
    weekStarts: weekStarts,
    byRegion: {
      for (final region in MuscleRegion.values)
        region: series(region.label, [
          for (var i = 0; i < weekStarts.length; i++)
            region.parts.fold(0, (s, m) => s + counts[m]![i]),
        ]),
    },
    byMuscle: {
      for (final entry in counts.entries)
        entry.key: series(humanizeEnum(entry.key.name), entry.value),
    },
  );
}

/// A span of [weeks] weeks as a caption names it: `13 weeks`, `18 months`,
/// `5 years`.
///
/// Weeks while the span is about a year or less, because a week is the unit
/// the training is written in and a year's range still reads as a count of
/// them. Past that a count of weeks is a number nobody holds in their head:
/// `Last 261 weeks` asked the reader to divide by fifty-two. Months up to two
/// years, where a whole number of years would round eighteen months to two,
/// and whole years after.
String spanOfWeeks(int weeks) {
  if (weeks <= spanWeeksMax) return '$weeks ${weeks == 1 ? 'week' : 'weeks'}';
  final months = (weeks * 7 / 30.436875).round();
  if (months < 24) return '$months months';
  return '${(weeks * 7 / 365.2425).round()} years';
}

/// The longest span [spanOfWeeks] still counts in weeks: a year's range, with
/// the weeks a window part way through one adds at each end.
const spanWeeksMax = 56;
