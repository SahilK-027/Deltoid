/// The date labels under every time-based chart: which days are labelled, what
/// each label says, and where it sits.
///
/// One function for every chart, because the charts used to do this twice and
/// each copy failed in its own way. The line charts printed seven labels at a
/// fixed count, chosen by span alone and never measured, so `1M` collided at a
/// 1.3 font, every `All` range of one to eight years collided at 1.0, `3M`
/// printed `Jul Aug Aug Aug Sep Sep Oct`, and twenty years printed
/// `2006 2010 2013`. The bar charts spread seven bar indices evenly and printed
/// each bar's first day, so thirteen weeks ended on a Monday rather than today
/// and five years mixed `Oct '21` with `Jan '22`.
///
/// The ladder follows THEME → Charts:
///
/// - **The last label is today, and the rest are counted back from it.** Every
///   rolling window ends on the day you are standing in. Past about two years
///   the labels fall mid-year instead, where a year's point is drawn, every 1,
///   2, 5 or 10 years counted back from this year, so a decade reads
///   `2011 2016 2021 2026`. A month or year the window opens part way through
///   keeps its label.
/// - **The same margin at both ends.** The first label stands as far from the
///   left edge of the plot as the last does from the right.
/// - **The labels are named by how much time is on screen** ([DateScale]): a
///   week by its weekdays, a season by dates, a year by months, a decade by
///   years.
/// - **Whether they fit is a measurement.** Every label is measured at the size
///   it is drawn, system font scale included, and two neighbours may not come
///   closer than [DateAxis.minGap]. When seven do not fit, the step widens and
///   the count falls, to four where four fit. A step is always one a person
///   can count in.
/// - **Every label on an axis is worded the same way, and in full.** Dates
///   read `18 Sep 25 Sep 2 Oct`, never `18 Sep 25 2 Oct`. Months inside a year
///   read `Dec Feb Apr`, and across more than a year every one carries its
///   year, `Apr '25 Oct '25 Apr '26`. When the words do not fit, there are
///   fewer of them; they are never shortened.
///
/// A line chart takes [DateAxis.line]; a bar chart takes [DateAxis.bars], whose
/// row of labels runs flush from one end of the plot to the other wherever
/// its step allows, with the gaps between labels equal.
///
/// Pure, and tested without a database (RULES § 7).
library;

import 'package:intl/intl.dart';

import '../core/ids.dart';
import 'chart_buckets.dart';
import 'volume_history.dart' show weekStartOf;

/// What the labels name, chosen by how much time is on screen.
enum DateScale {
  /// Up to about ten days: `Fri Sat Sun … Thu`.
  weekdays,

  /// Up to about four months: `16 Sep`, or `21` once the month is printed.
  dates,

  /// Up to two years: `Apr`, with the year where it changes.
  months,

  /// Beyond two years: `2026`, in the middle of the year.
  years,
}

/// One label under the plot.
class DateLabel {
  const DateLabel({required this.date, required this.text, required this.at});

  /// The day it names, at local midnight.
  final DateTime date;

  final String text;

  /// Its centre, as a fraction of the plot's width: of the padded axis on a
  /// line chart, of the row of bars on a bar chart.
  final double at;

  @override
  String toString() => '$text@${at.toStringAsFixed(3)}';
}

class DateAxis {
  const DateAxis._({
    required this.scale,
    required this.labels,
    required this.minX,
    required this.maxX,
    required this.interval,
    required this.baselineX,
  });

  /// The narrowest gap two labels may leave between them, in logical pixels.
  static const minGap = 8.0;

  /// The most labels an axis prints.
  static const maxLabels = 7;

