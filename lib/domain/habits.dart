import '../core/ids.dart';

/// How many days a habit tile's grid covers.
///
/// Three rows of ten in half a phone's width. A month is the span at which a
/// missed week shows as a gap rather than as the whole grid.
const habitWindowDays = 30;

/// The days a habit tile draws, oldest first and today last.
///
/// Built through [daysBefore] rather than by subtracting `Duration(days: n)`,
/// which across a daylight-saving change lands on 23:00 the day before and
/// repeats a day in the grid.
List<int> habitWindow(DateTime today) => [
  for (var i = habitWindowDays - 1; i >= 0; i--) dayKeyOf(daysBefore(today, i)),
];

/// How many days of the calendar week to [today], Monday first, hold at least
/// one of [dayKeys].
///
/// Days rather than entries: two sessions on a Tuesday, or a weigh-in
/// corrected twice, are one day kept, so the figure never exceeds the seven
/// cells it is read against. A calendar week rather than a rolling seven days,
/// so the count does not fall on a Monday morning without anything having been
/// missed. Both habit tiles count this way, and so did the Consistency card
/// before them ([computeConsistency] calls this).
int daysKeptThisWeek(Iterable<int> dayKeys, {required DateTime today}) {
  final todayKey = dayKeyOf(today);
  // `weekday` is 1 for Monday, so this subtracts nothing on a Monday.
  final monday = dayKeyOf(daysBefore(today, today.weekday - 1));
  return {
    for (final key in dayKeys)
      if (key >= monday && key <= todayKey) key,
  }.length;
}
