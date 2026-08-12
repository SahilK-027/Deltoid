// ignore_for_file: recursive_getters
//
// `check()` names the column it constrains, which reads as a getter returning
// itself. It is how drift spells a CHECK constraint — the generator reads the
// expression at build time and the getter is never actually called.

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
  TextColumn get deviceId => text().clientDefault(() => currentDeviceId)();
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

  /// Whether a set of this is counted in reps or in seconds held. Defaults to
  /// `reps`, which is the honest answer for every row that existed before the
  /// column did — the catalog is movements, and a plank has to be said out
  /// loud to be one.
  TextColumn get measureMode =>
      textEnum<MeasureMode>().withDefault(const Constant('reps'))();

  /// Which bar this is loaded on, for the plate view. `none` — the default —
  /// means the movement has no bar and gets no plate maths.
  TextColumn get barKind =>
      textEnum<BarKind>().withDefault(const Constant('none'))();

  /// The `starterExercises` key this row was seeded from, when it was.
  ///
  /// Templates match on this rather than on the name, so renaming "Dips" to
  /// "Weighted dips" and then applying a template reuses the row instead of
  /// creating a second one under the old name.
  TextColumn get starterKey => text().nullable()();
  TextColumn get formVideoUrls =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// A training programme: an ordered set of sessions plus its deload policy.
///
/// Switching regimes creates a new row rather than editing sessions in place,
/// so past history keeps pointing at the programme it was actually run under.
/// At most one live regime is active, enforced by the database.
///
/// A unique index on a column filtered to a single value is how SQLite says
/// "one row at most": with `WHERE is_active = 1` only the active rows are
/// indexed, and they all share the same key. `setActiveRegime` already
/// deactivates-then-activates in one transaction; this is what holds when the
/// write does not come through it.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_regimes_single_active '
  'ON regimes (is_active) WHERE is_active = 1 AND deleted_at IS NULL',
)
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

  /// Which of the identity hues this regime wears, as an index into
  /// `DeltoidColors.identity`.
  ///
  /// Stored rather than hashed off the id. A hash collides — two regimes out of
  /// six share a colour about a third of the time — and the mark is the thing
  /// History and Today are scanned by, so two programmes wearing the same one
  /// is the one failure it cannot have. A live regime holds its slot; deleting
  /// one hands the slot back.
  IntColumn get identityIndex => integer().withDefault(const Constant(0))();

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

  /// Rest target for this slot, in seconds.
  ///
  /// Per slot rather than global: heavy compounds want three minutes and cable
  /// work wants sixty seconds, and re-dialling that on every exercise is the
  /// kind of friction that gets an app closed mid-session.
  IntColumn get restSeconds => integer().nullable()();

  /// Per-exercise deload overrides. Schema only for now — no v1 UI.
  IntColumn get deloadSetDelta => integer().nullable()();
  IntColumn get deloadWeightPct => integer().nullable()();
}

