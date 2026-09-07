import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/prefill.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltoid/domain/session_name.dart';

/// The rule every raw-SQL conversion in this repository is held to: an
/// unbounded query is only rewritten once a test has run the drift path and the
/// raw one over the same seeded data and found them identical field by field.
/// The drift implementations below are the ones `TrainingRepository` carried
/// before each rewrite, copied verbatim; they stay here because a parity test
/// whose reference implementation was deleted proves nothing on the next
/// change.
///
/// The second reason they stay: raw SQL gives up compile-time column names, so
/// a renamed column compiles and fails on a device. These read every column the
/// converted queries return.

/// [TrainingRepository.loggedDays] as it was: `selectOnly` plus four
/// `TypedResult.read` calls per day trained.
Future<List<LoggedDay>> loggedDaysViaDrift(AppDatabase db) async {
  final counted = db.workouts.id.count();
  final anyId = db.workouts.id.max();
  final deload = db.workouts.isDeload.cast<int>().max();

  final rows = await (db.selectOnly(db.workouts)
        ..addColumns([db.workouts.dayKey, counted, anyId, deload])
        ..where(db.workouts.status.equalsValue(WorkoutStatus.completed) &
            db.workouts.deletedAt.isNull())
        ..groupBy([db.workouts.dayKey])
        ..orderBy([OrderingTerm(expression: db.workouts.dayKey)]))
      .get();

  return [
    for (final r in rows)
      if (r.read(anyId) != null)
        LoggedDay(
          dayKey: r.read(db.workouts.dayKey)!,
          workouts: r.read(counted) ?? 0,
          isDeload: (r.read(deload) ?? 0) != 0,
          anyWorkoutId: r.read(anyId)!,
        ),
  ];
}

/// [TrainingRepository.bodyweightSeries] as it was: whole `BodyweightLog` row
/// objects, every column of them, to read two.
Future<List<({int dayKey, double weightKg})>> bodyweightSeriesViaDrift(
  AppDatabase db,
) async {
  final rows = await (db.select(db.bodyweightLogs)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
      .get();
  return [for (final r in rows) (dayKey: r.dayKey, weightKg: r.weightKg)];
}

/// `TrainingRepository._performances` as it was: a drift join hydrating whole
/// `WorkoutExercise`, `Workout` and `Session` rows, then a second query
/// gathering set logs with `WHERE workout_exercise_id IN (…)` — one bound
/// parameter per performance — a statement thousands of variables wide on a
/// long history.
Future<List<PastPerformance>> performancesViaDrift(
  AppDatabase db,
  String exerciseId, {
  required int? limit,
  String? excludeWorkoutId,
  String? sessionId,
}) async {
  final q = db.select(db.workoutExercises).join([
    innerJoin(
        db.workouts, db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
    leftOuterJoin(
        db.sessions, db.sessions.id.equalsExp(db.workouts.sessionId)),
  ])
    ..where(db.workoutExercises.exerciseId.equals(exerciseId) &
        db.workoutExercises.deletedAt.isNull() &
        db.workouts.deletedAt.isNull() &
        db.workouts.status.equalsValue(WorkoutStatus.completed))
    ..orderBy([
      OrderingTerm(
          expression: db.workouts.startedAt, mode: OrderingMode.desc),
    ]);
  if (limit != null) q.limit(limit);
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
          slotId: we.id,
          sessionId: w.sessionId,
          sessionName: session?.name ?? unplannedSessionName,
          dayKey: w.dayKey,
          startedAt: w.startedAt,
          isDeload: w.isDeload,
          skipReason: we.skipReason,
          sets: [
            for (final s in sets)
              if (s.isDone)
                PastSet(
                  type: s.setType,
                  weight: s.weight,
                  reps: s.reps,
                  partialReps: s.partialReps,
                  addedWeight: s.addedWeight,
                  isLeg: s.parentSetId != null,
                ),
          ],
        );
      }(),
  ];
}

