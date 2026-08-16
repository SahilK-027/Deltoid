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
///
/// [deviceId] is **the device that wrote the version in front of you**, not the
/// one that created the row. `clientDefault` only fires on an insert, so this
/// used to name the creator for the rest of the row's life — and last-write-wins
/// breaks a same-millisecond tie on it, which meant both devices compared the
/// same originating id, found it equal, and each kept its own copy. Every write
/// stamps it now; see `stampedNow` in `lib/core/ids.dart` for the trio that
/// travels together.
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  IntColumn get updatedAt => integer().clientDefault(nowMs)();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get deviceId => text().clientDefault(() => currentDeviceId)();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A tombstone is set once and never moved backwards past the row's own birth.
///
/// Table-level rather than per-column because it is the one rule every syncable
/// table shares, and a restore or a merge is exactly the writer that can put a
/// delete before the insert it deletes.
const _liveOrTombstoned = 'CHECK (deleted_at IS NULL OR deleted_at > 0)';

/// The exercise catalog. Shared across every regime — swapping PPL for
/// upper/lower reuses these rows, which is what keeps history comparable.
/// What this device still owes the server, countable without a scan.
///
/// Sync's state is derived rather than remembered ([SYNC.md § 17](SYNC.md#17-the-architecture)),
/// which means `COUNT(*) WHERE dirty` is asked every time a set is ticked —
/// across a `set_logs` holding 168k rows at fifty years, that is a full scan per
/// tick. Partial on `dirty = 1`, so the index is *empty* whenever nothing is
/// owed and holds only the queue when something is.
@TableIndex.sql(
  'CREATE INDEX idx_exercises_dirty '
  'ON exercises (dirty) WHERE dirty = 1',
)
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

  /// An enum column is read back through `textEnum`, which **throws on a value
  /// it does not know** — and not for the one row, but for every read of the
  /// table, because a single bad string fails the whole result set. So an
  /// unparseable movement would take the catalog, the log and history down
  /// together. The app can only ever write a name from the enum; a restore or a
  /// merged row is the writer this refuses.
  ///
  /// The lengths are here for the same reason the checks are: nothing in the UI
  /// can type a 10 MB name, and a row that arrives with one breaks every screen
  /// that draws it and every backup that carries it.
  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (length(name) BETWEEN 1 AND 80)',
        'CHECK (notes IS NULL OR length(notes) <= 4000)',
        "CHECK (muscle IN ('chest', 'back', 'shoulders', 'biceps', 'triceps', "
            "'forearms', 'quads', 'hamstrings', 'glutes', 'calves', 'core', "
            "'other'))",
        "CHECK (equipment IN ('barbell', 'dumbbell', 'machine', 'cable', "
            "'bodyweight', 'band', 'other'))",
        "CHECK (load_mode IN ('total', 'perSide', 'bodyweight', "
            "'bodyweightPlus'))",
        "CHECK (measure_mode IN ('reps', 'hold'))",
        "CHECK (bar_kind IN ('none', 'olympic', 'womens', 'ez', 'trap'))",
      ];
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
/// And no two live regimes wear the same identity hue.
///
/// `nextIdentitySlot` (`regime_repository.dart:158`) hands out the lowest free
/// one and `createRegime` refuses when all six are taken, which covers every
/// write that comes through a tap. A file does not: `identity_index` defaults
/// to 0 and the CHECK below bounds the range only, so an export carrying the
/// key on every regime is taken at its word — the restore's backfill runs only
/// when a row *lacks* it (`backup_service.dart:723-726`). A hand-edited or
/// merged file with the same slot twice restored two programmes onto one
/// colour, and the mark is what History and Today are scanned by.
///
/// Partial on `deleted_at IS NULL` because deleting a regime hands its slot
/// back — an unscoped index would keep it held by a programme that is gone
/// from every screen.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_regimes_identity_live '
  'ON regimes (identity_index) WHERE deleted_at IS NULL',
)
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_regimes_dirty '
  'ON regimes (dirty) WHERE dirty = 1',
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

  /// The deload figures are the ones worth constraining hardest, because they
  /// are read straight into a suggestion and a wrong one is plausible rather
  /// than obviously broken: a `deload_weight_pct` of 0 prefills a light week at
  /// nothing at all, and `deload_after_cycles` of 0 asks `planNextCycle` when
  /// to deload against a period of zero cycles. Both are unreachable through
  /// the settings screen and both are one bad row away from a restore.
  ///
  /// `deload_set_delta` is documented as negative and was enforced nowhere; a
  /// positive one adds sets to a light week.
  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (length(name) BETWEEN 1 AND 60)',
        'CHECK (deload_after_cycles BETWEEN 1 AND 52)',
        'CHECK (deload_weight_pct BETWEEN 1 AND 100)',
        'CHECK (deload_set_delta BETWEEN -20 AND 0)',
        'CHECK (identity_index BETWEEN 0 AND ${identitySlots - 1})',
        'CHECK (created_at > 0)',
      ];
}

