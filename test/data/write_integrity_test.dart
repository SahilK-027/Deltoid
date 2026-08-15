import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/session_diff.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a write leaves behind when it is not the only one happening.
///
/// Two shapes of the same fault, both of which used to be reachable with a
/// thumb rather than with a debugger:
///
/// * **A position taken from a count.** Every "append" here read the number of
///   live rows and used it as the next `orderIndex`. Deletes are tombstones and
///   nothing renumbers behind them, so after one removal the count names a
///   position a surviving row still holds — and two rows on one index leave the
///   order to whichever way SQLite breaks the tie.
/// * **A look-up and a write that are not one act.** Find-then-insert across an
///   `await` lets a second caller find the same nothing and insert a second row.
///
/// Both matter more than they read: once sync lands, a duplicate index or a
/// second open cycle is not one phone's confusion, it is what gets pushed.
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

  void expectDistinct(List<int> indexes) {
    expect(indexes.toSet().length, indexes.length,
        reason: 'two rows share a position: $indexes');
  }

  group('a position is never reused', () {
    test('an exercise added after one is dropped mid-session', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);

      final before = (await repo.workoutDetail(workoutId))!;
      await repo
          .removeExerciseFromWorkout(before.entries[1].workoutExercise.id);
      final spare = await (db.select(db.exercises)..limit(1)).getSingle();
      await repo.addExerciseToWorkout(workoutId, spare.id);

      final after = (await repo.workoutDetail(workoutId))!;
      expectDistinct(
        [for (final e in after.entries) e.workoutExercise.orderIndex],
      );
    });

    test('a slot added to a session after one is removed', () async {
      final session = await sessionNamed('Push 1');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.removeSessionExercise(slots[1].id);

      final spare = await (db.select(db.exercises)
            ..where((t) =>
                t.id.isNotIn([for (final s in slots) s.exerciseId]))
            ..limit(1))
          .getSingle();
      await regimes.addExerciseToSession(session.id, spare.id);

      final live = await (db.select(db.sessionExercises)
            ..where(
                (t) => t.sessionId.equals(session.id) & t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in live) s.orderIndex]);
    });

    test('a session added after one is deleted', () async {
      final regime = await activeRegime();
      final sessions = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regime.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.deleteSession(sessions[1].id);
      await regimes.addSession(regime.id, 'Extra');

      final live = await (db.select(db.sessions)
            ..where(
                (t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in live) s.orderIndex]);
    });

    test('undoing a removed slot after another was added still finds a free '
        'position', () async {
      // The undo action is the only revival that kept the row's old position.
      // It only collides when the tombstone held the *highest* index, because
      // that is the one the append behind it then takes: remove the last slot
      // and the next append lands exactly where the buried row is pointing.
      final session = await sessionNamed('Push 1');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.removeSessionExercise(slots.last.id);

      final spare = await (db.select(db.exercises)
            ..where((t) => t.id.isNotIn([for (final s in slots) s.exerciseId]))
            ..limit(1))
          .getSingle();
      await regimes.addExerciseToSession(session.id, spare.id);

      await regimes.restoreSessionExercise(slots.last.id);

      final live = await (db.select(db.sessionExercises)
            ..where(
                (t) => t.sessionId.equals(session.id) & t.deletedAt.isNull()))
          .get();
      expect(
        live.map((s) => s.id),
        contains(slots.last.id),
        reason: 'the undo did not put the slot back',
      );
      expectDistinct([for (final s in live) s.orderIndex]);
    });

    test("keeping today's added movement, after one was removed before it",
        () async {
      final session = await sessionNamed('Push 1');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      await regimes.removeSessionExercise(slots[1].id);

      final spare = await (db.select(db.exercises)
            ..where((t) =>
                t.id.isNotIn([for (final s in slots) s.exerciseId]))
            ..limit(1))
          .getSingle();
      await repo.applySessionChanges(
        sessionId: session.id,
        changes: [
          SessionChange(
            kind: SessionChangeKind.added,
            exerciseIds: [spare.id],
            label: 'Added ${spare.name}',
          ),
        ],
      );

      final live = await (db.select(db.sessionExercises)
            ..where(
                (t) => t.sessionId.equals(session.id) & t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in live) s.orderIndex]);
    });
  });

  group('a look-up and its write are one act', () {
    test('two taps on + never share a set index', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      final entry = (await repo.workoutDetail(workoutId))!.entries.first;

      await Future.wait([
        repo.addSet(entry.workoutExercise.id),
        repo.addSet(entry.workoutExercise.id),
      ]);

      final sets = await (db.select(db.setLogs)
            ..where((t) =>
                t.workoutExerciseId.equals(entry.workoutExercise.id) &
                t.deletedAt.isNull()))
          .get();
      expectDistinct([for (final s in sets) s.setIndex]);
    });

    test('one day of bodyweight logged twice at once leaves one row', () async {
      final day = DateTime(2026, 8, 9);
      await Future.wait([
        repo.logBodyweight(day, 80),
        repo.logBodyweight(day, 81),
      ]);

      final rows = await (db.select(db.bodyweightLogs)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      expect(rows.length, 1);
    });

    test('two readers of a fresh regime open one cycle between them', () async {
      final regime = await activeRegime();

      // Today and the Regime screen both resolve the cycle, and on a regime
      // that has never been trained each of them found nothing to resolve.
      await Future.wait([
        repo.cycleStatus(regime.id),
        repo.cycleStatus(regime.id),
        repo.ensureOpenCycle(regime.id),
      ]);

      final open = await (db.select(db.cycles)
            ..where((t) =>
                t.regimeId.equals(regime.id) &
                t.completedAt.isNull() &
                t.deletedAt.isNull()))
          .get();
      expect(open.length, 1);
    });
  });

  test('a phone already carrying duplicate open cycles is healed', () async {
    final regime = await activeRegime();
    final keeper = (await repo.ensureOpenCycle(regime.id))!;

    // What the old, untransacted `ensureOpenCycle` left behind — and which
    // `idx_cycles_regime_open_live` now refuses outright, so the only way to
    // build the state the healer exists for is to stand the index down while
    // writing it. That is honest about where such a phone comes from: a build
    // that did not have the index, or a file written by one.
    //
    // The index is put back *after* the heal rather than before it, because a
    // unique index cannot be created over rows that already violate it — which
    // is the point: the successful rebuild at the end is itself the assertion
    // that the heal left a state the shipped schema accepts.
    await db.customStatement('DROP INDEX idx_cycles_regime_open_live');
    final stray = newId();
    await db.into(db.cycles).insert(
          CyclesCompanion.insert(
            id: Value(stray),
            regimeId: regime.id,
            cycleIndex: keeper.cycleIndex + 1,
          ),
        );
    final session = await sessionNamed('Push 1');
    final workoutId =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    // The workout attached itself to the stray, because that is the one
    // `ensureOpenCycle` hands back.
    await (db.update(db.workouts)..where((t) => t.id.equals(workoutId)))
        .write(WorkoutsCompanion(cycleId: Value(stray)));

    expect(await repo.healDuplicateOpenCycles(), 1);

    final open = await (db.select(db.cycles)
          ..where((t) =>
              t.regimeId.equals(regime.id) &
              t.completedAt.isNull() &
              t.deletedAt.isNull()))
        .get();
    expect(open.length, 1);
    expect(open.single.id, keeper.id);
    // Nothing logged under the stray is orphaned by its removal.
    final workout = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId)))
        .getSingle();
    expect(workout.cycleId, keeper.id);
    // And running it again on a healthy database does nothing.
    expect(await repo.healDuplicateOpenCycles(), 0);

    // The heal left a database the shipped schema accepts. A unique index
    // refuses to be built over rows that violate it, so this statement
    // completing is the assertion — and it is a stronger one than counting the
    // open cycles above, because it is the database's own opinion.
    await db.customStatement(
      'CREATE UNIQUE INDEX idx_cycles_regime_open_live '
      'ON cycles (regime_id) WHERE completed_at IS NULL AND deleted_at IS NULL',
    );
  });

  test('a second session cannot be opened while one is running', () async {
    final regime = await activeRegime();
    final push = await sessionNamed('Push 1');
    final pull = await sessionNamed('Pull 1');

    final running =
        await repo.startWorkout(regimeId: regime.id, sessionId: push.id);
    // The same session again is the double tap, and hands back the same log.
    expect(
      await repo.startWorkout(regimeId: regime.id, sessionId: push.id),
      running,
    );
    // A different one would be a second workout in progress, and `openWorkout`
    // only ever returns the newest — the older would be unreachable.
    expect(
      () => repo.startWorkout(regimeId: regime.id, sessionId: pull.id),
      throwsA(isA<StateError>()),
    );

    final open = await (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.inProgress) &
              t.deletedAt.isNull()))
        .get();
    expect(open.length, 1);
  });

  test('unticking a set takes its completion time with it', () async {
    final regime = await activeRegime();
    final session = await sessionNamed('Push 1');
    final workoutId =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    final set = (await repo.workoutDetail(workoutId))!.entries.first.sets.first;

    await repo.updateSet(set.id,
        weight: const Value(60), reps: const Value(8), isDone: const Value(true));
    expect(
      (await (db.select(db.setLogs)..where((t) => t.id.equals(set.id)))
              .getSingle())
          .completedAt,
      isNotNull,
    );

    await repo.updateSet(set.id, isDone: const Value(false));
    final after =
        await (db.select(db.setLogs)..where((t) => t.id.equals(set.id)))
            .getSingle();
    expect(after.isDone, isFalse);
    expect(after.completedAt, isNull);
  });

  // ── Applying a new order ────────────────────────────────────────────────
  //
  // A position is unique among live rows now, checked on every statement
  // rather than at the commit. So the obvious renumber — walk the list, write
  // `i` — puts the first row it moves onto a position a surviving row still
  // holds, and the whole reorder rolls back for a permutation that is
  // perfectly legal once it has finished. See `renumber`.

  group('a reorder lands whole', () {
    test('reversing a session\'s slots', () async {
      final session = await sessionNamed('Push 1');
      final before = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(before.length, greaterThan(2), reason: 'a permutation needs room');

      final reversed = before.reversed.map((s) => s.id).toList();
      await regimes.reorderSessionExercises(reversed);

      final after = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect([for (final s in after) s.id], reversed);
      expectDistinct([for (final s in after) s.orderIndex]);
      expect([for (final s in after) s.orderIndex],
          List.generate(after.length, (i) => i),
          reason: 'and it comes to rest on 0..n-1, not on the scratch range');
    });

    test('swapping the first two sessions of a regime', () async {
      final regime = await activeRegime();
      final before = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      final swapped = [before[1].id, before[0].id, for (final s in before.skip(2)) s.id];

      await regimes.reorderSessions(swapped);

      final after = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect([for (final s in after) s.id], swapped);
      expectDistinct([for (final s in after) s.orderIndex]);
    });

    test('reordering a workout after one of its exercises was dropped',
        () async {
      // The case a one-pass renumber survives least: the live rows are at
      // 0, 2, 3 and the new order wants them at 0, 1, 2.
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);

      final before = (await repo.workoutDetail(workoutId))!;
      await repo
          .removeExerciseFromWorkout(before.entries[1].workoutExercise.id);

      final live = (await repo.workoutDetail(workoutId))!.entries;
      final reversed =
          live.reversed.map((e) => e.workoutExercise.id).toList();
      await repo.reorderWorkoutExercises(reversed);

      final after = (await repo.workoutDetail(workoutId))!.entries;
      expect([for (final e in after) e.workoutExercise.id], reversed);
      expectDistinct([for (final e in after) e.workoutExercise.orderIndex]);
    });

    test('a reorder that omits a live row is refused rather than colliding',
        () async {
      // A partial list is not a permutation. The second pass brings the rows it
      // was handed down to 0..n-1, and a row it never saw is still standing in
      // that range — so today this dies on the unique index, several writes into
      // a transaction, with a message about nothing the caller did wrong.
      final session = await sessionNamed('Push 1');
      final live = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(live.length, greaterThan(2), reason: 'need a row to drop');

      final missingMiddle = [
        for (final s in live)
          if (s.id != live[1].id) s.id,
      ];
      await expectLater(
        regimes.reorderSessionExercises(missingMiddle),
        throwsA(isA<StateError>()),
      );
    });

    test('a reorder that omits the last live row is refused too', () async {
      // The half that fails quietly. The omitted row holds the highest position,
      // which is above everything the second pass writes, so nothing collides
      // and the reorder reports success — having renumbered a scope it only
      // partly knew about.
      final session = await sessionNamed('Push 1');
      final live = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(live.length, greaterThan(2), reason: 'need a row to drop');

      await expectLater(
        regimes.reorderSessionExercises(
            [for (final s in live.take(live.length - 1)) s.id]),
        throwsA(isA<StateError>()),
      );
    });

    test('an empty list is not a reorder', () async {
      await repo.reorderWorkoutExercises([]);
      await regimes.reorderSessions([]);
      await regimes.reorderSessionExercises([]);
    });
  });

  group('a bodyweight moved to another day', () {
    test('leaves nothing behind on the day it left', () async {
      final from = DateTime(2026, 3, 1);
      final to = DateTime(2026, 3, 2);
      await repo.logBodyweight(from, 80);

      await repo.logBodyweight(to, 80, replacing: from);

      final live = await (db.select(db.bodyweightLogs)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      expect(live.length, 1, reason: 'one entry, not two and not none');
      expect(live.single.dayKey, dayKeyOf(to));
      expect(live.single.weightKg, 80);
    });

    test('is one write, so it cannot half-happen', () async {
      final from = DateTime(2026, 3, 1);
      await repo.logBodyweight(from, 80);

      // A move onto a day that cannot hold the weight fails at the insert,
      // *after* the delete has run. Both have to come back together, or the
      // reading is gone from the day it was on and never arrived anywhere.
      await expectLater(
        repo.logBodyweight(DateTime(2026, 3, 2), 900, replacing: from),
        throwsA(isA<SqliteException>()),
      );

      final live = await (db.select(db.bodyweightLogs)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      expect(live.single.dayKey, dayKeyOf(from),
          reason: 'the failed move put it back where it was');
    });

    test('re-logging the same day is an edit, not a move', () async {
      final day = DateTime(2026, 3, 1);
      await repo.logBodyweight(day, 80);
      await repo.logBodyweight(day, 81, replacing: day);

      final live = await (db.select(db.bodyweightLogs)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      expect(live.single.weightKg, 81);
    });
  });

  group('a write says who wrote it and when', () {
    test('an update re-stamps the device, not just the insert', () async {
      // `clientDefault` only fires on an insert, so this column used to name
      // the row's creator for the rest of its life — and last-write-wins breaks
      // a same-millisecond tie on it, so both devices compared the same
      // originating id, found it equal, and each kept its own copy.
      final session = await sessionNamed('Push 1');
      await db
          .customStatement("UPDATE sessions SET device_id = 'another-phone'");

      await regimes.renameSession(session.id, 'Push A');

      final after = await (db.select(db.sessions)
            ..where((t) => t.id.equals(session.id)))
          .getSingle();
      expect(after.deviceId, currentDeviceId);
      expect(after.dirty, isTrue);
    });

    test('a clock that jumps backwards never issues an earlier stamp',
        () async {
      // The number last-write-wins compares. A clock moved back — a network
      // time correction after a flat battery, a manual change — would make a
      // row lose to the version it was written to replace.
      final stamps = [for (var i = 0; i < 500; i++) nowMs()];
      for (var i = 1; i < stamps.length; i++) {
        expect(stamps[i], greaterThan(stamps[i - 1]),
            reason: 'stamp $i went backwards or stood still');
      }
    });
  });

  group('finishing a workout that is no longer there', () {
    test('says so rather than throwing or pretending', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);

      expect(await repo.completeWorkout(workoutId), isTrue);

      await repo.deleteWorkout(workoutId);
      // Deleted from History while its own log was open. `getSingle` threw
      // here, which died in the gesture handler; returning nothing at all sent
      // the caller on to open a summary of a session that does not exist.
      expect(await repo.completeWorkout(workoutId), isFalse);
      expect(await repo.completeWorkout('no-such-workout'), isFalse);
    });
  });

  /// INVARIANTS.md § 2.
  ///
  /// The sweep exists for a mis-tapped Start: a workout with nothing in it,
  /// opened long enough ago that you are not coming back. It decided "long
  /// enough ago" from `startedAt` — the one column the app **deliberately
  /// moves into the past**, because backfilling last Tuesday's session is a
  /// thing this log has to let you do. A backfill was therefore already past
  /// the cutoff the instant it was created, and `sweepAbandonedWorkouts` runs
  /// before first paint on every launch.
  group('the sweep reads how long ago the row was written', () {
    Future<Workout> workoutRow(String id) =>
        (db.select(db.workouts)..where((t) => t.id.equals(id))).getSingle();

    test('a backdated session is not swept the moment it is created', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');

      // The backfill sheet: pick a date three weeks ago, get the log screen,
      // put the phone down without ticking anything. Android reclaims the
      // process; the next launch runs the sweep.
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: session.id,
        at: DateTime.now().subtract(const Duration(days: 21)),
      );

      expect(await repo.sweepAbandonedWorkouts(), 0,
          reason: 'a session you are backfilling has not been abandoned — it '
              'was opened seconds ago');

      final after = await workoutRow(id);
      expect(after.status, WorkoutStatus.inProgress);
      expect(after.deletedAt, isNull);
    });

    test('a session genuinely left open is still swept', () async {
      // The guard on the test above: the fix must narrow the sweep, not
      // disable it.
      final id = await repo.startWorkout(
        regimeId: (await activeRegime()).id,
        sessionId: (await sessionNamed('Push 1')).id,
      );
      await (db.update(db.workouts)..where((t) => t.id.equals(id))).write(
        WorkoutsCompanion(updatedAt: Value(nowMs() - const Duration(hours: 30).inMilliseconds)),
      );

      expect(await repo.sweepAbandonedWorkouts(), 1);
      expect((await workoutRow(id)).deletedAt, isNotNull);
    });
  });

  /// INVARIANTS.md § 1.
  ///
  /// **The rule is not "no live row under a tombstoned parent".** It is: a
  /// tombstoned row takes the rows that only exist to *describe* it, and never
  /// the rows that *record what was done*. `session_exercises` describe a
  /// session; `workouts` record training under it.
  ///
  /// So `deleteRegime` owes its cycles and must leave its sessions and its
  /// workouts exactly where they are — `deleteRegime`'s own doc says history
  /// stays in History as it was logged, and `loggedSessions` filters
  /// `sessions.deleted_at`, so cascading there would delete the only way to
  /// page a retired programme's history. Widening this group to "every foreign
  /// key" deletes training. The companion assertions below are what stop that.
  ///
  /// Invisible on this phone: every read that carries a number joins the parent
  /// and filters `deleted_at`. These are live rows carrying `dirty`, which is
  /// what the first sync push sends, and no tombstone will ever follow them.
  group('a tombstoned parent leaves nothing live beneath it', () {
    Future<int> countOf(String from) async => (await db
            .customSelect('SELECT COUNT(*) AS n FROM $from')
            .getSingle())
        .read<int>('n');

    /// Live `set_logs` under a tombstoned `workout_exercises`.
    Future<int> orphanedSets() => countOf(
          'set_logs s JOIN workout_exercises we ON we.id = s.workout_exercise_id '
          'WHERE s.deleted_at IS NULL AND we.deleted_at IS NOT NULL',
        );

    /// Live `workout_exercises` under a tombstoned `workouts`. The one
    /// `healOrphanedSnapshots` already repairs at launch — asserted here so the
    /// heal keeps working, not because it is open.
    Future<int> orphanedSnapshots() => countOf(
          'workout_exercises we JOIN workouts w ON w.id = we.workout_id '
          'WHERE we.deleted_at IS NULL AND w.deleted_at IS NOT NULL',
        );

    /// Live `session_exercises` under a tombstoned `sessions`.
    Future<int> orphanedSlots() => countOf(
          'session_exercises se JOIN sessions ss ON ss.id = se.session_id '
          'WHERE se.deleted_at IS NULL AND ss.deleted_at IS NOT NULL',
        );

    /// Live `cycles` under a tombstoned `regimes`.
    Future<int> orphanedCycles() => countOf(
          'cycles c JOIN regimes r ON r.id = c.regime_id '
          'WHERE c.deleted_at IS NULL AND r.deleted_at IS NOT NULL',
        );

    Future<void> expectNoOrphans() async {
      expect(await orphanedSets(), 0, reason: 'live sets under a dead slot');
      expect(await orphanedSnapshots(), 0,
          reason: 'live snapshots under a dead workout');
      expect(await orphanedSlots(), 0, reason: 'live slots under a dead session');
      expect(await orphanedCycles(), 0, reason: 'live cycles under a dead regime');
    }

    test('removing an exercise mid-session takes its sets', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);

      final before = (await repo.workoutDetail(workoutId))!;
      final slot = before.entries[1].workoutExercise;
      expect(before.entries[1].sets, isNotEmpty,
          reason: 'the fixture must have sets to orphan');

      await repo.removeExerciseFromWorkout(slot.id);

      await expectNoOrphans();
    });

    test('swapping an exercise takes the sets logged into the old one',
        () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);

      final before = (await repo.workoutDetail(workoutId))!;
      final slot = before.entries[1].workoutExercise;
      final logged = before.entries[1].sets.first;
      // Real work, not an empty row: this is the sequence that loses it —
      // two sets in, then a swap, and the sets stay live under a dead slot.
      await repo.updateSet(
        logged.id,
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );

      final spare = await (db.select(db.exercises)
            ..where((t) => t.id.isNotIn(
                [for (final e in before.entries) e.workoutExercise.exerciseId]))
            ..limit(1))
          .getSingle();
      await repo.replaceExerciseInWorkout(slot.id, spare.id);

      await expectNoOrphans();
    });

    test('deleting a training day takes its slots', () async {
      final session = await sessionNamed('Push 1');
      final slots = await (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(session.id) & t.deletedAt.isNull()))
          .get();
      expect(slots, isNotEmpty, reason: 'the fixture must have slots to orphan');

      await regimes.deleteSession(session.id);

      await expectNoOrphans();
    });

    test('deleting a programme takes its cycles and nothing else', () async {
      final regime = await activeRegime();
      final session = await sessionNamed('Push 1');
      final workoutId =
          await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
      await repo.completeWorkout(workoutId);
      expect(await repo.ensureOpenCycle(regime.id), isNotNull,
          reason: 'the fixture must have a cycle to orphan');

      await regimes.deleteRegime(regime.id);

      await expectNoOrphans();

      // The companion half, and the reason this test is not just the four
      // counts. A fix that cascades past `cycles` deletes the history the
      // programme was deleted to get away from.
      final liveWorkouts = await (db.select(db.workouts)
            ..where((t) =>
                t.regimeId.equals(regime.id) & t.deletedAt.isNull()))
          .get();
      expect(liveWorkouts.map((w) => w.id), contains(workoutId),
          reason: 'a deleted programme keeps its logged workouts');

      final liveSessions = await (db.select(db.sessions)
            ..where((t) =>
                t.regimeId.equals(regime.id) & t.deletedAt.isNull()))
          .get();
      expect(liveSessions.map((s) => s.id), contains(session.id),
          reason: 'a deleted programme keeps its sessions, or History loses '
              'the only way to page by them');
    });
  });
}
