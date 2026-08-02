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
/// Takes rows rather than fetching them: they arrive with the rest of Today in
/// one query, so the grid is no longer a card that fills in a few frames late.
HeatmapData buildHeatmap(List<Workout> completed) {
  final days = <int, HeatDay>{};
  for (final w in completed) {
    final existing = days[w.dayKey];
    days[w.dayKey] = HeatDay(
      workouts: (existing?.workouts ?? 0) + 1,
      isDeload: (existing?.isDeload ?? false) || w.isDeload,
      workoutId: existing?.workoutId ?? w.id,
    );
  }

  return HeatmapData(
    days: days,
    consistency: computeConsistency(
      completedDayKeys: completed.map((w) => w.dayKey),
      today: DateTime.now(),
    ),
  );
}

/// The same grid, from rows SQL has already folded by day.
///
/// What the all-time view uses. A day's session count still counts twice
/// towards the rate — [computeConsistency] wants one key per session — so the
/// keys are expanded back out, which is a few thousand integers rather than a
/// few thousand objects across an isolate port.
HeatmapData buildHeatmapFromDays(List<LoggedDay> logged) {
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
      today: DateTime.now(),
    ),
  );
}
