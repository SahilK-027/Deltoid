import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/enums.dart';
import '../../domain/metrics.dart';
import '../../domain/prefill.dart';
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

class HistoryCell {
  const HistoryCell({required this.sets, required this.skipReason});

  final List<SetLog> sets;
  final SkipReason skipReason;
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
    required this.exerciseCount,
    required this.setCount,
    required this.skippedCount,
  });

  final Workout workout;

  /// Null when the session template has since been deleted.
  final String? sessionName;

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

/// One session's history, shaped as a table: exercises down, dates across.
class SessionHistory {
  const SessionHistory({
    required this.workouts,
    required this.exerciseOrder,
    required this.exercises,
    required this.cells,
  });

  /// Newest first — the column order on screen.
  final List<Workout> workouts;

  final List<String> exerciseOrder;
  final Map<String, Exercise> exercises;

  /// workoutId → exerciseId → cell.
  final Map<String, Map<String, HistoryCell>> cells;

  bool get isEmpty => workouts.isEmpty;
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
  Future<List<PastPerformance>> pastPerformances(
    String exerciseId, {
    int limit = 60,
    String? excludeWorkoutId,
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
            isDeload: w.isDeload,
            sets: [
              for (final s in sets)
                if (s.isDone)
                  PastSet(
                    type: s.setType,
                    weight: s.weight,
                    reps: s.reps,
                    addedWeight: s.addedWeight,
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
  }) async {
    var predicate = db.workouts.status.equalsValue(WorkoutStatus.completed) &
        db.workouts.deletedAt.isNull();
    if (sessionId != null) {
      predicate = predicate & db.workouts.sessionId.equals(sessionId);
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
          ..where((t) => t.workoutId.isIn(workoutIds) & t.deletedAt.isNull()))
        .get();

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
          final mine = entries.where((e) => e.workoutId == w.id);
          return WorkoutSummary(
            workout: w,
            sessionName:
                w.sessionId == null ? null : sessionNames[w.sessionId!],
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
          ..where(db.workoutExercises.deletedAt.isNull() &
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

  /// Everything needed to render one session's history side by side.
  ///
  /// Rows are the union of every exercise ever done in this session, ordered by
  /// the most recent workout that contained them, so a swap made three weeks
  /// ago doesn't scramble the table.
  Future<SessionHistory> sessionHistory(String sessionId, {int limit = 12}) async {
    final workouts = await (db.select(db.workouts)
          ..where((t) =>
              t.sessionId.equals(sessionId) &
              t.status.equalsValue(WorkoutStatus.completed) &
              t.deletedAt.isNull())
          ..orderBy(_newestFirst)
          ..limit(limit))
        .get();

    if (workouts.isEmpty) {
      return const SessionHistory(
        workouts: [],
        exerciseOrder: [],
        exercises: {},
        cells: {},
      );
    }

    final workoutIds = workouts.map((w) => w.id).toList();
    final rows = await (db.select(db.workoutExercises).join([
      innerJoin(db.exercises, db.exercises.id.equalsExp(db.workoutExercises.exerciseId)),
    ])
          ..where(db.workoutExercises.workoutId.isIn(workoutIds) &
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

    final setsByWe = <String, List<SetLog>>{};
    for (final s in sets) {
      setsByWe.putIfAbsent(s.workoutExerciseId, () => []).add(s);
    }

    final exercises = <String, Exercise>{};
    final cells = <String, Map<String, HistoryCell>>{};
    final order = <String>[];

    // Walk newest first so the freshest layout wins the row order.
    for (final workout in workouts) {
      for (final r in rows) {
        final we = r.readTable(db.workoutExercises);
        if (we.workoutId != workout.id) continue;
        final exercise = r.readTable(db.exercises);
        exercises[exercise.id] = exercise;
        if (!order.contains(exercise.id)) order.add(exercise.id);
        cells.putIfAbsent(workout.id, () => {})[exercise.id] = HistoryCell(
          sets: setsByWe[we.id] ?? const [],
          skipReason: we.skipReason,
        );
      }
    }

    return SessionHistory(
      workouts: workouts,
      exerciseOrder: order,
      exercises: exercises,
      cells: cells,
    );
  }

  /// Bodyweight history, used to score bodyweight and BW+ lifts.
  Future<List<({int dayKey, double weightKg})>> bodyweightSeries() async {
    final rows = await (db.select(db.bodyweightLogs)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
        .get();
    return [for (final r in rows) (dayKey: r.dayKey, weightKg: r.weightKg)];
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
  Future<String> startWorkout({
    required String regimeId,
    required String sessionId,
  }) async {
    // A double tap on "Start" — or a screen that hasn't rebuilt yet — must not
    // open a second parallel log for the same session. Hand back the running
    // one instead; the sets already in it are the ones being asked for.
    final running = await openWorkout();
    if (running != null && running.sessionId == sessionId) return running.id;

    final regime =
        await (db.select(db.regimes)..where((t) => t.id.equals(regimeId))).getSingle();
    final cycle = await ensureOpenCycle(regimeId);
    final slots = await (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    final workoutId = newId();
    final now = DateTime.now();

    // Prefill is resolved before the transaction so the write stays short.
    final plans = <({SessionExercise slot, PrefillResult prefill})>[];
    for (final slot in slots) {
      final past = await pastPerformances(slot.exerciseId, limit: 30);
      plans.add((
        slot: slot,
        prefill: resolvePrefill(
          candidates: past,
          sessionId: sessionId,
          targetIsDeload: cycle.isDeload,
          deloadSetDelta: slot.deloadSetDelta ?? regime.deloadSetDelta,
          deloadWeightPct: slot.deloadWeightPct ?? regime.deloadWeightPct,
        ),
      ));
    }

    await db.transaction(() async {
      await db.into(db.workouts).insert(
            WorkoutsCompanion.insert(
              id: Value(workoutId),
              regimeId: regimeId,
              sessionId: Value(sessionId),
              cycleId: Value(cycle.id),
              dayKey: dayKeyOf(now),
              isDeload: Value(cycle.isDeload),
              status: const Value(WorkoutStatus.inProgress),
            ),
          );

      for (var i = 0; i < plans.length; i++) {
        final slot = plans[i].slot;
        final prefill = plans[i].prefill;

        var targetSets = slot.targetSets;
        if (cycle.isDeload) {
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
            ? prefill.sets.map((s) => s.type).toList()
            : List.filled(targetSets, SetType.working);

        for (var k = 0; k < shape.length; k++) {
          await db.into(db.setLogs).insert(
                SetLogsCompanion.insert(
                  id: Value(newId()),
                  workoutExerciseId: weId,
                  setIndex: k,
                  setType: Value(shape[k]),
                ),
              );
        }
      }
    });

    return workoutId;
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

  Stream<SessionHistory> watchSessionHistory(String sessionId, {int limit = 12}) {
    return db.watchQuery(
      [db.workouts, db.workoutExercises, db.setLogs],
      () => sessionHistory(sessionId, limit: limit),
    );
  }

  Stream<List<ExerciseHistorySummary>> watchExercisesWithHistory() {
    return db.watchQuery(
      [db.workouts, db.workoutExercises, db.exercises],
      exercisesWithHistory,
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
  }) async {
    await (db.update(db.setLogs)..where((t) => t.id.equals(setId))).write(
      SetLogsCompanion(
        weight: weight,
        reps: reps,
        addedWeight: addedWeight,
        setType: setType,
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
    final id = newId();
    await db.into(db.setLogs).insert(
          SetLogsCompanion.insert(
            id: Value(id),
            workoutExerciseId: workoutExerciseId,
            setIndex: existing.length,
            setType: Value(type),
          ),
        );
    return id;
  }

  Future<void> deleteSet(String setId) async {
    await (db.update(db.setLogs)..where((t) => t.id.equals(setId))).write(
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

  Future<String> addExerciseToWorkout(String workoutId, String exerciseId) async {
    final existing = await (db.select(db.workoutExercises)
          ..where((t) => t.workoutId.equals(workoutId) & t.deletedAt.isNull()))
        .get();
    final id = newId();
    await db.transaction(() async {
      await db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              id: Value(id),
              workoutId: workoutId,
              exerciseId: exerciseId,
              orderIndex: existing.length,
            ),
          );
      for (var k = 0; k < 3; k++) {
        await db.into(db.setLogs).insert(
              SetLogsCompanion.insert(
                id: Value(newId()),
                workoutExerciseId: id,
                setIndex: k,
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
      await (db.delete(db.setLogs)
            ..where((t) =>
                t.isDone.equals(false) &
                t.workoutExerciseId.isInQuery(
                  db.selectOnly(db.workoutExercises)
                    ..addColumns([db.workoutExercises.id])
                    ..where(db.workoutExercises.workoutId.equals(workoutId)),
                )))
          .go();

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

  /// Sessions with at least one completed workout, newest activity first.
  ///
  /// Deliberately not "the active regime's sessions": the side-by-side table is
  /// a history view, and switching regimes must not hide the history of the one
  /// that came before.
  Future<List<Session>> sessionsWithHistory() async {
    final lastTrained = db.workouts.startedAt.max();
    final rows = await (db.selectOnly(db.workouts)
          ..addColumns([db.workouts.sessionId, lastTrained])
          ..where(db.workouts.deletedAt.isNull() &
              db.workouts.sessionId.isNotNull() &
              db.workouts.status.equalsValue(WorkoutStatus.completed))
          ..groupBy([db.workouts.sessionId])
          ..orderBy([OrderingTerm(expression: lastTrained, mode: OrderingMode.desc)]))
        .get();
    if (rows.isEmpty) return const [];

    final ids = [for (final r in rows) r.read(db.workouts.sessionId)!];
    final sessions =
        await (db.select(db.sessions)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final s in sessions) s.id: s};

    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Stream<List<Session>> watchSessionsWithHistory() {
    return db.watchQuery(
      [db.workouts, db.sessions],
      sessionsWithHistory,
    );
  }
}
