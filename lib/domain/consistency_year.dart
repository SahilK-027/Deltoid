import '../core/ids.dart';
import 'volume_history.dart' show weekStartOf;

/// What one logged day contributes to a year of consistency: how many sessions
/// it held, and whether any of them was a deload.
typedef LoggedDayCount = ({int sessions, bool deload});

/// One week of a [ConsistencyYear]: a bar on the Consistency chart.
class TrainingWeek {
  const TrainingWeek({
    required this.start,
    required this.first,
    required this.last,
    required this.sessions,
    required this.deload,
  });

  /// The Monday the week begins on, which for the first week of a year can
  /// fall in December of the year before.
  final DateTime start;

  /// The first and last days of the week that belong to the year. A week
  /// straddling New Year counts only its own year's days, as the calendar
  /// under the chart draws them, so its range is named by those days too.
  final DateTime first;
  final DateTime last;

  final int sessions;

  /// Whether any session in the week was a deload. The bar is then drawn in
  /// the deload colour, as the days are in the calendar.
  final bool deload;
}

/// One calendar year of training, a week at a time.
class ConsistencyYear {
  const ConsistencyYear({
    required this.year,
    required this.weeks,
    required this.sessions,
    required this.trainingDays,
    required this.weeksCounted,
    required this.weeksTrained,
    required this.sessionsCounted,
  });

  final int year;

  /// Oldest first, from the week of the first session ever logged or the first
  /// week of the year, whichever is later, to the week holding today or the
  /// last week of the year. A year before the first session has no weeks.
  final List<TrainingWeek> weeks;

  /// Every session in the year, and every day that held one.
  final int sessions;
  final int trainingDays;

  /// The whole weeks the figures are taken over. The week under way is left
  /// out: on a Monday morning it holds nothing yet, and counting it as a week
  /// without a session would report a miss that has not happened.
  final int weeksCounted;

  /// Of [weeksCounted], the weeks with at least one session.
  final int weeksTrained;

  /// The sessions in [weeksCounted], which is what [averagePerWeek] divides.
  final int sessionsCounted;

  /// Sessions a week over the whole weeks, or null before there is one.
  double? get averagePerWeek =>
      weeksCounted == 0 ? null : sessionsCounted / weeksCounted;

  /// The most sessions any week held, which is what the chart is scaled to.
  int get peak => weeks.fold(0, (m, w) => w.sessions > m ? w.sessions : m);
}

/// The years the Consistency screen offers, newest first: from the year of the
/// first session to this one. This year is always offered, so the screen opens
/// on it even before anything is logged in it.
List<int> consistencyYears(Iterable<int> dayKeys, {required DateTime today}) {
  var first = today.year;
  for (final key in dayKeys) {
    final year = key ~/ 10000;
    if (year < first) first = year;
  }
  return [for (var y = today.year; y >= first; y--) y];
}

/// Folds logged days into one calendar year of weeks.
///
/// Weeks run Monday to Sunday, as the calendar draws them, and are clipped to
/// the year: the days of 29 to 31 December 2025 belong to 2025's last week,
/// not to 2026's first.
ConsistencyYear foldConsistencyYear(
  Map<int, LoggedDayCount> days, {
  required int year,
  required DateTime today,
}) {
  final now = DateTime(today.year, today.month, today.day);
  final yearStart = DateTime(year, 1, 1);
  final yearEnd = DateTime(year, 12, 31);
  final last = year == now.year ? now : yearEnd;

  int? firstKey;
  var sessions = 0;
  var trainingDays = 0;
  for (final MapEntry(:key, :value) in days.entries) {
    if (value.sessions <= 0) continue;
    if (firstKey == null || key < firstKey) firstKey = key;
    if (key ~/ 10000 == year) {
      sessions += value.sessions;
      trainingDays++;
    }
  }

  final firstDay = firstKey == null ? null : dateFromDayKey(firstKey);
  final weeks = <TrainingWeek>[];
  var weeksCounted = 0;
  var weeksTrained = 0;
  var sessionsCounted = 0;

  if (firstDay != null && !firstDay.isAfter(last) && year <= now.year) {
    final from = firstDay.isAfter(yearStart) ? firstDay : yearStart;
    final thisWeek = weekStartOf(now);
    // Stepped as calendar dates, not as 7 × 24 hours, which lands on 23:00
    // the day before once a clock change sits in between.
    for (var w = weekStartOf(from);
        !w.isAfter(last);
        w = DateTime(w.year, w.month, w.day + 7)) {
      var count = 0;
      var deload = false;
      DateTime? first;
      DateTime? end;
      for (var i = 0; i < 7; i++) {
        final d = DateTime(w.year, w.month, w.day + i);
        if (d.year != year) continue;
        first ??= d;
        end = d;
        final day = days[dayKeyOf(d)];
        if (day == null || day.sessions <= 0) continue;
        count += day.sessions;
        deload = deload || day.deload;
      }
      weeks.add(TrainingWeek(
        start: w,
        first: first!,
        last: end!,
        sessions: count,
        deload: deload,
      ));
      if (w == thisWeek) continue;
      weeksCounted++;
      sessionsCounted += count;
      if (count > 0) weeksTrained++;
    }
  }

  return ConsistencyYear(
    year: year,
    weeks: weeks,
    sessions: sessions,
    trainingDays: trainingDays,
    weeksCounted: weeksCounted,
    weeksTrained: weeksTrained,
    sessionsCounted: sessionsCounted,
  );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The days a week covers within its year, as `19–25 Jan` or `26 Jan–1 Feb`.
///
/// The form the phase strip already prints a span in: the month once when both
/// ends share it, and no spaces around the dash.
String weekRangeLabel(TrainingWeek week) {
  final a = week.first;
  final b = week.last;
  if (a.month == b.month) {
    return a.day == b.day
        ? '${a.day} ${_months[a.month - 1]}'
        : '${a.day}–${b.day} ${_months[b.month - 1]}';
  }
  return '${a.day} ${_months[a.month - 1]}–${b.day} ${_months[b.month - 1]}';
}