  /// The axis of a line chart over [from] to [to], inclusive calendar days.
  ///
  /// [width] is the plot's width in logical pixels and [measure] the width of
  /// a label as it will be drawn. [zoom] is the pinch scale: `1` is the whole
  /// window and `4` a quarter of it on screen. The scale and the step follow
  /// the time on screen, so zooming into a decade turns years into months, and
  /// the labels are laid out across the whole window so a pan finds them.
  ///
  /// The plot is padded either side by half a step, or a twelfth of the
  /// window where that is less, and by more where the outer labels need it,
  /// so the first and last labels sit inside it centred on their days. No
  /// label is ever pulled in from its day: that shortened the gap beside it.
  factory DateAxis.line({
    required DateTime from,
    required DateTime to,
    required double width,
    required double Function(String label) measure,
    double zoom = 1,
  }) {
    final start = _day(from);
    final end = _day(to);
    final span = daysBetween(start, end).toDouble();
    final z = zoom > 1 ? zoom : 1.0;
    final visible = span / z;

    _Ladder? fallback;
    for (final pass in [4, 1]) {
      for (final c in _candidates(_scaleFor(visible), null)) {
        final ladder =
            _ladderOf(c, start, end, visible: z > 1 ? visible : null);
        if (ladder == null || ladder.ticks.length < pass) continue;
        fallback ??= ladder;
        final axis = _lineAxis(ladder, start, end, span,
            room: z > 1 ? null : (width: width, measure: measure));
        final texts = [for (final l in axis.labels) l.text];
        final centres = [for (final l in axis.labels) l.at * width * z];
        if (_fits(texts, centres, width * z, measure, edges: z <= 1)) {
          return axis;
        }
      }
    }
    // Nothing fits even one label apart: today on its own, which is the one
    // label every rolling window has to print.
    final only = fallback ??
        _Ladder(const _Candidate(DateScale.dates, _Unit.day, 1), [end],
            [DateFormat('d MMM').format(end)]);
    return _lineAxis(only.newest, start, end, span, room: null);
  }

  /// The axis of a bar chart of [count] bars folded at [by], the first of
  /// which holds [from] and the last [to].
  ///
  /// The first choice is a step that divides the bars evenly, so a label names
  /// each end bar, and the row is laid out flush with both ends of the plot
  /// and spaced evenly: the same margin, none, at each end, and every gap the
  /// same. Failing that, the calendar ladder is counted back from today, laid
  /// out the same way where its oldest label falls within half a step of the
  /// first bar. Otherwise every label is centred on its bar, the newest may
  /// run on past the plot by [rightRoom], into the value gutter, which is
  /// empty below the baseline, and an oldest label that would hang off the
  /// left end is left out.
  factory DateAxis.bars({
    required DateTime from,
    required DateTime to,
    required Granularity by,
    required int count,
    required double width,
    required double Function(String label) measure,
    double rightRoom = 0,
  }) {
    final start = _day(from);
    final end = _day(to);
    if (count <= 0 || end.isBefore(start)) {
      return const DateAxis._(
        scale: DateScale.dates,
        labels: [],
        minX: 0,
        maxX: 1,
        interval: 1,
        baselineX: 0,
      );
    }
    final span = daysBetween(start, end).toDouble();
    final bars = (by: by, count: count, first: bucketStartOf(start, by));

    // First choice: a step that divides the bars evenly from the first to the
    // last, so a label stands on each end bar and the two margins are the same.
    final ends = _endToEnd(start, end, span, bars, width, measure);
    if (ends != null) return ends;

    _Ladder? fallback;
    for (final pass in [4, 1]) {
      for (final c in _candidates(_scaleFor(span), by)) {
        final ladder = _ladderOf(c, start, end);
        if (ladder == null || ladder.ticks.length < pass) continue;
        fallback ??= ladder;
        final built = _barAxis(ladder, bars);
        final stepBars = _stepInBars(c, by);
        var kept = built.labels;
        // The oldest label within half a step of the first bar: the row is
        // laid out flush with both ends and spaced evenly, as [_endToEnd]
        // lays it, each label within half a step of its own bar. Otherwise
        // every label stays centred on its bar, and one that would hang off
        // the left end is left out.
        if (kept.length > 1 &&
            kept.first.at * count < stepBars / 2 + 0.5) {
          final first = measure(kept.first.text) / 2;
          final last = width - measure(kept.last.text) / 2;
          final n = kept.length - 1;
          kept = [
            for (var i = 0; i <= n; i++)
              DateLabel(
                date: kept[i].date,
                text: kept[i].text,
                at: (first + (last - first) * i / n) / width,
              ),
          ];
        } else {
          kept = [
            for (final l in kept)
              if (l.at * width - measure(l.text) / 2 >= 0) l,
          ];
        }
        if (kept.length < pass) continue;
        final axis = DateAxis._(
          scale: built.scale,
          labels: kept,
          minX: 0,
          maxX: 1,
          interval: built.interval,
          baselineX: 0,
        );
        final texts = [for (final l in kept) l.text];
        final centres = [for (final l in kept) l.at * width];
        if (_fits(texts, centres, width, measure,
            edges: true, rightRoom: rightRoom)) {
          return axis;
        }
      }
    }
    final only = fallback;
    if (only == null) {
      return const DateAxis._(
        scale: DateScale.dates,
        labels: [],
        minX: 0,
        maxX: 1,
        interval: 1,
        baselineX: 0,
      );
    }
    return _barAxis(only.newest, bars);
  }

