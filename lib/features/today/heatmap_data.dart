import '../../data/db/database.dart';
import '../../domain/consistency.dart';

/// One day on the consistency heatmap.
class HeatDay {
  const HeatDay({
    required this.workouts,
    required this.isDeload,
    this.workoutIds = const [],
  });

  final int workouts;

  /// Deload days render in a different hue — an easy week should be visibly an
  /// easy week, not a gap in the record.
  final bool isDeload;

  /// What was logged that day, oldest first. Carried so a day picked on the
  /// calendar can open the workout it already holds instead of only offering to
  /// write a second one.
  final List<String> workoutIds;
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
      workoutIds: [...?existing?.workoutIds, w.id],
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
