import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/db/watch.dart';
import '../../data/repositories/training_repository.dart';
import 'heatmap_data.dart';

/// How far back the consistency grid looks.
///
/// Chosen to *fill* the card rather than as a round number: thirteen columns of
/// 14pt cells left ~90pt of dead space down the right-hand side of every phone
/// wider than a 5s. Eighteen fills the same width at the same cell size, so the
/// grid got taller in information without getting taller in pixels — which
/// matters, because it has to clear the fold.
const heatmapWeeks = 18;

/// Today, as one value that arrives all at once.
///
/// See [TodaySnapshot] for why this is a single query rather than the dozen
/// watched providers it replaced. The screen holds the last value while a
/// reload is in flight, so a write elsewhere never blanks it either.
class TodayData {
  const TodayData({required this.snapshot, required this.heatmap});

  final TodaySnapshot snapshot;
  final HeatmapData heatmap;

  Regime? get regime => snapshot.regime;
  List<Session> get sessions => snapshot.sessions;
  Workout? get openWorkout => snapshot.openWorkout;
  bool get hasHistory => snapshot.hasHistory;
  ({Workout workout, String? sessionName})? get lastCompleted =>
      snapshot.lastCompleted;
}

/// Every day ever logged, for the full-history heatmap behind Today's grid.
///
/// Its own provider, and `autoDispose`: Today reads thirteen weeks on every
/// write to any of six tables, and a year-by-year view is worth a second query
/// when it is opened rather than a permanent tax on the first screen.
final fullHeatmapProvider = StreamProvider.autoDispose<HeatmapData>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(trainingRepositoryProvider);

  return db.watchQuery(
    [db.workouts],
    () async => buildHeatmap(await repo.allCompleted()),
  );
});

final todayProvider = StreamProvider<TodayData>((ref) {
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
      final from = dayKeyOf(
        DateTime.now().subtract(const Duration(days: heatmapWeeks * 7 + 7)),
      );
      final snapshot = await repo.todaySnapshot(heatmapFromDayKey: from);
      return TodayData(
        snapshot: snapshot,
        heatmap: buildHeatmap(snapshot.recentCompleted),
      );
    },
  );
});