  final DateScale scale;

  /// Oldest first.
  final List<DateLabel> labels;

  /// A line chart's padded bounds, in days since the epoch: the unit its x
  /// values are plotted in. A bar chart's are `0` and `1`.
  final double minX;
  final double maxX;

  /// The days between two labels, and the x of the newest, which is what
  /// `fl_chart` walks its ticks from. Across months and years the interval is
  /// the average month or year, so the labels are evenly spaced and each sits
  /// within two days of the date it names.
  final double interval;
  final double baselineX;

  /// The label of the tick `fl_chart` walks to at [x], or null where there is
  /// none.
  String? labelAt(double x) {
    if (labels.isEmpty || interval <= 0) return null;
    final k = ((baselineX - x) / interval).round();
    final i = labels.length - 1 - k;
    if (k < 0 || i < 0) return null;
    return labels[i].text;
  }

  /// The x a line chart plots [date] at.
  static double xOf(DateTime date) => date.millisecondsSinceEpoch / 86400000;
}

// ─── The ladder ─────────────────────────────────────────────────────────────

enum _Unit { day, week, month, year }

class _Candidate {
  const _Candidate(this.scale, this.unit, this.step);

  final DateScale scale;
  final _Unit unit;
  final int step;

  /// The step in days, near enough to pad the plot and space `fl_chart`'s
  /// ticks.
  double get days => switch (unit) {
        _Unit.day => step.toDouble(),
        _Unit.week => step * 7.0,
        _Unit.month => step * _month,
        _Unit.year => step * _year,
      };
}

const _month = 365.2425 / 12;
const _year = 365.2425;

/// The ticks one candidate puts down, newest first, and their words.
class _Ladder {
  const _Ladder(this.candidate, this.ticks, this.texts);

  final _Candidate candidate;
  final List<DateTime> ticks;
  final List<String> texts;

  _Ladder get newest =>
      _Ladder(candidate, ticks.take(1).toList(), texts.take(1).toList());
}

DateScale _scaleFor(double days) {
  if (days <= 10) return DateScale.weekdays;
  if (days <= 125) return DateScale.dates;
  if (days <= 731) return DateScale.months;
  return DateScale.years;
}