/// One full pass through every session in a regime.
///
/// Not a calendar week. The cycle advances when the work is done, which is the
/// whole point — life happens and the programme shouldn't care.
@TableIndex(name: 'idx_cycles_regime', columns: {#regimeId, #cycleIndex})
/// A regime cannot hold the same cycle number twice.
///
/// `_ensureOpenCycle` is a transaction for this reason, and there is repair
/// code for regimes that already carry more than one open cycle — which is the
/// evidence that this went wrong once, under a build where it was not.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_cycles_regime_index_live '
  'ON cycles (regime_id, cycle_index) WHERE deleted_at IS NULL',
)
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
/// History pages by keyset on `(startedAt, id)` descending, which without this
/// was a scan of every workout and a temp B-tree to sort them — once per page,
/// with the first page the dearest because nothing is filtered out yet. Small
/// either way at a human number of sessions, and the index is 148 kB against
/// thirty years, so this buys under two milliseconds. It is here because it
/// costs nothing to declare while the schema is still free to change.
@TableIndex(name: 'idx_workouts_started', columns: {#startedAt, #id})
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
/// No two live sets under one exercise share a position.
///
/// Inserting mid-list shifts the rows above it from the top down for exactly
/// this reason — each one moves into a slot the row above has already left.
/// Tombstones are excluded, so the gap a deleted set leaves is free to be
/// filled again.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_set_logs_position_live '
  'ON set_logs (workout_exercise_id, set_index) WHERE deleted_at IS NULL',
)
class SetLogs extends Table with SyncColumns {
  TextColumn get workoutExerciseId => text().references(WorkoutExercises, #id)();
  IntColumn get setIndex => integer().check(setIndex.isBiggerOrEqualValue(0))();
  TextColumn get setType =>
      textEnum<SetType>().withDefault(const Constant('working'))();

  /// As entered. Interpretation depends on the exercise's [LoadMode].
  ///
  /// Never negative. Assisted movements are a [LoadMode], not a minus sign —
  /// a negative load here would be scored, charted and compared as one.
  RealColumn get weight =>
      real().nullable().check(weight.isBiggerOrEqualValue(0))();

  /// Reps, or seconds when the exercise is measured as a hold.
  IntColumn get reps =>
      integer().nullable().check(reps.isBiggerOrEqualValue(0))();

  /// Reps that did not finish the range of motion, counted apart from [reps].
  ///
  /// Recorded, never arithmetic: partials are out of volume, out of e1RM and
  /// out of `beatsPrevious` on purpose. Eight full reps and three halves is a
  /// fact about how the set went, not eleven reps — folding them together
  /// would let a set of grinding halves read as a personal record.
  ///
  /// Null and 0 both mean "none". Only meaningful on a set counted in reps: a
  /// hold has no such thing as half a second.
  IntColumn get partialReps =>
      integer().nullable().check(partialReps.isBiggerOrEqualValue(0))();

  /// Extra load for bodyweight-plus movements (weighted pull-ups, dips).
  RealColumn get addedWeight =>
      real().nullable().check(addedWeight.isBiggerOrEqualValue(0))();

  /// The head of the drop group this set is a leg of, or null when the set
  /// stands on its own.
  ///
  /// Consecutive `drop` rows used to be treated as one group by position
  /// alone, which cannot tell "one drop set with two legs" from "two separate
  /// drop sets that happen to sit next to each other" — converting two sets in
  /// a row swallowed the second into the first.
  ///
  /// A real reference, like every other relationship here. It was a bare text
  /// column, so the database would accept a head id that names no set at all —
  /// the one place the schema took the app's word for it.
  TextColumn get parentSetId =>
      text().nullable().references(SetLogs, #id)();

  IntColumn get restSeconds => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
}

/// Needed to make bodyweight lifts comparable over time: 7 pull-ups at 70kg
/// and 7 at 76kg are not the same lift.
///
/// Indexed on the day, because this is the one table with a row *per day*:
/// every other table grows with sessions, and this one grows whether you train
/// or not. Fifty years of it is 18 000 rows, and the bodyweight screen asks it
/// three questions — a month's days, a chart window, the newest entry — all of
/// which were full scans until this existed.
@TableIndex(name: 'idx_bodyweight_day', columns: {#dayKey})
/// One live row per day, enforced here rather than only in the upsert.
///
/// `logBodyweight` already does the look-up and the write in one transaction,
/// which is what makes a double tap on Save safe. That defence is Dart, and a
/// second writer — a restore, or a device merging someone else's rows — never
/// passes through it. Two weights for one day is the invisible kind of wrong:
/// the screen shows whichever the query returns first and every
/// bodyweight-scored lift that day reads the other one half the time.
///
/// Partial, so a tombstoned row never blocks re-logging the day it was on.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_bodyweight_day_live '
  'ON bodyweight_logs (day_key) WHERE deleted_at IS NULL',
)
class BodyweightLogs extends Table with SyncColumns {
  IntColumn get dayKey => integer()();

  /// A bodyweight of zero is not a light reading, it is a missing one — and it
  /// divides into every bodyweight-scored lift on the day it lands.
  RealColumn get weightKg => real().check(weightKg.isBiggerThanValue(0))();
}

/// Key/value store for local preferences and sync bookkeeping
/// (`last_pull_at`, `device_id`, `user_id`, `units`). Not synced.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
