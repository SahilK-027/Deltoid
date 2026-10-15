import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/features/home/heatmap_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday 15 July 2026.
///
/// Worked out rather than looked up: 1 January 2026 is a Thursday, 15 July is
/// day 196 of the year, and 195 mod 7 is 6 — six days on from Thursday is
/// Wednesday. So `weekday` is 3 and the Monday of this week is the 13th, which
/// is what every `thisWeek` literal below is counted against.
final _today = DateTime(2026, 7, 15, 9);

/// A completed workout, with only the columns the two folds read.
Workout _workout(String id, int dayKey, {bool isDeload = false}) => Workout(
      id: id,
      updatedAt: 0,
      deviceId: 'test',
      dirty: false,
      regimeId: 'r',
      dayKey: dayKey,
      startedAt: 0,
      tzOffsetMinutes: 330,
      isDeload: isDeload,
      status: WorkoutStatus.completed,
    );

void main() {
  // Four sessions, three days: one well back, two on one Monday, one today.
  //
  //   1 June  — w-1
  //  17 June  — w-b, the last day outside the 28-day window
  //  18 June  — w-a, the first day inside it
  //  13 July  — w-2, w-3 (w-3 a deload)
  //  15 July  — w-4  (today)
  //
  // The 17th and the 18th are there on purpose, and **both** are needed. With
  // no session on the boundary, moving the cutoff by a day lands in the empty
  // stretch between 1 June and 13 July and changes no count, so the window
  // arithmetic below would be asserted and not tested — which is exactly what
  // happened to the first draft of this fixture. One day either side of the
  // cutoff makes an off-by-one in either direction move `sessions`.
  final rows = [
    _workout('w-1', 20260601),
    _workout('w-b', 20260617),
    _workout('w-a', 20260618),
    _workout('w-2', 20260713),
    _workout('w-3', 20260713, isDeload: true),
    _workout('w-4', 20260715),
  ];

  // The same history as SQL folds it: one row per day, `count`, `max(isDeload)`
  // and `max(id)`.
  const folded = [
    LoggedDay(
        dayKey: 20260601, workouts: 1, isDeload: false, anyWorkoutId: 'w-1'),
    LoggedDay(
        dayKey: 20260617, workouts: 1, isDeload: false, anyWorkoutId: 'w-b'),
    LoggedDay(
        dayKey: 20260618, workouts: 1, isDeload: false, anyWorkoutId: 'w-a'),
    LoggedDay(
        dayKey: 20260713, workouts: 2, isDeload: true, anyWorkoutId: 'w-3'),
    LoggedDay(
        dayKey: 20260715, workouts: 1, isDeload: false, anyWorkoutId: 'w-4'),
  ];

  test('a day is counted, and a light day says so', () {
    final grid = buildHeatmap(rows, today: _today).days;

    expect(grid.keys.toSet(), {20260601, 20260617, 20260618, 20260713, 20260715});
    expect(grid[20260713]!.workouts, 2);
    expect(grid[20260713]!.isDeload, isTrue,
        reason: 'one deload in the day makes the day a light one');
    expect(grid[20260601]!.workouts, 1);
    expect(grid[20260601]!.isDeload, isFalse);
  });

  test('a two-session day opens the same workout on both grids', () {
    // The query behind `buildHeatmap` orders on `dayKey` alone, so the order
    // within a day is whatever SQLite gives — `w-2` first here, `w-3` first on
    // the next run. `loggedDays` takes `max(id)` and says in its own comment
    // that it has to be *some* deterministic one. The fold had no such rule.
    expect(buildHeatmap(rows, today: _today).days[20260713]!.workoutId, 'w-3');
    expect(
      buildHeatmap(rows.reversed.toList(), today: _today)
          .days[20260713]!
          .workoutId,
      'w-3',
      reason: 'the answer cannot depend on the order the rows arrive in',
    );
    expect(
      buildHeatmapFromDays(folded, today: _today).days[20260713]!.workoutId,
      'w-3',
    );
  });

  test('the rate is what the sessions say', () {
    // First key 20260601, today 20260715. June has 30 days, so 1 June to 1 July
    // is 30 days and 1 July to 15 July is 14: 44 days apart, and both ends
    // count, so historyDays is 45.
    //
    // windowDays = 45 clamped to 28. The window opens 27 days before today:
    // 15 July back 15 days is 30 June, back another 12 is 18 June.
    //
    // Sessions on or after 20260618: 18 June once, 13 July twice, 15 July once
    // — four. 1 June and 17 June are outside it; 18 June is the boundary,
    // which is inclusive.
    //
    // perWeek = 4 / (28 / 7) = 4 / 4 = 1.0.
    //
    // thisWeek counts *days*, not sessions, from Monday the 13th: the 13th and
    // the 15th, so two.
    final c = buildHeatmap(rows, today: _today).consistency;

    expect(c.historyDays, 45);
    expect(c.windowDays, 28);
    expect(c.sessions, 4);
    expect(c.thisWeek, 2);
    expect(c.perWeek, closeTo(1.0, 1e-9));
  });

  test('both heatmap paths agree on the same history', () {
    // The re-expansion in `buildHeatmapFromDays` — one key per session rather
    // than per day — exists solely to make this true, and nothing checked that
    // it did. A day with two sessions is where it would show: fold it once and
    // the rate is a third lower.
    final fromRows = buildHeatmap(rows, today: _today);
    final fromDays = buildHeatmapFromDays(folded, today: _today);

    expect(fromDays.days.keys.toSet(), fromRows.days.keys.toSet());
    for (final key in fromRows.days.keys) {
      final a = fromRows.days[key]!;
      final b = fromDays.days[key]!;
      expect(b.workouts, a.workouts, reason: '$key sessions');
      expect(b.isDeload, a.isDeload, reason: '$key deload');
      expect(b.workoutId, a.workoutId, reason: '$key workout to open');
    }

    expect(fromDays.consistency.sessions, fromRows.consistency.sessions);
    expect(fromDays.consistency.thisWeek, fromRows.consistency.thisWeek);
    expect(fromDays.consistency.windowDays, fromRows.consistency.windowDays);
    expect(fromDays.consistency.historyDays, fromRows.consistency.historyDays);
    expect(fromDays.consistency.perWeek, fromRows.consistency.perWeek);
  });

  test('no history is no rate, not a rate of zero', () {
    final empty = buildHeatmap(const [], today: _today);
    expect(empty.days, isEmpty);
    expect(empty.consistency.sessions, 0);
    expect(empty.consistency.perWeek, isNull);

    expect(buildHeatmapFromDays(const [], today: _today).consistency.perWeek,
        isNull);
  });
}