/// Every candidate for an axis, in the order they are tried: the scale the
/// span asks for and then each coarser one; within a scale, the steps from
/// fine to coarse.
///
/// A bar chart's step is whole bars, so a scale finer than its bars is skipped
/// and a weekly chart counts its dates in weeks. Its months are calendar
/// months, spaced at the average month (see [_barAxis]); counted in whole
/// weeks instead, the months drifted, and six months began on `May` with
/// April's bars unlabelled.
Iterable<_Candidate> _candidates(DateScale from, Granularity? bars) sync* {
  final floor = switch (bars) {
    Granularity.monthly => DateScale.months,
    Granularity.yearly => DateScale.years,
    // A bar is a week, and a weekday names a day.
    Granularity.weekly => DateScale.dates,
    _ => DateScale.weekdays,
  };
  final weekly = bars == Granularity.weekly;
  for (final scale in DateScale.values) {
    if (scale.index < from.index || scale.index < floor.index) continue;
    switch (scale) {
      case DateScale.weekdays:
        for (final s in const [1, 2, 3]) {
          yield _Candidate(scale, _Unit.day, s);
        }
      case DateScale.dates:
        for (final s in weekly ? const [1, 2, 3, 4, 8] : const [1, 2, 3, 5, 7, 10, 15, 30]) {
          yield _Candidate(scale, weekly ? _Unit.week : _Unit.day, s);
        }
      case DateScale.months:
        for (final s in const [1, 2, 3, 4, 6, 12]) {
          yield _Candidate(scale, _Unit.month, s);
        }
      case DateScale.years:
        for (final s in const [1, 2, 5, 10, 20, 50, 100]) {
          yield _Candidate(scale, _Unit.year, s);
        }
    }
  }
}

typedef _Bars = ({Granularity by, int count, DateTime first});

/// The ticks [c] puts between [start] and [end], newest first, and what each
/// says. Null when the step would print more than [DateAxis.maxLabels] in the
/// [visible] days on screen, so the caller moves on to a wider one.
///
/// [visible] is null when the whole window is on screen, and the count is then
/// the ticks themselves. A zoomed line chart lays its ticks across the whole
/// window, so the count is estimated over what is on screen instead.
_Ladder? _ladderOf(
  _Candidate c,
  DateTime start,
  DateTime end, {
  double? visible,
}) {
  if (visible != null && visible / c.days + 1 > DateAxis.maxLabels + 0.5) {
    return null;
  }
  final cap = visible == null ? DateAxis.maxLabels : 1000;
  // Months carry their year on every label once the window holds the same
  // month in two years, and on none inside one. A year back from 16 October
  // starts on 16 October, so `1Y` reads `Oct '25 … Oct '26` from edge to edge
  // rather than dropping one `Oct` and leaving the plot's left end bare.
  final withYear =
      (end.year - start.year) * 12 + end.month - start.month >= 12;
  final ticks = <DateTime>[];
  for (var j = 0;; j++) {
    final tick = switch (c.unit) {
      _Unit.day => daysBefore(end, j * c.step),
      _Unit.week => daysBefore(end, j * c.step * 7),
      _Unit.month => _monthsBefore(end, j * c.step),
      // The middle of the year, where a yearly point or bar is drawn, so
      // `2026` sits under 2026 rather than half a year to its left. Before
      // July that is still to come, so the labels sit on today's date instead
      // and the newest is today.
      _Unit.year => end.month < 7
          ? DateTime(end.year - j * c.step, end.month,
              end.month == 2 && end.day == 29 ? 28 : end.day)
          : DateTime(end.year - j * c.step, 7),
    };
    if (tick.isBefore(start)) {
      // A month or year the window opens part way through is still on the
      // chart, so it keeps its label: six months back from 16 October start
      // on 17 April, and `Apr` belongs under them.
      final opens = switch (c.scale) {
        DateScale.months => tick.year == start.year && tick.month == start.month,
        DateScale.years => tick.year == start.year,
        _ => false,
      };
      if (opens && !ticks.any((t) => _sameName(t, tick, c, withYear))) {
        ticks.add(tick);
      }
      break;
    }
    // The count stops before a month would be named twice: a year back from
    // October reaches the October before.
    if (ticks.any((t) => _sameName(t, tick, c, withYear))) break;
    if (ticks.length == cap) return null;
    ticks.add(tick);
  }
  if (ticks.isEmpty) return null;
  return _Ladder(c, ticks, _textsOf(c, ticks, withYear: withYear));
}

/// Whether [a] and [b] would print the same month: the count stops before
/// one is named twice.
bool _sameName(DateTime a, DateTime b, _Candidate c, bool withYear) =>
    c.scale == DateScale.months &&
    a.month == b.month &&
    (!withYear || a.year == b.year);

