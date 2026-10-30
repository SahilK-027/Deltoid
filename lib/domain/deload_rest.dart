/// Which days a deload rested, worked out from the cycles rather than stored.
///
/// A deload is a stretch of time, not a set of sessions: from the day after
/// the cycle before it closed to the day it closes itself. Inside that stretch
/// a day with a session is a light day, and every other day is deload rest,
/// whether it was rested on purpose with `Rest today`, planned with `Rest the
/// remaining days`, or simply passed without the app being opened. Only the
/// days a person chose to rest are written down (`cycle_rests`), because those
/// spend a position of the cycle; the calendar's dots are derived, so a week
/// away from the app inside a deload marks itself.
library;

/// One deload cycle, as the days it covers.
class DeloadSpan {
  const DeloadSpan({
    required this.startDayKey,
    required this.endDayKey,
    required this.restsToday,
  });

  /// The first day of the deload, as `yyyyMMdd`.
  final int startDayKey;

  /// The day it closed on, or null while it is still open.
  final int? endDayKey;

  /// Whether today is rested in it. A day is not over until it has passed, so
  /// today counts as rest only when it was chosen as rest: an untrained
  /// morning may still become a light day.
  final bool restsToday;
}

/// The first day a deload covers, or null when it covers none yet.
///
/// The cycle opens the moment the one before it closes, which is usually
/// during that cycle's last session, and that day belongs to the cycle it
/// finished. So the deload starts the day after, unless something in it already
/// happened on the day it opened: a light day trained, or rest chosen, that
/// same evening.
///
/// A cycle already holding sessions at full weight was made a deload part of
/// the way through, from the cycle sheet, and its days before that were not
/// light. Nothing records when the switch was thrown, so such a deload starts
/// on its first light day or rest day, and covers nothing until it has one.
int? deloadStartDayKey({
  required int openedDayKey,
  int? firstActivityDayKey,
  bool madePartWay = false,
}) {
  if (madePartWay) return firstActivityDayKey;
  final next = addDaysToKey(openedDayKey, 1);
  if (firstActivityDayKey != null && firstActivityDayKey < next) {
    return firstActivityDayKey < openedDayKey
        ? openedDayKey
        : firstActivityDayKey;
  }
  return next;
}

/// Every day of [spans] up to [todayKey] that held no session.
///
/// [trainedDays] are the days with a completed workout, in any regime: a day
/// trained is never rest, whatever cycle it counted towards.
Set<int> deloadRestDays(
  Iterable<DeloadSpan> spans, {
  required Set<int> trainedDays,
  required int todayKey,
}) {
  final out = <int>{};
  for (final span in spans) {
    final end = span.endDayKey ?? todayKey;
    var day = span.startDayKey;
    while (day <= end && day <= todayKey) {
      final counts = day < todayKey || span.restsToday;
      if (counts && !trainedDays.contains(day)) out.add(day);
      day = addDaysToKey(day, 1);
    }
  }
  return out;
}

/// The days `Rest the remaining days` plans, one per day still owed.
///
/// They start today, unless today already holds a choice: a session trained
/// or a day rested. A deload rests one day at a time, so a day that has been
/// spent starts the plan tomorrow.
List<int> plannedRestDays({
  required int count,
  required int todayKey,
  required bool todayTaken,
}) {
  var day = todayTaken ? addDaysToKey(todayKey, 1) : todayKey;
  return [
    for (var i = 0; i < count; i++)
      if (i == 0) day else day = addDaysToKey(day, 1),
  ];
}

/// [key] moved by [days] calendar days.
///
/// In UTC, where every day is twenty-four hours: local midnight plus a day
/// lands an hour short across a clock change.
int addDaysToKey(int key, int days) {
  final moved =
      DateTime.utc(key ~/ 10000, (key ~/ 100) % 100, key % 100 + days);
  return moved.year * 10000 + moved.month * 100 + moved.day;
}
