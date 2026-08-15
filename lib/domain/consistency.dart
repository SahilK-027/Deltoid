import '../core/ids.dart';

/// The window a sessions-per-week average is taken over, once there is enough
/// history to take one.
const consistencyWindowDays = 28;

/// Below this much history, no rate is reported at all.
///
/// One session on your second day is not "0.3 / week" — that number came from
/// dividing by four weeks that hadn't happened yet. A rate drawn from a
/// three-day sample is noise wearing a metric's clothes, so under two weeks
/// this reports the raw count and lets the screen say "1 session logged".
const consistencyMinDays = 14;

/// How often you have actually been training.
class Consistency {
  const Consistency({
    required this.sessions,
    required this.thisWeek,
    required this.windowDays,
    required this.historyDays,
    required this.perWeek,
  });

  /// Sessions completed inside [windowDays].
  final int sessions;

  /// **Days trained** since Monday of the current week — not sessions.
  ///
  /// It counted sessions, and read `6 this week` beside a grid with four cells
  /// filled in it: two of those days held a second session, which the grid
  /// cannot show and this line was not asking about. The line is printed
  /// `4 of 7 this week`, and a day is either trained or it is not.
  ///
  /// Deliberately a calendar week rather than a rolling seven days: the number
  /// answers "how am I doing this week", and a rolling window makes that answer
  /// drop on a Monday morning for no reason the user did anything about.
  final int thisWeek;

  /// Days the count covers: the whole of your history, or
  /// [consistencyWindowDays], whichever is shorter.
  final int windowDays;

  /// Days from the first ever logged session to today, inclusive. Zero when
  /// nothing has been logged.
  final int historyDays;

  /// Sessions per week across [windowDays]. Null when [historyDays] is under
  /// [consistencyMinDays] — see that constant for why.
  final double? perWeek;

  bool get isEmpty => sessions == 0;
}

/// Folds completed session days into a rate.
///
/// [completedDayKeys] may be in any order and may contain duplicates: two
/// sessions on one day count twice, which is the honest answer for a rate.
///
/// The caller's list only needs to reach back [consistencyWindowDays]. A longer
/// window is harmless — the earliest key is used to decide whether there is
/// enough history for a rate, and any list reaching further back than
/// [consistencyMinDays] settles that question the same way.
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
  // Inclusive of both ends: logging your first session today is one day of
  // history, not zero.
  final historyDays = daysBetweenKeys(first, todayKey) + 1;

  final windowDays = historyDays.clamp(1, consistencyWindowDays);
  // `windowDays - 1`, because the window includes today. Off by one here is how
  // a 4-week divisor ended up describing 29 days of sessions.
  final cutoff = dayKeyOf(
    daysBefore(dateFromDayKey(todayKey), windowDays - 1),
  );
  final sessions = completedDayKeys.where((k) => k >= cutoff).length;

  // Monday of the week containing today. `weekday` is 1 for Monday, so today
  // minus (weekday - 1) days lands on it, and on a Monday subtracts nothing.
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
