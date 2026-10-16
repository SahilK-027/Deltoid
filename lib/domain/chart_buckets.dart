/// Aggregation of logged rows into the marks a chart can render.
///
/// Every chart in the application answers the same question about its own data,
/// namely what occurred over a given period, and each encounters the same
/// limit: fifty years of daily entries is eighteen thousand marks across a
/// phone display, which is not legible as a chart. No chart therefore plots raw
/// rows. Each selects a [Granularity], aggregates its rows into buckets, and
/// renders one mark per bucket.
///
/// Three rules govern that aggregation.
///
/// - A measurement is averaged; a count is summed. Bodyweight in March is the
///   mean of that month's weigh-ins, since the mean of measurements is itself a
///   measurement. Sets in March is their sum, because "4.2 sets in March" would
///   misreport the month whereas "62 sets in March" does not. Which of the two
///   applies to a series is given by [BucketFold] and must be supplied by the
///   caller.
/// - An empty bucket is not necessarily zero. A month with no weigh-in has no
///   weight, and the line breaks. A month with no training has zero sets, and
///   the bar rests on the baseline. The same absence carries two different
///   meanings, so [bucketize] reports empty buckets and leaves the
///   interpretation to the caller.
/// - Buckets are advanced as calendar dates rather than by day arithmetic.
///   Adding seven days to a local `DateTime` crosses a daylight-saving
///   transition correctly; adding `7 * 86400` seconds does not, and
///   `difference().inDays` across such a transition yields 6 or 8.
///
/// Pure, and tested without a database (RULES § 7).
library;

import '../core/ids.dart';
import 'volume_history.dart' show weekStartOf;

/// How wide one mark on a chart is.
///
/// Ordered coarsest-last, so `Granularity.values.indexOf` is a zoom level and
/// two granularities can be compared with `>`.
enum Granularity {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  const Granularity(this.label, this.noun);

  /// As it appears in the picker.
  final String label;

  /// As it appears mid-sentence — "12 sets a week".
  final String noun;
}

/// Whether a bucket's value is the mean of what fell in it or the sum.
///
/// See the library doc: this is the difference between a measurement and a
/// count, and getting it wrong is the difference between a chart and a fiction.
enum BucketFold { mean, sum }

/// One mark on a chart.
class Bucket {
  const Bucket({
    required this.start,
    required this.end,
    required this.value,
    required this.count,
  });

  /// First calendar day the bucket covers, at midnight local.
  final DateTime start;

  /// The last calendar day the bucket covers, inclusive, so that a readout can
  /// state a span rather than a boundary.
  final DateTime end;

  /// The aggregated value, or null when no rows fell within this bucket.
  ///
  /// Null is not zero. A line chart breaks at a null, a bar chart rests on the
  /// baseline, and only the calling chart knows which its data implies.
  final double? value;

  /// How many rows were folded into it. What makes an average readable as
  /// "twelve weigh-ins" rather than as a number with no provenance.
  final int count;

  bool get isEmpty => count == 0;
}

/// The first day of the bucket [date] falls in.
///
/// Weekly is Monday, the rule [weekStartOf] already sets for the whole app —
/// two week rules in one app means the same Sunday session lands in different
/// weeks on two screens.
DateTime bucketStartOf(DateTime date, Granularity by) => switch (by) {
      Granularity.daily => DateTime(date.year, date.month, date.day),
      Granularity.weekly => weekStartOf(date),
      Granularity.monthly => DateTime(date.year, date.month),
      Granularity.yearly => DateTime(date.year),
    };

/// The first day of the bucket after the one starting at [start].
DateTime nextBucket(DateTime start, Granularity by) => switch (by) {
      // Built by naming the next date rather than by adding a `Duration`, so a
      // clock change is the calendar's problem and not the chart's.
      Granularity.daily => DateTime(start.year, start.month, start.day + 1),
      Granularity.weekly => DateTime(start.year, start.month, start.day + 7),
      Granularity.monthly => DateTime(start.year, start.month + 1),
      Granularity.yearly => DateTime(start.year + 1),
    };

