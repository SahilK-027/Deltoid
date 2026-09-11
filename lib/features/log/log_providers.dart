import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import '../../domain/prefill.dart';
import '../../domain/session_diff.dart';

final workoutDetailProvider =
    StreamProvider.family<WorkoutDetail?, String>((ref, workoutId) {
  return ref.watch(trainingRepositoryProvider).watchWorkoutDetail(workoutId);
});

/// Every bodyweight ever logged, for the maths that needs it.
///
/// A pull-up's volume is bodyweight × reps; without this series a session of
/// nothing but bodyweight work totals zero, which is not a light session, it is
/// an unanswered question.
final bodyweightSeriesProvider =
    FutureProvider<List<({int dayKey, double weightKg})>>((ref) {
  return ref.watch(trainingRepositoryProvider).bodyweightSeries();
});

/// What today did that its session template doesn't know about — added
/// movements, dropped ones, a different running order.
///
/// Empty for an ad-hoc workout with no session behind it, and empty for the
/// common case of a day trained as written, which is what keeps the summary
/// screen quiet when there is nothing to ask about.
final sessionChangesProvider =
    FutureProvider.family<List<SessionChange>, String>((ref, workoutId) async {
  final detail = await ref.watch(workoutDetailProvider(workoutId).future);
  final sessionId = detail?.workout.sessionId;
  if (detail == null || sessionId == null) return const [];

  final repo = ref.watch(trainingRepositoryProvider);
  final template = await repo.sessionTemplate(sessionId);
  final targets = await repo.sessionSetTargets(sessionId);

  return [
    ...diffSession(
      template: template,
      // Everything on the workout, skips included: a skip is a decision about
      // one day, not a request to drop the movement from the programme.
      logged: [
        for (final e in detail.entries)
          (exerciseId: e.exercise.id, name: e.exercise.name),
      ],
    ),
    ...diffSetCounts(
      template: targets,
      logged: [
        for (final e in detail.entries)
          (
            exerciseId: e.exercise.id,
            workingDone: e.sets
                .where((s) =>
                    s.isDone &&
                    s.setType == SetType.working &&
                    s.parentSetId == null)
                .length,
            skipped: e.workoutExercise.skipReason != SkipReason.none,
          ),
      ],
      isDeload: detail.workout.isDeload,
    ),
  ];
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
/// Resolved once, an exercise added or swapped in at 19:40 reads "First time —
/// no previous log" with a year of history behind it, and — with no ghost to
/// adopt — a set typed with only reps is stored against a null weight.
final workoutPrefillProvider =
    FutureProvider.family<Map<String, PrefillResult>, String>(
        (ref, workoutId) async {
  // Watch the *identity* of the exercise list, not the whole detail. The detail
  // stream re-emits on every write to workouts, workout_exercises or set_logs —
  // once per completed set — and rebuilding this map on each of those rebuilds
  // every listener with it. The ids only change when an exercise is added,
  // swapped or removed, which is exactly when this map is stale.
  // Joined into a string on purpose: Dart lists compare by identity, so
  // selecting a List would rebuild every time regardless and quietly do
  // nothing at all.
  //
  // **Sorted**, because which order they are in is not one of the things that
  // makes this map stale. Unsorted, dragging a tab changed the key, which
  // re-walked every exercise's history through `resolvePrefill` — six
  // movements against fifty years of logs — for a result guaranteed to be
  // identical. That work lands on the frame the drop animation is trying to
  // play, which is what makes a reorder judder and then jump.
  final exerciseIds = await ref.watch(
    workoutDetailProvider(workoutId).selectAsync(
      (detail) => ([
        for (final e in detail?.entries ?? const []) e.exercise.id,
      ]..sort())
          .join(','),
    ),
  );

  final ids = [
    for (final id in exerciseIds.split(',')) if (id.isNotEmpty) id,
  ];

  // Resolved together, not one after another. Each exercise is its own chain of
  // queries across the database isolate's port, and awaiting them in series
  // makes the log screen's first paint the *sum* of six round trips instead of
  // the longest one.
  final results = await Future.wait([
    for (final exerciseId in ids)
      ref.watch(exercisePrefillProvider((
        workoutId: workoutId,
        exerciseId: exerciseId,
      )).future),
  ]);

  return {for (var i = 0; i < ids.length; i++) ids[i]: results[i]};
});