void main() {
  late AppDatabase db;
  late TrainingRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
  });

  tearDown(() => db.close());

  /// A history with every shape the two queries have to distinguish: several
  /// workouts on one day, a deload day, an abandoned workout, a deleted one,
  /// and days with nothing on them at all.
  Future<void> seedHistory() async {
    final regime =
        await (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
            .getSingle();
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    final base = DateTime(2026, 3, 2);
    for (var i = 0; i < 8; i++) {
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: sessions[i % sessions.length].id,
        at: base.add(Duration(days: i)),
      );
      await repo.completeWorkout(id);
    }
    // Two on the same day, so a day's count is not always one.
    final twice = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: sessions[1].id,
      at: base,
    );
    await repo.completeWorkout(twice);

    // One day marked as a light week — `is_deload` is per workout and the
    // day-level answer is "was any of them".
    await (db.update(db.workouts)
          ..where((t) => t.dayKey.equals(20260304)))
        .write(const WorkoutsCompanion(isDeload: Value(true)));

    // An abandoned workout and a deleted one: neither is a day trained.
    final abandoned = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: sessions[2].id,
      at: base.add(const Duration(days: 20)),
    );
    await repo.abandonWorkout(abandoned);
    final deleted = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: sessions[3].id,
      at: base.add(const Duration(days: 21)),
    );
    await repo.completeWorkout(deleted);
    await repo.deleteWorkout(deleted);

    for (var i = 0; i < 6; i++) {
      await repo.logBodyweight(base.add(Duration(days: i * 3)), 80.0 + i * 0.4);
    }
    // A deleted weigh-in, which neither path may return.
    await repo.logBodyweight(base.add(const Duration(days: 40)), 99.9);
    await repo.deleteBodyweight(20260411);
  }

  test('loggedDays returns exactly what the drift query returned', () async {
    await seedHistory();

    final was = await loggedDaysViaDrift(db);
    final now = await repo.loggedDays();

    expect(was, isNotEmpty, reason: 'a parity test over no rows proves nothing');
    expect(now.length, was.length);
    for (var i = 0; i < was.length; i++) {
      expect(now[i].dayKey, was[i].dayKey, reason: 'row $i dayKey');
      expect(now[i].workouts, was[i].workouts, reason: 'row $i workouts');
      expect(now[i].isDeload, was[i].isDeload, reason: 'row $i isDeload');
      expect(now[i].anyWorkoutId, was[i].anyWorkoutId,
          reason: 'row $i anyWorkoutId');
    }
  });

  test('loggedDays reads every column it names', () async {
    await seedHistory();
    final days = await repo.loggedDays();

    // Hand-checked against the seed above: eight consecutive days from
    // 2026-03-02, the first of them logged twice, the third of them a deload.
    expect(days.map((d) => d.dayKey).toList(), [
      20260302,
      20260303,
      20260304,
      20260305,
      20260306,
      20260307,
      20260308,
      20260309,
    ]);
    expect(days.first.workouts, 2);
    expect(days.map((d) => d.isDeload).toList(),
        [false, false, true, false, false, false, false, false]);
    // The id has to be a real workout, or the calendar opens a screen saying
    // the session is gone.
    for (final d in days) {
      expect(
        await (db.select(db.workouts)..where((t) => t.id.equals(d.anyWorkoutId)))
            .getSingleOrNull(),
        isNotNull,
        reason: 'day ${d.dayKey} points at a workout that does not exist',
      );
    }
  });

  test('loggedDays agrees with the drift query on an empty history', () async {
    expect(await repo.loggedDays(), await loggedDaysViaDrift(db));
    expect(await repo.loggedDays(), isEmpty);
  });

  test('bodyweightSeries returns exactly what the drift query returned',
      () async {
    await seedHistory();

    final was = await bodyweightSeriesViaDrift(db);
    final now = await repo.bodyweightSeries();

    expect(was, isNotEmpty);
    expect(now.length, was.length);
    for (var i = 0; i < was.length; i++) {
      expect(now[i].dayKey, was[i].dayKey, reason: 'row $i dayKey');
      expect(now[i].weightKg, was[i].weightKg, reason: 'row $i weightKg');
    }
  });

  test('bodyweightSeries reads every column it names', () async {
    await seedHistory();
    final series = await repo.bodyweightSeries();

    // Six weigh-ins three days apart from 2026-03-02 at 80.0 + 0.4 each, and a
    // seventh deleted on 2026-04-11.
    expect(series.map((r) => r.dayKey).toList(),
        [20260302, 20260305, 20260308, 20260311, 20260314, 20260317]);
    expect(series.map((r) => r.weightKg).toList(),
        [80.0, 80.4, 80.8, 81.2, 81.6, 82.0]);
  });

  test('bodyweightSeries agrees with the drift query on an empty history',
      () async {
    expect(await repo.bodyweightSeries(), await bodyweightSeriesViaDrift(db));
    expect(await repo.bodyweightSeries(), isEmpty);
  });

  // ── pastPerformances ────────────────────────────────────────────────────

  void expectSame(
    List<PastPerformance> now,
    List<PastPerformance> was, {
    required String reason,
  }) {
    expect(now.length, was.length, reason: '$reason: length');
    for (var i = 0; i < was.length; i++) {
      final a = now[i], b = was[i];
      expect(a.workoutId, b.workoutId, reason: '$reason: row $i workoutId');
      expect(a.slotId, b.slotId, reason: '$reason: row $i slotId');
      expect(a.sessionId, b.sessionId, reason: '$reason: row $i sessionId');
      expect(a.sessionName, b.sessionName, reason: '$reason: row $i name');
      expect(a.dayKey, b.dayKey, reason: '$reason: row $i dayKey');
      expect(a.startedAt, b.startedAt, reason: '$reason: row $i startedAt');
      expect(a.isDeload, b.isDeload, reason: '$reason: row $i isDeload');
      expect(a.skipReason, b.skipReason, reason: '$reason: row $i skipReason');
      expect(a.sets.length, b.sets.length, reason: '$reason: row $i sets');
      for (var j = 0; j < b.sets.length; j++) {
        final x = a.sets[j], y = b.sets[j];
        expect(x.type, y.type, reason: '$reason: row $i set $j type');
        expect(x.weight, y.weight, reason: '$reason: row $i set $j weight');
        expect(x.reps, y.reps, reason: '$reason: row $i set $j reps');
        expect(x.partialReps, y.partialReps,
            reason: '$reason: row $i set $j partialReps');
        expect(x.addedWeight, y.addedWeight,
            reason: '$reason: row $i set $j addedWeight');
        expect(x.isLeg, y.isLeg, reason: '$reason: row $i set $j isLeg');
      }
    }
  }

  /// Several performances of one movement, carrying every field the two paths
  /// have to agree on: a drop leg, partial reps, an untouched set, a deleted
  /// set, a skipped slot, a deload, an ad-hoc workout with no session, and a
  /// deleted workout that neither path may return.
  Future<String> seedPerformances() async {
    final regime =
        await (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
            .getSingle();
    final push1 = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();
    late String exerciseId;
    for (var i = 0; i < 4; i++) {
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: push1.id,
        at: DateTime(2026, 4, 1 + i, 9),
      );
      final detail = await repo.workoutDetail(id);
      final entry = detail!.entries.first;
      exerciseId = entry.exercise.id;

      await repo.updateSet(
        entry.sets.first.id,
        weight: Value(60 + i * 2.5),
        reps: const Value(8),
        partialReps: Value(i == 1 ? 2 : null),
        isDone: const Value(true),
      );
      if (i == 1) {
        // A drop leg hangs off the set above it and comes back as `isLeg`.
        final legId = await repo.addDropLeg(
          entry.workoutExercise.id,
          headSetId: entry.sets.first.id,
        );
        await repo.updateSet(legId,
            weight: const Value(40), reps: const Value(6),
            isDone: const Value(true));
      }
      if (i == 2) {
        // Logged then deleted: gone from both paths.
        await repo.deleteSet(entry.sets[1].id);
      }
      if (i == 3) {
        // Sets logged before the slot was marked skipped still happened.
        await repo.setSkipReason(entry.workoutExercise.id, SkipReason.injury);
        await (db.update(db.workouts)..where((t) => t.id.equals(id)))
            .write(const WorkoutsCompanion(isDeload: Value(true)));
      }
      await repo.completeWorkout(id);
    }

    // An ad-hoc workout — no session behind it, so `sessionName` falls back.
    final adhoc = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: push1.id,
      at: DateTime(2026, 4, 9, 9),
    );
    await (db.update(db.workouts)..where((t) => t.id.equals(adhoc)))
        .write(const WorkoutsCompanion(sessionId: Value(null)));
    final adhocDetail = await repo.workoutDetail(adhoc);
    await repo.updateSet(adhocDetail!.entries.first.sets.first.id,
        weight: const Value(70), reps: const Value(5),
        isDone: const Value(true));
    await repo.completeWorkout(adhoc);

    final deleted = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: push1.id,
      at: DateTime(2026, 4, 10, 9),
    );
    await repo.completeWorkout(deleted);
    await repo.deleteWorkout(deleted);

    return exerciseId;
  }

  test('pastPerformances returns exactly what the drift queries returned',
      () async {
    final exerciseId = await seedPerformances();
    final push1 = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();

    final windowed = await repo.pastPerformances(exerciseId, limit: 3);
    expect(windowed, hasLength(3), reason: 'the horizon has to be real');
    expectSame(
      windowed,
      await performancesViaDrift(db, exerciseId, limit: 3),
      reason: 'limit 3',
    );

    // The unbounded call: the one the IN list could have blown up on.
    expectSame(
      await repo.pastPerformances(exerciseId, limit: null),
      await performancesViaDrift(db, exerciseId, limit: null),
      reason: 'limit null',
    );

    // Both optional predicates, since each one changes the statement.
    final excluded = (await repo.pastPerformances(exerciseId)).first.workoutId;
    expectSame(
      await repo.pastPerformances(exerciseId, excludeWorkoutId: excluded),
      await performancesViaDrift(db, exerciseId,
          limit: 60, excludeWorkoutId: excluded),
      reason: 'excludeWorkoutId',
    );
    // `pastPerformances` merges two queries when a session is named, so this
    // one is held against the merge of the same two drift calls.
    final byDrift = <String, PastPerformance>{
      for (final p in await performancesViaDrift(db, exerciseId, limit: 60))
        p.slotId: p,
    };
    for (final p in await performancesViaDrift(db, exerciseId,
        limit: 5, sessionId: push1.id)) {
      byDrift.putIfAbsent(p.slotId, () => p);
    }
    final merged = byDrift.values.toList()
      ..sort((a, b) {
        final byStart = b.startedAt.compareTo(a.startedAt);
        return byStart != 0 ? byStart : a.slotId.compareTo(b.slotId);
      });
    expectSame(
      await repo.pastPerformances(exerciseId, sessionId: push1.id),
      merged,
      reason: 'sessionId',
    );
  });

  test('pastPerformances reads every column it names', () async {
    final exerciseId = await seedPerformances();
    final all = await repo.pastPerformances(exerciseId, limit: null);

    // Five performances, newest first: the ad-hoc one on 2026-04-09, then the
    // four seeded 2026-04-04 back to 2026-04-01. The deleted workout is gone.
    expect(all.map((p) => p.dayKey).toList(),
        [20260409, 20260404, 20260403, 20260402, 20260401]);
    expect(all.first.sessionId, isNull);
    expect(all.first.sessionName, unplannedSessionName);
    expect(all.map((p) => p.isDeload).toList(),
        [false, true, false, false, false]);
    expect(all.map((p) => p.skipReason).toList(), [
      SkipReason.none,
      SkipReason.injury,
      SkipReason.none,
      SkipReason.none,
      SkipReason.none,
    ]);
    expect(all.every((p) => p.slotId.isNotEmpty), isTrue);
    expect(all.every((p) => p.startedAt > 0), isTrue);

    // 2026-04-02 is the one with partials and a drop leg.
    final second = all.firstWhere((p) => p.dayKey == 20260402);
    expect(second.sets.map((s) => s.weight).toList(), [62.5, 40.0]);
    expect(second.sets.map((s) => s.reps).toList(), [8, 6]);
    expect(second.sets.map((s) => s.partialReps).toList(), [2, null]);
    expect(second.sets.map((s) => s.isLeg).toList(), [false, true]);
    expect(second.sets.first.type, SetType.working);
  });
}
