import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/prefill.dart';

final workoutDetailProvider =
    StreamProvider.family<WorkoutDetail?, String>((ref, workoutId) {
  return ref.watch(trainingRepositoryProvider).watchWorkoutDetail(workoutId);
});

/// Ticks when the shape of history changes — a workout deleted or backdated,
/// an exercise added or swapped — and deliberately *not* when a set is
/// written, which happens on every keystroke. Emits immediately so anything
/// awaiting it resolves on first build rather than on the first edit.
final historyShapeProvider = StreamProvider<int>((ref) async* {
  var ticks = 0;
  yield ticks;
  await for (final _
      in ref.watch(trainingRepositoryProvider).historyShapeChanges()) {
    yield ++ticks;
  }
});

/// One exercise's last-time numbers, in the context of one workout.
///
/// The unit of resolution is the exercise, not the workout: adding a seventh
/// movement mid-session must not re-walk history for the six already on screen,
/// and the six must not be recomputed just because the seventh arrived.
final exercisePrefillProvider = FutureProvider.family<
    PrefillResult,
    ({String workoutId, String exerciseId})>((ref, key) async {
  // Re-resolve when logged history changes. Deleting a past workout is
  // reachable from History while a session is open, and without this the
  // ghosts in the running log keep showing numbers from the day just deleted.
  // Finding 2 fixed the added-exercise case; this is its mirror.
  await ref.watch(historyShapeProvider.future);

  return ref.watch(trainingRepositoryProvider).prefillForWorkout(
        workoutId: key.workoutId,
        exerciseId: key.exerciseId,
      );
});

/// Last-time numbers for every exercise in a workout, keyed by exercise id.
///
/// Watches the workout rather than being resolved once when the log opens.
/// Resolving once meant an exercise added or swapped in at 19:40 read "First
/// time — no previous log" with a year of history behind it, and — because
/// there was no ghost to adopt — a set typed with only reps was stored against
/// a null weight.
final workoutPrefillProvider =
    FutureProvider.family<Map<String, PrefillResult>, String>(
        (ref, workoutId) async {
  final detail = await ref.watch(workoutDetailProvider(workoutId).future);
  if (detail == null) return const {};

  final out = <String, PrefillResult>{};
  for (final entry in detail.entries) {
    out[entry.exercise.id] = await ref.watch(
      exercisePrefillProvider((
        workoutId: workoutId,
        exerciseId: entry.exercise.id,
      )).future,
    );
  }
  return out;
});
