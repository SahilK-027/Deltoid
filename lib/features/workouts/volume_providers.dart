import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/widgets/trend_chart.dart';
import '../../data/db/watch.dart';
import '../../domain/chart_buckets.dart';
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

/// How finely the weekly bars are folded, or null for "let the range decide".
///
/// Shared by the grid and a region for the same reason [volumeWindowProvider]
/// is: two charts of the same data, one control.
final volumeGranularityProvider = StateProvider<Granularity?>((ref) => null);

/// The most bars this screen will draw. See [volumeGranularityOf].
const _barCeiling = 400;

/// The averaging in force, **measured from the weeks actually in hand**.
///
/// Deliberately not from the window. The two disagree for as long as a query
/// takes: pick `All` on a thirty-year log and for a frame the control says
/// `All` — so the fold says yearly — while the series is still the thirteen
/// weeks of the range you left. Thirteen weeks folded yearly is *one bar*,
/// stretched across the whole chart, and that flash is what you see before the
/// real data lands.
///
/// Reading the span off the data cannot produce that: whatever is on screen is
/// folded at a level that suits it, and the level changes when the data does,
/// in the same frame.
///
/// Weekly is this feature's floor — a day is not a unit weekly volume has — so
/// `Auto` never resolves below it however short the span is.
Granularity volumeGranularityOf(VolumeHistory? history, Granularity? chosen) {
  // A span of at least a week, so an empty history resolves to something rather
  // than dividing by nothing.
  final days = ((history?.weekCount ?? 0) * 7).clamp(7, 1 << 30);
  return resolveGranularity(
    chosen,
    days,
    // A bar needs a point of width to be a bar; past this the chart is a solid
    // block of ink. A line has no such floor, which is why it offers more.
    ceiling: _barCeiling,
    // No daily: a week is this feature's smallest honest unit.
    allowed: const [
      Granularity.weekly,
      Granularity.monthly,
      Granularity.yearly,
    ],
  );
}

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

/// The span the screens are showing, clamped at both ends.
///
/// A calendar year that has not finished yet ends today, not on 31 December:
/// the span decides how many weeks an average divides by, and counting weeks
/// that have not happened would report a year in progress as a year of
/// half-training.
///
/// And `All` starts where **the log** starts, not where [TrendWindow.fromDayKey]
/// does — that is `0`, which is day zero of year zero, and folding a hundred
/// thousand empty weeks is not a chart, it is a hang. With nothing logged at
/// all it falls back to a year, which is what "all" honestly is then.
({int from, int to}) _spanOf(TrendWindow window, int? firstLogged) {
  final todayKey = dayKeyOf(DateTime.now());
  final from = window.isAll
      ? (firstLogged ??
          dayKeyOf(DateTime.now().subtract(const Duration(days: 365))))
      : window.fromDayKey;
  return (
    from: from,
    to: window.toDayKey > todayKey ? todayKey : window.toDayKey,
  );
}

/// The first day anything was logged, which `All` needs before it can name its
/// own left edge. Null on an empty log.
final firstLoggedDayProvider = FutureProvider<int?>((ref) async {
  return ref.watch(trainingRepositoryProvider).firstLoggedDayKey();
});

/// The same, as a date a chart can be scaled against.
DateTime? firstLoggedDay(WidgetRef ref) {
  final key = ref.watch(firstLoggedDayProvider).valueOrNull;
  return key == null ? null : dateFromDayKey(key);
}

/// Which movements produced a region's sets, over the selected span.
final regionExercisesProvider = StreamProvider.family<
    List<({String exerciseId, String name, int sets})>, MuscleRegion>(
  (ref, region) {
    final db = ref.watch(databaseProvider);
    final repo = ref.watch(trainingRepositoryProvider);
    final window = ref.watch(volumeWindowProvider);
    final firstLogged = ref.watch(firstLoggedDayProvider).valueOrNull;

    return db.watchQuery(
      [db.setLogs, db.workoutExercises, db.workouts, db.exercises],
      () async {
        final span = _spanOf(window, firstLogged);
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

  final firstLogged = ref.watch(firstLoggedDayProvider).valueOrNull;

  return db.watchQuery([db.setLogs, db.workoutExercises, db.workouts], () async {
    final span = _spanOf(window, firstLogged);
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
