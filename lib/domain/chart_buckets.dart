/// Folding a log into the marks a chart can actually draw.
///
/// Every chart in the app answers the same question about its own data — *what
/// happened over this stretch of time* — and every one of them hits the same
/// wall: fifty years of daily entries is eighteen thousand marks across a phone,
/// which is not a chart, it is a texture. So no chart plots raw rows. It picks a
/// [Granularity], folds its rows into buckets, and draws one mark per bucket.
///
/// The rules that make that honest rather than merely tidy:
///
/// - **A measurement averages; a count totals.** Bodyweight in March is the mean
///   of the weigh-ins in March — the mean of measurements is a measurement. Sets
///   in March is their sum, because "4.2 sets in March" is a lie about March and
///   "62 sets in March" is not. Which one a series is, is [BucketFold], and the
///   caller has to say.
/// - **An empty bucket is not a zero, except when it is.** A month you did not
///   weigh yourself has no weight — the line breaks. A month you did not train
///   has zero sets — the bar sits on the baseline. Same absence, two different
///   truths, so [bucketize] reports empties and lets the caller decide.
/// - **Buckets are walked as calendar dates, never as day arithmetic.** Adding
///   seven days to a local `DateTime` crosses a daylight-saving change
///   correctly; adding `7 * 86400` seconds does not, and `difference().inDays`
///   across one is 6 or 8.
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

  /// Last calendar day it covers, inclusive — so a readout can name a span
  /// rather than a boundary.
  final DateTime end;

  /// The folded value, or null when nothing fell in this bucket. **Null is not
  /// zero**: a line breaks here, a bar sits on the baseline, and only the chart
  /// knows which of those its own data means.
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

/// The same ceiling applied to marks **already in hand** rather than to a span
/// somebody else measured.
///
/// A window and its data can disagree for a frame — the range says `All` before
/// the query that knows where `All` starts has come back — and in that frame a
/// chart can be handed every week of fifty years to draw in a card the width of
/// a thumb. This is the backstop: whatever arrives, it is coarsened until it
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
/// **The target is a mark you can see, not a mark that fits.** Anything past
/// about sixty on a phone is a comb — the marks touch, and the shape you came
/// for is hidden inside the points it is made of. So the coarsest granularity is
/// not chosen; the *finest one that stays under the ceiling* is, which is what
/// makes a week open on days and fifty years open on years without either being
/// special-cased.
Granularity autoGranularity(int spanDays, {int ceiling = 60}) {
  if (spanDays <= ceiling) return Granularity.daily;
  if (spanDays / 7 <= ceiling) return Granularity.weekly;
  if (spanDays / 30.44 <= ceiling) return Granularity.monthly;
  return Granularity.yearly;
}

/// The averaging levels that mean anything over [spanDays].
///
/// **A level you cannot see is not a choice**, and that cuts one way only.
/// Yearly over a month is a chart of a single dot — the picker must not offer
/// it, because there is no reading of "average by year" that a month can
/// satisfy. Going the other way is different: monthly over fifty years is six
/// hundred marks, which is dense rather than impossible, and you can pinch into
/// it. So the floor is hard — at least two marks, always — and the [ceiling] is
/// the *drawing's* limit rather than the fold's: a line carries thousands of
/// points, a bar needs a point of width to be a bar at all, so the two pass
/// different numbers.
///
/// This is deliberately far looser than [autoGranularity]'s ~60, which is about
/// what opens by default. What you can ask for and what you are given unasked
/// are two questions.
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

/// The averaging actually in force: what you picked, if the range can still
/// show it, and otherwise the automatic one.
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
/// [rows] are `(dayKey, value)` in any order. [from] and [to] are inclusive
/// calendar days and decide the span: the result runs from the bucket containing
/// [from] to the bucket containing [to], **with the empty ones in their places**,
/// so a chart can tell a gap from a shortage of data. Rows outside the span are
/// dropped rather than trusted — a caller that widens its query without widening
/// its span cannot silently add a bucket.
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