/// Applies the same ceiling to marks already produced, rather than to a
/// measured span.
///
/// A window and its data may disagree for a single frame: the range reports
/// `All` before the query that determines where `All` begins has returned. In
/// that frame a chart may be supplied with every week of fifty years to render
/// in a narrow card. This is the safeguard: whatever arrives is coarsened until
/// it
/// fits, and never refined below the fold it already has.
Granularity autoGranularityFor(int marks, Granularity of, {int ceiling = 60}) {
  final days = switch (of) {
    Granularity.daily => marks,
    Granularity.weekly => marks * 7,
    Granularity.monthly => marks * 30,
    Granularity.yearly => marks * 365,
  };
  final auto = autoGranularity(days, ceiling: ceiling);
  return auto.index < of.index ? of : auto;
}

/// How many marks a span would draw at each granularity, and therefore which
/// one a chart should open at.
///
/// The target is a legible mark rather than merely a mark that fits. Beyond
/// approximately sixty marks on a phone display the marks touch, and the shape
/// being examined is obscured by the points composing it. The coarsest
/// granularity is therefore not selected; the finest one remaining below the
/// ceiling is. This is what causes a week to open at daily granularity and
/// fifty years to open at yearly, without either being special-cased.
///
/// **About sixty is a tenth either way.** The marks counted are the buckets the
/// fold draws, a partial one at each end included, and they may run to a tenth
/// over the [ceiling]. Held to sixty exactly, five years came to 60.02 months
/// and folded into six yearly bars, the first of them a partial October, where
/// sixty-one monthly bars draw the same five years legibly.
Granularity autoGranularity(int spanDays, {int ceiling = 60}) {
  final most = ceiling * 1.1;
  for (final g in const [
    Granularity.daily,
    Granularity.weekly,
    Granularity.monthly,
  ]) {
    if (_marksIn(spanDays, g) <= most) return g;
  }
  return Granularity.yearly;
}

/// The averaging levels that mean anything over [spanDays].
///
/// A level that cannot be rendered is not a valid choice, and the constraint
/// applies asymmetrically. Yearly granularity over a month produces a single
/// point, so the picker must not offer it: no interpretation of "average by
/// year" can be satisfied by one month of data. The converse differs. Monthly
/// granularity over fifty years produces six hundred marks, which is dense but
/// legible, and can be examined by zooming. The floor is therefore absolute —
/// at least two marks in all cases — while the [ceiling] is a limit on
/// rendering rather than on aggregation: a line chart carries thousands of
/// points whereas a bar requires measurable width, so the two supply different
/// values.
///
/// This is deliberately far looser than the approximate ceiling of 60 applied
/// by [autoGranularity], which governs the default. What may be selected and
/// what is applied by default are separate questions.
///
/// Always at least one: a span too short for anything is still drawn daily,
/// because a chart of one day is a chart of one day and the picker should say
/// so rather than being empty.
List<Granularity> granularitiesFor(int spanDays, {int ceiling = 3000}) {
  final out = [
    for (final g in Granularity.values)
      if (_marksIn(spanDays, g) >= 2 && _marksIn(spanDays, g) <= ceiling) g,
  ];
  return out.isEmpty ? const [Granularity.daily] : out;
}

double _marksIn(int spanDays, Granularity by) => switch (by) {
      Granularity.daily => spanDays + 1,
      Granularity.weekly => spanDays / 7 + 1,
      Granularity.monthly => spanDays / 30.44 + 1,
      Granularity.yearly => spanDays / 365.25 + 1,
    };

/// The granularity in force: the selected value where the range can still
/// render it, and the automatic value otherwise.
///
/// A choice survives a change of range whenever it can — picking Monthly and
/// then widening to a year should keep monthly, not silently revert. What it
/// must not do is *outlive* the range that made sense of it: Yearly chosen on
/// `All` and then `1M` selected would draw one dot, so at that point the choice
/// is stood down rather than honoured.
Granularity resolveGranularity(
  Granularity? chosen,
  int spanDays, {
  List<Granularity> allowed = Granularity.values,
  int ceiling = 3000,
}) {
  final fits = [
    for (final g in granularitiesFor(spanDays, ceiling: ceiling))
      if (allowed.contains(g)) g,
  ];
  if (chosen != null && fits.contains(chosen)) return chosen;
  final auto = autoGranularity(spanDays);
  if (fits.contains(auto)) return auto;
  // Nothing fits — a span shorter than this screen's finest unit. The coarsest
  // thing it does support is the honest answer, not a level it cannot draw.
  return fits.isNotEmpty ? fits.first : (allowed.isNotEmpty ? allowed.first : auto);
}