/// One training day template within a regime: "Push 1", "Pull 2", "Lower A".
@TableIndex(name: 'idx_sessions_regime', columns: {#regimeId})
/// No two live sessions in a regime share a position.
///
/// `set_logs` has carried this rule since a `+` inside a deleted drop group put
/// two sets on one index; it is the same rule and the same failure, and the
/// programme's running order is what breaks instead of the set table. Every
/// append here already takes one past the highest live position rather than the
/// live count — this is what holds when the write is a restore or a merge
/// rather than a tap.
///
/// A reorder therefore cannot renumber in place: writing position 0 onto the
/// row currently at 1 collides with the row still sitting at 0. See
/// `renumber` in `db/renumber.dart` for the two-pass that avoids it.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_sessions_position_live '
  'ON sessions (regime_id, order_index) WHERE deleted_at IS NULL',
)
/// One name per regime, compared the way a person compares them.
///
/// The whole app turns on which *session* a number came from — the prefill
/// disclosure says "borrowed from Push 1 on 3 March" and History filters by the
/// day's name. Two live sessions called `Push 1` in one regime makes every one
/// of those sentences ambiguous, and there is nothing else on screen to tell
/// them apart. `regimes` has answered to this rule since the same shelf of
/// identical names got built there; sessions were left open.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_sessions_name_live '
  'ON sessions (regime_id, lower(trim(name))) WHERE deleted_at IS NULL',
)
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_sessions_dirty '
  'ON sessions (dirty) WHERE dirty = 1',
)
class Sessions extends Table with SyncColumns {
  TextColumn get regimeId => text().references(Regimes, #id)();
  TextColumn get name => text()();
  IntColumn get orderIndex => integer()();

  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (length(trim(name)) BETWEEN 1 AND 60)',
        'CHECK (order_index >= 0)',
      ];
}

