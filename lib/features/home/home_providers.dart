import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/db/watch.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/muscle_volume.dart';
import 'heatmap_data.dart';

/// How far back the consistency grid looks.
///
/// Chosen to *fill* the card rather than as a round number: thirteen columns of
/// 14pt cells left ~90pt of dead space down the right-hand side of every phone
/// wider than a 5s. Eighteen fills the same width at the same cell size, so the
/// grid got taller in information without getting taller in pixels — which
/// matters, because it has to clear the fold.
const heatmapWeeks = 18;

/// Workouts, as one value that arrives all at once.
///
/// See [TodaySnapshot] for why this is a single query rather than the dozen
/// watched providers it replaced. The screen holds the last value while a
/// reload is in flight, so a write elsewhere never blanks it either.
class HomeData {
  const HomeData({required this.snapshot, required this.heatmap});

  final TodaySnapshot snapshot;
  final HeatmapData heatmap;

  Regime? get regime => snapshot.regime;
  List<Session> get sessions => snapshot.sessions;
  Workout? get openWorkout => snapshot.openWorkout;
  bool get hasHistory => snapshot.hasHistory;
  ({Workout workout, String? sessionName})? get lastCompleted =>
      snapshot.lastCompleted;
}

/// Every day ever logged, for the full-history heatmap behind the Workouts grid.
///
/// **Kept alive, and warmed while Workouts is on screen.** `autoDispose` would
/// argue that a year-by-year view is worth a query when it is opened — but
/// "when it is opened" is precisely the moment there is nothing to draw, and
/// the screen renders blank until the query comes back. The data is on local
/// disk and it is one row per day: it should be sitting there before the route
/// animation finishes, not started by it.
final fullHeatmapProvider = StreamProvider<HeatmapData>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(trainingRepositoryProvider);

  return db.watchQuery(
    [db.workouts],
    () async => buildHeatmapFromDays(await repo.loggedDays()),
  );
});

/// This week's hard sets per muscle, for the bar list under the heatmap.
///
/// Its own provider rather than a field on [HomeData], and this is the one
/// place that split is right: `todaySnapshot` is what the screen *is* — a
/// missing field there is a frame where "no sessions" is indistinguishable from
/// "not loaded yet" (RULES § Data). The bars are a section further down that
/// has an
/// honest empty state of its own, so a frame without them costs nothing, and
/// they are the only thing in the app that reads `set_logs` for Workouts. Folding
/// this query into the snapshot would re-run the whole screen's read on every
/// set you tick mid-session.
final weeklyVolumeProvider = StreamProvider<WeeklyVolume>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(trainingRepositoryProvider);

  return db.watchQuery([db.setLogs, db.workoutExercises, db.workouts], () async {
    // `volumeWindowDays - 1`, because the window includes today — the same
    // off-by-one `computeConsistency` documents.
    final from = dayKeyOf(daysBefore(DateTime.now(), volumeWindowDays - 1));
    return computeWeeklyVolume(setsByMuscle: await repo.setsByMuscleSince(from));
  });
});

/// Ticked and total sets in the open workout, kept in step with the log.
///
/// Its own query rather than a field read off [homeProvider], for the same
/// reason [weeklyVolumeProvider] is one: `todaySnapshot` does not watch
/// `set_logs`, and must not, or every keystroke in a live session would re-run
/// the whole screen's read. But the resume card counts sets and the stale
/// session's prompts promise how many would be lost, and a number frozen at the
/// moment Start was tapped leaves all three wrong — "0 of 18 sets" over two
/// that were logged, and "nothing was logged in it, so nothing is lost" over
/// work that discarding does delete.
///
/// Two counts and no join to anything else, so it is cheap enough to re-run on
/// a set being ticked. The snapshot's figures stand in until it lands, so the
/// card never shows a blank where a number belongs.
final openWorkoutSetsProvider =
    StreamProvider.family<({int done, int total}), String>((ref, workoutId) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(trainingRepositoryProvider);

  return db.watchQuery(
    [db.setLogs, db.workoutExercises],
    () async => (
      done: await repo.doneSetCount(workoutId),
      total: await repo.setCount(workoutId),
    ),
  );
});

final homeProvider = StreamProvider<HomeData>((ref) {
  // Gated on the seeder rather than racing it: this watches `exercises` for
  // renames, and a first launch would otherwise load an empty catalog and then
  // immediately reload when the starter rows land.
  final init = ref.watch(appInitProvider);
  if (!init.hasValue) return const Stream.empty();

  final db = ref.watch(databaseProvider);
  final repo = ref.watch(trainingRepositoryProvider);

  return db.watchQuery(
    [
      db.regimes,
      db.sessions,
      db.sessionExercises,
      db.exercises,
      db.workouts,
      db.cycles,
    ],
    () async {
      final from = dayKeyOf(daysBefore(DateTime.now(), heatmapWeeks * 7 + 7));
      final snapshot = await repo.todaySnapshot(heatmapFromDayKey: from);
      return HomeData(
        snapshot: snapshot,
        heatmap: buildHeatmap(snapshot.recentCompleted),
      );
    },
  );
});
