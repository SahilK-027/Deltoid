import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/consistency.dart';

/// One day on the consistency heatmap.
class HeatDay {
  const HeatDay({
    required this.workouts,
    required this.isDeload,
    this.workoutId,
  });

  final int workouts;

  /// Deload days render in a different hue — an easy week should be visibly an
  /// easy week, not a gap in the record.
  final bool isDeload;

  /// One of the day's workouts, so a day picked on the calendar can open what
  /// it already holds instead of only offering to write a second one. Null when
  /// the day came from a source that does not carry ids.
  final String? workoutId;
}

class HeatmapData {
  const HeatmapData({required this.days, required this.consistency});

  final Map<int, HeatDay> days;

  /// How often you have been training. The number that used to live in a
  /// second app — see [computeConsistency] for why it is not always a rate.
  final Consistency consistency;
}

/// Folds completed workouts into the grid.
///
/// Takes rows rather than fetching them: they arrive with the rest of Workouts in
/// one query, so the grid is no longer a card that fills in a few frames late.
/// [today] is the seam the tests need and nothing else passes: a grid folded
/// against `DateTime.now()` can be checked for its `days` and never for its
/// rate.
HeatmapData buildHeatmap(List<Workout> completed, {DateTime? today}) {
  final days = <int, HeatDay>{};
  for (final w in completed) {
    final existing = days[w.dayKey];
    days[w.dayKey] = HeatDay(
      workouts: (existing?.workouts ?? 0) + 1,
      isDeload: (existing?.isDeload ?? false) || w.isDeload,
      // **The largest id, matching `loggedDays`' `max(id)`.** It used to be the
      // first row of the day the loop happened to see, and the query behind it
      // orders on `dayKey` alone — so on a day with two sessions the grid on
      // Today opened whichever workout SQLite handed over first, while the
      // all-time grid opened the newest. Same day, same tap, two screens, two
      // sessions. Neither choice is more right than the other; agreeing is,
      // and only one of the two was deterministic.
      workoutId: _larger(existing?.workoutId, w.id),
    );
  }

  return HeatmapData(
    days: days,
    consistency: computeConsistency(
      completedDayKeys: completed.map((w) => w.dayKey),
      today: today ?? DateTime.now(),
    ),
  );
}

/// `max` over two ids, treating a missing one as no candidate. Ids are UUID v7,
/// so this is also the newest.
String _larger(String? a, String b) =>
    a == null || b.compareTo(a) > 0 ? b : a;

/// The same grid, from rows SQL has already folded by day.
///
/// What the all-time view uses. A day's session count still counts twice
/// towards the rate — [computeConsistency] wants one key per session — so the
/// keys are expanded back out, which is a few thousand integers rather than a
/// few thousand objects across an isolate port.
HeatmapData buildHeatmapFromDays(List<LoggedDay> logged, {DateTime? today}) {
  return HeatmapData(
    days: {
      for (final d in logged)
        d.dayKey: HeatDay(
          workouts: d.workouts,
          isDeload: d.isDeload,
          workoutId: d.anyWorkoutId,
        ),
    },
    consistency: computeConsistency(
      completedDayKeys: [
        for (final d in logged)
          for (var i = 0; i < d.workouts; i++) d.dayKey,
      ],
      today: today ?? DateTime.now(),
    ),
  );
}