/// Folds dated values into one bucket per period.
///
/// [rows] are `(dayKey, value)` pairs in any order. [from] and [to] are
/// inclusive calendar days and determine the span: the result runs from the
/// bucket containing [from] to the bucket containing [to], with empty buckets
/// retained in position, so that a chart can distinguish a gap from an absence
/// of data. Rows outside the span are discarded rather than accepted, so that a
/// caller widening its query without widening its span cannot silently
/// introduce a bucket.
///
/// Linear in the rows plus the buckets, with one pass over each: the fold is
/// done into a pre-allocated pair of lists indexed by bucket, because looking up
/// a bucket per row through a map keyed on `DateTime` is how a decade of dailies
/// goes quadratic on the hash.
List<Bucket> bucketize({
  required Iterable<({int dayKey, double value})> rows,
  required Granularity by,
  required DateTime from,
  required DateTime to,
  BucketFold fold = BucketFold.mean,
}) {
  final first = bucketStartOf(from, by);
  final last = bucketStartOf(to, by);
  if (last.isBefore(first)) return const [];

  final starts = <DateTime>[];
  final index = <DateTime, int>{};
  for (var s = first; !s.isAfter(last); s = nextBucket(s, by)) {
    index[s] = starts.length;
    starts.add(s);
  }

  final totals = List<double>.filled(starts.length, 0);
  final counts = List<int>.filled(starts.length, 0);

  final fromKey = dayKeyOf(from);
  final toKey = dayKeyOf(to);
  for (final row in rows) {
    if (row.dayKey < fromKey || row.dayKey > toKey) continue;
    final i = index[bucketStartOf(dateFromDayKey(row.dayKey), by)];
    if (i == null) continue;
    totals[i] += row.value;
    counts[i]++;
  }

  return [
    for (var i = 0; i < starts.length; i++)
      Bucket(
        start: starts[i],
        // The day before the next bucket opens, which is the only definition
        // that survives February and a 31st. Named as a date rather than
        // reached by subtracting a `Duration`, which across a clock change
        // lands at 23:00 on the right day and reads as the wrong one.
        end: () {
          final next = nextBucket(starts[i], by);
          return DateTime(next.year, next.month, next.day - 1);
        }(),
        value: counts[i] == 0
            ? null
            : fold == BucketFold.sum
                ? totals[i]
                : totals[i] / counts[i],
        count: counts[i],
      ),
  ];
}

/// Which series a multi-line chart draws when there are more than it has
/// colours for, and how many there were.
///
/// One line per key (a session name, on an exercise's trend), newest first —
/// ordered by the latest day each key was seen, so the line you trained most
/// recently is always the first, blue one. At most [max] are kept rather than
/// cycling the palette: two lines in one colour read as one progression, which
/// is the mistake a per-session chart exists to avoid. [total] is how many keys
/// there were, so the caller can say what it left out.
///
/// Ties on the latest day keep the order the keys were first seen in, so a
/// redraw never swaps two lines' colours.
({List<String> shown, int total}) mostRecentKeys(
  Iterable<({String key, int dayKey})> rows, {
  required int max,
}) {
  final latest = <String, int>{};
  for (final r in rows) {
    final seen = latest[r.key];
    if (seen == null || r.dayKey > seen) latest[r.key] = r.dayKey;
  }
  final order = latest.keys.toList();
  final keys = [...order]..sort((a, b) {
      final byDay = latest[b]!.compareTo(latest[a]!);
      return byDay != 0 ? byDay : order.indexOf(a).compareTo(order.indexOf(b));
    });
  return (shown: keys.take(max).toList(), total: keys.length);
}
