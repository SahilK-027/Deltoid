import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/enums.dart';
import 'converters.dart';

/// Columns every syncable row carries.
///
/// [updatedAt] drives last-write-wins merging, [deletedAt] is a tombstone so a
/// delete on one device propagates instead of being resurrected by the other,
/// and [dirty] marks rows the local device still owes the server.
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  IntColumn get updatedAt => integer().clientDefault(nowMs)();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The exercise catalog. Shared across every regime — swapping PPL for
/// upper/lower reuses these rows, which is what keeps history comparable.
class Exercises extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get muscle => textEnum<MuscleGroup>()();
  TextColumn get equipment => textEnum<Equipment>()();
  TextColumn get loadMode => textEnum<LoadMode>()();
  BoolColumn get isUnilateral => boolean().withDefault(const Constant(false))();
  TextColumn get formVideoUrls =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// A training programme: an ordered set of sessions plus its deload policy.
///
/// Switching regimes creates a new row rather than editing sessions in place,
/// so past history keeps pointing at the programme it was actually run under.
class Regimes extends Table with SyncColumns {
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  BoolColumn get deloadEnabled => boolean().withDefault(const Constant(true))();

  /// Number of completed cycles between deloads.
  IntColumn get deloadAfterCycles => integer().withDefault(const Constant(6))();

  /// Added to each exercise's target set count during a deload cycle. Negative.
  /// Floored at 1 set when applied.
  IntColumn get deloadSetDelta => integer().withDefault(const Constant(-1))();

  /// Percentage of the last working weight prefilled during a deload cycle.
  IntColumn get deloadWeightPct => integer().withDefault(const Constant(80))();

  IntColumn get createdAt => integer().clientDefault(nowMs)();
}

/// One training day template within a regime: "Push 1", "Pull 2", "Lower A".
@TableIndex(name: 'idx_sessions_regime', columns: {#regimeId})
class Sessions extends Table with SyncColumns {
  TextColumn get regimeId => text().references(Regimes, #id)();
  TextColumn get name => text()();
  IntColumn get orderIndex => integer()();
}

/// An exercise slot inside a session template.
@TableIndex(name: 'idx_session_exercises_session', columns: {#sessionId})
class SessionExercises extends Table with SyncColumns {
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get orderIndex => integer()();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get targetRepLow => integer().nullable()();
  IntColumn get targetRepHigh => integer().nullable()();
  TextColumn get notes => text().nullable()();

  /// Per-exercise deload overrides. Schema only for now — no v1 UI.
  IntColumn get deloadSetDelta => integer().nullable()();
  IntColumn get deloadWeightPct => integer().nullable()();
}

/// One full pass through every session in a regime.
///
/// Not a calendar week. The cycle advances when the work is done, which is the
/// whole point — life happens and the programme shouldn't care.
@TableIndex(name: 'idx_cycles_regime', columns: {#regimeId, #cycleIndex})
class Cycles extends Table with SyncColumns {
  TextColumn get regimeId => text().references(Regimes, #id)();
  IntColumn get cycleIndex => integer()();
  IntColumn get startedAt => integer().clientDefault(nowMs)();
  IntColumn get completedAt => integer().nullable()();
  BoolColumn get isDeload => boolean().withDefault(const Constant(false))();
}

/// One instance of training — a session actually performed on a day.
@TableIndex(name: 'idx_workouts_session_lookup', columns: {#sessionId, #status})
@TableIndex(name: 'idx_workouts_day', columns: {#dayKey})
@TableIndex(name: 'idx_workouts_cycle', columns: {#cycleId})
class Workouts extends Table with SyncColumns {
  TextColumn get regimeId => text().references(Regimes, #id)();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  TextColumn get cycleId => text().nullable().references(Cycles, #id)();

  /// Local calendar day (`yyyyMMdd`) for heatmap and history grouping.
  IntColumn get dayKey => integer()();
  IntColumn get startedAt => integer().clientDefault(nowMs)();
  IntColumn get endedAt => integer().nullable()();
  BoolColumn get isDeload => boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      textEnum<WorkoutStatus>().withDefault(const Constant('inProgress'))();
  TextColumn get notes => text().nullable()();
}

/// An exercise as performed in a specific workout.
///
/// Deliberately a snapshot rather than a pointer to [SessionExercises]:
/// reordering or swapping mid-workout must never rewrite what you did in March.
@TableIndex(name: 'idx_workout_exercises_workout', columns: {#workoutId})
@TableIndex(name: 'idx_workout_exercises_exercise', columns: {#exerciseId})
class WorkoutExercises extends Table with SyncColumns {
  TextColumn get workoutId => text().references(Workouts, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get orderIndex => integer()();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  TextColumn get notes => text().nullable()();
  TextColumn get skipReason =>
      textEnum<SkipReason>().withDefault(const Constant('none'))();
}

@TableIndex(name: 'idx_set_logs_parent', columns: {#workoutExerciseId})
class SetLogs extends Table with SyncColumns {
  TextColumn get workoutExerciseId => text().references(WorkoutExercises, #id)();
  IntColumn get setIndex => integer()();
  TextColumn get setType =>
      textEnum<SetType>().withDefault(const Constant('working'))();

  /// As entered. Interpretation depends on the exercise's [LoadMode].
  RealColumn get weight => real().nullable()();
  IntColumn get reps => integer().nullable()();

  /// Extra load for bodyweight-plus movements (weighted pull-ups, dips).
  RealColumn get addedWeight => real().nullable()();
  RealColumn get rpe => real().nullable()();

  /// Drop and rest-pause sets hang off the working set they extend.
  TextColumn get parentSetId => text().nullable()();

  IntColumn get restSeconds => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
}

/// Needed to make bodyweight lifts comparable over time: 7 pull-ups at 70kg
/// and 7 at 76kg are not the same lift.
class BodyweightLogs extends Table with SyncColumns {
  IntColumn get dayKey => integer()();
  RealColumn get weightKg => real()();
}

/// Key/value store for local preferences and sync bookkeeping
/// (`last_pull_at`, `device_id`, `user_id`, `units`). Not synced.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
