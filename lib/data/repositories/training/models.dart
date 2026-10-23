import '../../../domain/cycle_engine.dart';
import '../../../domain/cycle_progress.dart';
import '../../../domain/enums.dart';
import '../../db/database.dart';
import '../../../domain/session_name.dart';

/// A workout exercise joined with its catalog row — what every log and history
/// view actually needs.
class ExerciseEntry {
  const ExerciseEntry({
    required this.workoutExercise,
    required this.exercise,
    required this.sets,
  });

  final WorkoutExercise workoutExercise;
  final Exercise exercise;
  final List<SetLog> sets;
}

/// Everything the Today screen renders, in one value.
///
/// The screen's regime, its sessions, the cycle status and the per-session
/// slot counts resolve together, from a single watched query. Assembling them
/// from separate queries would layer them by dependency and resolve each layer
/// a frame or two after the one above it, revealing a screen whose answers are
/// already on disk in stages; it would also make the frame before `sessions`
/// arrives indistinguishable from a regime with no sessions, flashing the
/// "no sessions" empty state at someone who has five.
class TodaySnapshot {
  const TodaySnapshot({
    required this.regime,
    required this.sessions,
    required this.status,
    required this.openWorkout,
    required this.openWorkoutOwner,
    required this.openWorkoutDoneSets,
    required this.openWorkoutTotalSets,
    required this.openWorkoutExerciseNames,
    required this.hasHistory,
    required this.exerciseNamesBySession,
    required this.recentCompleted,
    required this.lastCompleted,
  });

  final Regime? regime;
  final List<Session> sessions;

  /// Null only when there is no active regime.
  final CycleStatus? status;

  final Workout? openWorkout;

  /// The open workout's own session and regime, which are not necessarily the
  /// active regime's — see [workoutOwner].
  final ({String? sessionName, String regimeId, String? regimeName})?
      openWorkoutOwner;

  /// Sets actually ticked off in the open workout. Zero for a session started
  /// and never worked in. This distinguishes a session left running from one
  /// started by a mis-tap several days earlier, which is the sole criterion
  /// determining whether the application may discard it automatically.
  final int openWorkoutDoneSets;

  /// Every set row in the open workout, done or not — the denominator Today
  /// puts beside [openWorkoutDoneSets].
  final int openWorkoutTotalSets;

  /// Exercise names in the open workout, in slot order.
  ///
  /// Read from `workoutExercises` rather than from the session template: the log
  /// is
  /// a snapshot taken at Start, so an exercise swapped out of the programme
  /// since then remains in the session currently open.
  final List<String> openWorkoutExerciseNames;

  /// Whether anything has ever been finished — "brand new install" as opposed
  /// to "regime set up, nothing logged yet".
  final bool hasHistory;

  /// The most recently finished workout, whatever regime it belonged to.
  ///
  /// Not read off the tail of [recentCompleted]: that list is bounded by the
  /// heatmap window, so coming back after a long layoff would report "nothing
  /// logged yet" at someone with a year of history.
  final ({Workout workout, String? sessionName})? lastCompleted;

  /// Exercise names per session id, in slot order. Doubles as the slot count
  /// that decides whether a session row offers "start" or "add exercises".
  final Map<String, List<String>> exerciseNamesBySession;

  /// Completed workouts recent enough to appear on the consistency heatmap.
  final List<Workout> recentCompleted;
}

class WorkoutDetail {
  const WorkoutDetail({
    required this.workout,
    required this.session,
    required this.entries,
  });

  final Workout workout;
  final Session? session;
  final List<ExerciseEntry> entries;
}


/// What a lift is called, for the screen that lists lifts rather than numbers.
///
/// A [LiftId] is a pair of ids and deliberately says nothing a person can read.
/// The names come back beside it rather than inside it so that the domain layer
/// keeps comparing ids and the screen keeps printing words.
class LiftLabel {
  const LiftLabel({required this.exerciseName, required this.sessionName});

  final String exerciseName;
  final String sessionName;
}

/// A regime's cycle progress, with everything the three surfaces print.
class RegimeProgress {
  const RegimeProgress({
    required this.regimeId,
    required this.regimeName,
    required this.identityIndex,
    required this.isActive,
    required this.progress,
    required this.labels,
  });

  final String regimeId;
  final String regimeName;

  /// Which identity colour the regime wears, so the timeline and the card agree
  /// without either of them deciding.
  final int identityIndex;

  final bool isActive;

  final CycleProgress progress;

  /// A name for every lift in [progress]. Complete: a lift that scored has a
  /// slot, and a slot has an exercise.
  final Map<LiftId, LiftLabel> labels;

  LiftLabel labelOf(LiftId lift) =>
      labels[lift] ??
      const LiftLabel(exerciseName: '', sessionName: customSessionName);
}

/// A regime reduced to what a list needs of it.
class RegimeMark {
  const RegimeMark({
    required this.id,
    required this.name,
    required this.identityIndex,
    required this.isActive,
  });

