import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/cycle_progress.dart';
import '../../domain/enums.dart';
import '../../domain/metrics.dart';
import '../../domain/muscle_volume.dart';
import '../../domain/prefill.dart';
import '../../domain/rest.dart';
import '../../domain/session_diff.dart';
import '../../domain/units.dart';
import '../db/database.dart';
import '../db/renumber.dart';
import '../db/watch.dart';
import '../../domain/session_name.dart';

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
      const LiftLabel(exerciseName: '', sessionName: unplannedSessionName);
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

class TrainingRepository {
  TrainingRepository(this.db);

  final AppDatabase db;

  /// What [startWorkout] already worked out, waiting for the log screen to ask
  /// for it — keyed `workoutId:exerciseId`.
  ///
  /// Starting a session resolves prefill for every slot, because the set rows
  /// have to mirror last time's *shape*. The log screen then resolves prefill
  /// for the same exercises all over again, because it needs last time's
  /// *numbers* for the ghosts — the same walk through history, twice, on the
  /// single tap in the application that is waited on directly. On fifty years
  /// that is 96ms of work followed by another 121ms of the same work.
  ///
  /// Read once, then discarded. The entry is only ever handed to the first
  /// caller and every later resolution goes to the database, so the widest this
  /// can be out of date is the few milliseconds between writing the workout and
  /// the screen for it building — a window in which nothing can have changed
  /// the history it was resolved from. It is an accelerator on a cold path, not
  /// a cache with a lifetime to reason about, and the truth is always one query
  /// away underneath it.
  final _prefillOnOpen = <String, PrefillResult>{};

  static String _prefillKey(String workoutId, String exerciseId) =>
      '$workoutId:$exerciseId';

  // ── Cycles ────────────────────────────────────────────────────────────

