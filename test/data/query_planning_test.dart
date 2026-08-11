import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
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
  });
}
