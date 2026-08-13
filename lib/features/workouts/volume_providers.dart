import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/widgets/trend_chart.dart';
import '../../data/db/watch.dart';
import '../../domain/muscle_volume.dart';
import '../../domain/volume_history.dart';

/// The span the volume screens are showing.
///
/// One notifier for both screens on purpose: opening Legs from a 1Y grid and
/// finding it reset to 3M is the range control forgetting what you just asked
/// it. It is not `autoDispose` for the same reason — going back up to the grid
/// must not throw the span away.
///
/// Defaults to three months rather than to the shortest range: one month of
/// weekly bars is four bars, which is a number wearing a chart's clothes.
final volumeWindowProvider = StateProvider<TrendWindow>(
  (ref) => const TrendWindow.rolling(ChartRange.threeMonths),
);

/// Years the picker offers: every year from your first logged set to this one,
/// newest first.
///
/// Built from the first day rather than from a list of distinct years, which
/// would be a second aggregate query to remove a case that barely exists — a
/// whole calendar year inside your own training history with nothing logged in
/// it. That year is offered and draws an empty chart, which is a true statement
/// about that year. What the picker must never do is offer a year *before* you
/// started, and this cannot.
final volumeYearsProvider = FutureProvider<List<int>>((ref) async {
  final repo = ref.watch(trainingRepositoryProvider);
  final first = await repo.firstLoggedDayKey();
  if (first == null) return const [];
  final firstYear = first ~/ 10000;
  final thisYear = DateTime.now().year;
  return [
    for (var y = thisYear; y >= firstYear; y--) y,
  ];
});

/// The span the screens are showing, clamped to today.
///
/// A calendar year that has not finished yet ends today, not on 31 December:
/// the span decides how many weeks an average divides by, and counting weeks
/// that have not happened would report a year in progress as a year of
/// half-training.
({int from, int to}) _spanOf(TrendWindow window) {
  final todayKey = dayKeyOf(DateTime.now());
  return (
    from: window.fromDayKey,
    to: window.toDayKey > todayKey ? todayKey : window.toDayKey,
  );
}

/// Which movements produced a region's sets, over the selected span.
final regionExercisesProvider = StreamProvider.family<
    List<({String exerciseId, String name, int sets})>, MuscleRegion>(
  (ref, region) {
    final db = ref.watch(databaseProvider);
    final repo = ref.watch(trainingRepositoryProvider);
    final window = ref.watch(volumeWindowProvider);

    return db.watchQuery(
      [db.setLogs, db.workoutExercises, db.workouts, db.exercises],
      () async {
        final span = _spanOf(window);
        return repo.setsByExercise(
          fromDayKey: span.from,
          toDayKey: span.to,
          muscles: region.parts,
        );
      },
    );
  },
);

/// Weekly sets per muscle across [volumeWindowProvider].
///
/// Watches the same three tables Workouts' bars do, so a set ticked mid-session
/// moves this week's bar while you are standing in the session — the screens
/// agree because they read the same rows through the same filters.
final volumeHistoryProvider = StreamProvider<VolumeHistory>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(trainingRepositoryProvider);
  final window = ref.watch(volumeWindowProvider);

  return db.watchQuery([db.setLogs, db.workoutExercises, db.workouts], () async {
    final span = _spanOf(window);
    return computeVolumeHistory(
      daily: await repo.setsByMuscleDaily(
        fromDayKey: span.from,
        toDayKey: span.to,
      ),
      from: dateFromDayKey(span.from),
      to: dateFromDayKey(span.to),
    );
  });
});