/// An exercise slot inside a session template.
@TableIndex(name: 'idx_session_exercises_session', columns: {#sessionId})
/// No two live slots in a session share a position — see [Sessions] for the
/// rule and for what it costs a reorder.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_session_exercises_position_live '
  'ON session_exercises (session_id, order_index) WHERE deleted_at IS NULL',
)
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_session_exercises_dirty '
  'ON session_exercises (dirty) WHERE dirty = 1',
)
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

  /// A rep range that runs backwards is the one shape here that no single
  /// column can refuse: `8–5` reads as a range, sorts as a range, and prints on
  /// the slot as one. Both fields are optional and either may stand alone, so
  /// the rule only bites when both are present.
  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (order_index >= 0)',
        'CHECK (target_sets BETWEEN 1 AND 99)',
        'CHECK (target_rep_low IS NULL OR target_rep_low BETWEEN 1 AND 999)',
        'CHECK (target_rep_high IS NULL OR target_rep_high BETWEEN 1 AND 999)',
        'CHECK (target_rep_low IS NULL OR target_rep_high IS NULL '
            'OR target_rep_low <= target_rep_high)',
        'CHECK (rest_seconds IS NULL OR rest_seconds BETWEEN 1 AND 3600)',
        'CHECK (deload_set_delta IS NULL '
            'OR deload_set_delta BETWEEN -20 AND 0)',
        'CHECK (deload_weight_pct IS NULL '
            'OR deload_weight_pct BETWEEN 1 AND 100)',
        'CHECK (notes IS NULL OR length(notes) <= 4000)',
      ];
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
/// And a regime cannot hold two cycles that are both *open*.
///
/// The index above is on `(regime_id, cycle_index)`, so two cycles could be
/// open at once as long as they were numbered differently — which is exactly
/// the state `healDuplicateOpenCycles` (`training_repository.dart:446`) exists
/// to repair, and the evidence that a build reached it. The healer keeps its
/// job: it repairs a file that already carries the state, and this refuses the
/// write that would create it. A pull applier is the second writer that makes
/// that distinction matter.
///
/// Scoped on `deleted_at IS NULL` for the healer's sake as much as anyone's —
/// it repairs by tombstoning the duplicates, and an unscoped index would
/// refuse the repair.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_cycles_regime_open_live '
  'ON cycles (regime_id) WHERE completed_at IS NULL AND deleted_at IS NULL',
)
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_cycles_dirty '
  'ON cycles (dirty) WHERE dirty = 1',
)
class Cycles extends Table with SyncColumns {
  TextColumn get regimeId => text().references(Regimes, #id)();
  IntColumn get cycleIndex => integer()();
  IntColumn get startedAt => integer().clientDefault(nowMs)();
  IntColumn get completedAt => integer().nullable()();
  BoolColumn get isDeload => boolean().withDefault(const Constant(false))();

  /// Cycles number from 1 — `planNextCycle` counts up from the last one, and a
  /// zeroth cycle would make "Cycle 0" a thing Today can say. A cycle that
  /// finished before it started is the same class of nonsense one table down;
  /// see [Workouts].
  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (cycle_index >= 1)',
        'CHECK (started_at > 0)',
        'CHECK (completed_at IS NULL OR completed_at >= started_at)',
      ];
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
/// One session is open at a time, enforced here rather than only in the check
/// `startWorkout` makes.
///
/// That check is a read, and it happens before the transaction that writes the
/// rows — so two taps inside the write window both found nothing running and
/// both opened a log. `openWorkout` returns the newest by `startedAt`, so the
/// older one is then hidden behind it: unreachable from any screen, `inProgress`
/// for good, and counted by nothing. Today's Start button guards against the
/// double tap; the backfill sheet is a second door onto the same write, and a
/// sync pull is a third.
///
/// The same shape as `idx_regimes_single_active`: with the index filtered to
/// one value, every row in it collides.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_workouts_single_open '
  "ON workouts (status) WHERE status = 'inProgress' AND deleted_at IS NULL",
)
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_workouts_dirty '
  'ON workouts (dirty) WHERE dirty = 1',
)
class Workouts extends Table with SyncColumns {
  TextColumn get regimeId => text().references(Regimes, #id)();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  TextColumn get cycleId => text().nullable().references(Cycles, #id)();

  /// Local calendar day (`yyyyMMdd`) for heatmap and history grouping.
  IntColumn get dayKey => integer()();
  IntColumn get startedAt => integer().clientDefault(nowMs)();

  /// Minutes east of UTC where this session was logged, at the instant it was
  /// logged.
  ///
  /// The only reason it exists is to let the CHECK below compare the two
  /// columns above. `started_at` is an absolute instant and `day_key` is a local
  /// calendar day, and no expression can get from one to the other without
  /// knowing the zone. SQLite can be told the zone — `'localtime'` — but a CHECK
  /// must be deterministic, and `'localtime'` reads the *machine's* zone at
  /// evaluation time, so a row written in Delhi would be re-judged in London and
  /// the constraint would start refusing rows it had already accepted. Written
  /// down per row instead, the arithmetic is a closed function of the row.
  ///
  /// Historically correct rather than current: `DateTime.timeZoneOffset` answers
  /// for the instant it is asked about, so a session logged the hour before a
  /// clock change keeps the offset it was actually logged under.
  ///
  /// Nothing reads it. It is not a display value and no query filters on it.
  IntColumn get tzOffsetMinutes => integer()();
  IntColumn get endedAt => integer().nullable()();
  BoolColumn get isDeload => boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      textEnum<WorkoutStatus>().withDefault(const Constant('inProgress'))();
  TextColumn get notes => text().nullable()();

  /// `day_key` is what the heatmap and the calendar group on; `started_at` is
  /// what History pages by. Every write in the app sets the two from one
  /// `DateTime` — `setWorkoutDate` moves them together for exactly this reason —
  /// but nothing made them agree, so a restored or merged row could put one
  /// session on two different days at once: ringed on Tuesday in the grid, filed
  /// under Monday in the feed, and reachable from neither reliably.
  ///
  /// They agree here now, through [tzOffsetMinutes]. The arithmetic is in
  /// seconds rather than milliseconds so the only division is by `started_at`,
  /// which the CHECK above holds positive — SQLite truncates toward zero, which
  /// is a floor for a positive value and a ceiling for a negative one, and a
  /// ceiling here would put the last second of a day on the next one.
  ///
  /// The offset range is the real one: nowhere on earth runs west of UTC-12:00
  /// or east of UTC+14:00. It is not decoration. Without it a hand-edited file
  /// could name any offset it liked and talk this constraint into accepting a
  /// row that does claim two days.
  ///
  /// The day range is a real one too, rather than a sanity bound.
  /// `dateFromDayKey` does arithmetic on this, so `0` is a `DateTime` in year
  /// zero and the calendar silently scrolls to it.
  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (day_key BETWEEN 19000101 AND 21001231)',
        'CHECK (started_at > 0)',
        'CHECK (tz_offset_minutes BETWEEN -720 AND 840)',
        'CHECK (day_key = CAST(strftime('
            "'%Y%m%d', started_at / 1000 + tz_offset_minutes * 60, 'unixepoch'"
            ') AS INTEGER))',
        'CHECK (ended_at IS NULL OR ended_at >= started_at)',
        'CHECK (notes IS NULL OR length(notes) <= 4000)',
        "CHECK (status IN ('planned', 'inProgress', 'completed', 'abandoned'))",
      ];
}