/// The same day [months] months before [date], or the last day of a month too
/// short to have it.
DateTime _monthsBefore(DateTime date, int months) {
  final m = DateTime(date.year, date.month - months);
  final last = DateTime(m.year, m.month + 1, 0).day;
  return DateTime(m.year, m.month, date.day > last ? last : date.day);
}

/// The words of [ticks], newest first: one format for every label on an
/// axis, never a short form beside a long one.
List<String> _textsOf(
  _Candidate c,
  List<DateTime> ticks, {
  required bool withYear,
}) {
  final format = switch (c.scale) {
    DateScale.weekdays => DateFormat('EEE'),
    DateScale.dates => DateFormat('d MMM'),
    DateScale.months => DateFormat(withYear ? "MMM ''yy" : 'MMM'),
    DateScale.years => DateFormat('y'),
  };
  return [for (final t in ticks) format.format(t)];
}

/// [room] is the plot's width and the measure of a label, so the padding can
/// hold the outer labels centred on their days; null when zoomed, where the
/// ends are off screen.
DateAxis _lineAxis(
  _Ladder ladder,
  DateTime start,
  DateTime end,
  double span, {
  required ({double width, double Function(String) measure})? room,
}) {
  final c = ladder.candidate;
  final pad = _min(c.days / 2, span / 12);
  final n = ladder.ticks.length;
  final baselineX = DateAxis.xOf(ladder.ticks.first);
  // **The same margin at both ends.** The plot reaches past the window by
  // [pad] on each side, and past the outer labels by whichever of the two
  // gaps between label and window edge is wider, so the first label stands
  // as far from the left edge as the last does from the right. Where `fl_chart`
  // draws them, walked back from the baseline at the interval.
  var minX = DateAxis.xOf(start) - pad;
  var maxX = DateAxis.xOf(end) + pad;
  if (n > 1) {
    final first = baselineX - (n - 1) * c.days;
    final last = baselineX;
    final gap = [
      DateAxis.xOf(end) - last,
      first - DateAxis.xOf(start),
      0.0,
    ].reduce((a, b) => a > b ? a : b);
    var margin = gap + pad;
    // Room for the wider of the two outer labels, half of it either side of
    // its day, on both ends alike. Solved for the margin in days that gives
    // that many pixels once the margin itself has taken its share.
    if (room != null) {
      final half = [
            room.measure(ladder.texts.first),
            room.measure(ladder.texts.last),
          ].reduce((a, b) => a > b ? a : b) /
              2 +
          1;
      final inner = last - first;
      if (room.width > 2 * half) {
        final needed = half * inner / (room.width - 2 * half);
        if (needed > margin) margin = needed;
      }
    }
    minX = first - margin;
    maxX = last + margin;
  }
  final width = maxX - minX;
  return DateAxis._(
    scale: c.scale,
    labels: [
      for (var k = n - 1; k >= 0; k--)
        DateLabel(
          date: ladder.ticks[k],
          text: ladder.texts[k],
          // Where `fl_chart` will draw it: walked back from the baseline at
          // the interval, which across months and years is the average one.
          at: (baselineX - k * c.days - minX) / width,
        ),
    ],
    minX: minX,
    maxX: maxX,
    interval: c.days,
    baselineX: baselineX,
  );
}

DateAxis _barAxis(_Ladder ladder, _Bars bars) {
  final c = ladder.candidate;
  final labels = <DateLabel>[];
  // Months and years over days or weeks are not a whole number of bars, so
  // the labels are spaced at the average month or year, walked back from the
  // newest, as a line chart's are. Each stays within a bar of the week its day
  // falls in, and the gaps are equal; placed on that week instead, they ran
  // twelve, thirteen and fourteen weeks apart by which weekday the 16th was.
  final averaged = c.unit.index >= _Unit.month.index &&
      bars.by.index < Granularity.monthly.index;
  final newest = _slotOf(ladder.ticks.first, bars);
  final stepBars = _stepInBars(c, bars.by);
  for (var k = ladder.ticks.length - 1; k >= 0; k--) {
    final slot = _slotOf(ladder.ticks[k], bars);
    if (slot >= bars.count) continue;
    final centre = averaged
        ? newest + 0.5 - k * stepBars
        : slot + 0.5;
    // A month or year the bars open part way through keeps its label while it
    // stands within half a step of the first bar; further off, it is not on
    // the chart. [DateAxis.bars] then lays the row flush with both ends.
    if (centre < -stepBars / 2) continue;
    labels.add(DateLabel(
      date: ladder.ticks[k],
      text: ladder.texts[k],
      at: centre / bars.count,
    ));
  }
  return DateAxis._(
    scale: c.scale,
    labels: labels,
    minX: 0,
    maxX: 1,
    interval: c.days,
    baselineX: 0,
  );
}

