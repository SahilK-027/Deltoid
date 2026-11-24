/// Which days a deload rested.
///
/// Only the days a person chose to rest are written down (`cycle_rests`),
/// because those spend a position of the cycle. They, and only they, are drawn
/// on the calendar as deload rest.
library;

/// The days the calendar dots as deload rest.
///
/// Only a day someone chose to rest in a deload counts: `Rest today`, or a day
/// planned by `Rest the remaining days` once it arrives. Each of those spent a
/// position of the cycle, which is what the orange dot records. A day simply
/// not trained inside a deload spent nothing, since the session due stays due,
/// so it is an ordinary rest day and draws as one.
///
/// A planned day after [todayKey] has not happened yet, and a day that was
/// trained after all is a light day rather than rest.
Set<int> deloadRestDays(
  Iterable<int> restDayKeys, {
  required Set<int> trainedDays,
  required int todayKey,
}) =>
    {
      for (final day in restDayKeys)
        if (day <= todayKey && !trainedDays.contains(day)) day,
    };

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
