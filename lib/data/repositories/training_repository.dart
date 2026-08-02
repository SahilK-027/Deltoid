import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/enums.dart';
import '../../domain/metrics.dart';
import '../../domain/prefill.dart';
import '../../domain/session_diff.dart';
import '../../domain/units.dart';
import '../db/database.dart';
import '../db/watch.dart';

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
/// Today used to assemble itself out of a dozen independently watched queries
/// arranged in dependency layers — regime, then its sessions, then the cycle
/// status, then a slot count per session row. Each layer resolved a frame or
/// two after the one above it, so an app whose answers were already on disk
/// still revealed its first screen in stages. Worse, the frame before
/// `sessions` arrived was indistinguishable from a regime with no sessions in
/// it, so the "no sessions" empty state flashed at people who had five.
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
  /// and never worked in — the difference between "you left this running" and
  /// "you mis-tapped Start three days ago", which is the only thing that
  /// decides whether the app may throw it away on its own.
  final int openWorkoutDoneSets;

  /// Every set row in the open workout, done or not — the denominator Today
  /// puts beside [openWorkoutDoneSets].
  final int openWorkoutTotalSets;

  /// Exercise names in the open workout, in slot order.
  ///
  /// Read off `workoutExercises`, **not** off the session template: the log is
  /// a snapshot taken at Start, so an exercise swapped out of the programme
  /// since then is still in the session you are standing in.
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
  Future<Cycle> ensureOpenCycle(String regimeId) async {
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

    final regime = await (db.select(db.regimes)..where((t) => t.id.equals(regimeId)))
        .getSingle();
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

  Future<CycleStatus> cycleStatus(String regimeId) async {
    final regime =
        await (db.select(db.regimes)..where((t) => t.id.equals(regimeId))).getSingle();
    final cycle = await ensureOpenCycle(regimeId);
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

  /// Every completed workout, oldest first, for the full-history heatmap.
  ///
  /// Deliberately separate from [todaySnapshot]: Today only ever needs the last
  /// thirteen weeks, and loading a decade of rows to render three months of grid
  /// would be a tax paid on every write to any of six tables.
  Future<List<Workout>> allCompleted() {
    return (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.completed) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
        .get();
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
                    updatedAt: Value(nowMs()),
                    dirty: const Value(true),
                  ),
                );
                continue;
              }
              final live = await (db.select(db.sessionExercises)
                    ..where((t) =>
                        t.sessionId.equals(sessionId) & t.deletedAt.isNull()))
                  .get();
              await db.into(db.sessionExercises).insert(
                    SessionExercisesCompanion.insert(
                      id: Value(newId()),
                      sessionId: sessionId,
                      exerciseId: exerciseId,
                      orderIndex: live.length,
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
        // its existing relative order — a slot you skipped is not a slot you
        // asked to move to the end.
        final wanted = <SessionExercise>[];
        for (final exerciseId in reorder.exerciseIds) {
          final slot =
              live.where((s) => s.exerciseId == exerciseId).firstOrNull;
          if (slot != null && !wanted.contains(slot)) wanted.add(slot);
        }
        for (final slot in live) {
          if (!wanted.contains(slot)) wanted.add(slot);
        }

        for (var i = 0; i < wanted.length; i++) {
          await (db.update(db.sessionExercises)
                ..where((t) => t.id.equals(wanted[i].id)))
              .write(
            SessionExercisesCompanion(
              orderIndex: Value(i),
              updatedAt: Value(nowMs()),
              dirty: const Value(true),
            ),
          );
        }
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
  Future<void> advanceCycle(String regimeId) async {
    final cycle = await ensureOpenCycle(regimeId);
    await (db.update(db.cycles)..where((t) => t.id.equals(cycle.id))).write(
      CyclesCompanion(
        completedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await ensureOpenCycle(regimeId);
  }

  /// The cycle that was open on [at], or null when the date predates every
  /// cycle this regime has had.
  ///
  /// A backdated workout used to attach to whatever cycle is open *now*.
  /// Backfilling yesterday is usually the same cycle and nobody notices;
  /// backfilling three weeks ago counted towards the current cycle, could
  /// complete it on the strength of work done under a previous one, and moved
  /// the deload counter early.
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
  /// Only `completeWorkout` used to close a cycle, so deleting the last
  /// untrained day of a cycle left it complete-but-open: Today showed
  /// "UP NEXT: Push 1" over a full row of filled dots until the next workout
  /// happened to heal it. A cycle should close the moment it is satisfied,
  /// whatever satisfied it.
  Future<bool> closeCycleIfSatisfied(String regimeId) async {
    final sessionIds = await _sessionIds(regimeId);
    if (sessionIds.isEmpty) return false;

    final cycle = await ensureOpenCycle(regimeId);
    final done = await _completedSessionIds(cycle.id);
    if (!sessionIds.every(done.contains)) return false;

    await (db.update(db.cycles)..where((t) => t.id.equals(cycle.id))).write(
      CyclesCompanion(
        completedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await ensureOpenCycle(regimeId);
    return true;
  }

  /// Overrides whether the open cycle is a deload. The suggestion is never
  /// binding.
  Future<void> setCycleDeload(String cycleId, bool isDeload) async {
    await (db.update(db.cycles)..where((t) => t.id.equals(cycleId))).write(
      CyclesCompanion(
        isDeload: Value(isDeload),
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
  /// many training days pushed a slot left untrained for 30-odd performances
  /// elsewhere out of the window, and prefill quietly fell back to another
  /// session — labelled honestly, but not the number you wanted. The
  /// same-session lookup should have no horizon; the cross-session fallback
  /// still does.
  Future<List<PastPerformance>> pastPerformances(
    String exerciseId, {
    int limit = 60,
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

    final byWorkout = {for (final p in recent) p.workoutId: p};
    for (final p in sameSession) {
      byWorkout.putIfAbsent(p.workoutId, () => p);
    }
    // Sort on the same key both queries ordered by. Sorting the merged list on
    // dayKey alone put two performances from one day in map insertion order,
    // so prefill could pick the earlier and call it last time.
    final merged = byWorkout.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return merged;
  }

  Future<List<PastPerformance>> _performances(
    String exerciseId, {
    required int limit,
    String? excludeWorkoutId,
    String? sessionId,
  }) async {
    final q = db.select(db.workoutExercises).join([
      innerJoin(db.workouts, db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
      leftOuterJoin(db.sessions, db.sessions.id.equalsExp(db.workouts.sessionId)),
    ])
      ..where(db.workoutExercises.exerciseId.equals(exerciseId) &
          db.workoutExercises.deletedAt.isNull() &
          db.workouts.deletedAt.isNull() &
          db.workouts.status.equalsValue(WorkoutStatus.completed))
      ..orderBy([OrderingTerm(expression: db.workouts.startedAt, mode: OrderingMode.desc)])
      ..limit(limit);

    if (excludeWorkoutId != null) {
      q.where(db.workouts.id.equals(excludeWorkoutId).not());
    }
    if (sessionId != null) {
      q.where(db.workouts.sessionId.equals(sessionId));
    }

    final rows = await q.get();
    if (rows.isEmpty) return const [];

    final weIds = rows.map((r) => r.readTable(db.workoutExercises).id).toList();
    final setRows = await (db.select(db.setLogs)
          ..where((t) => t.workoutExerciseId.isIn(weIds) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
        .get();

    final setsByWe = <String, List<SetLog>>{};
    for (final s in setRows) {
      setsByWe.putIfAbsent(s.workoutExerciseId, () => []).add(s);
    }

    return [
      for (final r in rows)
        () {
          final we = r.readTable(db.workoutExercises);
          final w = r.readTable(db.workouts);
          final session = r.readTableOrNull(db.sessions);
          final sets = setsByWe[we.id] ?? const <SetLog>[];
          return PastPerformance(
            workoutId: w.id,
            sessionId: w.sessionId,
            sessionName: session?.name ?? 'Ad-hoc',
            dayKey: w.dayKey,
            startedAt: w.startedAt,
            isDeload: w.isDeload,
            // Sets logged before the exercise was marked skipped did happen:
            // two sets then a bad shoulder is two real sets. They stay
            // eligible here *and* are shown under the skip pill in history, so
            // there is one story rather than two. This used to be decided by
            // accident — nothing read skipReason, and the empty-sets check did
            // the filtering.
            skipReason: we.skipReason,
            sets: [
              for (final s in sets)
                if (s.isDone)
                  PastSet(
                    type: s.setType,
                    weight: s.weight,
                    reps: s.reps,
                    addedWeight: s.addedWeight,
                    isLeg: s.parentSetId != null,
                  ),
            ],
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
    var predicate = db.workouts.status.equalsValue(WorkoutStatus.completed) &
        db.workouts.deletedAt.isNull();
    // Filters go in the query, never over the loaded page: History pages by
    // keyset (README invariant 5), and a page filtered after the fact comes
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
  Future<List<ExerciseHistorySummary>> exercisesWithHistory() async {
    final performed = db.workoutExercises.id.count();
    final lastDay = db.workouts.dayKey.max();

    final rows = await (db.selectOnly(db.workoutExercises).join([
      innerJoin(db.workouts,
          db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
    ])
          ..addColumns([db.workoutExercises.exerciseId, performed, lastDay])
          // "2 sessions" has to mean times trained. A slot left blank still
          // counts — you turned up and the row was there — but one you marked
          // skipped, with a reason, did not happen.
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
  /// regime's sessions would omit every day you trained under the split you
  /// stopped running, which is precisely the history worth filtering; one built
  /// from all sessions ever created would offer days that return an empty list.
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
    // Most recently trained first: the day you want back is nearly always one
    // you are still running.
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
  /// means something once you know whether it was Push 1 or Push 2.
  Future<List<ExercisePerformance>> exerciseHistoryPage(
    String exerciseId, {
    int limit = 20,
    HistoryCursor? olderThan,
  }) async {
    var predicate = db.workoutExercises.exerciseId.equals(exerciseId) &
        db.workoutExercises.deletedAt.isNull() &
        db.workouts.deletedAt.isNull() &
        db.workouts.status.equalsValue(WorkoutStatus.completed);
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

    final exercise =
        await (db.select(db.exercises)..where((t) => t.id.equals(exerciseId)))
            .getSingle();
    final bodyweight = await bodyweightSeries();

    return [
      for (final r in rows)
        () {
          final we = r.readTable(db.workoutExercises);
          final workout = r.readTable(db.workouts);
          final sets = setsByWe[we.id] ?? const <SetLog>[];
          final score = scorePerformance(
            mode: exercise.loadMode,
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
            sessionName: r.readTableOrNull(db.sessions)?.name ?? 'Ad-hoc',
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
  Future<List<({int dayKey, double weightKg})>> bodyweightSeries() async {
    final rows = await (db.select(db.bodyweightLogs)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
        .get();
    return [for (final r in rows) (dayKey: r.dayKey, weightKg: r.weightKg)];
  }

  /// A bodyweight entry is an input to every bodyweight and BW+ score, not a
  /// diary line, so a typo has to be removable rather than permanent.
  Future<void> deleteBodyweight(int dayKey) async {
    await (db.update(db.bodyweightLogs)
          ..where((t) => t.dayKey.equals(dayKey) & t.deletedAt.isNull()))
        .write(
      BodyweightLogsCompanion(
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> logBodyweight(DateTime date, double kg) async {
    final key = dayKeyOf(date);
    final existing = await (db.select(db.bodyweightLogs)
          ..where((t) => t.dayKey.equals(key) & t.deletedAt.isNull()))
        .getSingleOrNull();

    if (existing != null) {
      await (db.update(db.bodyweightLogs)..where((t) => t.id.equals(existing.id)))
          .write(
        BodyweightLogsCompanion(
          weightKg: Value(kg),
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
  Future<List<ProgressPoint>> exerciseProgress(String exerciseId) async {
    final performances = await pastPerformances(exerciseId, limit: 400);
    if (performances.isEmpty) return const [];

    final exercise =
        await (db.select(db.exercises)..where((t) => t.id.equals(exerciseId)))
            .getSingle();
    final bodyweight = await bodyweightSeries();

    final points = <ProgressPoint>[];
    for (final p in performances) {
      final score = scorePerformance(
        mode: exercise.loadMode,
        bodyweightKg: bodyweightOn(p.dayKey, bodyweight),
        sets: [
          for (final s in p.sets)
            ScoredSet(
              type: s.type,
              weight: s.weight,
              reps: s.reps,
              addedWeight: s.addedWeight,
            ),
        ],
      );
      if (score.isEmpty) continue;

      points.add(ProgressPoint(
        dayKey: p.dayKey,
        sessionId: p.sessionId,
        sessionName: p.sessionName,
        isDeload: p.isDeload,
        topSetLoad: score.topSetLoad,
        topSetReps: score.topSetReps,
        best1RM: score.best1RM,
        volume: score.volume,
      ));
    }

    points.sort((a, b) => a.dayKey.compareTo(b.dayKey));
    return points;
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
  /// [at] backdates the workout, for writing down a session you forgot to log
  /// on the day. It never returns a running workout, because a session being
  /// trained right now is not the one you are backfilling.
  Future<String> startWorkout({
    required String regimeId,
    required String sessionId,
    DateTime? at,
  }) async {
    // A double tap on "Start" — or a screen that hasn't rebuilt yet — must not
    // open a second parallel log for the same session. Hand back the running
    // one instead; the sets already in it are the ones being asked for.
    final running = await openWorkout();
    if (at == null) {
      if (running != null && running.sessionId == sessionId) return running.id;
    } else if (running != null) {
      // Only one workout may be open at a time. `openWorkout` returns the
      // newest by startedAt, so an abandoned backdated log would be hidden by
      // the next session you start and become unreachable — in progress
      // forever, listed nowhere.
      throw StateError('Finish the session in progress first');
    }

    final regime =
        await (db.select(db.regimes)..where((t) => t.id.equals(regimeId))).getSingle();
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
    final workoutId = newId();
    // A backdated session keeps the current clock time: the date is what was
    // forgotten, the hour is unknowable and unimportant.
    final now = at == null
        ? DateTime.now()
        : DateTime(at.year, at.month, at.day, DateTime.now().hour,
            DateTime.now().minute);

    // Prefill is resolved before the transaction so the write stays short.
    final plans = <({SessionExercise slot, PrefillResult prefill})>[];
    for (final slot in slots) {
      final past = await pastPerformances(
        slot.exerciseId,
        limit: 30,
        sessionId: sessionId,
      );
      plans.add((
        slot: slot,
        prefill: resolvePrefill(
          candidates: past,
          sessionId: sessionId,
          targetIsDeload: cycle?.isDeload ?? false,
          deloadSetDelta: slot.deloadSetDelta ?? regime.deloadSetDelta,
          deloadWeightPct: slot.deloadWeightPct ?? regime.deloadWeightPct,
          unit: unit,
        ),
      ));
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
        // Only the *types* were mirrored, so last week's drop set came back as
        // a row of unrelated `D`s — each its own group, each with its own
        // capsule and `+`, none of them a leg of anything.
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
  /// Falls back to the last rest actually taken on that exercise, then to two
  /// minutes. The timer's doc comment always claimed rest was "captured without
  /// asking for a single extra tap"; until now nothing wrote it down.
  Future<int> restTargetFor({
    required String exerciseId,
    required String? sessionId,
  }) async {
    if (sessionId != null) {
      final slot = await (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(sessionId) &
                t.exerciseId.equals(exerciseId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();
      final target = slot?.restSeconds;
      if (target != null) return target;
    }

    final last = await (db.select(db.setLogs).join([
      innerJoin(db.workoutExercises,
          db.workoutExercises.id.equalsExp(db.setLogs.workoutExerciseId)),
    ])
          ..where(db.workoutExercises.exerciseId.equals(exerciseId) &
              db.setLogs.restSeconds.isNotNull() &
              db.setLogs.deletedAt.isNull())
          ..orderBy([
            OrderingTerm(
                expression: db.setLogs.completedAt, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();

    return last?.readTable(db.setLogs).restSeconds ?? 120;
  }

  /// Remembers a rest target against the session slot, so next week opens with
  /// the number you settled on rather than a flat 120 seconds.
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
  /// Start a workout, switch regimes, and the resume card used to read
  /// "Workout" — the session was real, it just wasn't in the list being
  /// searched. Finishing it advances *its* regime's cycle, not the one on
  /// screen, so the card has to be able to say which.
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
    // Any write to these three tables invalidates the view.
    return db.watchQuery(
      [db.workouts, db.workoutExercises, db.setLogs],
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

  Stream<CycleStatus> watchCycleStatus(String regimeId) {
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
        addedWeight: addedWeight,
        setType: setType,
        parentSetId: parentSetId,
        isDone: isDone,
        restSeconds: restSeconds,
        note: note,
        completedAt: isDone.present && isDone.value
            ? Value(nowMs())
            : const Value.absent(),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<String> addSet(String workoutExerciseId, {SetType type = SetType.working}) async {
    final existing = await (db.select(db.setLogs)
          ..where((t) => t.workoutExerciseId.equals(workoutExerciseId) & t.deletedAt.isNull()))
        .get();
    // One past the highest index, not the number of rows. Deletes are
    // tombstones and nothing renumbers after them, so counting live rows handed
    // the new set an index another row still held: delete a drop group, press
    // `+`, and the new set landed in the middle of the table on top of an
    // existing one, in an order the database could break either way.
    final next =
        existing.fold<int>(-1, (m, s) => s.setIndex > m ? s.setIndex : m) + 1;
    final id = newId();
    await db.into(db.setLogs).insert(
          SetLogsCompanion.insert(
            id: Value(id),
            workoutExerciseId: workoutExerciseId,
            setIndex: next,
            setType: Value(type),
          ),
        );
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

      // Renumber from the back so no two rows hold the same index mid-flight.
      for (var i = sets.length - 1; i > at; i--) {
        await (db.update(db.setLogs)..where((t) => t.id.equals(sets[i].id)))
            .write(
              SetLogsCompanion(
                setIndex: Value(i + 1),
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
              setIndex: at + 1,
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
  }) async {
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
  }

  /// Changes a set's type, keeping the drop group around it consistent.
  ///
  /// The sheet wrote the type and nothing else, which left two shapes the table
  /// cannot draw: a drop set with no leg to have dropped into, and legs still
  /// nested under a head that is no longer a drop at all.
  Future<void> setSetType(String setId, SetType type) async {
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

    // A drop set is a set you dropped weight inside, so it needs somewhere to
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
      // turned one set into four: the legs a conversion adds for you are not
      // sets you decided to do, and undoing the conversion has to undo them
      // too. A leg with something logged in it is a set you did — that one is
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

  /// Deletes several sets as one act.
  ///
  /// Deleting the head of a drop group takes its legs with it: the legs are
  /// continuations of that set and mean nothing without it, and leaving them
  /// behind orphaned a `D` run with no set to have dropped from.
  Future<void> deleteSets(List<String> setIds) async {
    if (setIds.isEmpty) return;
    await (db.update(db.setLogs)..where((t) => t.id.isIn(setIds))).write(
      SetLogsCompanion(
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Reorders exercises within a workout only — the session template is
  /// untouched, so rearranging today never rewrites what you did in March.
  Future<void> reorderWorkoutExercises(List<String> orderedIds) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (db.update(db.workoutExercises)..where((t) => t.id.equals(orderedIds[i])))
            .write(
          WorkoutExercisesCompanion(
            orderIndex: Value(i),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
      }
    });
  }

  Future<void> setSkipReason(String workoutExerciseId, SkipReason reason) async {
    await (db.update(db.workoutExercises)..where((t) => t.id.equals(workoutExerciseId)))
        .write(
      WorkoutExercisesCompanion(
        skipReason: Value(reason),
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
    final unit = await weightUnit();
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId)))
        .getSingleOrNull();
    if (workout == null) return const PrefillResult.empty();

    final regime = await (db.select(db.regimes)
          ..where((t) => t.id.equals(workout.regimeId)))
        .getSingleOrNull();

    // The slot's own deload override, exactly as `startWorkout` reads it. This
    // used to take the regime's figures whatever the slot said, so the same
    // exercise deloaded one way when the session opened and another way when it
    // was added ten minutes later.
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
    final existing = await (db.select(db.workoutExercises)
          ..where((t) => t.workoutId.equals(workoutId) & t.deletedAt.isNull()))
        .get();
    final shape = await _shapeFor(
      workoutId: workoutId,
      exerciseId: exerciseId,
      targetSets: targetSets,
    );

    final id = newId();
    await db.transaction(() async {
      await db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              id: Value(id),
              workoutId: workoutId,
              exerciseId: exerciseId,
              orderIndex: existing.length,
              targetSets: Value(targetSets),
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
  /// takes the old slot's position and target, so the page you are standing on
  /// does not move out from under you mid-session. Doing this as
  /// remove-then-add sent the replacement to the end of the workout.
  Future<String> replaceExerciseInWorkout(
    String workoutExerciseId,
    String newExerciseId,
  ) async {
    final old = await (db.select(db.workoutExercises)
          ..where((t) => t.id.equals(workoutExerciseId)))
        .getSingle();

    final shape = await _shapeFor(
      workoutId: old.workoutId,
      exerciseId: newExerciseId,
      targetSets: old.targetSets,
    );

    final id = newId();
    await db.transaction(() async {
      await (db.update(db.workoutExercises)
            ..where((t) => t.id.equals(workoutExerciseId)))
          .write(
        WorkoutExercisesCompanion(
          deletedAt: Value(nowMs()),
          updatedAt: Value(nowMs()),
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

  Future<void> removeExerciseFromWorkout(String workoutExerciseId) async {
    await (db.update(db.workoutExercises)..where((t) => t.id.equals(workoutExerciseId)))
        .write(
      WorkoutExercisesCompanion(
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Finishes a workout and closes its cycle if that was the last session owed.
  Future<void> completeWorkout(String workoutId) async {
    final workout =
        await (db.select(db.workouts)..where((t) => t.id.equals(workoutId))).getSingle();

    await db.transaction(() async {
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
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );

      await (db.update(db.workouts)..where((t) => t.id.equals(workoutId))).write(
        WorkoutsCompanion(
          status: const Value(WorkoutStatus.completed),
          endedAt: Value(nowMs()),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    });

    final cycleId = workout.cycleId;
    if (cycleId == null) return;

    final status = await cycleStatus(workout.regimeId);
    // `cycleStatus` describes the cycle open *now*. A backdated session can
    // belong to an older, already-closed one — finishing it must not stamp a
    // fresh completion onto a cycle that closed weeks ago, and must not close
    // the current cycle on the strength of a workout that isn't in it.
    if (status.cycleId != cycleId) return;

    if (status.isComplete) {
      await (db.update(db.cycles)..where((t) => t.id.equals(cycleId))).write(
        CyclesCompanion(
          completedAt: Value(nowMs()),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    }
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
  /// blocking every other session behind "finish the one you are in". Nothing
  /// in it is worth keeping, so it goes at launch without asking.
  ///
  /// **Only when [doneSetCount] is zero.** A session with real sets in it left
  /// open overnight is the far more common shape — trained it, never pressed
  /// Finish — and deleting that would destroy a day's work to save a tap. Those
  /// stay, and Today offers to finish or discard them explicitly.
  Future<int> sweepAbandonedWorkouts({
    Duration olderThan = const Duration(hours: 24),
  }) async {
    final cutoff = nowMs() - olderThan.inMilliseconds;
    final stale = await (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.inProgress) &
              t.deletedAt.isNull() &
              t.startedAt.isSmallerThanValue(cutoff)))
        .get();

    var swept = 0;
    for (final workout in stale) {
      if (await doneSetCount(workout.id) > 0) continue;
      await abandonWorkout(workout.id);
      swept++;
    }
    return swept;
  }

  Future<void> abandonWorkout(String workoutId) async {
    await (db.update(db.workouts)..where((t) => t.id.equals(workoutId))).write(
      WorkoutsCompanion(
        status: const Value(WorkoutStatus.abandoned),
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Moves a logged day to another date.
  ///
  /// A training log has to let you write down Monday's session on Wednesday,
  /// and fix a date you got wrong. `startedAt` moves with `dayKey` on purpose:
  /// the heatmap reads the day key, but history pages on `startedAt`, and a row
  /// that sorts by one date while displaying another is worse than either.
  /// The clock time and the session's duration are preserved.
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

    await (db.update(db.workouts)..where((t) => t.id.equals(workoutId))).write(
      WorkoutsCompanion(
        dayKey: Value(dayKeyOf(moved)),
        startedAt: Value(moved.millisecondsSinceEpoch),
        endedAt: workout.endedAt == null
            ? const Value.absent()
            : Value(workout.endedAt! + shift),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// The context that explains a bad week when you read it back in six months.
  Future<void> setWorkoutNotes(String workoutId, String? notes) async {
    final trimmed = notes?.trim();
    await (db.update(db.workouts)..where((t) => t.id.equals(workoutId))).write(
      WorkoutsCompanion(
        notes: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
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
    await db.transaction(() async {
      final weIds = [
        for (final we in await (db.select(db.workoutExercises)
              ..where((t) => t.workoutId.equals(workoutId)))
            .get())
          we.id,
      ];

      if (weIds.isNotEmpty) {
        await (db.update(db.setLogs)
              ..where((t) => t.workoutExerciseId.isIn(weIds)))
            .write(
          SetLogsCompanion(
            deletedAt: Value(stamp),
            updatedAt: Value(stamp),
            dirty: const Value(true),
          ),
        );
      }

      await (db.update(db.workoutExercises)
            ..where((t) => t.workoutId.equals(workoutId)))
          .write(
        WorkoutExercisesCompanion(
          deletedAt: Value(stamp),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );

      await (db.update(db.workouts)..where((t) => t.id.equals(workoutId)))
          .write(
        WorkoutsCompanion(
          deletedAt: Value(stamp),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );
    });

    await _reopenCycleIfIncomplete(workout);
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

    for (final c in later) {
      if ((await _completedSessionIds(c.id)).isNotEmpty) return;
    }

    await db.transaction(() async {
      for (final c in later) {
        await (db.update(db.cycles)..where((t) => t.id.equals(c.id))).write(
          CyclesCompanion(
            deletedAt: Value(nowMs()),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
      }
      await (db.update(db.cycles)..where((t) => t.id.equals(cycle.id))).write(
        CyclesCompanion(
          completedAt: const Value(null),
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