  final String id;
  final String name;

  /// Which identity colour the regime wears, so the timeline, the legend and
  /// the cards agree without any of them deciding.
  final int identityIndex;

  final bool isActive;
}

/// One scored performance on the progress chart.
class ProgressPoint {
  const ProgressPoint({
    required this.dayKey,
    required this.sessionId,
    required this.sessionName,
    required this.isDeload,
    required this.topSetLoad,
    required this.topSetReps,
    required this.best1RM,
    required this.volume,
  });

  final int dayKey;
  final String? sessionId;
  final String sessionName;
  final bool isDeload;
  final double? topSetLoad;
  final int? topSetReps;
  final double? best1RM;
  final double volume;
}

/// What History's masthead says about itself: how much there is and how far
/// back it goes. Both null on an empty database — a span is not zero, it is
/// absent, and the header prints neither rather than inventing a date.
class HistoryOverview {
  const HistoryOverview({
    required this.sessions,
    required this.firstDayKey,
    required this.lastDayKey,
  });

  final int sessions;

  final int? firstDayKey;
  final int? lastDayKey;

  /// Whether the history covers more than one calendar month. Below that,
  /// "since July 2026" is a span dressed up out of a single day.
  bool get spansMonths {
    final first = firstDayKey;
    final last = lastDayKey;
    if (first == null || last == null) return false;
    return first ~/ 100 != last ~/ 100;
  }

  bool get isEmpty => sessions == 0;
}

/// Where a page of history ended, so the next page can continue from it.
///
/// Keyset rather than an offset: history is written to while it is being read
/// (finishing a session appends a row at the top), and an offset would silently
/// skip or repeat rows when that happens.
class HistoryCursor {
  const HistoryCursor({required this.startedAt, required this.id});

  final int startedAt;
  final String id;
}

/// One row in the history feed. Cheap enough to page through hundreds of them:
/// counts are aggregated in SQL, sets are not loaded.
class WorkoutSummary {
  const WorkoutSummary({
    required this.workout,
    required this.sessionName,
    required this.exerciseNames,
    required this.exerciseCount,
    required this.setCount,
    required this.skippedCount,
  });

  final Workout workout;

  /// Null when the session template has since been deleted.
  final String? sessionName;

  /// In the order they were performed. The history row prints them as one
  /// ellipsized line: what a day *was* is the movements in it, not a count.
  final List<String> exerciseNames;

  final int exerciseCount;
  final int setCount;
  final int skippedCount;

  HistoryCursor get cursor =>
      HistoryCursor(startedAt: workout.startedAt, id: workout.id);

  /// Minutes on the clock, when the session was finished rather than abandoned.
  int? get durationMinutes {
    final ended = workout.endedAt;
    if (ended == null) return null;
    final minutes = (ended - workout.startedAt) ~/ 60000;
    return minutes < 0 ? null : minutes;
  }
}

/// One calendar day that was trained, with only the facts a grid needs.
class LoggedDay {
  const LoggedDay({
    required this.dayKey,
    required this.workouts,
    required this.isDeload,
    required this.anyWorkoutId,
  });

  final int dayKey;
  final int workouts;

  /// True when any workout that day was a light week.
  final bool isDeload;

  /// One of the day's workouts, so a day on the calendar can be opened.
  final String anyWorkoutId;
}

/// A training day that appears in history, for the feed's filter.
class LoggedSession {
  const LoggedSession({
    required this.sessionId,
    required this.name,
    required this.regimeName,
    required this.workouts,
    required this.lastDayKey,
  });

  final String sessionId;
  final String name;

  /// Two regimes can both have a `Push 1`, so the row says which.
  final String regimeName;

  final int workouts;
  final int lastDayKey;
}

/// An exercise that has actually been trained, for the history index.
class ExerciseHistorySummary {
  const ExerciseHistorySummary({
    required this.exercise,
    required this.timesPerformed,
    required this.lastDayKey,
  });

  final Exercise exercise;
  final int timesPerformed;
  final int lastDayKey;
}

/// One past performance of a single exercise, with the numbers already scored.
class ExercisePerformance {
  const ExercisePerformance({
    required this.workoutId,
    required this.dayKey,
    required this.startedAt,
    required this.sessionId,
    required this.sessionName,
    required this.isDeload,
    required this.skipReason,
    required this.sets,
    required this.topSetLoad,
    required this.topSetReps,
    required this.best1RM,
  });

  final String workoutId;
  final int dayKey;
  final int startedAt;
  final String? sessionId;
  final String sessionName;
  final bool isDeload;
  final SkipReason skipReason;
  final List<SetLog> sets;
  final double? topSetLoad;
  final int? topSetReps;
  final double? best1RM;

  HistoryCursor get cursor => HistoryCursor(startedAt: startedAt, id: workoutId);
}