/// The labels of a bar chart on a step that divides its bars evenly, so the
/// oldest label names the first bar as the newest names the last, laid out
/// flush with both ends of the plot. Null where no such step fits three
/// labels or more.
///
/// The words follow the time on screen as everywhere else, and a step of
/// whole weeks is taken for months only where they come out evenly, every one
/// the same number of months on from the last; `Apr May Jul Aug` would read as
/// a June gone missing. The calendar ladder then takes over, laid out the
/// same way.
DateAxis? _endToEnd(
  DateTime start,
  DateTime end,
  double span,
  _Bars bars,
  double width,
  double Function(String) measure,
) {
  final n = bars.count;
  if (n < 3) return null;
  final floor = switch (bars.by) {
    Granularity.monthly => DateScale.months,
    Granularity.yearly => DateScale.years,
    Granularity.weekly => DateScale.dates,
    Granularity.daily => DateScale.weekdays,
  };
  var scale = _scaleFor(span);
  if (scale.index < floor.index) scale = floor;
  final withYear =
      (end.year - start.year) * 12 + end.month - start.month >= 12;

  for (var k = 1; k < n; k++) {
    if ((n - 1) % k != 0) continue;
    final steps = (n - 1) ~/ k;
    if (steps + 1 > DateAxis.maxLabels) continue;
    if (steps + 1 < 3) break;
    // Newest first, each a whole number of bars back from today.
    final ticks = [
      for (var j = 0; j <= steps; j++)
        switch (bars.by) {
          Granularity.daily => daysBefore(end, j * k),
          Granularity.weekly => daysBefore(end, j * k * 7),
          Granularity.monthly => _monthsBefore(end, j * k),
          Granularity.yearly => _monthsBefore(end, j * k * 12),
        },
    ];
    final texts = _endToEndTexts(scale, ticks, withYear);
    if (texts == null) continue;
    // **Justified.** The oldest label starts flush with the left end of the
    // plot and the newest ends flush with the right, and the rest are spaced
    // evenly between them: the bars they stand for are evenly spaced, so the
    // labels are too, each within a bar or two of its own. Centred on the end
    // bars instead, the outer two hung off the plot, and pulled in alone they
    // shortened the gaps beside them.
    final first = measure(texts[steps]) / 2;
    final last = width - measure(texts[0]) / 2;
    final labels = [
      for (var j = steps; j >= 0; j--)
        DateLabel(
          date: ticks[j],
          text: texts[j],
          at: (first + (last - first) * (steps - j) / steps) / width,
        ),
    ];
    if (last > first &&
        _fits(
          [for (final l in labels) l.text],
          [for (final l in labels) l.at * width],
          width,
          measure,
          edges: true,
        )) {
      return DateAxis._(
        scale: scale,
        labels: labels,
        minX: 0,
        maxX: 1,
        interval: span / steps,
        baselineX: 0,
      );
    }
  }
  return null;
}