/// An exercise as performed in a specific workout.
///
/// Deliberately a snapshot rather than a pointer to [SessionExercises]:
/// reordering or swapping mid-workout must never rewrite what you did in March.
@TableIndex(name: 'idx_workout_exercises_workout', columns: {#workoutId})
@TableIndex(name: 'idx_workout_exercises_exercise', columns: {#exerciseId})
/// No two live slots in a workout share a position — see [Sessions] for the
/// rule. The log screen is a `PageView` keyed on this order, so two rows on one
/// index means the page you swipe to is whichever way SQLite broke the tie.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_workout_exercises_position_live '
  'ON workout_exercises (workout_id, order_index) WHERE deleted_at IS NULL',
)
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_workout_exercises_dirty '
  'ON workout_exercises (dirty) WHERE dirty = 1',
)
class WorkoutExercises extends Table with SyncColumns {
  TextColumn get workoutId => text().references(Workouts, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get orderIndex => integer()();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  TextColumn get notes => text().nullable()();
  TextColumn get skipReason =>
      textEnum<SkipReason>().withDefault(const Constant('none'))();

  /// The muscle this movement trained, copied at the moment it was logged.
  ///
  /// The snapshot rule applied to a column that used to be read live. Weekly
  /// volume counted sets through a join onto `exercises.muscle`, which is fine
  /// over seven days and dishonest over years: recategorising one movement in
  /// the catalog silently rewrote every week it ever appeared in, and a chart
  /// of "sets per muscle since 2026" would redraw itself because you fixed a
  /// label today. What you trained in March is a fact about March.
  ///
  /// **Nullable, and null is not [MuscleGroup.other].** Null means the row was
  /// logged before this column existed and the catalog is the best answer we
  /// have; readers fall back to `exercises.muscle` for exactly those rows
  /// (`_muscleOfLog` in `training_repository.dart`). Defaulting to `other`
  /// instead would have been a value the app invented, and `other` belongs to
  /// no region — every pre-existing set would have quietly left the chart.
  TextColumn get muscle => textEnum<MuscleGroup>().nullable()();

  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (order_index >= 0)',
        'CHECK (target_sets BETWEEN 1 AND 99)',
        'CHECK (notes IS NULL OR length(notes) <= 4000)',
        "CHECK (skip_reason IN ('none', 'failed', 'equipmentBusy', "
            "'shortOnTime', 'injury', 'other'))",
        // Same reasoning as `Exercises.muscle`: `textEnum` throws on a value it
        // does not know, and it throws for the whole result set rather than the
        // one row — so an unparseable string here takes down the log, history
        // and every volume chart at once.
        "CHECK (muscle IS NULL OR muscle IN ('chest', 'back', 'shoulders', "
            "'biceps', 'triceps', 'forearms', 'quads', 'hamstrings', 'glutes', "
            "'calves', 'core', 'other'))",
      ];
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
/// Not a rule — the parent key the drop-group foreign key needs.
///
/// `id` is already the primary key, so this adds no uniqueness anything did not
/// already have. SQLite will only accept a composite foreign key whose parent
/// columns carry a unique index of their own, and `(id, workout_exercise_id)`
/// is what [SetLogs.parentSetId]'s pair points at. Unpartial and unqueried, and
/// deliberately so: see [SetLogs.customConstraints].
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_set_logs_slot_identity '
  'ON set_logs (id, workout_exercise_id)',
)
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_set_logs_dirty '
  'ON set_logs (dirty) WHERE dirty = 1',
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
  ///
  /// The head must also sit in the *same slot*, which this reference does not
  /// say and the composite foreign key in [customConstraints] does. That one
  /// subsumes this: a `(parent_set_id, workout_exercise_id)` pair that matches
  /// a row necessarily matches its id. Kept because it is where a reader looks
  /// to learn the column points at a set.
  TextColumn get parentSetId =>
      text().nullable().references(SetLogs, #id)();

  IntColumn get restSeconds => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();

  /// A set cannot be a leg of itself. The column is a real reference now, so
  /// the database already refuses a head that names no set — but it will happily
  /// accept a row pointing at its own id, and the drop group that describes has
  /// no head to draw and no end to walk to.
  ///
  /// Nor can a leg name a head under a **different slot**. That is the
  /// composite foreign key, and it has to be one: a CHECK sees one row and this
  /// rule compares two. Carrying `workout_exercise_id` into the key makes the
  /// pair the thing that must match, so a head under another exercise — or in
  /// another workout, since ids are unique table-wide — is refused by the same
  /// mechanism that already refused a head that does not exist. `addDropLeg`
  /// (`training_repository.dart:2513`) and `setSetType` (`:2581`) only ever
  /// pass a head from the same slot; a restore and a merge do not come through
  /// either, and the walk that draws a group is scoped to one slot's list, so a
  /// cross-slot head draws a leg with no head at all.
  ///
  /// SQLite requires the referenced columns to carry a unique index, which
  /// `idx_set_logs_slot_identity` above exists for and nothing else reads. It
  /// cannot be partial: a foreign key's parent key has to cover the whole
  /// table, tombstones included, or the index does not qualify at all.
  ///
  /// The upper bounds are the other half of the checks above. `weight >= 0`
  /// refuses the assisted-lift minus sign that made a negative load scoreable;
  /// these refuse the misplaced decimal on the other side, where a set of
  /// 1 000 000 kg becomes the top set of the chart forever and rescales every
  /// axis it appears on. `reps` carries seconds on a hold, so its ceiling is
  /// generous enough for a very long plank and still short of a stuck timer.
  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (parent_set_id IS NULL OR parent_set_id <> id)',
        'FOREIGN KEY (parent_set_id, workout_exercise_id) '
            'REFERENCES set_logs (id, workout_exercise_id)',
        'CHECK (weight IS NULL OR weight <= 2000)',
        'CHECK (added_weight IS NULL OR added_weight <= 2000)',
        'CHECK (reps IS NULL OR reps <= 86400)',
        'CHECK (partial_reps IS NULL OR partial_reps <= 999)',
        'CHECK (rest_seconds IS NULL OR rest_seconds BETWEEN 0 AND 86400)',
        'CHECK (completed_at IS NULL OR completed_at > 0)',
        'CHECK (note IS NULL OR length(note) <= 4000)',
        "CHECK (set_type IN ('warmup', 'working', 'backoff', 'drop', "
            "'restPause', 'amrap'))",
      ];
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
/// What this device still owes the server — see [Exercises] for why it is
/// partial.
@TableIndex.sql(
  'CREATE INDEX idx_bodyweight_logs_dirty '
  'ON bodyweight_logs (dirty) WHERE dirty = 1',
)
class BodyweightLogs extends Table with SyncColumns {
  IntColumn get dayKey => integer()();

  /// A bodyweight of zero is not a light reading, it is a missing one — and it
  /// divides into every bodyweight-scored lift on the day it lands.
  RealColumn get weightKg => real().check(weightKg.isBiggerThanValue(0))();

  /// The ceiling matters as much as the floor, and for the same reason: this
  /// number is not read on its own, it is interpolated between neighbours and
  /// multiplied into every pull-up and dip around it. A fat-fingered `850`
  /// rescales weeks of history either side of the day it lands on, and the
  /// screen it lands on shows one number that looks merely wrong.
  @override
  List<String> get customConstraints => [
        _liveOrTombstoned,
        'CHECK (day_key BETWEEN 19000101 AND 21001231)',
        'CHECK (weight_kg < 500)',
      ];
}

/// Key/value store for local preferences and sync bookkeeping
/// (`last_pull_at`, `device_id`, `user_id`, `units`). Not synced.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  List<String> get customConstraints => [
        'CHECK (length(key) BETWEEN 1 AND 100)',
        'CHECK (length(value) <= 4000)',
      ];
}
