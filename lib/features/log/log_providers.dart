import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/prefill.dart';

final workoutDetailProvider =
    StreamProvider.family<WorkoutDetail?, String>((ref, workoutId) {
  return ref.watch(trainingRepositoryProvider).watchWorkoutDetail(workoutId);
});

/// Last-time numbers for every exercise in a workout, keyed by exercise id.
///
/// Resolved once when the log opens rather than per set row — the lookup walks
/// history and shouldn't run on every keystroke.
final workoutPrefillProvider =
    FutureProvider.family<Map<String, PrefillResult>, String>(
        (ref, workoutId) async {
  final repo = ref.watch(trainingRepositoryProvider);
  final db = ref.watch(databaseProvider);

  final detail = await repo.workoutDetail(workoutId);
  if (detail == null) return {};

  final regime = await (db.select(db.regimes)
        ..where((t) => t.id.equals(detail.workout.regimeId)))
      .getSingleOrNull();

  final out = <String, PrefillResult>{};
  for (final entry in detail.entries) {
    final past = await repo.pastPerformances(
      entry.exercise.id,
      limit: 30,
      excludeWorkoutId: workoutId,
    );
    out[entry.exercise.id] = resolvePrefill(
      candidates: past,
      sessionId: detail.workout.sessionId,
      targetIsDeload: detail.workout.isDeload,
      deloadSetDelta: regime?.deloadSetDelta ?? -1,
      deloadWeightPct: regime?.deloadWeightPct ?? 80,
    );
  }
  return out;
});
