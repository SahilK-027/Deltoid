import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/data/db/invariants.dart';
import 'package:deltoid/data/db/table_spec.dart';

import 'invariant_oracle.dart';

/// Two halves, and the second is the one that makes the first mean anything.
///
/// **The oracle holds over real work.** A run through the operations a phone
/// actually performs, asserting every rule after each one. This half is green
/// on arrival — every rule in it was already enforced before the oracle was
/// written, which is the point: gathering them changed no behaviour.
///
/// **The oracle can feel every break.** One test per rule, each building the
/// state that rule forbids and asserting the oracle names *that* rule. A judge
/// nobody has watched convict is an assertion that a `COUNT(*)` returned zero,
/// and a typo in a join makes it return zero forever. The perturbations are
/// written down instead of performed by hand once, because the fuzz harness
/// depends on this file being right rather than merely quiet.
///
/// Standing an index down to build a forbidden state is the shape
/// `test/data/write_integrity_test.dart` already uses, and it is honest about
/// where such a state comes from: a build without the index, a file written by
/// one, and after [SYNC.md](../../SYNC.md) a row another device pushed.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late RegimeRepository regimes;

  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    regimes = RegimeRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  Future<Regime> activeRegime() =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true))).getSingle();

  Future<Session> sessionNamed(String name) =>
      (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();

  /// The names the oracle reported, so a perturbation test can assert it caught
  /// the rule it aimed at rather than merely caught something.
  Future<List<String>> broken() async =>
      [for (final v in await invariantViolations(db)) v.rule];

  group('the oracle holds over real work', () {
    test('a seeded database is sound before anything is done', () async {
      await expectInvariants(db, after: 'seeding');
    });

    test('a full session: start, log, complete, reopen, delete', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');

      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      await expectInvariants(db, after: 'startWorkout');

      final detail = (await repo.workoutDetail(workoutId))!;
      await repo.updateSet(
        detail.entries.first.sets.first.id,
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );
      await expectInvariants(db, after: 'updateSet');

      await repo.addSet(detail.entries.first.workoutExercise.id);
      await expectInvariants(db, after: 'addSet');

      await repo.removeExerciseFromWorkout(detail.entries[1].workoutExercise.id);
      await expectInvariants(db, after: 'removeExerciseFromWorkout');

      final spare = await (db.select(db.exercises)
            ..where((t) => t.id.isNotIn(
                [for (final e in detail.entries) e.workoutExercise.exerciseId]))
            ..limit(1))
          .getSingle();
      await repo.addExerciseToWorkout(workoutId, spare.id);
      await expectInvariants(db, after: 'addExerciseToWorkout');

      await repo.completeWorkout(workoutId);
      await expectInvariants(db, after: 'completeWorkout');

      await repo.deleteWorkout(workoutId);
      await expectInvariants(db, after: 'deleteWorkout');
    });

    test('a programme edited under a logged history', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      await repo.completeWorkout(workoutId);

      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.removeSessionExercise(slots[1].id);
      await expectInvariants(db, after: 'removeSessionExercise');

      await regimes.reorderSessionExercises([
        for (final s in slots.reversed)
          if (s.id != slots[1].id) s.id,
      ]);
      await expectInvariants(db, after: 'reorderSessionExercises');

      await regimes.addSession(regime.id, 'Extra');
      await expectInvariants(db, after: 'addSession');

      await regimes.deleteSession(session.id);
      await expectInvariants(db, after: 'deleteSession');

      await regimes.deleteRegime(regime.id);
      await expectInvariants(db, after: 'deleteRegime');
    });

    test('bodyweight logged, moved and deleted', () async {
      await repo.logBodyweight(DateTime(2026, 3, 1), 80);
      await expectInvariants(db, after: 'logBodyweight');

      await repo.logBodyweight(DateTime(2026, 3, 2), 81,
          replacing: DateTime(2026, 3, 1));
      await expectInvariants(db, after: 'logBodyweight replacing');
    });

    test('a cycle advanced by training through a whole rotation', () async {
      final regime = await activeRegime();
      final sessions = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();

      for (final s in sessions) {
        final id = await repo.startWorkout(regimeId: regime.id, sessionId: s.id);
        final set = (await repo.workoutDetail(id))!.entries.first.sets.first;
        await repo.updateSet(set.id,
            weight: const Value(20),
            reps: const Value(8),
            isDone: const Value(true));
        await repo.completeWorkout(id);
        await expectInvariants(db, after: 'completing ${s.name}');
      }

      // The rotation closes the first cycle and opens the second beneath it.
      await repo.startWorkout(
          regimeId: regime.id, sessionId: sessions.first.id);
      await expectInvariants(db, after: 'opening the second cycle');
    });
  });

  group('the oracle can feel every break', () {
    /// A workout with one exercise and one set, for the tests that need a row
    /// under a row.
    Future<({String workoutId, String slotId, String setId})> logged() async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final id =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      final entry = (await repo.workoutDetail(id))!.entries.first;
      return (
        workoutId: id,
        slotId: entry.workoutExercise.id,
        setId: entry.sets.first.id,
      );
    }

    // ── Tombstone cascade ───────────────────────────────────────────────
    //
    // Nothing has to be stood down for these: the cascade is enforced by the
    // repository, so tombstoning a parent by hand is exactly the write a
    // half-finished cascade would leave.

    test('live sets under a dead slot', () async {
      final w = await logged();
      await (db.update(db.workoutExercises)
            ..where((t) => t.id.equals(w.slotId)))
          .write(WorkoutExercisesCompanion(deletedAt: Value(nowMs())));

      expect(await broken(), contains('live sets under a dead slot'));
    });

    test('live snapshots under a dead workout', () async {
      final w = await logged();
      await (db.update(db.workouts)..where((t) => t.id.equals(w.workoutId)))
          .write(WorkoutsCompanion(deletedAt: Value(nowMs())));

      expect(await broken(), contains('live snapshots under a dead workout'));
    });

    test('live slots under a dead session', () async {
      final session = await sessionNamed('Push 1');
      await (db.update(db.sessions)..where((t) => t.id.equals(session.id)))
          .write(SessionsCompanion(deletedAt: Value(nowMs())));

      expect(await broken(), contains('live slots under a dead session'));
    });

    test('live cycles under a dead regime', () async {
      final regime = await activeRegime();
      await repo.ensureOpenCycle(regime.id);
      await (db.update(db.regimes)..where((t) => t.id.equals(regime.id)))
          .write(RegimesCompanion(deletedAt: Value(nowMs())));

      expect(await broken(), contains('live cycles under a dead regime'));
    });

    test('live workouts naming a dead cycle', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      final cycleId = (await (db.select(db.workouts)
                ..where((t) => t.id.equals(workoutId)))
              .getSingle())
          .cycleId;
      expect(cycleId, isNotNull, reason: 'the fixture needs a cycle to kill');

      await (db.update(db.cycles)..where((t) => t.id.equals(cycleId!)))
          .write(CyclesCompanion(deletedAt: Value(nowMs())));

      expect(await broken(), contains('live workouts naming a dead cycle'));
    });

    test('a regime deleted with its cycles is NOT a violation', () async {
      // The other half of the rule above, and the reason it carries a
      // qualifier: a deleted programme keeps its logged workouts, so live
      // workouts naming dead cycles is the designed outcome there. An oracle
      // that flagged it would make every legitimate deletion look like
      // corruption, and the fuzz harness would stop on the first one.
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      await repo.completeWorkout(workoutId);

      await regimes.deleteRegime(regime.id);

      await expectInvariants(db, after: 'deleteRegime');
      final live = await (db.select(db.workouts)
            ..where((t) => t.id.equals(workoutId) & t.deletedAt.isNull()))
          .get();
      expect(live, hasLength(1),
          reason: 'the fixture must still hold the workout it kept');
    });

    // ── One position, one live row ──────────────────────────────────────

    test('two live sessions share a position', () async {
      final regime = await activeRegime();
      await db.customStatement('DROP INDEX idx_sessions_position_live');
      final first = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regime.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
            ..limit(2))
          .get();
      await (db.update(db.sessions)..where((t) => t.id.equals(first[1].id)))
          .write(SessionsCompanion(orderIndex: Value(first[0].orderIndex)));

      expect(await broken(), contains('two live sessions share a position'));
    });

    test('two live session slots share a position', () async {
      final session = await sessionNamed('Push 1');
      await db.customStatement('DROP INDEX idx_session_exercises_position_live');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
            ..limit(2))
          .get();
      await (db.update(db.sessionExercises)
            ..where((t) => t.id.equals(slots[1].id)))
          .write(
              SessionExercisesCompanion(orderIndex: Value(slots[0].orderIndex)));

      expect(
          await broken(), contains('two live session slots share a position'));
    });

    test('two live workout slots share a position', () async {
      final w = await logged();
      await db.customStatement('DROP INDEX idx_workout_exercises_position_live');
      final slots = await (db.select(db.workoutExercises)
            ..where((t) => t.workoutId.equals(w.workoutId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
            ..limit(2))
          .get();
      await (db.update(db.workoutExercises)
            ..where((t) => t.id.equals(slots[1].id)))
          .write(
              WorkoutExercisesCompanion(orderIndex: Value(slots[0].orderIndex)));

      expect(
          await broken(), contains('two live workout slots share a position'));
    });

    test('two live sets share a position', () async {
      final w = await logged();
      await db.customStatement('DROP INDEX idx_set_logs_position_live');
      final sets = await (db.select(db.setLogs)
            ..where((t) => t.workoutExerciseId.equals(w.slotId))
            ..orderBy([(t) => OrderingTerm(expression: t.setIndex)])
            ..limit(2))
          .get();
      expect(sets, hasLength(2), reason: 'the fixture needs two sets to collide');
      await (db.update(db.setLogs)..where((t) => t.id.equals(sets[1].id)))
          .write(SetLogsCompanion(setIndex: Value(sets[0].setIndex)));

      expect(await broken(), contains('two live sets share a position'));
    });

    // ── One live row where only one may exist ───────────────────────────

    test('a regime holds two open cycles', () async {
      final regime = await activeRegime();
      final keeper = (await repo.ensureOpenCycle(regime.id))!;
      await db.customStatement('DROP INDEX idx_cycles_regime_open_live');
      await db.into(db.cycles).insert(
            CyclesCompanion.insert(
              id: Value(newId()),
              regimeId: regime.id,
              cycleIndex: keeper.cycleIndex + 1,
            ),
          );

      expect(await broken(), contains('a regime holds two open cycles'));
    });

    test('two workouts are in progress at once', () async {
      final regime = await activeRegime();
      final push = await sessionNamed('Push 1');
      final pull = await sessionNamed('Pull 1');
      await repo.startWorkout(regimeId: regime.id, sessionId: push.id);

      await db.customStatement('DROP INDEX idx_workouts_single_open');
      // The second one has to be built by hand: `startWorkout` refuses it, and
      // that refusal is what this rule exists to keep true after a restore.
      final open = await (db.select(db.workouts)..limit(1)).getSingle();
      await db.into(db.workouts).insert(
            WorkoutsCompanion.insert(
              id: Value(newId()),
              regimeId: regime.id,
              sessionId: Value(pull.id),
              dayKey: open.dayKey,
              startedAt: Value(open.startedAt),
              tzOffsetMinutes: open.tzOffsetMinutes,
            ),
          );

      expect(await broken(), contains('two workouts are in progress at once'));
    });

    test('two regimes are active at once', () async {
      await db.customStatement('DROP INDEX idx_regimes_single_active');
      await db.customStatement('DROP INDEX idx_regimes_identity_live');
      final live = await activeRegime();
      await db.into(db.regimes).insert(
            RegimesCompanion.insert(
              id: Value(newId()),
              name: 'Second',
              identityIndex: Value(live.identityIndex + 1),
              isActive: const Value(true),
            ),
          );

      expect(await broken(), contains('two regimes are active at once'));
    });

    test('two live regimes wear one identity', () async {
      await db.customStatement('DROP INDEX idx_regimes_identity_live');
      final live = await activeRegime();
      await db.into(db.regimes).insert(
            RegimesCompanion.insert(
              id: Value(newId()),
              name: 'Second',
              identityIndex: Value(live.identityIndex),
            ),
          );

      expect(await broken(), contains('two live regimes wear one identity'));
    });

    test('two live cycles share an index', () async {
      final regime = await activeRegime();
      final keeper = (await repo.ensureOpenCycle(regime.id))!;
      await db.customStatement('DROP INDEX idx_cycles_regime_index_live');
      await db.customStatement('DROP INDEX idx_cycles_regime_open_live');
      await db.into(db.cycles).insert(
            CyclesCompanion.insert(
              id: Value(newId()),
              regimeId: regime.id,
              cycleIndex: keeper.cycleIndex,
            ),
          );

      expect(await broken(), contains('two live cycles share an index'));
    });

    test('a day carries two bodyweights', () async {
      final day = DateTime(2026, 3, 1);
      await repo.logBodyweight(day, 80);
      await db.customStatement('DROP INDEX idx_bodyweight_day_live');
      await db.into(db.bodyweightLogs).insert(
            BodyweightLogsCompanion.insert(
              id: Value(newId()),
              dayKey: dayKeyOf(day),
              weightKg: 81,
            ),
          );

      expect(await broken(), contains('a day carries two bodyweights'));
    });

    // ── A session is logged on one day ──────────────────────────────────

    test('a workout claims two different days', () async {
      final w = await logged();
      // A CHECK cannot be dropped, and a table rebuild would be a different
      // schema. Standing the constraints down for one statement is the same
      // fiction as dropping an index above: it produces the row a file from
      // another build could carry, without pretending the shipped schema would
      // have accepted it.
      await db.customStatement('PRAGMA ignore_check_constraints = ON');
      final before = await (db.select(db.workouts)
            ..where((t) => t.id.equals(w.workoutId)))
          .getSingle();
      await (db.update(db.workouts)..where((t) => t.id.equals(w.workoutId)))
          .write(WorkoutsCompanion(dayKey: Value(before.dayKey - 1)));
      await db.customStatement('PRAGMA ignore_check_constraints = OFF');

      expect(await broken(), contains('a workout claims two different days'));
    });

    // ── The columns a merge decides on ──────────────────────────────────
    //
    // Nothing else in the app looks at these. `updated_at` and `device_id` are
    // only ever *compared*, by `resolveRow`, which has no way to say the number
    // it is reading is absurd — so a row wrong in one of these ways is invisible
    // until it has already won a conflict it should have lost.

    test('a row is stamped at or before the epoch', () async {
      final regime = await activeRegime();
      // No CHECK holds `updated_at`, so this is a plain write rather than a
      // constraint stood down. That is the point: it is the one shape a build
      // that forgot a default, or a file written by one, arrives in.
      await db.customStatement(
        'UPDATE regimes SET updated_at = 0 WHERE id = ?',
        [regime.id],
      );

      expect(await broken(), contains(stampAtOrBeforeEpoch));
    });

    test('a row is stamped further ahead than any clock explains', () async {
      final regime = await activeRegime();
      final wall = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.customStatement(
        'UPDATE regimes SET updated_at = ? WHERE id = ?',
        [wall + stampSkewToleranceMs + 60 * 1000, regime.id],
      );

      expect(await broken(), contains(stampBeyondAnyClock));
    });

    test('the lease a launch writes is not called skew', () async {
      // The tolerance has to clear `stampLeaseMs`, or every phone would report
      // itself broken in the first minutes after a launch that clamped.
      final regime = await activeRegime();
      final wall = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.customStatement(
        'UPDATE regimes SET updated_at = ? WHERE id = ?',
        [wall + stampLeaseMs, regime.id],
      );

      expect(await broken(), isNot(contains(stampBeyondAnyClock)));
    });

    test('a row names no device', () async {
      final regime = await activeRegime();
      await db.customStatement(
        "UPDATE regimes SET device_id = '' WHERE id = ?",
        [regime.id],
      );

      expect(await broken(), contains(rowNamesNoDevice));
    });

    test('every syncable table is judged, not just the one with a test',
        () async {
      // The SQL is one UNION ALL per table, built from `tableSpecs`, so a table
      // added later is covered without anyone remembering. This is what says
      // the loop really ran over all of them.
      final tables = [
        for (final spec in tableSpecs(db))
          if (spec.syncs) spec.name,
      ];
      for (final table in tables) {
        await db.customStatement('UPDATE $table SET updated_at = 0');
      }

      final violations = await invariantViolations(db);
      final epoch = violations.firstWhere((v) => v.rule == stampAtOrBeforeEpoch);
      // Every table that had a row in it is named by one, and `detail` carries
      // which — a count alone would not say the union covered more than one.
      expect(epoch.count, greaterThan(1));
    });

    test('every rule has a test that has seen it fire', () {
      // The list this group must keep up with. A rule added to the oracle
      // without a perturbation is a `COUNT(*)` nobody has watched return
      // anything, which is indistinguishable from a typo in its join.
      const perturbed = {
        stampAtOrBeforeEpoch,
        stampBeyondAnyClock,
        rowNamesNoDevice,
        'live sets under a dead slot',
        'live snapshots under a dead workout',
        'live slots under a dead session',
        'live cycles under a dead regime',
        'live workouts naming a dead cycle',
        'two live sessions share a position',
        'two live session slots share a position',
        'two live workout slots share a position',
        'two live sets share a position',
        'a regime holds two open cycles',
        'two workouts are in progress at once',
        'two regimes are active at once',
        'two live regimes wear one identity',
        'two live cycles share an index',
        'a day carries two bodyweights',
        'a workout claims two different days',
      };
      expect(invariantRuleNames.toSet(), perturbed,
          reason: 'add the perturbation test, then add the name here');
    });

    test('every rule a repair claims to fix, or refuses to refuse, is a rule',
        () {
      expect(
        advisoryInvariants.difference(invariantRuleNames.toSet()),
        isEmpty,
        reason: 'advice cannot be given about a rule that does not exist',
      );
      // `healableInvariants` is what the restore subtracts before deciding
      // whether a file can be put back at all, so a name that no longer
      // matches a rule silently widens what a restore refuses — and the file it
      // starts refusing is one the app could have healed. Renaming a rule has
      // to rename it here too.
      expect(
        healableInvariants.keys.toSet().difference(invariantRuleNames.toSet()),
        isEmpty,
        reason: 'a repair cannot fix a rule that does not exist',
      );
      expect(
        unhealableInvariantNames
            .union(healableInvariants.keys.toSet())
            .union(advisoryInvariants),
        invariantRuleNames.toSet(),
        reason: 'every rule is on exactly one of the three lists',
      );
      expect(
        healableInvariants.keys.toSet().intersection(advisoryInvariants),
        isEmpty,
        reason: 'a rule a repair fixes is not merely advice',
      );
    });
  });
}