/// The words of an end-to-end bar strip, newest first, or null where its
/// months or years would not come out evenly.
List<String>? _endToEndTexts(
  DateScale scale,
  List<DateTime> ticks,
  bool withYear,
) {
  bool even(List<int> at) {
    if (at.length < 2) return true;
    final step = at[0] - at[1];
    if (step <= 0) return false;
    for (var i = 1; i < at.length; i++) {
      if (at[i - 1] - at[i] != step) return false;
    }
    return true;
  }

  switch (scale) {
    case DateScale.weekdays:
      return [for (final t in ticks) DateFormat('EEE').format(t)];
    case DateScale.dates:
      return [for (final t in ticks) DateFormat('d MMM').format(t)];
    case DateScale.months:
      if (even([for (final t in ticks) t.year * 12 + t.month])) {
        final f = DateFormat(withYear ? "MMM ''yy" : 'MMM');
        return [for (final t in ticks) f.format(t)];
      }
      return null;
    case DateScale.years:
      if (even([for (final t in ticks) t.year])) {
        return [for (final t in ticks) '${t.year}'];
      }
      return null;
  }
}

/// How many bars one step of [c] spans, near enough for months and years.
double _stepInBars(_Candidate c, Granularity by) =>
    c.days /
    switch (by) {
      Granularity.daily => 1.0,
      Granularity.weekly => 7.0,
      Granularity.monthly => _month,
      Granularity.yearly => _year,
    };

/// Which bar [day] falls in, counted from the first.
int _slotOf(DateTime day, _Bars bars) => switch (bars.by) {
      Granularity.daily => daysBetween(bars.first, day),
      Granularity.weekly => daysBetween(bars.first, weekStartOf(day)) ~/ 7,
      Granularity.monthly => (day.year - bars.first.year) * 12 +
          day.month -
          bars.first.month,
      Granularity.yearly => day.year - bars.first.year,
    };

/// Whether [texts] at [centres] can all be printed: none naming the same
/// weekday or month twice (a bare day may repeat, `16` of September and `16`
/// of October), none within [DateAxis.minGap] of the next, and none past
/// either end of a plot [width] wide, centred on its day, but for [rightRoom]
/// past the right. [edges] false, for a zoomed chart whose ends are off
/// screen, checks only the gaps.
bool _fits(
  List<String> texts,
  List<double> centres,
  double width,
  double Function(String) measure, {
  required bool edges,
  double leftRoom = 0,
  double rightRoom = 0,
}) {
  final named = [for (final t in texts) if (int.tryParse(t) == null) t];
  if (named.toSet().length != named.length) return false;
  double? right;
  for (var i = 0; i < texts.length; i++) {
    final w = measure(texts[i]);
    final left = centres[i] - w / 2;
    if (edges &&
        (left < -leftRoom - 0.5 || left + w > width + rightRoom + 0.5)) {
      return false;
    }
    if (right != null && left - right < DateAxis.minGap) return false;
    right = left + w;
  }
  return true;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

double _min(double a, double b) => a < b ? a : b;

/// How a year map's month strip is worded: every month by its short name,
/// every other month by it, or every month by its initial.
enum MonthLabels { full, alternate, initials }

/// The fullest wording of a year map's month strip that does not collide.
///
/// [centres] is where each month's label is centred along the strip, January
/// first, and [full] and [initials] are the widths of each month's short name
/// and initial at the size they will be drawn, system font scale included. Two
/// labels collide when the room between their centres is less than half of
/// each plus [gap].
///
/// **The type never shrinks.** The strip used to scale its labels down until
/// all twelve fitted, which drew them at about 7 sp on a phone and ignored the
/// system font. Labels stay at their size (THEME → Type, 11 sp at least) and
/// there are fewer words instead: every other month while those fit, which
/// keeps the months readable as names, then every month by its initial, as the
/// timeline strip on All time prints them. A strip too narrow even for
/// initials still prints initials; there is nothing smaller left to print.
MonthLabels monthLabelsFor({
  required List<double> centres,
  required List<double> full,
  required List<double> initials,
  double gap = 4,
}) {
  assert(centres.length == full.length && full.length == initials.length);
  bool fits(List<double> widths, int step) {
    for (var i = step; i < centres.length; i += step) {
      final room = centres[i] - centres[i - step];
      if (room < (widths[i] + widths[i - step]) / 2 + gap) return false;
    }
    return true;
  }

  if (fits(full, 1)) return MonthLabels.full;
  if (fits(full, 2)) return MonthLabels.alternate;
  return MonthLabels.initials;
}
