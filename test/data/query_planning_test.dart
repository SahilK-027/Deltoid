import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The planner has to be given statistics, or it guesses — and on this schema
/// it guessed wrong in the most expensive place available.
///
/// Every index the app needs already existed. What was missing was the evidence
/// to use them: with no `sqlite_stat1`, the weekly volume query was planned as
/// a scan of every `workout_exercises` row ever written in order to answer a
/// question about the last seven days. That query re-runs every time a set is
/// ticked, so on a long history it was ~143ms of work per tick.
void main() {
  test('opening the database leaves the planner some statistics', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Enough rows to be worth analysing, written before the pragma runs.
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    final repo = TrainingRepository(db);
    final regime =
        await (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
            .getSingle();
    final session = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..limit(1))
        .getSingle();
    for (var i = 0; i < 5; i++) {
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: session.id,
        at: DateTime.now().subtract(Duration(days: 5 - i)),
      );
      await repo.completeWorkout(id);
    }

    // What `beforeOpen` does on a real launch. Asserted through the pragma
    // rather than by timing anything: a benchmark in the suite would be a test
    // that fails on a busy machine.
    await db.customStatement('PRAGMA optimize');

    final stats = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM sqlite_master "
          "WHERE type = 'table' AND name = 'sqlite_stat1'",
        )
        .getSingle();
    expect(
      stats.read<int>('c'),
      1,
      reason: 'no sqlite_stat1 means the planner is still guessing',
    );

    // And the query that pays for it is planned off the day index rather than
    // by scanning every snapshot row.
    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN '
          'SELECT e.muscle, COUNT(s.id) FROM set_logs s '
          '  INNER JOIN workout_exercises we ON we.id = s.workout_exercise_id '
          '  INNER JOIN workouts w ON w.id = we.workout_id '
          '  INNER JOIN exercises e ON e.id = we.exercise_id '
          "WHERE w.day_key >= 20260101 AND w.deleted_at IS NULL "
          '  AND we.deleted_at IS NULL AND s.is_done = 1 '
          'GROUP BY e.muscle',
        )
        .get();
    final detail = plan.map((r) => r.data['detail'].toString()).join(' | ');
    expect(
      detail,
      contains('idx_workouts_day'),
      reason: 'the seven-day window should be found on the day index: $detail',
    );
    // Cycle progress walks a whole regime, so it is driven from `cycles` —
    // `workouts.regime_id` carries no index, and the same question asked that
    // way is a scan of every workout ever logged. `idx_cycles_regime` finds the
    // regime's cycles and `idx_workouts_cycle` finds each cycle's workouts.
    //
    // Enough workouts for the planner to have an opinion worth holding: with a
    // handful of rows, scanning them is genuinely the cheaper plan and the
    // assertion below would be testing the size of the fixture rather than the
    // shape of the query.
    await db.batch((b) {
      b.insertAll(db.workouts, [
        for (var i = 0; i < 300; i++)
          () {
            // `day_key` and `started_at` are checked against each other by the
            // schema, so the two are named from one date rather than invented
            // separately.
            final day = DateTime.utc(2020, 1, 1 + i);
            return WorkoutsCompanion.insert(
              id: Value('bulk-$i'),
              regimeId: regime.id,
              dayKey: day.year * 10000 + day.month * 100 + day.day,
              startedAt: Value(day.millisecondsSinceEpoch),
              tzOffsetMinutes: 0,
              status: const Value(WorkoutStatus.completed),
            );
          }(),
      ]);
    });
    await db.customStatement('ANALYZE');

    final cyclePlan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN '
          'SELECT we.id, wo.day_key, e.load_mode '
          'FROM cycles c '
          '  INNER JOIN workouts wo ON wo.cycle_id = c.id '
          '  INNER JOIN workout_exercises we ON we.workout_id = wo.id '
          '  INNER JOIN exercises e ON e.id = we.exercise_id '
          "WHERE c.regime_id = ?1 AND c.deleted_at IS NULL "
          "  AND wo.deleted_at IS NULL AND wo.status = 'completed' "
          '  AND we.deleted_at IS NULL',
          variables: [Variable.withString(regime.id)],
        )
        .get();
    final cycleDetail =
        cyclePlan.map((r) => r.data['detail'].toString()).join(' | ');
    expect(
      cycleDetail,
      contains('idx_cycles_regime'),
      reason: "a regime's cycles should be found on their own index: "
          '$cycleDetail',
    );
    expect(
      cycleDetail,
      isNot(contains('SCAN wo')),
      reason: 'the workouts of a regime should be reached through its cycles '
          'rather than by scanning every workout ever logged: $cycleDetail',
    );
  });
}
