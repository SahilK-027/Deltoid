import '../core/ids.dart';

/// The window over which a sessions-per-week average is calculated, once
/// sufficient history exists.
const consistencyWindowDays = 28;

/// The minimum days of history required before a rate is reported.
///
/// Below this threshold no rate is calculated. A single session on the second
/// day of use would otherwise be reported as "0.3 / week", a figure derived by
/// dividing by four weeks that have not yet elapsed. A rate drawn from a
/// three-day sample is not meaningful, so below two weeks the raw count is
/// reported instead and the screen states "1 session logged".
const consistencyMinDays = 14;

/// A summary of training frequency over a recent window.
class Consistency {
  const Consistency({
    required this.sessions,
    required this.thisWeek,
    required this.windowDays,
    required this.historyDays,
    required this.perWeek,
  });

  /// The number of sessions completed within [windowDays].
  final int sessions;

  /// The number of days trained since Monday of the current week.
  ///
  /// This counts days, not sessions. Counting sessions would report
  /// `6 this week` alongside a grid showing four filled cells, because two of
  /// those days held a second session. The grid cannot represent that, and it
  /// is not the question this figure answers. The value is rendered as
  /// `4 of 7 this week`: a day is either trained or it is not.
  ///
  /// The period is a calendar week rather than a rolling seven days. The figure
  /// answers how the current week is progressing, and a rolling window would
  /// cause that answer to fall on a Monday morning without any change in the
  /// user's behaviour.
  final int thisWeek;

  /// The number of days [sessions] covers.
  ///
  /// This is the shorter of the total history and [consistencyWindowDays].
  final int windowDays;

  /// The number of days from the first logged session to today, inclusive.
  ///
  /// Zero when nothing has been logged.
  final int historyDays;

  /// Sessions per week across [windowDays].
  ///
  /// Null when [historyDays] is below [consistencyMinDays]; see that constant
  /// for the rationale.
  final double? perWeek;

  bool get isEmpty => sessions == 0;
}

/// Calculates a training frequency summary from completed session days.
///
/// [completedDayKeys] may be supplied in any order and may contain duplicates.
/// Two sessions on one day are counted twice, which is the correct behaviour
/// for a rate.
///
/// The supplied list need only extend back [consistencyWindowDays]. A longer
/// list is harmless: the earliest key is used solely to determine whether
/// enough history exists to report a rate, and any list extending beyond
/// [consistencyMinDays] resolves that question identically.
Consistency computeConsistency({
  required Iterable<int> completedDayKeys,
  required DateTime today,
}) {
  if (completedDayKeys.isEmpty) {
    return const Consistency(
      sessions: 0,
      thisWeek: 0,
      windowDays: consistencyWindowDays,
      historyDays: 0,
      perWeek: null,
    );
  }

  final todayKey = dayKeyOf(today);
  final first = completedDayKeys.reduce((a, b) => a < b ? a : b);
  // Both ends are inclusive: a first session logged today constitutes one day
  // of history rather than zero.
  final historyDays = daysBetweenKeys(first, todayKey) + 1;

  final windowDays = historyDays.clamp(1, consistencyWindowDays);
  // The window includes today, hence `windowDays - 1`. An off-by-one here
  // produces a four-week divisor applied to 29 days of sessions.
  final cutoff = dayKeyOf(
    daysBefore(dateFromDayKey(todayKey), windowDays - 1),
  );
  final sessions = completedDayKeys.where((k) => k >= cutoff).length;

  // Monday of the week containing today. `weekday` returns 1 for Monday, so
  // subtracting `weekday - 1` days lands on it and subtracts nothing when today
  // is a Monday.
  final startOfWeek = dayKeyOf(
    daysBefore(dateFromDayKey(todayKey), today.weekday - 1),
  );

  return Consistency(
    sessions: sessions,
    thisWeek: completedDayKeys.where((k) => k >= startOfWeek).toSet().length,
    windowDays: windowDays,
    historyDays: historyDays,
    perWeek: historyDays < consistencyMinDays
        ? null
        : sessions / (windowDays / 7),
  );
}