  /// Completed non-deload cycles before [beforeIndex], counting from the last
  /// deload.
  ///
  /// [beforeIndex] is exclusive and matters: a [CycleStatus] describes a cycle
  /// in terms of what came *before* it. Counting the cycle itself would make
  /// the deload land one cycle early.
  Future<int> _cyclesSinceDeload(String regimeId, {required int beforeIndex}) async {
    final completed = await (db.select(db.cycles)
          ..where((t) =>
              t.regimeId.equals(regimeId) &
              t.completedAt.isNotNull() &
              t.cycleIndex.isSmallerThanValue(beforeIndex) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.cycleIndex)]))
        .get();

    var count = 0;
    for (final c in completed) {
      // A deload resets the count; everything after it accumulates again.
      count = c.isDeload ? 0 : count + 1;
    }
    return count;
  }

  /// The cycle currently being trained, creating one if the regime has never
  /// been started or the previous cycle just closed.
  ///
  /// Find-and-create in one transaction, because this is a *write* reached from
  /// several watched reads at once — `workoutsProvider` and `cycleStatusProvider`
  /// both land here, and on a regime with no cycle yet each of them would find
  /// nothing and insert one. Three open cycles for one regime, and every count
  /// downstream — the deload counter included — reading whichever came back
  /// first.
  /// Null when the regime is gone — deleted from the Regimes screen while
  /// Today, the log or a chart was still watching it.
  ///
  /// The missing regime is reported as null rather than thrown. This is reached
  /// from watched queries, and every screen reads those with `valueOrNull`, so a
  /// throw would surface as that screen returning to its loading state and
  /// staying there. "There is no cycle" is an answer the callers already know
  /// how to render; an exception is not.
  Future<Cycle?> ensureOpenCycle(String regimeId) =>
      db.transaction(() => _ensureOpenCycle(regimeId));

  Future<Cycle?> _ensureOpenCycle(String regimeId) async {
    final open = await (db.select(db.cycles)
          ..where((t) =>
              t.regimeId.equals(regimeId) &
              t.completedAt.isNull() &
              t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.cycleIndex, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
    if (open != null) return open;

    // A deleted programme opens no new cycles. A tombstoned regime is absent
    // from every screen, and `invariant_oracle` refuses a live cycle under one
    // — the cycle is the counter a deload is scheduled off, and scheduling
    // against a programme nobody can see is meaningless.
    //
    // Reachable without sync at all: delete the active regime while a session
    // logged under it is still open, then finish that session. Covered by the
    // two-device fuzz and not by `model_fuzz_test`, which has no delete-regime
    // operation.
    final regime = await (db.select(db.regimes)
          ..where((t) => t.id.equals(regimeId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (regime == null) return null;
    final last = await (db.select(db.cycles)
          ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.cycleIndex, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();

    var index = 1;
    var isDeload = false;

    if (last != null) {
      final status = CycleStatus(
        cycleId: last.id,
        cycleIndex: last.cycleIndex,
        isDeload: last.isDeload,
        sessionIds: await _sessionIds(regimeId),
        completedSessionIds: await _completedSessionIds(last.id),
        cyclesSinceDeload:
            await _cyclesSinceDeload(regimeId, beforeIndex: last.cycleIndex),
        deloadEnabled: regime.deloadEnabled,
        deloadAfterCycles: regime.deloadAfterCycles,
      );
      final next = planNextCycle(status);
      index = next.cycleIndex;
      isDeload = next.isDeload;
    }

    final id = newId();
    await db.into(db.cycles).insert(
          CyclesCompanion.insert(
            id: Value(id),
            regimeId: regimeId,
            cycleIndex: index,
            isDeload: Value(isDeload),
          ),
        );
    return (db.select(db.cycles)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Collapses regimes that already carry more than one open cycle.
  ///
  /// [ensureOpenCycle] is a transaction, so no new pair can be made — but a
  /// phone that ran an earlier build carries the pairs it made then, and
  /// nothing about them heals on its own: Today reads the newest open cycle, so a
  /// regime that has never been trained opens on "Cycle 2", the sessions logged
  /// under one of them do not count towards the other, and the deload lands
  /// wherever the count happens to fall.
  ///
  /// The lowest index wins, because duplicates were minted within milliseconds
  /// of each other and the first is the one the programme actually meant. Any
  /// workout pointing at a loser is moved onto the keeper before the loser is
  /// tombstoned, so nothing logged is orphaned.
  ///
  /// Idempotent and one query wide on a database with nothing wrong with it,
  /// which is what lets it run at every launch.
  Future<int> healDuplicateOpenCycles() async {
    // Two steps on purpose, and the order matters for what this costs.
    //
    // This runs at every launch, before first paint, and on a database with
    // nothing wrong with it the answer is "no duplicates" — so the healthy path
    // has to stay a single read. Opening a transaction to find that out takes
    // the write lock on the boot path of every launch for the rest of the app's
    // life, to do nothing.
    //
    // So the cheap scan runs first and outside, and only a database that
    // actually has a pair pays for the transaction — which then re-reads inside
    // it, because the scan that decided to heal is not the one the merge is
    // allowed to act on.
    if (!await _hasDuplicateOpenCycles()) return 0;
    return db.transaction(_healDuplicateOpenCycles);
  }

  Future<bool> _hasDuplicateOpenCycles() async {
    final counted = db.cycles.id.count();
    final rows = await (db.selectOnly(db.cycles)
          ..addColumns([db.cycles.regimeId, counted])
          ..where(db.cycles.completedAt.isNull() & db.cycles.deletedAt.isNull())
          ..groupBy(
            [db.cycles.regimeId],
            having: counted.isBiggerThanValue(1),
          ))
        .get();
    return rows.isNotEmpty;
  }

  Future<int> _healDuplicateOpenCycles() async {
    final open = await (db.select(db.cycles)
          ..where((t) => t.completedAt.isNull() & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.cycleIndex)]))
        .get();

    final byRegime = <String, List<Cycle>>{};
    for (final cycle in open) {
      byRegime.putIfAbsent(cycle.regimeId, () => []).add(cycle);
    }

    var healed = 0;
    for (final cycles in byRegime.values) {
      if (cycles.length < 2) continue;
      final keeper = cycles.first;
      final losers = cycles.skip(1).toList();

      {
        for (final loser in losers) {
          await (db.update(db.workouts)
                ..where((t) => t.cycleId.equals(loser.id)))
              .write(
            WorkoutsCompanion(
              cycleId: Value(keeper.id),
              deviceId: Value(currentDeviceId),
              updatedAt: Value(nowMs()),
              dirty: const Value(true),
            ),
          );
          await (db.update(db.cycles)..where((t) => t.id.equals(loser.id)))
              .write(
            CyclesCompanion(
              deletedAt: Value(nowMs()),
              deviceId: Value(currentDeviceId),
              updatedAt: Value(nowMs()),
              dirty: const Value(true),
            ),
          );
          healed++;
        }
      }
    }
    return healed;
  }

  /// Moves a live workout off a cycle that has been tombstoned under it.
  ///
  /// `healDuplicateOpenCycles` already repoints its own workouts before it
  /// tombstones a duplicate — but only the ones on the phone it runs on. The
  /// other device is holding workouts on the same loser cycle, learns about the
  /// tombstone through a pull, and is left with live workouts naming a dead
  /// cycle under a live regime, which `invariant_oracle` refuses.
  ///
  /// Repointed at the regime's open cycle where there is one, its newest cycle
  /// otherwise, and null when the programme has none left. Null is a legal
  /// value here and an honest one: the session happened, and which cycle it
  /// counted towards is no longer known.
  ///
  /// The qualifier is the same one the oracle applies. A deleted programme
  /// keeps its history and its workouts go on naming its tombstoned cycles by
  /// design; this is only about live ones.
  Future<int> healWorkoutsNamingDeadCycles() async {
    final stamp = nowMs();
    return db.customUpdate(
      'UPDATE workouts SET cycle_id = ('
      '  SELECT c.id FROM cycles c'
      '  WHERE c.regime_id = workouts.regime_id AND c.deleted_at IS NULL'
      '  ORDER BY c.completed_at IS NULL DESC, c.cycle_index DESC LIMIT 1'
      '), updated_at = ?, device_id = ?, dirty = 1 '
      'WHERE deleted_at IS NULL '
      'AND cycle_id IN (SELECT id FROM cycles WHERE deleted_at IS NOT NULL) '
      'AND regime_id IN (SELECT id FROM regimes WHERE deleted_at IS NULL)',
      variables: [
        Variable<int>(stamp),
        Variable<String>(currentDeviceId),
      ],
      updates: {db.workouts},
    );
  }

  /// Tombstones cycles left alive under a deleted regime.
  ///
  /// `deleteRegime` takes its cycles with it, so no tap can produce this — but a
  /// merge can, and it is not an exotic case: one phone deletes a programme
  /// while the other, offline, trains under it and advances its cycle. The
  /// cycle arrives naming a regime that is gone, and `invariant_oracle` calls
  /// that *live cycles under a dead regime*.
  ///
  /// Only the cycles are affected. A deleted programme retains its history,
  /// which is why
  /// the oracle has no rule about workouts under a dead regime — and the cycle
  /// is the counter the deload is scheduled off rather than a record of
  /// anything performed.
  ///
  /// Idempotent, and one scan on a database with nothing wrong with it.
  Future<int> healCyclesUnderDeadRegimes() async {
    final stamp = nowMs();
    return db.customUpdate(
      'UPDATE cycles SET deleted_at = ?, updated_at = ?, device_id = ?, '
      'dirty = 1 WHERE deleted_at IS NULL AND regime_id IN ('
      'SELECT id FROM regimes WHERE deleted_at IS NOT NULL)',
      variables: [
        Variable<int>(stamp),
        Variable<int>(stamp),
        Variable<String>(currentDeviceId),
      ],
      updates: {db.cycles},
    );
  }

  /// Tombstones exercise snapshots and sets left alive under a deleted workout.
  ///
  /// [abandonWorkout] now takes the whole tree, so this repairs databases
  /// carrying pairs from a build that did not. Nothing heals them on its own and
  /// nothing on screen shows them, because every read joins the workout — but
  /// they are live rows carrying `dirty`, so they are exactly what a first sync
  /// push would send.
  ///
  /// Idempotent, and one query wide on a database with nothing wrong with it,
  /// which is what lets it run at every launch.
  Future<int> healOrphanedSnapshots() async {
    final orphaned = await (db.select(db.workoutExercises).join([
      innerJoin(
          db.workouts, db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
    ])
          ..where(db.workoutExercises.deletedAt.isNull() &
              db.workouts.deletedAt.isNotNull()))
        .get();

    final stamp = nowMs();
    final workoutIds = {
      for (final row in orphaned) row.readTable(db.workouts).id,
    };
    if (workoutIds.isNotEmpty) {
      await db.transaction(() async {
        for (final id in workoutIds) {
          await _tombstoneChildren(id, stamp);
        }
      });
    }

    // And a live set under a snapshot that is already tombstoned, which the
    // pass above cannot see: it looks for *live* snapshots, and this row's
    // parent is dead.
    //
    // A sync pull is what makes this state reachable. One device deletes a
    // session, taking the whole tree; the other, offline, adds a set inside it
    // and pushes afterwards — [SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does)
    // row 8. The set arrives under a tombstoned parent, and `invariant_oracle`
    // calls that *live sets under a dead slot*. The set is kept, as a
    // tombstone: nothing logged is deleted, and nothing that cannot be reached
    // from a screen is left carrying `dirty`.
    final adopted = await db.customUpdate(
      'UPDATE set_logs SET deleted_at = ?, updated_at = ?, device_id = ?, '
      'dirty = 1 WHERE deleted_at IS NULL AND workout_exercise_id IN ('
      'SELECT id FROM workout_exercises WHERE deleted_at IS NOT NULL)',
      variables: [
        Variable<int>(stamp),
        Variable<int>(stamp),
        Variable<String>(currentDeviceId),
      ],
      updates: {db.setLogs},
    );

    return orphaned.length + adopted;
  }

  Future<List<String>> _sessionIds(String regimeId) async {
    final rows = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    return rows.map((e) => e.id).toList();
  }

  Future<Set<String>> _completedSessionIds(String cycleId) async {
    final rows = await (db.select(db.workouts)
          ..where((t) =>
              t.cycleId.equals(cycleId) &
              t.status.equalsValue(WorkoutStatus.completed) &
              t.deletedAt.isNull()))
        .get();
    return rows.map((e) => e.sessionId).whereType<String>().toSet();
  }

  /// Null when the regime is gone — see [ensureOpenCycle].
  Future<CycleStatus?> cycleStatus(String regimeId) async {
    final regime = await (db.select(db.regimes)
          ..where((t) => t.id.equals(regimeId)))
        .getSingleOrNull();
    if (regime == null) return null;
    final cycle = await ensureOpenCycle(regimeId);
    if (cycle == null) return null;
    return CycleStatus(
      cycleId: cycle.id,
      cycleIndex: cycle.cycleIndex,
      isDeload: cycle.isDeload,
      sessionIds: await _sessionIds(regimeId),
      completedSessionIds: await _completedSessionIds(cycle.id),
      cyclesSinceDeload:
          await _cyclesSinceDeload(regimeId, beforeIndex: cycle.cycleIndex),
      deloadEnabled: regime.deloadEnabled,
      deloadAfterCycles: regime.deloadAfterCycles,
    );
  }

  /// Loads the whole Today screen in one pass, so it paints at once.
  ///
  /// Independent queries go through `Future.wait`; the rest are sequential only
  /// where they genuinely depend on what came before. Everything is on local
  /// disk, so the win here is not milliseconds saved — it is that the screen
  /// has one loading state instead of six, and cannot render a half-answer.
  ///
  /// [heatmapFromDayKey] bounds the consistency grid; the caller owns how far
  /// back it looks.
  Future<TodaySnapshot> todaySnapshot({required int heatmapFromDayKey}) async {
    // The heat query below hydrates whole `Workout` rows, which is affordable
    // only because the window is a fixed thirteen weeks — the exact shape DEBT
    // § 3 is about, and § 1's answer to it: state the bound where it can fail
    // rather than in a comment nothing checks. An open-ended key here is every
    // workout ever written, once per rebuild of Today.
    assert(
      heatmapFromDayKey >=
          dayKeyOf(DateTime.now().subtract(const Duration(days: 400))),
      "Today's heatmap is a fixed recent window, not the whole log: "
      '$heatmapFromDayKey is more than a year back',
    );
    final regimeQuery = db.select(db.regimes)
      ..where((t) => t.isActive.equals(true) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
      ])
      ..limit(1);

    final openQuery = db.select(db.workouts)
      ..where((t) =>
          t.status.equalsValue(WorkoutStatus.inProgress) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)
      ])
      ..limit(1);

    // Ordered, so the row that answers `hasHistory` is also the one Today wants
    // to talk about. Sorted on `dayKey` before `startedAt`: a session backfilled
    // for last Monday must not outrank one actually trained today just because
    // it was typed in later.
    final historyQuery = db.select(db.workouts).join([
      leftOuterJoin(
          db.sessions, db.sessions.id.equalsExp(db.workouts.sessionId)),
    ])
      ..where(db.workouts.status.equalsValue(WorkoutStatus.completed) &
          db.workouts.deletedAt.isNull())
      ..orderBy([
        OrderingTerm(expression: db.workouts.dayKey, mode: OrderingMode.desc),
        OrderingTerm(
            expression: db.workouts.startedAt, mode: OrderingMode.desc),
      ])
      ..limit(1);

    final heatQuery = db.select(db.workouts)
      ..where((t) =>
          t.dayKey.isBiggerOrEqualValue(heatmapFromDayKey) &
          t.status.equalsValue(WorkoutStatus.completed) &
          t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]);

    Future<({String? sessionName, String regimeId, String? regimeName})?>
        ownerOf(Workout? w) async => w == null ? null : workoutOwner(w.id);

    Future<int> doneOf(Workout? w) async =>
        w == null ? 0 : doneSetCount(w.id);

    Future<int> totalOf(Workout? w) async =>
        w == null ? 0 : setCount(w.id);

    Future<List<String>> namesOf(Workout? w) async =>
        w == null ? const <String>[] : workoutExerciseNames(w.id);

    final (regime, open, history, recent) = await (
      regimeQuery.getSingleOrNull(),
      openQuery.getSingleOrNull(),
      historyQuery.get(),
      heatQuery.get(),
    ).wait;

    final last = history.isEmpty
        ? null
        : (
            workout: history.first.readTable(db.workouts),
            sessionName: history.first.readTableOrNull(db.sessions)?.name,
          );

    if (regime == null) {
      return TodaySnapshot(
        regime: null,
        sessions: const [],
        status: null,
        openWorkout: open,
        openWorkoutOwner: await ownerOf(open),
        openWorkoutDoneSets: await doneOf(open),
        openWorkoutTotalSets: await totalOf(open),
        openWorkoutExerciseNames: await namesOf(open),
        hasHistory: history.isNotEmpty,
        lastCompleted: last,
        exerciseNamesBySession: const {},
        recentCompleted: recent,
      );
    }


    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    final (status, names, owner, doneSets, totalSets, openNames) = await (
      cycleStatus(regime.id),
      _exerciseNamesBySession(sessions.map((s) => s.id).toList()),
      ownerOf(open),
      doneOf(open),
      totalOf(open),
      namesOf(open),
    ).wait;

    return TodaySnapshot(
      regime: regime,
      sessions: sessions,
      status: status,
      openWorkout: open,
      openWorkoutOwner: owner,
      openWorkoutDoneSets: doneSets,
      openWorkoutTotalSets: totalSets,
      openWorkoutExerciseNames: openNames,
      hasHistory: history.isNotEmpty,
      lastCompleted: last,
      exerciseNamesBySession: names,
      recentCompleted: recent,
    );
  }

  /// One row per day trained, ever — for the full-history heatmap and for the
  /// rings on the calendar.
  ///
  /// Aggregated in SQL rather than folded in Dart. The grid needs three facts
  /// about a day, and a plain select of every completed workout hands over every
  /// column of every workout to get them: fifty years is a few thousand rows,
  /// each one serialised across the database isolate's port and rebuilt as an
  /// object on the UI isolate, to be thrown away the moment the day it belongs
  /// to has been counted. That transfer is the delay observed when Consistency
  /// opens.
  ///
  /// Raw SQL, because the query is unbounded. Its row count is one per day ever
  /// trained, which is the case the row-mapping rule addresses: at four grouped
  /// columns per row through drift's `TypedResult.read`, at 14µs a call, a long
  /// history spends most of Consistency's opening inside the row mapper rather
  /// than inside SQLite. Read positionally off a `QueryRow` the same rows and the same
  /// numbers cost a fraction of it; see [exerciseProgress], where the
  /// measurement was taken. The price is that a renamed column compiles and
  /// fails on a device, so `query_conversion_test.dart` reads every column this
  /// names, and holds it against the drift query it replaced.
  Future<List<LoggedDay>> loggedDays() async {
    final rows = await db.customSelect(
      'SELECT day_key AS day_key, COUNT(id) AS n, '
      // Any workout on the day, so a ringed day on the calendar has something
      // to open. `max` because it has to be *some* deterministic one.
      'MAX(id) AS any_id, '
      // Stored as an integer, so the max is "was any of them a deload".
      'MAX(is_deload) AS deload '
      'FROM workouts '
      "WHERE status = 'completed' AND deleted_at IS NULL "
      'GROUP BY day_key ORDER BY day_key',
      readsFrom: {db.workouts},
    ).get();

    return [
      for (final r in rows)
        // A day with no id behind it is not a day that can be opened. Handing
        // one over would send the empty string to the calendar as a workout to
        // push, `workoutDetail` would find nothing, and the tap would land on a
        // screen saying the session was gone. `max(id)` over a group that
        // produced a row cannot actually be null — the guard is for the shape
        // of the answer, not for a case anyone has seen.
        if (r.readNullable<String>('any_id') != null)
          LoggedDay(
            dayKey: r.read<int>('day_key'),
            workouts: r.readNullable<int>('n') ?? 0,
            isDeload: (r.readNullable<int>('deload') ?? 0) != 0,
            anyWorkoutId: r.read<String>('any_id'),
          ),
    ];
  }

  /// Hard sets per muscle since [fromDayKey], for the weekly volume bars.
  ///
  /// Aggregated in SQL for the same reason [loggedDays] is: the answer is
  /// twelve numbers, and folding it in Dart means shipping every set row of
  /// every workout in the window across the isolate port to count them.
  ///
  /// Three rules, all of them decisions rather than defaults:
  ///
  /// * Ticked sets only. [startWorkout] writes the planned rows in advance,
  ///   so counting rows would credit a session that has not been performed.
  /// * Volume set types only ([countsAsVolume]), which is not the progress
  ///   rule.
  ///   A backoff set is work; a drop leg is the same set continued.
  /// * Deload weeks are counted. A light week is still sets performed, and
  ///   this
  ///   number is about work done rather than about progress — the same call
  ///   `domain/consistency.dart` already made for the heatmap. The chart is
  ///   where deloads are excluded, because an e1RM off 80% describes the
  ///   programme rather than the lifter.
  ///
  /// Left in drift deliberately: the `GROUP BY` is on the muscle, so this
  /// returns one row per muscle group — twelve, whatever the history behind
  /// them weighs. Row mapping is only a cost when the row count grows with the
  /// log, and the count here is a property of the enum.
  Future<Map<MuscleGroup, int>> setsByMuscleSince(int fromDayKey) async {
    final counted = db.setLogs.id.count();
    final muscle = _loggedMuscle;
    final rows = await (_volumeQuery()
          ..addColumns(<Expression<Object>>[muscle, counted])
          ..where(db.workouts.dayKey.isBiggerOrEqualValue(fromDayKey))
          ..groupBy([muscle]))
        .get();

    return {
      for (final r in rows)
        MuscleGroup.values.byName(r.read(muscle)!): r.read(counted) ?? 0,
    };
  }

  /// The catalog's muscle for each of [exerciseIds], for snapshotting onto the
  /// rows a workout is built from.
  ///
  /// One query for a whole session rather than one per slot: this is on the
  /// path of the tap that opens the log.
  Future<Map<String, MuscleGroup>> _musclesOf(
    Iterable<String> exerciseIds,
  ) async {
    final ids = exerciseIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await (db.selectOnly(db.exercises)
          ..addColumns([db.exercises.id, db.exercises.muscle])
          ..where(db.exercises.id.isIn(ids)))
        .get();
    return {
      for (final r in rows)
        r.read(db.exercises.id)!:
            r.readWithConverter(db.exercises.muscle)!,
    };
  }

  /// The bar each of these exercises names on its catalog row.
  Future<Map<String, BarKind>> _catalogBarsOf(
    Iterable<String> exerciseIds,
  ) async {
    final ids = exerciseIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await (db.selectOnly(db.exercises)
          ..addColumns([db.exercises.id, db.exercises.barKind])
          ..where(db.exercises.id.isIn(ids)))
        .get();
    return {
      for (final r in rows)
        r.read(db.exercises.id)!: r.readWithConverter(db.exercises.barKind)!,
    };
  }

  /// The bar a movement is actually loaded on in one training day: the day's
  /// override if it has been given one, otherwise the catalog's answer.
  ///
  /// This is the value snapshotted onto every `workout_exercises` row as it is
  /// created, which is what makes a bar changed today leave March alone.
  ///
  /// [sessionId] is null for a workout that came from no template — and for an
  /// exercise added mid-session, which has no slot to carry an override. Both
  /// fall through to the catalog, which is the only answer that exists for
  /// them.
  Future<BarKind> _barForWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId)))
        .getSingleOrNull();
    final sessionId = workout?.sessionId;
    if (sessionId != null) {
      final slot = await _slotFor(sessionId: sessionId, exerciseId: exerciseId);
      final own = slot?.barKind;
      if (own != null) return own;
    }
    return (await _catalogBarsOf([exerciseId]))[exerciseId] ?? BarKind.none;
  }

  /// The template slot for one movement in one day.
  ///
  /// Ordered and limited rather than requested as a single row, because a
  /// day is allowed to hold the same movement twice — squats early and again
  /// as a burnout — and the picker says so in as many words: it *marks* an
  /// exercise already in the session rather than refusing it. `getSingleOrNull`
  /// throws on two rows, and it throws inside a tap handler, so the symptom of
  /// doing a supported thing would be a menu that will not open at all. A merge
  /// or a restore can deliver the same shape without anyone having chosen it.
  ///
  /// The first occurrence in the day wins, so every reader agrees on which slot
  /// answers for the movement rather than each getting whichever row SQLite
  /// happened to return.
  Future<SessionExercise?> _slotFor({
    required String sessionId,
    required String exerciseId,
  }) {
    return (db.select(db.sessionExercises)
          ..where((t) =>
              t.sessionId.equals(sessionId) &
              t.exerciseId.equals(exerciseId) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The template slot a logged exercise came from, or null when there is
  /// none.
  ///
  /// Null is an ordinary answer rather than a failure: an exercise added
  /// mid-session is not in the template, and neither is any exercise in a
  /// workout that came from no session at all. The caller uses it to decide
  /// whether there are per-day overrides to offer.
  Future<String?> slotIdFor({
    required String? sessionId,
    required String exerciseId,
  }) async {
    if (sessionId == null) return null;
    final slot = await _slotFor(sessionId: sessionId, exerciseId: exerciseId);
    return slot?.id;
  }

  /// The muscle a logged set counts toward: the snapshot on the row, falling
  /// back to the catalog for rows written before that column existed.
  ///
  /// The fallback is the whole reason the column is nullable — see
  /// `WorkoutExercises.muscle`. Every row this app writes from now on carries
  /// its own answer, so the join below is only load-bearing for history logged
  /// before the snapshot, and for rows restored from an older backup.
  Expression<String> get _loggedMuscle =>
      coalesce([db.workoutExercises.muscle, db.exercises.muscle]);

  /// The joins and filters every volume count shares.
  ///
  /// Factored so the rolling window and the weekly history cannot drift apart:
  /// two copies of these predicates is two definitions of "a hard set", and the
  /// screens that showed different numbers for the same week would be right to.
  JoinedSelectStatement<HasResultSet, dynamic> _volumeQuery() {
    return db.selectOnly(db.setLogs).join([
      innerJoin(
        db.workoutExercises,
        db.workoutExercises.id.equalsExp(db.setLogs.workoutExerciseId),
      ),
      innerJoin(
        db.workouts,
        db.workouts.id.equalsExp(db.workoutExercises.workoutId),
      ),
      innerJoin(
        db.exercises,
        db.exercises.id.equalsExp(db.workoutExercises.exerciseId),
      ),
    ])
      ..where(
        // Sets logged in the open session count from the moment they are
        // ticked. The bar list is read mid-workout, and a completed set is
        // counted whether or not the session has been finished.
        db.workouts.status.equalsValue(WorkoutStatus.abandoned).not() &
            db.workouts.deletedAt.isNull() &
            db.workoutExercises.deletedAt.isNull() &
            db.workoutExercises.skipReason.equalsValue(SkipReason.none) &
            db.setLogs.isDone.equals(true) &
            db.setLogs.deletedAt.isNull() &
            db.setLogs.setType.isIn([
              for (final t in SetType.values)
                if (countsAsVolume(t)) t.name,
            ]),
      );
  }

  /// Hard sets per muscle per day, between two day keys inclusive.
  ///
  /// Counted by day rather than by week on purpose. `day_key` is a `yyyyMMdd`
  /// integer, not a date, so bucketing into weeks in SQL would mean unpacking
  /// it into a real date on every row and doing calendar arithmetic there;
  /// `domain/volume_history.dart` does that once in Dart, where the week rule
  /// is testable without a database.
  ///
  /// The volume rules are [setsByMuscleSince]'s, exactly — same joins, same
  /// filters, same definition of a hard set.
  ///
  /// Unbounded, which is why it is raw SQL. The range control's `All` requests
  /// for fifty years. Forty thousand grouped rows through drift's
  /// `TypedResult.read` is over half a second on the UI isolate, which is the
  /// pause between picking `All` and seeing bars. Read positionally off a
  /// `QueryRow` it is a fraction of that, for the same rows and the same
  /// numbers — see [exerciseProgress], which is where this measurement was
  /// taken.
  Future<List<({int dayKey, MuscleGroup muscle, int sets})>> setsByMuscleDaily({
    required int fromDayKey,
    required int toDayKey,
  }) async {
    final rows = await db.customSelect(
      'SELECT wo.day_key AS day_key, '
      // The muscle the row was logged with, falling back to the catalog's —
      // exactly [_loggedMuscle], which is what keeps refiling an exercise from
      // rewriting every week it ever appeared in.
      'COALESCE(we.muscle, e.muscle) AS logged_muscle, '
      'COUNT(s.id) AS n '
      'FROM set_logs s '
      'INNER JOIN workout_exercises we ON we.id = s.workout_exercise_id '
      'INNER JOIN workouts wo ON wo.id = we.workout_id '
      'INNER JOIN exercises e ON e.id = we.exercise_id '
      // [_volumeQuery]'s filters, one for one.
      "WHERE wo.status <> 'abandoned' AND wo.deleted_at IS NULL "
      "AND we.deleted_at IS NULL AND we.skip_reason = 'none' "
      'AND s.is_done = 1 AND s.deleted_at IS NULL '
      'AND s.set_type IN ($_volumeSetTypes) '
      'AND wo.day_key BETWEEN ?1 AND ?2 '
      // Grouped on the expression, not on the alias: `muscle` is a column on
      // two of the joined tables and SQLite calls it ambiguous.
      'GROUP BY wo.day_key, COALESCE(we.muscle, e.muscle)',
      variables: [Variable.withInt(fromDayKey), Variable.withInt(toDayKey)],
      readsFrom: {db.setLogs, db.workoutExercises, db.workouts, db.exercises},
    ).get();

    return [
      for (final r in rows)
        (
          dayKey: r.read<int>('day_key'),
          muscle: MuscleGroup.values.byName(r.read<String>('logged_muscle')),
          sets: r.read<int>('n'),
        ),
    ];
  }

  /// The set types that count as volume, as a SQL list.
  ///
  /// Built from [countsAsVolume] rather than written out, so the raw statement
  /// above cannot drift from the rule the rest of the app counts by.
  static final String _volumeSetTypes = [
    for (final t in SetType.values)
      if (countsAsVolume(t)) "'${t.name}'",
  ].join(', ');

  /// Which movements produced a region's sets, most first.
  ///
  /// The question a regional total cannot answer: `Back 17.8 per week` is a
  /// figure that can be read but not acted on, whereas "eleven of those were
  /// lat pulldowns and none were rows" describes the same training in terms
  /// that indicate what to change. Counted over the same span and through the same filters as
  /// [setsByMuscleDaily], so the parts add up to the whole.
  ///
  /// The name is read live rather than snapshotted, unlike the muscle:
  /// renaming "Dips" to "Weighted dips" is the same movement under a corrected
  /// label, and a list showing both would be the rename failing rather than
  /// history being preserved. What a movement *trained* is a fact about the
  /// session; what it is *called* is a fact about now.
  ///
  /// Drift, for [setsByMuscleSince]'s reason: grouped by movement, so the row
  /// count is bounded by the catalog — a couple of hundred at the outside —
  /// rather than by the number of sets counted into it.
  Future<List<({String exerciseId, String name, int sets})>> setsByExercise({
    required int fromDayKey,
    required int toDayKey,
    required List<MuscleGroup> muscles,
  }) async {
    if (muscles.isEmpty) return const [];
    final counted = db.setLogs.id.count();
    final rows = await (_volumeQuery()
          ..addColumns(<Expression<Object>>[
            db.workoutExercises.exerciseId,
            db.exercises.name,
            counted,
          ])
          ..where(
            db.workouts.dayKey.isBetweenValues(fromDayKey, toDayKey) &
                _loggedMuscle.isIn([for (final m in muscles) m.name]),
          )
          ..groupBy([db.workoutExercises.exerciseId, db.exercises.name])
          ..orderBy([OrderingTerm.desc(counted)]))
        .get();

    return [
      for (final r in rows)
        (
          exerciseId: r.read(db.workoutExercises.exerciseId)!,
          name: r.read(db.exercises.name)!,
          sets: r.read(counted) ?? 0,
        ),
    ];
  }

  /// The oldest day anything countable was logged on, or null on a fresh app.
  ///
  /// What the year picker offers is built from this: a year with nothing in it
  /// is a year the picker has no business listing.
  ///
  /// One row, by construction: `MIN` over the whole log.
  Future<int?> firstLoggedDayKey() async {
    final oldest = db.workouts.dayKey.min();
    final row = await (_volumeQuery()..addColumns([oldest])).getSingleOrNull();
    return row?.read(oldest);
  }

  /// The session template as the diff wants it: exercise id and name, in order.
  Future<List<ExerciseRef>> sessionTemplate(String sessionId) async {
    final rows = await (db.select(db.sessionExercises).join([
      innerJoin(db.exercises,
          db.exercises.id.equalsExp(db.sessionExercises.exerciseId)),
    ])
          ..where(db.sessionExercises.sessionId.equals(sessionId) &
              db.sessionExercises.deletedAt.isNull())
          ..orderBy([OrderingTerm(expression: db.sessionExercises.orderIndex)]))
        .get();
    return [
      for (final r in rows)
        (
          exerciseId: r.readTable(db.sessionExercises).exerciseId,
          name: r.readTable(db.exercises).name,
        ),
    ];
  }

  /// How many working sets each slot of the day programmes, in template order.
  /// Read against today's ticked sets by `diffSetCounts`.
  Future<List<SetTarget>> sessionSetTargets(String sessionId) async {
    final rows = await (db.select(db.sessionExercises).join([
      innerJoin(db.exercises,
          db.exercises.id.equalsExp(db.sessionExercises.exerciseId)),
    ])
          ..where(db.sessionExercises.sessionId.equals(sessionId) &
              db.sessionExercises.deletedAt.isNull())
          ..orderBy([OrderingTerm(expression: db.sessionExercises.orderIndex)]))
        .get();
    return [
      for (final r in rows)
        (
          exerciseId: r.readTable(db.sessionExercises).exerciseId,
          name: r.readTable(db.exercises).name,
          targetSets: r.readTable(db.sessionExercises).targetSets,
        ),
    ];
  }

  /// Writes today's improvisation back into the programme — only the parts of
  /// it that were ticked.
  ///
  /// Everything here touches `session_exercises` and nothing else. Past
  /// workouts are snapshots and stay exactly as they were logged (invariant 2);
  /// this changes what *next* week opens with.
  ///
  /// Prefill is unaffected in the way that matters: a slot added here inherits
  /// the session's own history for that movement, which is empty until today,
  /// so next week borrows from today's log through the normal path rather than
  /// being handed numbers by this write.
  Future<void> applySessionChanges({
    required String sessionId,
    required List<SessionChange> changes,
  }) async {
    if (changes.isEmpty) return;

    await db.transaction(() async {
      // One past the highest live position. Counting live rows hands a new
      // slot a position a surviving one still holds, because a removed slot is
      // tombstoned and nothing renumbers behind it.
      Future<int> nextOrderIndex() async {
        final live = await (db.select(db.sessionExercises)
              ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull()))
            .get();
        return nextPosition(live.map((s) => s.orderIndex));
      }

      for (final change in changes) {
        switch (change.kind) {
          case SessionChangeKind.added:
            for (final exerciseId in change.exerciseIds) {
              // A slot removed weeks ago is tombstoned, not gone. Re-adding the
              // movement revives that row rather than inserting a second one,
              // so its set target and rep range come back with it.
              final buried = await (db.select(db.sessionExercises)
                    ..where((t) =>
                        t.sessionId.equals(sessionId) &
                        t.exerciseId.equals(exerciseId) &
                        t.deletedAt.isNotNull())
                    ..limit(1))
                  .getSingleOrNull();
              if (buried != null) {
                await (db.update(db.sessionExercises)
                      ..where((t) => t.id.equals(buried.id)))
                    .write(
                  SessionExercisesCompanion(
                    deletedAt: const Value(null),
                    // Back at the end rather than at the position it held when
                    // it was removed — that position belongs to whatever moved
                    // up behind it, and two slots on one index is an order the
                    // database is free to break either way.
                    orderIndex: Value(await nextOrderIndex()),
                    deviceId: Value(currentDeviceId),
                    updatedAt: Value(nowMs()),
                    dirty: const Value(true),
                  ),
                );
                continue;
              }
              await db.into(db.sessionExercises).insert(
                    SessionExercisesCompanion.insert(
                      id: Value(newId()),
                      sessionId: sessionId,
                      exerciseId: exerciseId,
                      orderIndex: await nextOrderIndex(),
                    ),
                  );
            }

          case SessionChangeKind.removed:
            for (final exerciseId in change.exerciseIds) {
              await (db.update(db.sessionExercises)
                    ..where((t) =>
                        t.sessionId.equals(sessionId) &
                        t.exerciseId.equals(exerciseId) &
                        t.deletedAt.isNull()))
                  .write(
                SessionExercisesCompanion(
                  deletedAt: Value(nowMs()),
                  deviceId: Value(currentDeviceId),
                  updatedAt: Value(nowMs()),
                  dirty: const Value(true),
                ),
              );
            }

          case SessionChangeKind.setCount:
            // `diffSetCounts` offers this only for a movement the day runs
            // once, so the update names exactly one slot.
            final count = change.setCount;
            if (count == null || count < 1) break;
            for (final exerciseId in change.exerciseIds) {
              await (db.update(db.sessionExercises)
                    ..where((t) =>
                        t.sessionId.equals(sessionId) &
                        t.exerciseId.equals(exerciseId) &
                        t.deletedAt.isNull()))
                  .write(
                SessionExercisesCompanion(
                  targetSets: Value(count),
                  deviceId: Value(currentDeviceId),
                  updatedAt: Value(nowMs()),
                  dirty: const Value(true),
                ),
              );
            }

          case SessionChangeKind.reordered:
            // Applied last by the caller's ordering below, so it sees whatever
            // the adds and removes left behind.
            break;
        }
      }

      // Order is resolved once, at the end, against the slots that actually
      // exist now. Doing it inside the loop would write positions for rows that
      // a later change deletes.
      final reordering = changes
          .where((c) => c.kind == SessionChangeKind.reordered)
          .toList();
      final reorder = reordering.isEmpty ? null : reordering.first;
      if (reorder != null) {
        final live = await (db.select(db.sessionExercises)
              ..where(
                  (t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();

        // Today's order first, then anything the workout never touched, kept in
        // its existing relative order: a skipped slot has not been requested
        // to move to the end.
        final wanted = <SessionExercise>[];
        for (final exerciseId in reorder.exerciseIds) {
          final slot =
              live.where((s) => s.exerciseId == exerciseId).firstOrNull;
          if (slot != null && !wanted.contains(slot)) wanted.add(slot);
        }
        for (final slot in live) {
          if (!wanted.contains(slot)) wanted.add(slot);
        }

        // Two passes through free ground — see [renumber]. Applying a
        // permutation one row at a time puts the first row it moves onto a
        // position a surviving row still holds, and
        // `idx_session_exercises_position_live` refuses it mid-transaction.
        await renumber(
          [for (final slot in wanted) slot.id],
          scope: {for (final s in live) s.id: s.orderIndex},
          write: (id, orderIndex) async {
            await (db.update(db.sessionExercises)..where((t) => t.id.equals(id)))
                .write(
              SessionExercisesCompanion(
                orderIndex: Value(orderIndex),
                deviceId: Value(currentDeviceId),
                updatedAt: Value(nowMs()),
                dirty: const Value(true),
              ),
            );
          },
        );
      }
    });
  }

  /// One query for every session's exercise names, rather than one per row.
  Future<Map<String, List<String>>> _exerciseNamesBySession(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const {};

    final rows = await (db.select(db.sessionExercises).join([
      innerJoin(db.exercises,
          db.exercises.id.equalsExp(db.sessionExercises.exerciseId)),
    ])
          ..where(db.sessionExercises.sessionId.isIn(sessionIds) &
              db.sessionExercises.deletedAt.isNull())
          ..orderBy([OrderingTerm(expression: db.sessionExercises.orderIndex)]))
        .get();

    // Seeded for every session, so an empty list means "no exercises" rather
    // than "not loaded" — the distinction the session rows act on.
    final names = {for (final id in sessionIds) id: <String>[]};
    for (final row in rows) {
      final slot = row.readTable(db.sessionExercises);
      names[slot.sessionId]?.add(row.readTable(db.exercises).name);
    }
    return names;
  }

  /// Closes the current cycle early. The escape hatch for "I'm skipping leg 2
  /// this round" — without it a single missed session would stall the
  /// programme forever.
  /// One transaction, because the three steps only make sense together: between
  /// closing this cycle and opening the next, the regime has no open cycle at
  /// all, and every read of `cycleStatus` that lands there mints one of its own.
  /// `ensureOpenCycle` is a transaction for exactly that reason, and leaving
  /// the gap open between two of them hands the race straight back.
  Future<void> advanceCycle(String regimeId) => db.transaction(() async {
        final cycle = await _ensureOpenCycle(regimeId);
        if (cycle == null) return;
        await (db.update(db.cycles)..where((t) => t.id.equals(cycle.id))).write(
          CyclesCompanion(
            completedAt: Value(nowMs()),
            deviceId: Value(currentDeviceId),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
        await _ensureOpenCycle(regimeId);
      });

  /// The cycle that was open on [at], or null when the date predates every
  /// cycle this regime has had.
  ///
  /// A backdated workout belongs to the cycle that was open when it happened,
  /// not to whichever is open now. Backfilling yesterday is usually the same
  /// cycle either way; backfilling three weeks ago would otherwise count
  /// towards the current cycle, complete it on the strength of work done under
  /// a previous one, and move the deload counter early.
  Future<Cycle?> cycleCovering(String regimeId, DateTime at) async {
    final stamp = at.millisecondsSinceEpoch;
    final cycles = await (db.select(db.cycles)
          ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.cycleIndex, mode: OrderingMode.desc)
          ]))
        .get();

    for (final c in cycles) {
      final ended = c.completedAt;
      // Open-ended on the right: the cycle still running covers everything
      // since it began, including today.
      if (c.startedAt <= stamp && (ended == null || stamp <= ended)) return c;
    }
    return null;
  }

  /// Closes the open cycle if every session it still owes has been trained.
  ///
  /// A cycle closes the moment it is satisfied, whatever satisfied it — which
  /// is why deletion calls this and not only `completeWorkout`. Deleting the
  /// last untrained day of a cycle otherwise leaves it complete-but-open, and
  /// Today shows "UP NEXT: Push 1" over a full row of filled dots until the
  /// next workout happens to heal it.
  ///
  /// One transaction, for the reason [advanceCycle] gives: the close and the
  /// open that follows it are a single act, and the moment between them is a
  /// regime with no open cycle.
  ///
  /// Safe to call from inside another transaction — drift nests this as a
  /// savepoint — which is what lets [setWorkoutDate] settle both cycles inside
  /// the write that moved the workout.
  Future<bool> closeCycleIfSatisfied(String regimeId) =>
      db.transaction(() async {
        final sessionIds = await _sessionIds(regimeId);
        if (sessionIds.isEmpty) return false;

        final cycle = await _ensureOpenCycle(regimeId);
        if (cycle == null) return false;
        final done = await _completedSessionIds(cycle.id);
        if (!sessionIds.every(done.contains)) return false;

        await (db.update(db.cycles)..where((t) => t.id.equals(cycle.id))).write(
          CyclesCompanion(
            completedAt: Value(nowMs()),
            deviceId: Value(currentDeviceId),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
        await _ensureOpenCycle(regimeId);
        return true;
      });

  /// Overrides whether the open cycle is a deload. The suggestion is never
  /// binding.
  Future<void> setCycleDeload(String cycleId, bool isDeload) async {
    await (db.update(db.cycles)..where((t) => t.id.equals(cycleId))).write(
      CyclesCompanion(
        isDeload: Value(isDeload),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  // ── History lookups ───────────────────────────────────────────────────

  /// Every past performance of one exercise, newest first.
  ///
  /// Feeds both prefill and the progress chart, so it carries session identity
  /// and deload status rather than just numbers.
  ///
  /// [sessionId] guarantees the most recent performances *in that session* are
  /// in the result whatever [limit] is. Without it, fanning one movement across
  /// many training days pushes a slot left untrained for 30-odd performances
  /// elsewhere out of the window, and prefill quietly falls back to another
  /// session, labelled accurately but not the intended figure. The
  /// same-session lookup should have no horizon; the cross-session fallback
  /// still does.
  /// A null [limit] takes the whole history — for the chart, which is the one
  /// caller that has to see all of it.
  Future<List<PastPerformance>> pastPerformances(
    String exerciseId, {
    int? limit = 60,
    String? excludeWorkoutId,
    String? sessionId,
  }) async {
    final recent = await _performances(
      exerciseId,
      limit: limit,
      excludeWorkoutId: excludeWorkoutId,
    );
    if (sessionId == null) return recent;

    final sameSession = await _performances(
      exerciseId,
      limit: 5,
      excludeWorkoutId: excludeWorkoutId,
      sessionId: sessionId,
    );

    // Keyed on the slot rather than the workout. The same movement can be run
    // twice in one session — a second pass, a different implement — and keying
    // this on the workout throws one of the two away before prefill sees it.
    String keyOf(PastPerformance p) =>
        p.slotId.isEmpty ? p.workoutId : p.slotId;

    final bySlot = {for (final p in recent) keyOf(p): p};
    for (final p in sameSession) {
      bySlot.putIfAbsent(keyOf(p), () => p);
    }
    // Sort on the same key both queries ordered by. Sorting the merged list on
    // dayKey alone leaves two performances from one day in map insertion order,
    // so prefill can pick the earlier and call it last time.
    //
    // Two slots of one workout tie on `startedAt`, so the slot id breaks it —
    // ids are UUID v7, so the lower one is the slot that was created first,
    // which is the one the session template opened with. Last time's numbers
    // come from the programmed slot rather than from whatever was improvised
    // after it.
    final merged = bySlot.values.toList()
      ..sort((a, b) {
        final byStart = b.startedAt.compareTo(a.startedAt);
        return byStart != 0 ? byStart : a.slotId.compareTo(b.slotId);
      });
    return merged;
  }

  /// Raw SQL, because of the gather. This is unbounded at `limit: null`, so
  /// hydrating whole `WorkoutExercise`, `Workout` and `Session` rows to read
  /// eight columns of them, then collecting their sets with
  /// `WHERE workout_exercise_id IN (…)`, would put one bound parameter per
  /// performance into a statement thousands of variables wide on a long
  /// history, built and bound on the UI isolate. The slot list is a subquery
  /// inside the set statement instead: the same predicate text, built once
  /// below so the two statements cannot drift apart, and four bound parameters
  /// however long the history gets.
  ///
  /// The price is a renamed column that compiles and fails on a device, so
  /// `query_conversion_test.dart` reads every column named here and holds the
  /// result against the drift queries this replaced.
  Future<List<PastPerformance>> _performances(
    String exerciseId, {
    required int? limit,
    String? excludeWorkoutId,
    String? sessionId,
  }) async {
    // `?2` and `?3` are the optional predicates, passed as null when they do
    // not apply so the statement text — and so SQLite's compiled-statement
    // cache entry — is the same one every call.
    final where = 'we.exercise_id = ?1 AND we.deleted_at IS NULL '
        "AND wo.deleted_at IS NULL AND wo.status = 'completed' "
        'AND (?2 IS NULL OR wo.id <> ?2) '
        'AND (?3 IS NULL OR wo.session_id = ?3) ';
    // A null limit is the whole history — see [pastPerformances]. SQLite reads
    // a negative limit as no limit, which keeps the text constant too.
    const order = 'ORDER BY wo.started_at DESC LIMIT ?4';
    final variables = [
      Variable.withString(exerciseId),
      Variable<String>(excludeWorkoutId),
      Variable<String>(sessionId),
      Variable.withInt(limit ?? -1),
    ];

    final rows = await db.customSelect(
      'SELECT we.id AS slot_id, we.skip_reason AS skip_reason, '
      'wo.id AS workout_id, wo.session_id AS session_id, '
      'wo.day_key AS day_key, wo.started_at AS started_at, '
      'wo.is_deload AS is_deload, se.name AS session_name '
      'FROM workout_exercises we '
      'INNER JOIN workouts wo ON wo.id = we.workout_id '
      'LEFT JOIN sessions se ON se.id = wo.session_id '
      'WHERE $where$order',
      variables: variables,
      readsFrom: {db.workoutExercises, db.workouts, db.sessions},
    ).get();
    if (rows.isEmpty) return const [];

    // The same slots again as a subquery rather than as a list of ids: the
    // window is expressed once in SQL instead of once per row in parameters.
    final setRows = await db.customSelect(
      'SELECT s.workout_exercise_id AS slot_id, s.set_type AS set_type, '
      's.weight AS weight, s.reps AS reps, s.partial_reps AS partial_reps, '
      's.added_weight AS added_weight, s.parent_set_id AS parent_set_id, '
      's.is_done AS is_done '
      'FROM set_logs s WHERE s.deleted_at IS NULL '
      'AND s.workout_exercise_id IN ('
      'SELECT we.id FROM workout_exercises we '
      'INNER JOIN workouts wo ON wo.id = we.workout_id '
      'WHERE $where$order) '
      'ORDER BY s.set_index',
      variables: variables,
      readsFrom: {db.setLogs, db.workoutExercises, db.workouts},
    ).get();

    final setsByWe = <String, List<PastSet>>{};
    for (final s in setRows) {
      // Ticked sets only, as before: a planned row is not a performance.
      if (!s.read<bool>('is_done')) continue;
      setsByWe.putIfAbsent(s.read<String>('slot_id'), () => []).add(PastSet(
            type: SetType.values.byName(s.read<String>('set_type')),
            weight: s.readNullable<double>('weight'),
            reps: s.readNullable<int>('reps'),
            partialReps: s.readNullable<int>('partial_reps'),
            addedWeight: s.readNullable<double>('added_weight'),
            isLeg: s.readNullable<String>('parent_set_id') != null,
          ));
    }

    return [
      for (final r in rows)
        () {
          final slotId = r.read<String>('slot_id');
          return PastPerformance(
            workoutId: r.read<String>('workout_id'),
            slotId: slotId,
            sessionId: r.readNullable<String>('session_id'),
            sessionName:
                r.readNullable<String>('session_name') ??
                unplannedSessionName,
            dayKey: r.read<int>('day_key'),
            startedAt: r.read<int>('started_at'),
            isDeload: r.read<bool>('is_deload'),
            // Sets logged before the exercise was marked skipped did happen:
            // two sets then a bad shoulder is two real sets. They stay
            // eligible here *and* are shown under the skip pill in history, so
            // there is one story rather than two. Read from `skipReason`
            // deliberately, rather than falling out of the empty-sets check.
            skipReason: SkipReason.values.byName(r.read<String>('skip_reason')),
            sets: setsByWe[slotId] ?? const <PastSet>[],
          );
        }(),
    ];
  }

  /// `startedAt` is strictly older than [cursor], ties broken on id.
  ///
  /// Ids are UUID v7, so lexicographic order is creation order and the tie
  /// break is stable rather than arbitrary.
  Expression<bool> _olderThan(HistoryCursor cursor) =>
      db.workouts.startedAt.isSmallerThanValue(cursor.startedAt) |
      (db.workouts.startedAt.equals(cursor.startedAt) &
          db.workouts.id.isSmallerThanValue(cursor.id));

  List<OrderingTerm Function($WorkoutsTable)> get _newestFirst => [
        (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ];

  /// One page of the history feed, newest first.
  ///
  /// Pass the last row's [WorkoutSummary.cursor] as [olderThan] to get the next
  /// page. A short page means the end of history.
  Future<List<WorkoutSummary>> workoutFeed({
    int limit = 20,
    HistoryCursor? olderThan,
    String? sessionId,
    String? regimeId,
    bool deloadOnly = false,
  }) async {
    // Bounded by the page rather than by the log, which is the answer every
    // query in this
    // repository owes. It stays drift rather than raw because its row
    // count is what the user has scrolled into view; the `IN (…)` gathers below
    // are one bound parameter per row of *that*. The ceiling is not a product
    // rule, it is the assert § 1 asks for: a limit this large is a paging bug
    // upstream, and this is where it becomes visible instead of becoming a
    // statement thousands of variables wide.
    assert(limit > 0 && limit <= 5000,
        'the feed pages by keyset — $limit rows is a paging bug, not a page');
    var predicate = db.workouts.status.equalsValue(WorkoutStatus.completed) &
        db.workouts.deletedAt.isNull();
    // Filters go in the query, never over the loaded page: History pages by
    // keyset (RULES § Data), and a page filtered after the fact comes
    // back short, which the feed reads as the end of history.
    if (sessionId != null) {
      predicate = predicate & db.workouts.sessionId.equals(sessionId);
    }
    if (regimeId != null) {
      predicate = predicate & db.workouts.regimeId.equals(regimeId);
    }
    if (deloadOnly) {
      predicate = predicate & db.workouts.isDeload.equals(true);
    }
    if (olderThan != null) predicate = predicate & _olderThan(olderThan);

    final workouts = await (db.select(db.workouts)
          ..where((_) => predicate)
          ..orderBy(_newestFirst)
          ..limit(limit))
        .get();
    if (workouts.isEmpty) return const [];

    final workoutIds = workouts.map((w) => w.id).toList();
    final sessionIds =
        workouts.map((w) => w.sessionId).whereType<String>().toSet().toList();
    final sessions = sessionIds.isEmpty
        ? <Session>[]
        : await (db.select(db.sessions)..where((t) => t.id.isIn(sessionIds)))
            .get();
    final sessionNames = {for (final s in sessions) s.id: s.name};

    final entries = await (db.select(db.workoutExercises)
          ..where((t) => t.workoutId.isIn(workoutIds) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();

    final exerciseIds = entries.map((e) => e.exerciseId).toSet().toList();
    final exercises = exerciseIds.isEmpty
        ? <Exercise>[]
        : await (db.select(db.exercises)..where((t) => t.id.isIn(exerciseIds)))
            .get();
    final exerciseNames = {for (final e in exercises) e.id: e.name};

    final setCounts = <String, int>{};
    if (entries.isNotEmpty) {
      final counted = db.setLogs.id.count();
      final rows = await (db.selectOnly(db.setLogs)
            ..addColumns([db.setLogs.workoutExerciseId, counted])
            ..where(db.setLogs.workoutExerciseId
                    .isIn(entries.map((e) => e.id).toList()) &
                db.setLogs.deletedAt.isNull() &
                db.setLogs.isDone.equals(true))
            ..groupBy([db.setLogs.workoutExerciseId]))
          .get();
      for (final r in rows) {
        setCounts[r.read(db.setLogs.workoutExerciseId)!] = r.read(counted) ?? 0;
      }
    }

    return [
      for (final w in workouts)
        () {
          final mine = entries.where((e) => e.workoutId == w.id).toList();
          return WorkoutSummary(
            workout: w,
            sessionName:
                w.sessionId == null ? null : sessionNames[w.sessionId!],
            exerciseNames: [
              for (final e in mine)
                if (exerciseNames[e.exerciseId] != null)
                  exerciseNames[e.exerciseId]!,
            ],
            exerciseCount: mine.length,
            setCount: mine.fold(0, (sum, e) => sum + (setCounts[e.id] ?? 0)),
            skippedCount:
                mine.where((e) => e.skipReason != SkipReason.none).length,
          );
        }(),
    ];
  }

  /// Every exercise with at least one logged performance, most recently trained
  /// first. The index for the per-exercise history views.
  ///
  /// Drift rather than raw: grouped by exercise, so this returns one row per
  /// movement ever trained and the catalog bounds it. Years of training make
  /// the counts bigger, not the result longer.
  Future<List<ExerciseHistorySummary>> exercisesWithHistory() async {
    final performed = db.workoutExercises.id.count();
    final lastDay = db.workouts.dayKey.max();

    final rows = await (db.selectOnly(db.workoutExercises).join([
      innerJoin(db.workouts,
          db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
    ])
          ..addColumns([db.workoutExercises.exerciseId, performed, lastDay])
          // "2 sessions" has to mean times trained. A slot left blank still
          // counts, the session having been attended and the row present, but
          // one marked skipped with a reason did not occur.
          ..where(db.workoutExercises.deletedAt.isNull() &
              db.workoutExercises.skipReason
                  .equalsValue(SkipReason.none) &
              db.workouts.deletedAt.isNull() &
              db.workouts.status.equalsValue(WorkoutStatus.completed))
          ..groupBy([db.workoutExercises.exerciseId]))
        .get();
    if (rows.isEmpty) return const [];

    final ids = [
      for (final r in rows) r.read(db.workoutExercises.exerciseId)!,
    ];
    final exercises =
        await (db.select(db.exercises)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final e in exercises) e.id: e};

    final summaries = <ExerciseHistorySummary>[
      for (final r in rows)
        if (byId[r.read(db.workoutExercises.exerciseId)!] != null)
          ExerciseHistorySummary(
            exercise: byId[r.read(db.workoutExercises.exerciseId)!]!,
            timesPerformed: r.read(performed) ?? 0,
            lastDayKey: r.read(lastDay) ?? 0,
          ),
    ];
    summaries.sort((a, b) => b.lastDayKey.compareTo(a.lastDayKey));
    return summaries;
  }

  /// The training days that actually appear in completed history, with the
  /// regime each belongs to and how many times it was logged.
  ///
  /// The filter offers these and nothing else. A picker built from the *active*
  /// regime's sessions would omit every day trained under a discontinued
  /// split, which is precisely the history worth filtering; one built
  /// from all sessions ever created would offer days that return an empty list.
  ///
  /// Grouped by session, so the row count is the number of distinct training
  /// days ever run, a handful per regime, rather than the number of workouts
  /// behind them. Drift is the right cost at that size.
  Future<List<LoggedSession>> loggedSessions() async {
    final logged = db.workouts.id.count();
    final lastDay = db.workouts.dayKey.max();

    final rows = await (db.selectOnly(db.workouts).join([
      innerJoin(db.sessions, db.sessions.id.equalsExp(db.workouts.sessionId)),
      innerJoin(db.regimes, db.regimes.id.equalsExp(db.sessions.regimeId)),
    ])
          ..addColumns([
            db.sessions.id,
            db.sessions.name,
            db.regimes.name,
            logged,
            lastDay,
          ])
          ..where(db.workouts.status.equalsValue(WorkoutStatus.completed) &
              db.workouts.deletedAt.isNull() &
              db.sessions.deletedAt.isNull())
          ..groupBy([db.sessions.id]))
        .get();

    final sessions = [
      for (final r in rows)
        LoggedSession(
          sessionId: r.read(db.sessions.id)!,
          name: r.read(db.sessions.name)!,
          regimeName: r.read(db.regimes.name)!,
          workouts: r.read(logged) ?? 0,
          lastDayKey: r.read(lastDay) ?? 0,
        ),
    ];
    // Most recently trained first: the day being sought is almost always one
    // still in use.
    sessions.sort((a, b) => b.lastDayKey.compareTo(a.lastDayKey));
    return sessions;
  }

  Stream<List<LoggedSession>> watchLoggedSessions() {
    return db.watchQuery(
      [db.workouts, db.sessions, db.regimes],
      loggedSessions,
    );
  }

  /// One page of a single exercise's history, newest first.
  ///
  /// Carries the session each performance belongs to, because "3×8 at 22.5" only
  /// is meaningful only once it is known whether it was Push 1 or Push 2.
  Future<List<ExercisePerformance>> exerciseHistoryPage(
    String exerciseId, {
    int limit = 20,
    HistoryCursor? olderThan,
  }) async {
    // Bounded by the page for the reasons [workoutFeed] gives, and asserted for
    // the same one: the set gather below binds one parameter per row returned.
    assert(limit > 0 && limit <= 5000,
        'this list pages by keyset — $limit rows is a paging bug, not a page');
    // A slot with nothing ticked in it and no reason given is not a
    // performance: it is a row that was on the screen. Left in, it draws a card
    // reading "Nothing logged" with a dash where the weight goes — most easily
    // reached by running one movement twice in a day and only working the
    // second of them. A skipped slot stays, sets or not: the reason is the
    // story, and `pastPerformances` still carries the whole lot for prefill.
    //
    // Filtered in the query rather than over the loaded page, because this list
    // pages by keyset (RULES § Data) — dropping rows afterwards returns a short
    // page, which the feed reads as the end of history.
    final logged = existsQuery(
      db.selectOnly(db.setLogs)
        ..addColumns([db.setLogs.id])
        ..where(
          db.setLogs.workoutExerciseId.equalsExp(db.workoutExercises.id) &
              db.setLogs.isDone.equals(true) &
              db.setLogs.deletedAt.isNull(),
        ),
    );

    var predicate = db.workoutExercises.exerciseId.equals(exerciseId) &
        db.workoutExercises.deletedAt.isNull() &
        db.workouts.deletedAt.isNull() &
        db.workouts.status.equalsValue(WorkoutStatus.completed) &
        (logged |
            db.workoutExercises.skipReason
                .equalsValue(SkipReason.none)
                .not());
    if (olderThan != null) predicate = predicate & _olderThan(olderThan);

    final rows = await (db.select(db.workoutExercises).join([
      innerJoin(
          db.workouts, db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
      leftOuterJoin(
          db.sessions, db.sessions.id.equalsExp(db.workouts.sessionId)),
    ])
          ..where(predicate)
          ..orderBy([
            OrderingTerm(
                expression: db.workouts.startedAt, mode: OrderingMode.desc),
            OrderingTerm(expression: db.workouts.id, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    if (rows.isEmpty) return const [];

    final weIds = [
      for (final r in rows) r.readTable(db.workoutExercises).id,
    ];
    final setRows = await (db.select(db.setLogs)
          ..where((t) => t.workoutExerciseId.isIn(weIds) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
        .get();
    final setsByWe = <String, List<SetLog>>{};
    for (final s in setRows) {
      setsByWe.putIfAbsent(s.workoutExerciseId, () => []).add(s);
    }

    // The catalog row behind these performances, answered as null rather than
    // thrown when it is missing. That is unreachable through the app — a
    // movement is archived, never deleted — and entirely reachable through a
    // restore whose exercise rows were pruned, or a delete arriving from
    // another device. A throw lands inside a paged read, blanking the whole
    // history screen for that movement rather than the one row that has lost
    // its name.
    final exercise = await (db.select(db.exercises)
          ..where((t) => t.id.equals(exerciseId)))
        .getSingleOrNull();
    if (exercise == null) return const [];
    final bodyweight = await bodyweightSeries();

    return [
      for (final r in rows)
        () {
          final we = r.readTable(db.workoutExercises);
          final workout = r.readTable(db.workouts);
          final sets = setsByWe[we.id] ?? const <SetLog>[];
          final score = scorePerformance(
            mode: exercise.loadMode,
            measure: exercise.measureMode,
            bodyweightKg: bodyweightOn(workout.dayKey, bodyweight),
            sets: [
              for (final s in sets)
                if (s.isDone)
                  ScoredSet(
                    type: s.setType,
                    weight: s.weight,
                    reps: s.reps,
                    addedWeight: s.addedWeight,
                  ),
            ],
          );
          return ExercisePerformance(
            workoutId: workout.id,
            dayKey: workout.dayKey,
            startedAt: workout.startedAt,
            sessionId: workout.sessionId,
            sessionName:
                r.readTableOrNull(db.sessions)?.name ?? unplannedSessionName,
            isDeload: workout.isDeload,
            skipReason: we.skipReason,
            sets: sets,
            topSetLoad: score.topSetLoad,
            topSetReps: score.topSetReps,
            best1RM: score.best1RM,
          );
        }(),
    ];
  }

  /// Bodyweight history, used to score bodyweight and BW+ lifts.
  ///
  /// Raw SQL, because the query is unbounded. One row per day ever weighed,
  /// growing for
  /// as long as the app is used, so hydrating whole `BodyweightLog` row objects
  /// reads every column, sync bookkeeping included, to get at two of them.
  /// Whole rows are the most expensive of drift's three read paths (~120ms per
  /// five thousand rows against ~16ms positional), and this is on the path of
  /// every bodyweight and BW+ chart. Covered field by field, against the drift
  /// query it replaced, in `query_conversion_test.dart`.
  Future<List<({int dayKey, double weightKg})>> bodyweightSeries() async {
    final rows = await db.customSelect(
      'SELECT day_key AS day_key, weight_kg AS weight_kg '
      'FROM bodyweight_logs WHERE deleted_at IS NULL ORDER BY day_key',
      readsFrom: {db.bodyweightLogs},
    ).get();
    return [
      for (final r in rows)
        (dayKey: r.read<int>('day_key'), weightKg: r.read<double>('weight_kg')),
    ];
  }

  /// A bodyweight entry is an input to every bodyweight and BW+ score, not a
  /// diary line, so a typo has to be removable rather than permanent.
  Future<void> deleteBodyweight(int dayKey) => _deleteBodyweight(dayKey);

  Future<void> _deleteBodyweight(int dayKey) async {
    await (db.update(db.bodyweightLogs)
          ..where((t) => t.dayKey.equals(dayKey) & t.deletedAt.isNull()))
        .write(
      BodyweightLogsCompanion(
        deletedAt: Value(nowMs()),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// One row per day, upserted in a transaction.
  ///
  /// The look-up and the insert are one act on purpose: a double tap on Save,
  /// or the same day logged from Settings and the bodyweight screen at once,
  /// had both callers find no row and both insert one. Two weights for one day
  /// is not a visible duplicate: the screen displays whichever the query
  /// returns first, and every bodyweight-scored lift on that day reads the
  /// other one half the time.
  ///
  /// Writing a weight never removes one from another day. This method once took
  /// a `replacing` day and moved the entry, which meant that correcting the
  /// date on a sheet opened over today's weight deleted today's weight. A day
  /// is cleared by [deleteBodyweight] and by nothing else, because a lost
  /// weigh-in is silent twice over: nothing on the bodyweight screen says a day
  /// is missing, and the readings either side are simply interpolated across
  /// the hole, quietly rescoring every pull-up and dip in between.
  Future<void> logBodyweight(DateTime date, double kg) =>
      db.transaction(() => _logBodyweight(date, kg));

  Future<void> _logBodyweight(DateTime date, double kg) async {
    final key = dayKeyOf(date);
    final existing = await (db.select(db.bodyweightLogs)
          ..where((t) => t.dayKey.equals(key) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();

    if (existing != null) {
      await (db.update(db.bodyweightLogs)..where((t) => t.id.equals(existing.id)))
          .write(
        BodyweightLogsCompanion(
          weightKg: Value(kg),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
      return;
    }

    await db.into(db.bodyweightLogs).insert(
          BodyweightLogsCompanion.insert(
            id: Value(newId()),
            dayKey: key,
            weightKg: kg,
          ),
        );
  }

  /// One exercise's history scored into chartable points.
  ///
  /// Points carry their session so the chart can draw Push 1 and Push 2 as
  /// separate lines — averaging them would hide the very progression the
  /// per-session split exists to protect.
  ///
  /// Unbounded on purpose. The year picker is built from the points that come
  /// back, so any horizon would silently cut the chart off: a movement trained
  /// more times than the limit allows would lose its early years from the axis
  /// *and* from the list of years that can be asked for, with nothing on screen
  /// to say a horizon existed.
  ///
  /// Two raw statements, both the use of raw SQL and the split being
  /// deliberate. [pastPerformances] hydrates whole `SetLog` row objects, every
  /// column, sync bookkeeping included — and gathers them with
  /// `WHERE workout_exercise_id IN (…)`, one bound parameter per performance.
  /// Thirty years of one movement is 130ms of that before the chart can be
  /// drawn, landing it a beat after the list beneath it. Nearly all of it is
  /// drift's row mapping rather than SQLite: the same
  /// five thousand rows cost 120ms through `readTable`, 90ms through
  /// `TypedResult.read`, and 16ms read positionally off a `QueryRow`, so
  /// the two queries the chart needs ask for the columns it reads, by name, and
  /// map them here.
  ///
  /// The price of raw SQL is that a renamed column compiles and then fails on a
  /// device, so this is covered by tests that assert the shape it returns
  /// rather than only that it returns something.
  Future<List<ProgressPoint>> exerciseProgress(String exerciseId) async {
    // Missing for the reasons [exerciseHistoryPage] gives. A chart with no
    // catalog row behind it has no load mode to read its numbers through, so
    // there is nothing honest to plot.
    final exercise = await (db.select(db.exercises)
          ..where((t) => t.id.equals(exerciseId)))
        .getSingleOrNull();
    if (exercise == null) return const [];

    // The same predicate in both statements: a performance is a live slot on a
    // completed, live workout. Skipped slots stay in for the reason
    // [_performances] gives: sets logged before stopping did occur.
    const live = 'we.deleted_at IS NULL AND wo.deleted_at IS NULL '
        "AND wo.status = 'completed'";

    final slots = await db.customSelect(
      'SELECT we.id AS slot, wo.day_key AS day_key, wo.session_id AS session_id, '
      'wo.is_deload AS is_deload, se.name AS session_name '
      'FROM workout_exercises we '
      'INNER JOIN workouts wo ON wo.id = we.workout_id '
      'LEFT JOIN sessions se ON se.id = wo.session_id '
      'WHERE we.exercise_id = ?1 AND $live '
      // Ordered here rather than sorted afterwards. The chart reads left to
      // right in calendar time, and a backdated workout is not where
      // `started_at` would put it.
      'ORDER BY wo.day_key',
      variables: [Variable.withString(exerciseId)],
      readsFrom: {db.workoutExercises, db.workouts, db.sessions},
    ).get();
    if (slots.isEmpty) return const [];

    // No ORDER BY: scoring a performance is an aggregate over its sets and does
    // not care which order they arrive in, so five thousand rows are not sorted
    // to be folded.
    final setRows = await db.customSelect(
      'SELECT s.workout_exercise_id AS slot, s.set_type AS set_type, '
      's.weight AS weight, s.reps AS reps, s.added_weight AS added_weight '
      'FROM set_logs s '
      'INNER JOIN workout_exercises we ON we.id = s.workout_exercise_id '
      'INNER JOIN workouts wo ON wo.id = we.workout_id '
      'WHERE we.exercise_id = ?1 AND $live '
      'AND s.deleted_at IS NULL AND s.is_done = 1',
      variables: [Variable.withString(exerciseId)],
      readsFrom: {db.setLogs, db.workoutExercises, db.workouts},
    ).get();

    final setsBySlot = <String, List<ScoredSet>>{};
    for (final r in setRows) {
      setsBySlot.putIfAbsent(r.read<String>('slot'), () => []).add(ScoredSet(
            type: SetType.values.byName(r.read<String>('set_type')),
            weight: r.readNullable<double>('weight'),
            reps: r.readNullable<int>('reps'),
            addedWeight: r.readNullable<double>('added_weight'),
          ));
    }

    // Only the two modes that read it pay for it. A barbell press does not need
    // a bodyweight history to be scored, and loading one to hand `null` to
    // every call was a query plus a lookup per performance for nothing.
    final needsBodyweight = exercise.loadMode == LoadMode.bodyweight ||
        exercise.loadMode == LoadMode.bodyweightPlus;
    // Ordered once, then binary-searched per performance — see [orderedByDay].
    final bodyweight = needsBodyweight
        ? orderedByDay(await bodyweightSeries())
        : const <({int dayKey, double weightKg})>[];

    final points = <ProgressPoint>[];
    for (final r in slots) {
      final sets = setsBySlot[r.read<String>('slot')];
      if (sets == null) continue;
      final dayKey = r.read<int>('day_key');

      final score = scorePerformance(
        mode: exercise.loadMode,
        measure: exercise.measureMode,
        bodyweightKg:
            needsBodyweight ? bodyweightOnOrdered(dayKey, bodyweight) : null,
        sets: sets,
      );
      if (score.isEmpty) continue;

      points.add(ProgressPoint(
        dayKey: dayKey,
        sessionId: r.readNullable<String>('session_id'),
        sessionName:
            r.readNullable<String>('session_name') ?? unplannedSessionName,
        isDeload: r.read<bool>('is_deload'),
        topSetLoad: score.topSetLoad,
        topSetReps: score.topSetReps,
        best1RM: score.best1RM,
        volume: score.volume,
      ));
    }

    return points;
  }


  // ── Cycle progress ────────────────────────────────────────────────────

  /// How much stronger the active regime has made you, or null when none is
  /// active.
  Future<RegimeProgress?> activeRegimeProgress() async {
    final regime = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
    if (regime == null) return null;
    return regimeProgress(regime.id);
  }

  /// One regime scored cycle by cycle, for the Workouts card, the regime screen
  /// and the All time cards.
  ///
  /// Three raw statements, for the reasons [exerciseProgress] gives at length:
  /// the window is the whole life of a regime, and hydrating every
  /// `WorkoutExercise` and `SetLog` row to read five columns of each is most of
  /// a second on a long history. The shape is deliberately the one that file
  /// already uses — slots, then their sets gathered by a subquery repeating the
  /// same predicate — rather than a third way of asking the same question.
  ///
  /// Driven from `cycles` rather than from `workouts.regime_id`, which carries
  /// no index: `idx_cycles_regime` finds the regime's cycles and
  /// `idx_workouts_cycle` finds each cycle's workouts, so the read is two index
  /// walks instead of a scan of every workout ever logged.
  /// `query_planning_test.dart` holds that.
  Future<RegimeProgress?> regimeProgress(String regimeId) async {
    final regime = await (db.select(db.regimes)
          ..where((t) => t.id.equals(regimeId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (regime == null) return null;

    // A cycle is real, its workouts are live and completed. The same text in
    // all three statements, so the set query cannot drift from the slot query
    // it is meant to gather for.
    const live = 'c.regime_id = ?1 AND c.deleted_at IS NULL '
        'AND wo.deleted_at IS NULL AND wo.status = \'completed\' '
        'AND we.deleted_at IS NULL';

    final cycleRows = await db.customSelect(
      'SELECT c.id AS cycle_id, c.cycle_index AS cycle_index, '
      'c.is_deload AS is_deload, c.completed_at AS completed_at, '
      'MIN(wo.day_key) AS first_day, MAX(wo.day_key) AS last_day '
      'FROM cycles c '
      'LEFT JOIN workouts wo ON wo.cycle_id = c.id '
      '  AND wo.deleted_at IS NULL AND wo.status = \'completed\' '
      'WHERE c.regime_id = ?1 AND c.deleted_at IS NULL '
      'GROUP BY c.id ORDER BY c.cycle_index',
      variables: [Variable.withString(regimeId)],
      readsFrom: {db.cycles, db.workouts},
    ).get();
    if (cycleRows.isEmpty) {
      return RegimeProgress(
        regimeId: regime.id,
        regimeName: regime.name,
        identityIndex: regime.identityIndex,
        isActive: regime.isActive,
        progress: computeCycleProgress(cycles: const []),
        labels: const {},
      );
    }

    // The dates a cycle covers are the days actually trained in it, not the
    // cycle row's own timestamps: a cycle opens when the one before it closes
    // and stays open over a week off, so `started_at` would name a day nothing
    // happened on.
    final slotRows = await db.customSelect(
      'SELECT we.id AS slot, we.exercise_id AS exercise_id, '
      'wo.cycle_id AS cycle_id, wo.session_id AS session_id, '
      'wo.day_key AS day_key, e.name AS exercise_name, '
      'e.load_mode AS load_mode, e.measure_mode AS measure_mode, '
      'se.name AS session_name '
      'FROM cycles c '
      'INNER JOIN workouts wo ON wo.cycle_id = c.id '
      'INNER JOIN workout_exercises we ON we.workout_id = wo.id '
      'INNER JOIN exercises e ON e.id = we.exercise_id '
      'LEFT JOIN sessions se ON se.id = wo.session_id '
      'WHERE $live',
      variables: [Variable.withString(regimeId)],
      readsFrom: {
        db.cycles,
        db.workouts,
        db.workoutExercises,
        db.exercises,
        db.sessions,
      },
    ).get();

    // No ORDER BY, for the reason [exerciseProgress] gives: scoring a
    // performance is an aggregate over its sets and does not care what order
    // they arrive in.
    final setRows = await db.customSelect(
      'SELECT s.workout_exercise_id AS slot, s.set_type AS set_type, '
      's.weight AS weight, s.reps AS reps, s.added_weight AS added_weight '
      'FROM set_logs s '
      'INNER JOIN workout_exercises we ON we.id = s.workout_exercise_id '
      'INNER JOIN workouts wo ON wo.id = we.workout_id '
      'INNER JOIN cycles c ON c.id = wo.cycle_id '
      'WHERE $live AND s.deleted_at IS NULL AND s.is_done = 1',
      variables: [Variable.withString(regimeId)],
      readsFrom: {db.setLogs, db.workoutExercises, db.workouts, db.cycles},
    ).get();

    final setsBySlot = <String, List<ScoredSet>>{};
    for (final r in setRows) {
      setsBySlot.putIfAbsent(r.read<String>('slot'), () => []).add(ScoredSet(
            type: SetType.values.byName(r.read<String>('set_type')),
            weight: r.readNullable<double>('weight'),
            reps: r.readNullable<int>('reps'),
            addedWeight: r.readNullable<double>('added_weight'),
          ));
    }

    final labels = <LiftId, LiftLabel>{};
    final performances = <String, List<LiftPerformance>>{};
    var needsBodyweight = false;

    for (final r in slotRows) {
      final sets = setsBySlot[r.read<String>('slot')];
      if (sets == null) continue;
      final mode = LoadMode.values.byName(r.read<String>('load_mode'));
      needsBodyweight = needsBodyweight ||
          mode == LoadMode.bodyweight ||
          mode == LoadMode.bodyweightPlus;

      // An unplanned workout has no session, so its lifts key on the exercise
      // alone. That is the honest answer rather than a defect: the split
      // exists because Push 1 and Push 2 are different progressions, and work
      // done outside the programme belongs to neither.
      final lift = LiftId(
        sessionId: r.readNullable<String>('session_id') ?? '',
        exerciseId: r.read<String>('exercise_id'),
      );
      labels.putIfAbsent(
        lift,
        () => LiftLabel(
          exerciseName: r.read<String>('exercise_name'),
          sessionName:
              r.readNullable<String>('session_name') ?? unplannedSessionName,
        ),
      );

      performances.putIfAbsent(r.read<String>('cycle_id'), () => []).add(
            LiftPerformance(
              lift: lift,
              dayKey: r.read<int>('day_key'),
              load: mode,
              measure:
                  MeasureMode.values.byName(r.read<String>('measure_mode')),
              sets: sets,
            ),
          );
    }

    // Only a regime containing a chin-up pays for the weigh-in series, as in
    // [exerciseProgress]. Ordering it once here is what keeps the lookup inside
    // the scoring loop to a binary search.
    final bodyweight = needsBodyweight
        ? orderedByDay(await bodyweightSeries())
        : const <({int dayKey, double weightKg})>[];

    final cycles = [
      for (final r in cycleRows)
        CycleInput(
          cycleId: r.read<String>('cycle_id'),
          index: r.read<int>('cycle_index'),
          isDeload: r.read<bool>('is_deload'),
          isOpen: r.readNullable<int>('completed_at') == null,
          startDayKey: r.readNullable<int>('first_day'),
          endDayKey: r.readNullable<int>('last_day'),
          performances:
              performances[r.read<String>('cycle_id')] ?? const [],
        ),
    ];

    return RegimeProgress(
      regimeId: regime.id,
      regimeName: regime.name,
      identityIndex: regime.identityIndex,
      isActive: regime.isActive,
      progress: computeCycleProgress(
        cycles: cycles,
        bodyweightLog: bodyweight,
      ),
      labels: labels,
    );
  }

  /// [activeRegimeProgress], re-read when the shape of the log changes.
  ///
  /// `set_logs` is deliberately not watched. It is the hot table during a
  /// session — the reason [historyShapeChanges] exists — and this read walks a
  /// whole regime, so watching it would score every cycle ever trained once per
  /// set ticked. The open cycle's partial point therefore moves when a session
  /// is completed rather than while it is being logged, which is also when it
  /// means anything: half a session in, the cycle has not changed its mind.
  Stream<RegimeProgress?> watchActiveRegimeProgress() {
    return db.watchQuery(
      [db.regimes, db.cycles, db.workouts, db.workoutExercises, db.exercises],
      activeRegimeProgress,
    );
  }

  /// [regimeProgress], on the same terms as [watchActiveRegimeProgress].
  Stream<RegimeProgress?> watchRegimeProgress(String regimeId) {
    return db.watchQuery(
      [db.regimes, db.cycles, db.workouts, db.workoutExercises, db.exercises],
      () => regimeProgress(regimeId),
    );
  }

  /// Every day trained between two day keys, for the All time timeline.
  ///
  /// Bounded by the caller, because the timeline shows one year at a time: the
  /// whole log would be a year's strip drawn from thirty years of rows. The
  /// window is found on `idx_workouts_day`, the same index the weekly volume
  /// query is planned off.
  Future<List<TrainedDay>> trainedDaysBetween({
    required int fromDayKey,
    required int toDayKey,
  }) async {
    final rows = await db.customSelect(
      'SELECT wo.day_key AS day_key, wo.regime_id AS regime_id, '
      'wo.is_deload AS is_deload, c.cycle_index AS cycle_index '
      'FROM workouts wo '
      'LEFT JOIN cycles c ON c.id = wo.cycle_id '
      'WHERE wo.day_key >= ?1 AND wo.day_key <= ?2 '
      'AND wo.deleted_at IS NULL AND wo.status = \'completed\' '
      'ORDER BY wo.day_key',
      variables: [
        Variable.withInt(fromDayKey),
        Variable.withInt(toDayKey),
      ],
      readsFrom: {db.workouts, db.cycles},
    ).get();

    return [
      for (final r in rows)
        TrainedDay(
          dayKey: r.read<int>('day_key'),
          regimeId: r.read<String>('regime_id'),
          isDeload: r.read<bool>('is_deload'),
          cycleIndex: r.readNullable<int>('cycle_index'),
        ),
    ];
  }

  /// [trainedDaysBetween], re-read when a workout is written.
  Stream<List<TrainedDay>> watchTrainedDaysBetween({
    required int fromDayKey,
    required int toDayKey,
  }) {
    return db.watchQuery(
      [db.workouts, db.cycles],
      () => trainedDaysBetween(fromDayKey: fromDayKey, toDayKey: toDayKey),
    );
  }

  /// One regime as the All time screen lists it: its name, its mark, and
  /// whether it is the one being trained.
  ///
  /// Deleted regimes are absent, because their cycles are tombstoned with them
  /// and a card drawn for one would have nothing in it. That was decided rather
  /// than overlooked. Their *workouts* remain, so the timeline can still hold a
  /// week nothing here can name — see how the strip draws one.
  Future<List<RegimeMark>> liveRegimes() async {
    final rows = await (db.select(db.regimes)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    return [
      for (final r in rows)
        RegimeMark(
          id: r.id,
          name: r.name,
          identityIndex: r.identityIndex,
          isActive: r.isActive,
        ),
    ];
  }

  /// [liveRegimes], re-read when a programme is created, renamed or deleted.
  Stream<List<RegimeMark>> watchLiveRegimes() =>
      db.watchQuery([db.regimes], liveRegimes);

  /// Every lift the programme holds: each exercise in each session, with the
  /// names a screen prints, in programme order.
  ///
  /// One row per (session, exercise) pair rather than per exercise, because
  /// that is what a lift is (CLAUDE.md rule 1). It is what the first cycle of a
  /// regime is measured out of — `8 of 15 lifts recorded` — and the denominator
  /// the card prints.
  Future<List<({LiftId lift, LiftLabel label})>> regimeLifts(
    String regimeId,
  ) async {
    final rows = await db.customSelect(
      'SELECT se.id AS session_id, se.name AS session_name, '
      'e.id AS exercise_id, e.name AS exercise_name '
      'FROM sessions se '
      'INNER JOIN session_exercises sx ON sx.session_id = se.id '
      'INNER JOIN exercises e ON e.id = sx.exercise_id '
      'WHERE se.regime_id = ?1 AND se.deleted_at IS NULL '
      'AND sx.deleted_at IS NULL '
      'ORDER BY se.order_index, sx.order_index',
      variables: [Variable.withString(regimeId)],
      readsFrom: {db.sessions, db.sessionExercises, db.exercises},
    ).get();

    return [
      for (final r in rows)
        (
          lift: LiftId(
            sessionId: r.read<String>('session_id'),
            exerciseId: r.read<String>('exercise_id'),
          ),
          label: LiftLabel(
            exerciseName: r.read<String>('exercise_name'),
            sessionName: r.read<String>('session_name'),
          ),
        ),
    ];
  }

  /// [regimeLifts], re-read when the programme is edited.
  Stream<List<({LiftId lift, LiftLabel label})>> watchRegimeLifts(
    String regimeId,
  ) {
    return db.watchQuery(
      [db.sessions, db.sessionExercises, db.exercises],
      () => regimeLifts(regimeId),
    );
  }

  // ── Starting and running a workout ────────────────────────────────────

  /// An unfinished workout, if one is open. Closing the app mid-session must
  /// never lose the sets already logged.
  Future<Workout?> openWorkout() async {
    return (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.inProgress) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Creates a workout from a session template.
  ///
  /// Set rows are pre-created to mirror *last time in this session* — including
  /// its warmup structure — rather than a flat "3 sets". Repeating last week's
  /// shape is the behaviour being carried over from the Notion tables.
  /// [at] backdates the workout, for recording a session that was not logged on
  /// the day. It never returns a running workout, because a session currently
  /// being trained is not the one being backfilled.
  Future<String> startWorkout({
    required String regimeId,
    required String sessionId,
    DateTime? at,
  }) async {
    // A double tap on "Start" — or a screen that hasn't rebuilt yet — must not
    // open a second parallel log for the same session. Hand back the running
    // one instead; the sets already in it are the ones being asked for.
    final running = await openWorkout();
    if (running != null) {
      // The same session again is the double tap: hand back the running log,
      // because the sets already in it are the ones being asked for.
      if (at == null && running.sessionId == sessionId) return running.id;
      // Anything else would be a second workout open at once. `openWorkout`
      // returns the newest by startedAt, so the older one is hidden behind it
      // and becomes unreachable — in progress forever, listed nowhere. Today
      // hides Start behind the resume card, but this is the invariant and it
      // belongs here rather than in whichever screen remembers to check.
      throw StateError('Finish the session in progress first');
    }

    final regime = await (db.select(db.regimes)
          ..where((t) => t.id.equals(regimeId)))
        .getSingleOrNull();
    // Deleted between the tap and the write. A `StateError` here rather than the
    // bare one `getSingle` throws, because Today already catches this type by
    // name and puts its message on a toast.
    if (regime == null) {
      throw StateError('That programme has been deleted');
    }
    // A backdated session belongs to the cycle that was open on its date, not
    // to the one open now. When the date predates every cycle — backfilling
    // from before this regime existed — it belongs to no cycle at all rather
    // than being forced into the current one.
    final cycle = at == null
        ? await ensureOpenCycle(regimeId)
        : await cycleCovering(regimeId, at);
    final slots = await (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    final unit = await weightUnit();
    // Snapshotted onto every row this writes — see `WorkoutExercises.muscle`.
    // One query for the whole session rather than one per slot: this runs on
    // the tap that opens the log, where six round trips to the database isolate
    // are six frames.
    final muscles = await _musclesOf([for (final s in slots) s.exerciseId]);
    // The catalog's bars, resolved once for the whole session. The day's own
    // override wins over them per slot, just below.
    final catalogBars =
        await _catalogBarsOf([for (final s in slots) s.exerciseId]);
    final workoutId = newId();
    // A backdated session keeps the current clock time: the date is what was
    // forgotten, the hour is unknowable and unimportant.
    final now = at == null
        ? DateTime.now()
        : DateTime(at.year, at.month, at.day, DateTime.now().hour,
            DateTime.now().minute);

    // Prefill is resolved before the transaction so the write stays short.
    //
    // Resolved together rather than sequentially: each slot is its own chain
    // of queries across the database isolate's port, and awaiting them in
    // series made the tap cost the sum of six round trips instead of the
    // longest one. The same reasoning `workoutPrefillProvider` already applies
    // on the other side of the navigation.
    final plans = await Future.wait([
      for (final slot in slots)
        () async {
          final past = await pastPerformances(
            slot.exerciseId,
            limit: 30,
            sessionId: sessionId,
          );
          return (
            slot: slot,
            prefill: resolvePrefill(
              candidates: past,
              sessionId: sessionId,
              targetIsDeload: cycle?.isDeload ?? false,
              deloadSetDelta: slot.deloadSetDelta ?? regime.deloadSetDelta,
              deloadWeightPct: slot.deloadWeightPct ?? regime.deloadWeightPct,
              unit: unit,
            ),
          );
        }(),
    ]);

    // Handed forward to the screen this tap is about to open, which needs the
    // same answer for its ghosts — see [_prefillOnOpen].
    _prefillOnOpen.clear();
    for (final plan in plans) {
      _prefillOnOpen[_prefillKey(workoutId, plan.slot.exerciseId)] =
          plan.prefill;
    }

    await db.transaction(() async {
      await db.into(db.workouts).insert(
            WorkoutsCompanion.insert(
              id: Value(workoutId),
              regimeId: regimeId,
              sessionId: Value(sessionId),
              cycleId: Value(cycle?.id),
              dayKey: dayKeyOf(now),
              // Explicit rather than the column default, so a backdated
              // session sorts into history where it belongs.
              startedAt: Value(now.millisecondsSinceEpoch),
              // All three from the one `DateTime`, which is what makes them
              // agree — see `Workouts.tzOffsetMinutes`.
              tzOffsetMinutes: tzOffsetOf(now),
              isDeload: Value(cycle?.isDeload ?? false),
              status: const Value(WorkoutStatus.inProgress),
            ),
          );

      for (var i = 0; i < plans.length; i++) {
        final slot = plans[i].slot;
        final prefill = plans[i].prefill;

        var targetSets = slot.targetSets;
        if (cycle?.isDeload ?? false) {
          final delta = slot.deloadSetDelta ?? regime.deloadSetDelta;
          targetSets = (targetSets + delta).clamp(1, 99);
        }

        final weId = newId();
        await db.into(db.workoutExercises).insert(
              WorkoutExercisesCompanion.insert(
                id: Value(weId),
                workoutId: workoutId,
                exerciseId: slot.exerciseId,
                orderIndex: i,
                targetSets: Value(targetSets),
                muscle: Value(muscles[slot.exerciseId]),
                // What is actually on the bar today, snapshotted like the
                // muscle beside it: the day's override if it has one, the
                // catalog otherwise. Changing either later leaves this row —
                // and its plate diagram — exactly as it was.
                barKind: Value(
                  slot.barKind ?? catalogBars[slot.exerciseId] ?? BarKind.none,
                ),
              ),
            );

        // Mirror last time's set structure when there is one; otherwise fall
        // back to plain working sets from the template.
        final shape = prefill.hasSuggestion
            ? [for (final s in prefill.sets) (type: s.type, isLeg: s.isLeg)]
            : [
                for (var k = 0; k < targetSets; k++)
                  (type: SetType.working, isLeg: false),
              ];

        // The template's set count is a floor, not a suggestion. Last time's
        // shape is only the sets that were actually *ticked* — finish a session
        // early, or leave a row filled but unticked, and it is thrown away on
        // the way out. Mirroring that number blindly meant one short session
        // permanently shrank the exercise: three sets logged as one, and the
        // week after opened with a single row and no sign the other two had
        // ever been programmed.
        final working = shape
            .where((s) => s.type == SetType.working && !s.isLeg)
            .length;
        for (var pad = working; pad < targetSets; pad++) {
          shape.add((type: SetType.working, isLeg: false));
        }

        // Drop legs are attached to the set above them as they are written.
        // Mirroring the *types* alone brings last week's drop set back as a
        // row of unrelated `D`s — each its own group, each with its own capsule
        // and `+`, none of them a leg of anything.
        String? head;
        for (var k = 0; k < shape.length; k++) {
          final id = newId();
          final isLeg = shape[k].isLeg && head != null;
          await db.into(db.setLogs).insert(
                SetLogsCompanion.insert(
                  id: Value(id),
                  workoutExerciseId: weId,
                  setIndex: k,
                  setType: Value(shape[k].type),
                  parentSetId: Value(isLeg ? head : null),
                ),
              );
          if (!isLeg) head = id;
        }
      }
    });

    return workoutId;
  }

  /// The unit weights are shown in, read straight from settings.
  ///
  /// Only deload scaling needs it down here: a suggestion has to land on a
  /// weight the gym actually has, and which weights those are depends on
  /// whether the plates are kilos or pounds.
  Future<WeightUnit> weightUnit() async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals('units')))
        .getSingleOrNull();
    return WeightUnitX.parse(row?.value);
  }

  /// The rest target for one exercise in one session, in seconds.
  ///
  /// Two readings, in order: the slot's own number if it has been given one,
  /// otherwise the default from Settings. Nothing else — see
  /// [rest.dart](../../domain/rest.dart) for why there is no third reading off
  /// the last rest actually taken on the movement.
  Future<int> restTargetFor({
    required String exerciseId,
    required String? sessionId,
  }) async {
    if (sessionId != null) {
      final slot = await _slotFor(sessionId: sessionId, exerciseId: exerciseId);
      final target = slot?.restSeconds;
      // Clamped rather than trusted: the column accepts 1–3600 so that a
      // restore or a merge can always be written back, and this is the one
      // place that turns a stored number into a timer.
      if (target != null) return clampRest(target);
    }
    return restDefaultSeconds();
  }

  /// The rest an exercise with no number of its own opens on.
  ///
  /// The between-exercises number is not here: nothing below the widget layer
  /// reads it, and `restPrefsProvider` is its one reader.
  Future<int> restDefaultSeconds() async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(restDefaultKey)))
        .getSingleOrNull();
    return parseRestSeconds(row?.value);
  }

  /// Remembers a rest target against the session slot, so next week opens with
  /// the configured value rather than a flat 120 seconds.
  ///
  /// Returns false when there is no slot to write it to — an exercise added
  /// mid-session isn't in the template, and the update would match no rows and
  /// return without complaint, leaving the timer back at 120s next week with
  /// no indication why. The caller says so instead.
  Future<bool> setRestTarget({
    required String exerciseId,
    required String? sessionId,
    required int seconds,
  }) async {
    if (sessionId == null) return false;
    final rows = await (db.update(db.sessionExercises)
          ..where((t) =>
              t.sessionId.equals(sessionId) &
              t.exerciseId.equals(exerciseId) &
              t.deletedAt.isNull()))
        .write(
      SessionExercisesCompanion(
        restSeconds: Value(seconds),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    return rows > 0;
  }

  /// How many logged sets an exercise carries.
  ///
  /// Used to say what changing a catalog row costs before it is changed: load
  /// mode is an interpretation, so flipping it re-reads every set ever logged
  /// for that movement.
  Future<int> loggedSetCount(String exerciseId) async {
    final count = db.setLogs.id.count();
    final row = await (db.selectOnly(db.setLogs).join([
      innerJoin(db.workoutExercises,
          db.workoutExercises.id.equalsExp(db.setLogs.workoutExerciseId)),
      innerJoin(
          db.workouts, db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
    ])
          ..addColumns([count])
          ..where(db.workoutExercises.exerciseId.equals(exerciseId) &
              db.setLogs.isDone.equals(true) &
              db.setLogs.deletedAt.isNull() &
              db.workoutExercises.deletedAt.isNull() &
              db.workouts.deletedAt.isNull()))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// Who a workout belongs to, looked up by id rather than filtered out of the
  /// active regime's sessions.
  ///
  /// Start a workout and switch regimes, and the session is still real but no
  /// longer in the active regime's list — searching that list would leave the
  /// resume card reading "Workout". Finishing it advances *its* regime's cycle,
  /// not the one on screen, so the card has to be able to say which.
  Future<({String? sessionName, String regimeId, String? regimeName})?>
      workoutOwner(String workoutId) async {
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId)))
        .getSingleOrNull();
    if (workout == null) return null;

    final session = workout.sessionId == null
        ? null
        : await (db.select(db.sessions)
              ..where((t) => t.id.equals(workout.sessionId!)))
            .getSingleOrNull();
    final regime = await (db.select(db.regimes)
          ..where((t) => t.id.equals(workout.regimeId)))
        .getSingleOrNull();

    return (
      sessionName: session?.name,
      regimeId: workout.regimeId,
      regimeName: regime?.name,
    );
  }

  /// Null once the workout is gone — deleted from history, or discarded from
  /// the log screen. Screens showing it can then say so instead of holding a
  /// stale copy of a day that no longer exists.
  Future<WorkoutDetail?> workoutDetail(String workoutId) async {
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (workout == null) return null;

    final session = workout.sessionId == null
        ? null
        : await (db.select(db.sessions)..where((t) => t.id.equals(workout.sessionId!)))
            .getSingleOrNull();

    final rows = await (db.select(db.workoutExercises).join([
      innerJoin(db.exercises, db.exercises.id.equalsExp(db.workoutExercises.exerciseId)),
    ])
          ..where(db.workoutExercises.workoutId.equals(workoutId) &
              db.workoutExercises.deletedAt.isNull())
          ..orderBy([OrderingTerm(expression: db.workoutExercises.orderIndex)]))
        .get();

    final weIds = rows.map((r) => r.readTable(db.workoutExercises).id).toList();
    final sets = weIds.isEmpty
        ? <SetLog>[]
        : await (db.select(db.setLogs)
              ..where((t) => t.workoutExerciseId.isIn(weIds) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
            .get();

    final byWe = <String, List<SetLog>>{};
    for (final s in sets) {
      byWe.putIfAbsent(s.workoutExerciseId, () => []).add(s);
    }

    return WorkoutDetail(
      workout: workout,
      session: session,
      entries: [
        for (final r in rows)
          ExerciseEntry(
            workoutExercise: r.readTable(db.workoutExercises),
            exercise: r.readTable(db.exercises),
            sets: byWe[r.readTable(db.workoutExercises).id] ?? const [],
          ),
      ],
    );
  }

  Stream<WorkoutDetail?> watchWorkoutDetail(String workoutId) {
    // Every table [workoutDetail] reads. The catalog and the day are read
    // live for whatever is not snapshotted (the exercise's name, load mode
    // and measure mode, and the day's name), so an edit made with the log
    // open has to redraw it rather than wait for the next set written.
    return db.watchQuery(
      [
        db.workouts,
        db.workoutExercises,
        db.setLogs,
        db.exercises,
        db.sessions,
      ],
      () => workoutDetail(workoutId),
    );
  }

  Stream<List<ExerciseHistorySummary>> watchExercisesWithHistory() {
    return db.watchQuery(
      [db.workouts, db.workoutExercises, db.exercises],
      exercisesWithHistory,
    );
  }

  /// Emits when the *shape* of history changes — a workout deleted or
  /// backdated, an exercise added, swapped or skipped — but not when a set is
  /// written.
  ///
  /// Deliberately narrower than [historyChanges]: `set_logs` is the hot table
  /// during a session, and anything that re-resolves history on it would run
  /// once per keystroke.
  Stream<void> historyShapeChanges() {
    return db.tableUpdates(
      TableUpdateQuery.onAllTables([db.workouts, db.workoutExercises]),
    );
  }

  /// Emits whenever logged history changes. Paged views reload their loaded
  /// window on this instead of holding a watched query per page.
  Stream<void> historyChanges() {
    return db.tableUpdates(
      TableUpdateQuery.onAllTables(
        [db.workouts, db.workoutExercises, db.setLogs],
      ),
    );
  }

  Stream<List<ProgressPoint>> watchExerciseProgress(String exerciseId) {
    return db.watchQuery(
      [db.workouts, db.workoutExercises, db.setLogs, db.bodyweightLogs],
      () => exerciseProgress(exerciseId),
    );
  }

  Stream<CycleStatus?> watchCycleStatus(String regimeId) {
    return db.watchQuery(
      [db.workouts, db.cycles, db.sessions, db.regimes],
      () => cycleStatus(regimeId),
    );
  }

  // ── Mutations during a workout ────────────────────────────────────────

  Future<void> updateSet(
    String setId, {
    Value<double?> weight = const Value.absent(),
    Value<int?> reps = const Value.absent(),
    Value<int?> partialReps = const Value.absent(),
    Value<double?> addedWeight = const Value.absent(),
    Value<SetType> setType = const Value.absent(),
    Value<bool> isDone = const Value.absent(),
    Value<int?> restSeconds = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String?> parentSetId = const Value.absent(),
  }) async {
    await (db.update(db.setLogs)..where((t) => t.id.equals(setId))).write(
      SetLogsCompanion(
        weight: weight,
        reps: reps,
        partialReps: partialReps,
        addedWeight: addedWeight,
        setType: setType,
        parentSetId: parentSetId,
        isDone: isDone,
        restSeconds: restSeconds,
        note: note,
        // Cleared on an untick as deliberately as it is stamped on a tick: a
        // set that is not done has no moment it was done at, and a stamp left
        // behind would leave `restTargetFor` reading a rest off a set that had
        // been taken back.
        completedAt: !isDone.present
            ? const Value.absent()
            : isDone.value
                ? Value(nowMs())
                : const Value(null),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// In a transaction, because the read that picks the index and the insert
  /// that takes it have to be one act: two taps on `+` inside a frame of each
  /// other both read the same highest index and both claimed it.
  Future<String> addSet(String workoutExerciseId, {SetType type = SetType.working}) async {
    final id = newId();
    await db.transaction(() async {
      final existing = await (db.select(db.setLogs)
            ..where((t) => t.workoutExerciseId.equals(workoutExerciseId) & t.deletedAt.isNull()))
          .get();
      // One past the highest index, not the number of rows. Deletes are
      // tombstones and nothing renumbers after them, so counting live rows handed
      // the new set an index another row still held: delete a drop group, press
      // `+`, and the new set landed in the middle of the table on top of an
      // existing one, in an order the database could break either way.
      final next = nextPosition(existing.map((s) => s.setIndex));
      await db.into(db.setLogs).insert(
            SetLogsCompanion.insert(
              id: Value(id),
              workoutExerciseId: workoutExerciseId,
              setIndex: next,
              setType: Value(type),
            ),
          );
    });
    return id;
  }

  /// Inserts a set directly after [afterSetId] rather than at the end.
  ///
  /// A drop set's `+` adds a leg to *its* group. [addSet] appends to the
  /// exercise, so pressing the `+` on the first group put the new row in the
  /// last one — visibly the wrong place, and silently the wrong set.
  Future<String> addSetAfter(
    String workoutExerciseId, {
    required String afterSetId,
    SetType type = SetType.working,
    String? parentSetId,
  }) async {
    final id = newId();
    await db.transaction(() async {
      final sets =
          await (db.select(db.setLogs)
                ..where(
                  (t) =>
                      t.workoutExerciseId.equals(workoutExerciseId) &
                      t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
              .get();

      final at = sets.indexWhere((s) => s.id == afterSetId);
      if (at < 0) return;

      // Every number here is a `setIndex`, never a position in [sets]. The two
      // are only the same while the exercise has never had a set deleted:
      // deletes are tombstones and nothing renumbers after them, so the live
      // rows of an exercise whose first set has been deleted are 1, 2, 3 held
      // at positions 0, 1, 2. Numbering from the position gave the new row an
      // index the row above it already held — two live rows on one index, in an
      // order the database could break either way, which is the same failure
      // [addSet] counts past the highest index to avoid.
      final afterIndex = sets[at].setIndex;

      // Renumber from the back so no two rows hold the same index mid-flight.
      for (var i = sets.length - 1; i > at; i--) {
        await (db.update(db.setLogs)..where((t) => t.id.equals(sets[i].id)))
            .write(
              SetLogsCompanion(
                setIndex: Value(sets[i].setIndex + 1),
                deviceId: Value(currentDeviceId),
                updatedAt: Value(nowMs()),
                dirty: const Value(true),
              ),
            );
      }

      await db
          .into(db.setLogs)
          .insert(
            SetLogsCompanion.insert(
              id: Value(id),
              workoutExerciseId: workoutExerciseId,
              setIndex: afterIndex + 1,
              setType: Value(type),
              parentSetId: Value(parentSetId),
            ),
          );
    });
    return id;
  }

  /// Adds a leg to the end of the drop group headed by [headSetId].
  ///
  /// Not `addSetAfter(lastLeg)`: the caller's idea of the last leg comes from
  /// the frame it was built in, so two quick taps both insert after the same
  /// row and the legs come out in the order they were not added. The end of
  /// the group is found inside the transaction instead.
  Future<String> addDropLeg(
    String workoutExerciseId, {
    required String headSetId,
  }) {
    // The read and the insert are one act. Finding the tail outside the
    // transaction left the same window the caller's stale frame did: two taps
    // inside a frame of each other both read the group before either had added
    // to it, and the legs came out in the order they were not added.
    return db.transaction(() async {
      final sets =
          await (db.select(db.setLogs)
                ..where(
                  (t) =>
                      t.workoutExerciseId.equals(workoutExerciseId) &
                      t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
              .get();

      final head = sets.indexWhere((s) => s.id == headSetId);
      if (head < 0) return '';

      // The end of this group, by parentage — not "the next row that happens to
      // be a drop", which belonged to whichever set came before it.
      var tail = head;
      while (tail + 1 < sets.length && sets[tail + 1].parentSetId == headSetId) {
        tail++;
      }

      return addSetAfter(
        workoutExerciseId,
        afterSetId: sets[tail].id,
        type: SetType.drop,
        parentSetId: headSetId,
      );
    });
  }

  /// Changes a set's type, keeping the drop group around it consistent.
  ///
  /// Writing the type and nothing else leaves two shapes the table cannot
  /// draw: a drop set with no leg to have dropped into, and legs still nested
  /// under a head that is not a drop at all.
  ///
  /// One transaction, because a conversion is several writes that only make
  /// sense together. Interrupted halfway, it leaves the set as it was.
  Future<void> setSetType(String setId, SetType type) =>
      db.transaction(() => _setSetType(setId, type));

  Future<void> _setSetType(String setId, SetType type) async {
    final set = await (db.select(db.setLogs)
          ..where((t) => t.id.equals(setId)))
        .getSingleOrNull();
    if (set == null || set.setType == type) return;

    await updateSet(setId, setType: Value(type));

    // A leg that is no longer a drop leaves its group, keeping its numbers.
    if (set.parentSetId != null) {
      if (type != SetType.drop) {
        await updateSet(setId, parentSetId: const Value(null));
      }
      return;
    }

    // A drop set is a set within which weight was reduced, so it requires
    // somewhere to
    // record the drop.
    if (type == SetType.drop) {
      await addDropLeg(set.workoutExerciseId, headSetId: setId);
      return;
    }

    if (set.setType == SetType.drop) {
      final legs =
          await (db.select(db.setLogs)..where(
                (t) => t.parentSetId.equals(setId) & t.deletedAt.isNull(),
              ))
              .get();

      // An empty leg goes with the drop that created it. Promoting them all
      // turned one set into four: the legs a conversion adds were not chosen
      // by the user, and reversing the conversion must remove them. A leg with
      // data logged in it is a performed set, and that one is
      // promoted rather than deleted, whatever the head becomes.
      final empty = [
        for (final leg in legs)
          if (leg.weight == null &&
              leg.addedWeight == null &&
              leg.reps == null &&
              !leg.isDone)
            leg.id,
      ];
      await deleteSets(empty);

      for (final leg in legs.where((l) => !empty.contains(l.id))) {
        await updateSet(
          leg.id,
          parentSetId: const Value(null),
          setType: const Value(SetType.working),
        );
      }
    }
  }

  Future<void> deleteSet(String setId) => deleteSets([setId]);

  /// Tombstones several sets as one act.
  ///
  /// Takes the whole group when the group is what was deleted — but it does
  /// not work that out for itself. The legs of a drop set are continuations of
  /// their head and mean nothing without it, so the row that owns the gesture
  /// hands over every id in the group when the head is the one swiped, and
  /// only its own when a leg is. This method writes down what it is given;
  /// see `_deleteIds` in the log screen for the rule.
  Future<void> deleteSets(List<String> setIds) async {
    if (setIds.isEmpty) return;
    await (db.update(db.setLogs)..where((t) => t.id.isIn(setIds))).write(
      SetLogsCompanion(
        deletedAt: Value(nowMs()),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Reorders exercises within a workout only — the session template is
  /// untouched, so rearranging today never rewrites what was logged in
  /// March.
  ///
  /// Two passes through free ground — see [renumber]. The log screen is a
  /// `PageView` keyed on this order, so a duplicate position determines the
  /// page
  /// swipe to being whichever way SQLite broke the tie;
  /// `idx_workout_exercises_position_live` refuses it, and a one-pass renumber
  /// walks straight into that refusal.
  Future<void> reorderWorkoutExercises(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    await db.transaction(() async {
      final live = await (db.select(db.workoutExercises)
            ..where((t) => t.id.isIn(orderedIds) & t.deletedAt.isNull()))
          .get();
      if (live.isEmpty) return;
      final scope = await (db.select(db.workoutExercises)
            ..where((t) =>
                t.workoutId.equals(live.first.workoutId) &
                t.deletedAt.isNull()))
          .get();

      await renumber(
        orderedIds,
        scope: {for (final e in scope) e.id: e.orderIndex},
        write: (id, orderIndex) async {
          await (db.update(db.workoutExercises)..where((t) => t.id.equals(id)))
              .write(
            WorkoutExercisesCompanion(
              orderIndex: Value(orderIndex),
              deviceId: Value(currentDeviceId),
              updatedAt: Value(nowMs()),
              dirty: const Value(true),
            ),
          );
        },
      );
    });
  }

  Future<void> setSkipReason(String workoutExerciseId, SkipReason reason) async {
    await (db.update(db.workoutExercises)..where((t) => t.id.equals(workoutExerciseId)))
        .write(
      WorkoutExercisesCompanion(
        skipReason: Value(reason),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// This exercise, on this day. The third and narrowest of the three notes.
  ///
  /// `exercises.notes` is the permanent cue and `set_logs.note` is one set;
  /// this one is "shoulder felt off on incline today" and belongs to the
  /// workout's snapshot row. Writing it must never reach the catalog or the
  /// template — the row is a copy for exactly this reason.
  Future<void> setWorkoutExerciseNotes(
    String workoutExerciseId,
    String? notes,
  ) async {
    final trimmed = notes?.trim();
    await (db.update(db.workoutExercises)
          ..where((t) => t.id.equals(workoutExerciseId)))
        .write(
      WorkoutExercisesCompanion(
        notes: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Last time's numbers for one exercise in the context of one workout.
  ///
  /// The same resolution `startWorkout` does, available afterwards: an exercise
  /// added at 19:40 must know the history it would have known at 19:00.
  Future<PrefillResult> prefillForWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    // Already resolved by the tap that opened this workout, if this is the log
    // screen's first ask. Taken rather than read, so everything after it — an
    // exercise added at 19:40, a past workout deleted from History mid-session
    // — resolves against the database as it always did.
    final ready = _prefillOnOpen.remove(_prefillKey(workoutId, exerciseId));
    if (ready != null) return ready;

    final unit = await weightUnit();
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId)))
        .getSingleOrNull();
    if (workout == null) return const PrefillResult.empty();

    final regime = await (db.select(db.regimes)
          ..where((t) => t.id.equals(workout.regimeId)))
        .getSingleOrNull();

    // The slot's own deload override, exactly as `startWorkout` reads it.
    // Taking the regime's figures regardless would deload the same exercise one
    // way when the session opened and another way when it was added ten minutes
    // later.
    final sessionId = workout.sessionId;
    final slot = sessionId == null
        ? null
        : await (db.select(db.sessionExercises)
              ..where((t) =>
                  t.sessionId.equals(sessionId) &
                  t.exerciseId.equals(exerciseId) &
                  t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();

    final past = await pastPerformances(
      exerciseId,
      excludeWorkoutId: workoutId,
      sessionId: workout.sessionId,
    );

    return resolvePrefill(
      candidates: past,
      sessionId: workout.sessionId,
      targetIsDeload: workout.isDeload,
      deloadSetDelta:
          slot?.deloadSetDelta ?? regime?.deloadSetDelta ?? -1,
      deloadWeightPct:
          slot?.deloadWeightPct ?? regime?.deloadWeightPct ?? 80,
      unit: unit,
    );
  }

  /// The set rows a newly added exercise should start with.
  ///
  /// Mirrors last time's shape exactly as `startWorkout` does, so an exercise
  /// added mid-session doesn't arrive with a flat three sets — and, in a deload
  /// week, doesn't arrive with a full-weight structure in a light week.
  Future<List<SetType>> _shapeFor({
    required String workoutId,
    required String exerciseId,
    required int targetSets,
  }) async {
    final prefill = await prefillForWorkout(
      workoutId: workoutId,
      exerciseId: exerciseId,
    );
    return prefill.hasSuggestion
        ? prefill.sets.map((s) => s.type).toList()
        : List.filled(targetSets, SetType.working);
  }

  Future<String> addExerciseToWorkout(
    String workoutId,
    String exerciseId, {
    int targetSets = 3,
  }) async {
    final shape = await _shapeFor(
      workoutId: workoutId,
      exerciseId: exerciseId,
      targetSets: targetSets,
    );
    final muscle = (await _musclesOf([exerciseId]))[exerciseId];
    final bar = await _barForWorkout(
      workoutId: workoutId,
      exerciseId: exerciseId,
    );

    final id = newId();
    await db.transaction(() async {
      // One past the highest position, not the number of live rows — the same
      // rule `addSet` follows, and for the same reason. A removed exercise is
      // tombstoned and nothing renumbers behind it, so counting live rows put
      // the new movement on a position another one still held, and the log's
      // page order became whichever way SQLite felt like breaking the tie.
      final existing = await (db.select(db.workoutExercises)
            ..where((t) => t.workoutId.equals(workoutId) & t.deletedAt.isNull()))
          .get();
      final next = nextPosition(existing.map((e) => e.orderIndex));
      await db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              id: Value(id),
              workoutId: workoutId,
              exerciseId: exerciseId,
              orderIndex: next,
              targetSets: Value(targetSets),
              muscle: Value(muscle),
              barKind: Value(bar),
            ),
          );
      for (var k = 0; k < shape.length; k++) {
        await db.into(db.setLogs).insert(
              SetLogsCompanion.insert(
                id: Value(newId()),
                workoutExerciseId: id,
                setIndex: k,
                setType: Value(shape[k]),
              ),
            );
      }
    });
    return id;
  }

  /// Substitutes one exercise for another in place.
  ///
  /// A swap is a substitution, not a delete plus an append: the replacement
  /// takes the replaced slot's position and target, so the page currently open
  /// does not move mid-session. Performing this as
  /// remove-then-add would send the replacement to the end of the workout.
  Future<String> replaceExerciseInWorkout(
    String workoutExerciseId,
    String newExerciseId,
  ) async {
    final old = await (db.select(db.workoutExercises)
          ..where((t) => t.id.equals(workoutExerciseId)))
        .getSingleOrNull();
    // Removed from the workout while its own swap sheet was open. Nothing to
    // substitute for, and the empty id says so rather than throwing at a
    // gesture handler — where the visible symptom is a button that does nothing.
    if (old == null) return '';

    final shape = await _shapeFor(
      workoutId: old.workoutId,
      exerciseId: newExerciseId,
      targetSets: old.targetSets,
    );
    // The replacement's muscle, not the row it displaces: a swap from a press
    // to a row is a different muscle trained, and the slot it inherits is a
    // position rather than a category.
    final muscle = (await _musclesOf([newExerciseId]))[newExerciseId];
    // And the replacement's bar, for the same reason: the slot it inherits is
    // a position, not an answer about how the new movement is loaded.
    final bar = await _barForWorkout(
      workoutId: old.workoutId,
      exerciseId: newExerciseId,
    );

    final id = newId();
    final stamp = nowMs();
    await db.transaction(() async {
      // The displaced slot's sets go with it. Two sets logged into a movement
      // subsequently swapped away do not belong to the new movement, and
      // leaving them live
      // under a tombstoned slot is the whole of the cascade rule — the sets
      // stay `dirty` and unreachable, and `doneSetCount` stops seeing them,
      // which is what lets the launch sweep call the whole session empty.
      await _tombstoneSetsOf([workoutExerciseId], stamp);
      await (db.update(db.workoutExercises)
            ..where((t) => t.id.equals(workoutExerciseId)))
          .write(
        WorkoutExercisesCompanion(
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );

      await db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              id: Value(id),
              workoutId: old.workoutId,
              exerciseId: newExerciseId,
              orderIndex: old.orderIndex,
              targetSets: Value(old.targetSets),
              muscle: Value(muscle),
              barKind: Value(bar),
            ),
          );

      for (var k = 0; k < shape.length; k++) {
        await db.into(db.setLogs).insert(
              SetLogsCompanion.insert(
                id: Value(newId()),
                workoutExerciseId: id,
                setIndex: k,
                setType: Value(shape[k]),
              ),
            );
      }
    });
    return id;
  }

  /// The slot goes and its sets go with it — see [_tombstoneSetsOf].
  Future<void> removeExerciseFromWorkout(String workoutExerciseId) async {
    final stamp = nowMs();
    await db.transaction(() async {
      await _tombstoneSetsOf([workoutExerciseId], stamp);
      await (db.update(db.workoutExercises)
            ..where((t) => t.id.equals(workoutExerciseId)))
          .write(
        WorkoutExercisesCompanion(
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Finishes a workout and closes its cycle if that was the last session owed.
  ///
  /// All of it in one transaction. Closing the cycle after the commit would
  /// leave a window — a crash, a kill, a battery — where the session is
  /// finished and the cycle it satisfied is still open. Today would then show
  /// "UP NEXT" over a full row of filled dots, and the deload would count a
  /// cycle that had already been trained. `deleteWorkout` keeps its own cycle
  /// repair inside its transaction for the mirror-image reason.
  /// False when there was no workout to finish — deleted from History while its
  /// own log was open, or discarded from a second door onto the same session.
  ///
  /// Answered rather than thrown, and answered rather than swallowed. A throw
  /// would die in the gesture handler and leave the log screen sitting there;
  /// returning nothing at all would be worse, because the caller would go on to
  /// open a summary of a workout that no longer exists.
  Future<bool> completeWorkout(String workoutId) =>
      db.transaction(() => _completeWorkout(workoutId));

  Future<bool> _completeWorkout(String workoutId) async {
    // Live rows only. A delete here is a tombstone, so a workout removed
    // from History is still a row. Without the `deletedAt` filter, finishing
    // one would stamp `completed` onto a deleted session and re-mark it dirty
    // for a sync to push, invisibly: every read path filters `deletedAt`, so
    // nothing on screen would show it.
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (workout == null) return false;

    {
      // Empty sets would otherwise look like real history full of nulls.
      //
      // Tombstoned rather than deleted, like every other delete in the app: a
      // row removed outright has no deleted_at to push, so the first pull from
      // another device would resurrect it once sync lands. Every read path
      // already filters deletedAt.
      await (db.update(db.setLogs)
            ..where((t) =>
                t.isDone.equals(false) &
                t.deletedAt.isNull() &
                t.workoutExerciseId.isInQuery(
                  db.selectOnly(db.workoutExercises)
                    ..addColumns([db.workoutExercises.id])
                    ..where(db.workoutExercises.workoutId.equals(workoutId)),
                )))
          .write(
        SetLogsCompanion(
          deletedAt: Value(nowMs()),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );

      await (db.update(db.workouts)..where((t) => t.id.equals(workoutId))).write(
        WorkoutsCompanion(
          status: const Value(WorkoutStatus.completed),
          endedAt: Value(nowMs()),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    }

    final cycleId = workout.cycleId;
    if (cycleId == null) return true;

    final status = await cycleStatus(workout.regimeId);
    if (status == null) return true;
    // `cycleStatus` describes the cycle open *now*. A backdated session can
    // belong to an older, already-closed one — finishing it must not stamp a
    // fresh completion onto a cycle that closed weeks ago, and must not close
    // the current cycle on the strength of a workout that isn't in it.
    if (status.cycleId != cycleId) return true;

    if (status.isComplete) {
      await (db.update(db.cycles)..where((t) => t.id.equals(cycleId))).write(
        CyclesCompanion(
          completedAt: Value(nowMs()),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    }
    return true;
  }

  /// Sets ticked off in a workout, ignoring the empty rows [startWorkout]
  /// creates up front. "Has anything actually been done in here."
  Future<int> doneSetCount(String workoutId) async {
    final total = db.setLogs.id.count();
    final query = db.selectOnly(db.setLogs).join([
      innerJoin(
        db.workoutExercises,
        db.workoutExercises.id.equalsExp(db.setLogs.workoutExerciseId),
      ),
    ])
      ..addColumns([total])
      ..where(db.workoutExercises.workoutId.equals(workoutId) &
          db.workoutExercises.deletedAt.isNull() &
          db.setLogs.isDone.equals(true) &
          db.setLogs.deletedAt.isNull());
    return (await query.getSingle()).read(total) ?? 0;
  }

  /// Every set row in the workout, ticked or not. The denominator to
  /// [doneSetCount] — "4 of 12" rather than a count with nothing to weigh it
  /// against.
  Future<int> setCount(String workoutId) async {
    final total = db.setLogs.id.count();
    final query = db.selectOnly(db.setLogs).join([
      innerJoin(
        db.workoutExercises,
        db.workoutExercises.id.equalsExp(db.setLogs.workoutExerciseId),
      ),
    ])
      ..addColumns([total])
      ..where(db.workoutExercises.workoutId.equals(workoutId) &
          db.workoutExercises.deletedAt.isNull() &
          db.setLogs.deletedAt.isNull());
    return (await query.getSingle()).read(total) ?? 0;
  }

  /// The workout's own exercise names, in slot order.
  ///
  /// Off `workoutExercises`, not the session template it was copied from — see
  /// [TodaySnapshot.openWorkoutExerciseNames].
  Future<List<String>> workoutExerciseNames(String workoutId) async {
    final rows = await (db.select(db.workoutExercises).join([
      innerJoin(db.exercises,
          db.exercises.id.equalsExp(db.workoutExercises.exerciseId)),
    ])
          ..where(db.workoutExercises.workoutId.equals(workoutId) &
              db.workoutExercises.deletedAt.isNull())
          ..orderBy([OrderingTerm(expression: db.workoutExercises.orderIndex)]))
        .get();
    return [for (final r in rows) r.readTable(db.exercises).name];
  }

  /// Clears out sessions started a day or more ago with nothing logged in them.
  ///
  /// A mis-tap on Start writes a workout that then sits on Today forever,
  /// blocking every other session behind a prompt to finish the open one.
  /// Nothing
  /// in it is worth keeping, so it goes at launch without asking.
  ///
  /// Only when [doneSetCount] is zero. A session containing logged sets, left
  /// open overnight is the far more common shape — trained it, never pressed
  /// Finish — and deleting that would destroy a day's work to save a tap. Those
  /// stay, and Today offers to finish or discard them explicitly.
  Future<int> sweepAbandonedWorkouts({
    Duration olderThan = const Duration(hours: 24),
  }) async {
    final cutoff = nowMs() - olderThan.inMilliseconds;
    // `updatedAt` rather than `startedAt`. This asks how long ago the row was
    // written, and `startedAt` is the one column the app deliberately moves
    // into the past: `startWorkout(at:)` backdates it so that a session not
    // to log sorts into history where it belongs. Keyed on `startedAt`, a
    // backfill for the previous week is already past this cutoff at the moment
    // it is created, and this runs before first paint on every launch, so
    // opening the backfill sheet, getting the log screen and being killed by
    // Android before anything was ticked lost the whole session with no
    // message.
    //
    // `updatedAt` is never backdated: it is stamped by `nowMs` on the insert
    // and re-stamped on every write to this row. Ticking a set writes
    // `set_logs` rather than `workouts`, so a session trained and left open
    // overnight still ages here — which is right, because `doneSetCount` below
    // is what keeps that one.
    final stale = await (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.inProgress) &
              t.deletedAt.isNull() &
              t.updatedAt.isSmallerThanValue(cutoff)))
        .get();

    var swept = 0;
    for (final workout in stale) {
      if (await doneSetCount(workout.id) > 0) continue;
      await abandonWorkout(workout.id);
      swept++;
    }
    return swept;
  }

  /// Throws a session away — the sweep at launch, and Discard from the log.
  ///
  /// The whole tree goes, exactly as [deleteWorkout] takes it. Tombstoning only
  /// the workout row left its exercise snapshots and set rows alive underneath a
  /// deleted parent: invisible here, because every read joins the workout and
  /// filters `deletedAt`, but they are live rows with `dirty` set, so the first
  /// push would hand another device a set that belongs to a session that does
  /// not exist. A device that had already pulled the parent would then hold the
  /// orphan for good, since nothing would ever come along to delete it.
  Future<void> abandonWorkout(String workoutId) async {
    final stamp = nowMs();
    await db.transaction(() async {
      await _tombstoneChildren(workoutId, stamp);
      await (db.update(db.workouts)..where((t) => t.id.equals(workoutId))).write(
        WorkoutsCompanion(
          status: const Value(WorkoutStatus.abandoned),
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Tombstones every set under [workoutExerciseIds], live or not.
  ///
  /// The one write a slot's disappearance owes, wherever the slot goes: leaving
  /// its `set_logs` alive under a deleted parent is invisible on this phone —
  /// every read that carries a number joins the slot and filters `deletedAt` —
  /// but they are live rows with `dirty` set, so the first push hands another
  /// device sets belonging to a slot that does not exist, and no tombstone ever
  /// follows to clear them.
  ///
  /// Not a transaction of its own, so every caller must provide one: this is
  /// half
  /// of a cascade and the other half is the parent's own write.
  Future<void> _tombstoneSetsOf(List<String> workoutExerciseIds, int stamp) =>
      (db.update(db.setLogs)
            ..where((t) => t.workoutExerciseId.isIn(workoutExerciseIds)))
          .write(
        SetLogsCompanion(
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );

  /// Tombstones a workout's exercise snapshots and every set under them.
  ///
  /// Shared by [deleteWorkout] and [abandonWorkout] because "the workout is
  /// gone" has to mean the same thing however it went.
  ///
  /// No `deletedAt` filter on the slots it collects, deliberately: a slot that
  /// was already swapped away may still be carrying live sets, and those are
  /// the workout's too.
  Future<void> _tombstoneChildren(String workoutId, int stamp) async {
    final weIds = [
      for (final we in await (db.select(db.workoutExercises)
            ..where((t) => t.workoutId.equals(workoutId)))
          .get())
        we.id,
    ];
    if (weIds.isEmpty) return;

    await _tombstoneSetsOf(weIds, stamp);
    await (db.update(db.workoutExercises)
          ..where((t) => t.workoutId.equals(workoutId)))
        .write(
      WorkoutExercisesCompanion(
        deletedAt: Value(stamp),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(stamp),
        dirty: const Value(true),
      ),
    );
  }

  /// Moves a logged day to another date.
  ///
  /// A training log must permit Monday's session to be recorded on Wednesday,
  /// and an incorrect date to be corrected. `startedAt` moves with `dayKey`
  /// deliberately:
  /// the heatmap reads the day key, but history pages on `startedAt`, and a row
  /// that sorts by one date while displaying another is worse than either.
  /// The clock time and the session's duration are preserved.
  ///
  /// The cycle moves with the date. [startWorkout] resolves a backdated session
  /// against [cycleCovering] for a reason — a day belongs to the cycle that was
  /// open when it happened — and re-dating one afterwards has to answer the
  /// same question, or dragging a workout three weeks back leaves it counting
  /// towards a cycle it was not part of and the deload lands early. Both cycles
  /// are then settled the way every other path settles them: the one it left
  /// reopens if it is no longer complete, and the one it joined closes if it now
  /// is.
  Future<void> setWorkoutDate(String workoutId, DateTime date) async {
    final workout =
        await (db.select(db.workouts)..where((t) => t.id.equals(workoutId)))
            .getSingleOrNull();
    if (workout == null) return;

    final was = DateTime.fromMillisecondsSinceEpoch(workout.startedAt);
    final moved = DateTime(
      date.year,
      date.month,
      date.day,
      was.hour,
      was.minute,
      was.second,
    );
    final shift = moved.millisecondsSinceEpoch - workout.startedAt;
    final covering = await cycleCovering(workout.regimeId, moved);
    final movedCycle = covering?.id != workout.cycleId;

    // One transaction: the move and the two cycles it disturbs are a single
    // act. Run loose, a crash between them left the workout on its new date
    // with the cycle it left still closed — the deload-lands-early failure this
    // method's own doc warns about, reached by the route that fixes it.
    await db.transaction(() async {
      await (db.update(db.workouts)..where((t) => t.id.equals(workoutId)))
          .write(
        WorkoutsCompanion(
          dayKey: Value(dayKeyOf(moved)),
          startedAt: Value(moved.millisecondsSinceEpoch),
          // Restamped rather than left alone. The row may have been written
          // under another offset — another zone, or the other side of a clock
          // change — and moving two of the three columns while the third keeps
          // an offset that no longer explains them is exactly the disagreement
          // `Workouts.tzOffsetMinutes` exists to refuse.
          tzOffsetMinutes: Value(tzOffsetOf(moved)),
          endedAt: workout.endedAt == null
              ? const Value.absent()
              : Value(workout.endedAt! + shift),
          cycleId: movedCycle ? Value(covering?.id) : const Value.absent(),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );

      if (!movedCycle) return;
      // In this order, and only after the row above has landed — within the
      // transaction it already has: the cycle it left is judged on what is
      // still in it, and `workout` still carries the old cycle id for exactly
      // that lookup.
      await _reopenCycleIfIncomplete(workout);
      await closeCycleIfSatisfied(workout.regimeId);
    });
  }

  /// The context that explains a poor week when the log is reviewed months
  /// later.
  Future<void> setWorkoutNotes(String workoutId, String? notes) async {
    final trimmed = notes?.trim();
    await (db.update(db.workouts)..where((t) => t.id.equals(workoutId))).write(
      WorkoutsCompanion(
        notes: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Removes one logged day from history.
  ///
  /// The whole tree is tombstoned — workout, exercise snapshots, sets — so a
  /// session logged by accident leaves the feed, the heatmap, the progress
  /// chart and prefill together, rather than half of each.
  Future<void> deleteWorkout(String workoutId) async {
    final workout =
        await (db.select(db.workouts)..where((t) => t.id.equals(workoutId)))
            .getSingleOrNull();
    if (workout == null) return;

    final stamp = nowMs();
    // Reopening the cycle is part of the delete, not a follow-up to it. It ran
    // after the transaction committed, which left a window — a crash or a kill
    // between the two — where the workout was gone and its cycle still carried
    // `completedAt`. The programme then counts a cycle for a day that never
    // happened and the deload lands early, which is the exact failure
    // [_reopenCycleIfIncomplete] exists to prevent.
    await db.transaction(() async {
      await _tombstoneChildren(workoutId, stamp);

      await (db.update(db.workouts)..where((t) => t.id.equals(workoutId)))
          .write(
        WorkoutsCompanion(
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );

      await _reopenCycleIfIncomplete(workout);
    });
  }

  /// A cycle closes the moment its last owed session is logged. Deleting that
  /// workout has to reopen it, or the programme counts a cycle for a day that
  /// never happened — and the deload lands early.
  ///
  /// The cycles after it are dropped, but only while they are still empty:
  /// closing a cycle immediately opens the next one, so an untouched successor
  /// is a placeholder rather than history. A successor with real training in it
  /// means the cycle genuinely happened, and nothing is renumbered.
  Future<void> _reopenCycleIfIncomplete(Workout workout) async {
    final cycleId = workout.cycleId;
    if (cycleId == null) return;

    final cycle = await (db.select(db.cycles)..where((t) => t.id.equals(cycleId)))
        .getSingleOrNull();
    if (cycle == null || cycle.completedAt == null) return;

    final sessionIds = await _sessionIds(cycle.regimeId);
    final done = await _completedSessionIds(cycle.id);
    if (sessionIds.isEmpty || sessionIds.every(done.contains)) return;

    final later = await (db.select(db.cycles)
          ..where((t) =>
              t.regimeId.equals(cycle.regimeId) &
              t.deletedAt.isNull() &
              t.cycleIndex.isBiggerThanValue(cycle.cycleIndex)))
        .get();

    // Anything *live* in a later cycle keeps it, not just anything finished.
    //
    // This read `_completedSessionIds(c.id).isNotEmpty`, which asks a narrower
    // question than the one that matters: a session still running, or one that
    // was abandoned, is not a completed session but it is still a row pointing
    // at this cycle. Tombstoning the cycle under it left the workout naming a
    // dead one — invisible on this phone, because nothing reads a workout's
    // cycle through a `deleted_at` filter, and a dangling reference on the wire
    // the moment there is a second device.
    //
    // Refusing to reopen is the conservative half of the trade. The reopen
    // exists to stop the deload landing early; leaving the earlier cycle closed
    // costs at most that, where repointing another cycle's workouts would move
    // logged work to a cycle it was not done in.
    for (final c in later) {
      final held = await (db.select(db.workouts)
            ..where((t) => t.cycleId.equals(c.id) & t.deletedAt.isNull()))
          .get();
      if (held.isNotEmpty) return;
    }

    // A regime holds one open cycle, and a later cycle is not the only one that
    // may be open. `later` is every live cycle numbered above this one,
    // and checking only those, as the loop above does, assumes the one cycle
    // that could still be open is among them. That holds on a single device,
    // where cycles close in index order and the open one is always the highest.
    // It does not hold once a second device exists:
    // the merge re-numbers a collided cycle ([SYNC.md § 9](../../../SYNC.md#9-collision--two-rows-one-slot)),
    // so index order stops matching the order they were closed in, and the
    // regime can carry an open cycle at or below this one's index.
    //
    // Reopening on top of that is refused by `idx_cycles_regime_open_live`,
    // would throw `UNIQUE constraint failed: cycles.regime_id` from inside
    // `deleteWorkout` and take the whole delete down with it. The index would
    // be doing its job — nothing corrupted, the transaction rolled back — but a
    // delete that cannot run is still a delete that cannot run.
    //
    // So this takes the same conservative half the comment above already
    // takes: leave the earlier cycle closed. It costs at most a deload landing
    // early, where closing the other open cycle to make room would end a cycle
    // the user is training in right now.
    final otherOpen = await (db.select(db.cycles)
          ..where((t) =>
              t.regimeId.equals(cycle.regimeId) &
              t.deletedAt.isNull() &
              t.completedAt.isNull() &
              t.id.equals(cycle.id).not() &
              t.cycleIndex.isSmallerOrEqualValue(cycle.cycleIndex)))
        .get();
    if (otherOpen.isNotEmpty) return;

    await db.transaction(() async {
      for (final c in later) {
        await (db.update(db.cycles)..where((t) => t.id.equals(c.id))).write(
          CyclesCompanion(
            deletedAt: Value(nowMs()),
            deviceId: Value(currentDeviceId),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
      }
      await (db.update(db.cycles)..where((t) => t.id.equals(cycle.id))).write(
        CyclesCompanion(
          completedAt: const Value(null),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// How much history there is, in one row: how many sessions, and the first
  /// and last day one was trained.
  ///
  /// One aggregate rather than a page of rows — the masthead needs the totals
  /// before the feed has scrolled anywhere near them.
  Future<HistoryOverview> historyOverview() async {
    final counted = db.workouts.id.count();
    final first = db.workouts.dayKey.min();
    final last = db.workouts.dayKey.max();
    final row = await (db.selectOnly(db.workouts)
          ..addColumns([counted, first, last])
          ..where(db.workouts.deletedAt.isNull() &
              db.workouts.status.equalsValue(WorkoutStatus.completed)))
        .getSingle();

    return HistoryOverview(
      sessions: row.read(counted) ?? 0,
      firstDayKey: row.read(first),
      lastDayKey: row.read(last),
    );
  }

  Stream<HistoryOverview> watchHistoryOverview() {
    return db.watchQuery([db.workouts], historyOverview);
  }

  /// Completed workouts logged under a regime. Shown before deleting one, so
  /// "this removes the programme, not the training" is a number rather than a
  /// promise.
  Future<int> completedWorkoutCount(String regimeId) async {
    final counted = db.workouts.id.count();
    final row = await (db.selectOnly(db.workouts)
          ..addColumns([counted])
          ..where(db.workouts.regimeId.equals(regimeId) &
              db.workouts.deletedAt.isNull() &
              db.workouts.status.equalsValue(WorkoutStatus.completed)))
        .getSingle();
    return row.read(counted) ?? 0;
  }
}
