import 'package:deltoid/core/failure.dart';
import 'package:deltoid/core/progress.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/invariants.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/pull.dart';
import 'package:deltoid/data/sync/sync_backend.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'two_devices.dart';

/// The pull applier, against two phones and one account.
///
/// Every test here is a row of
/// [SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does) or of
/// [§ 9](SYNC.md#9-collision--two-rows-one-slot). The list claims to be
/// exhaustive as far as the schema can be reasoned about, so a later change
/// that breaks one fails a build rather than a history.
void main() {
  late TwoDevices devices;
  late AppDatabase a;
  late AppDatabase b;

  setUp(() {
    devices = TwoDevices();
    a = devices.a;
    b = devices.b;
  });
  tearDown(() => devices.close());

  /// A programme on phone A, pushed, and pulled down onto phone B — the state
  /// most of these tests start from: two phones agreeing about everything.
  Future<void> bothInStep() async {
    await devices.as('device-a', () async {
      await ensureStarterCatalog(a);
      await createRegimeFromTemplate(
        a,
        regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
      );
    });
    await devices.push(a);
    await devices.pull(b);
  }

  Future<Session> sessionNamed(AppDatabase db, String name) =>
      (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();

  Future<Regime> activeRegime(AppDatabase db) =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true))).getSingle();

  group('the ordinary case', () {
    test('a new phone takes the account whole', () async {
      await devices.as('device-a', () async {
        await ensureStarterCatalog(a);
        await createRegimeFromTemplate(
          a,
          regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
        );
      });
      await devices.push(a);

      final report = await devices.pull(b);

      expect(report.applied, greaterThan(0));
      expect(report.skipped, 0);
      expect(await devices.rowsOf(b), await devices.rowsOf(a));
    });

    test('a pulled row lands settled, owing nothing', () async {
      await bothInStep();

      final owed = await b
          .customSelect('SELECT COUNT(*) AS n FROM exercises WHERE dirty = 1')
          .map((row) => row.read<int>('n'))
          .getSingle();
      expect(
        owed,
        0,
        reason: 'a pull down the ordinary write path would stamp every row as '
            'locally owed and push them all straight back',
      );
    });

    test('the cursor moves, and a second pull re-reads only the boundary',
        () async {
      await bothInStep();
      final before = await devices.rowsOf(b);

      final again = await devices.pull(b);

      // **Not zero, and deliberately.** The cursor compares `>=`, so the row
      // stamped exactly on it comes back — which is the point: a strict `>`
      // would drop whichever row fell on the far side of a page boundary,
      // silently, once, with no second chance. Re-reading it costs an upsert
      // that is idempotent anyway, and this asserts that idempotence rather
      // than a count of zero it must not have.
      expect(again.applied, lessThanOrEqualTo(1));
      expect(again.skipped, 0);
      expect(await devices.rowsOf(b), before);

      final cursor = await (b.select(b.appSettings)
            ..where((t) => t.key.equals(lastPullKey)))
          .getSingleOrNull();
      expect(cursor, isNotNull);
    });

    test('§ 12 row 1 — two devices edit different rows: union', () async {
      await bothInStep();

      await devices.as('device-a', () async {
        await RegimeRepository(a)
            .renameSession((await sessionNamed(a, 'Push 1')).id, 'Push A');
      });
      await devices.as('device-b', () async {
        await RegimeRepository(b)
            .renameSession((await sessionNamed(b, 'Pull 1')).id, 'Pull B');
      });

      await devices.converge();

      for (final db in [a, b]) {
        expect((await sessionNamed(db, 'Push A')).name, 'Push A');
        expect((await sessionNamed(db, 'Pull B')).name, 'Pull B');
      }
    });
  });

  group('§ 8 — two versions of one row', () {
    test('a clean local row takes the server\'s version', () async {
      await bothInStep();
      final id = (await sessionNamed(a, 'Push 1')).id;

      await devices.as('device-a', () => RegimeRepository(a).renameSession(id, 'Push A'));
      await devices.push(a);
      await devices.pull(b);

      expect((await sessionNamed(b, 'Push A')).id, id);
    });

    test('a newer unpushed local edit survives the pull and is then sent',
        () async {
      await bothInStep();
      final id = (await sessionNamed(a, 'Push 1')).id;

      // A edits and pushes; B edits the same row *later* and has not pushed.
      await devices.as('device-a', () => RegimeRepository(a).renameSession(id, 'From A'));
      await devices.push(a);
      await devices.as('device-b', () => RegimeRepository(b).renameSession(id, 'From B'));

      final report = await devices.pull(b);
      expect(report.kept, greaterThan(0));
      expect((await sessionNamed(b, 'From B')).id, id);

      // And the account learns about it, because the row stayed dirty.
      await devices.push(b);
      await devices.pull(a);
      expect((await sessionNamed(a, 'From B')).id, id);
    });

    test('§ 12 row 10 — a month offline loses to a newer server row', () async {
      await bothInStep();
      final id = (await sessionNamed(a, 'Push 1')).id;

      // B edited it long ago and never got signal.
      await devices.as('device-b', () => RegimeRepository(b).renameSession(id, 'Stale'));
      await b.customUpdate(
        'UPDATE sessions SET updated_at = ? WHERE id = ?',
        variables: [Variable<int>(1000), Variable<String>(id)],
        updates: {b.sessions},
      );

      await devices.as('device-a', () => RegimeRepository(a).renameSession(id, 'Fresh'));
      await devices.push(a);
      await devices.pull(b);

      expect((await sessionNamed(b, 'Fresh')).id, id);
    });
  });

  group('§ 9 — two rows, one slot', () {
    test('both phones append a set: both live, on different indexes', () async {
      await bothInStep();

      final workoutId = await devices.as('device-a', () async {
        final regime = await activeRegime(a);
        final push1 = await sessionNamed(a, 'Push 1');
        return TrainingRepository(a)
            .startWorkout(regimeId: regime.id, sessionId: push1.id);
      });
      await devices.push(a);
      await devices.pull(b);

      final slot = await (a.select(a.workoutExercises)
            ..where((t) => t.workoutId.equals(workoutId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
            ..limit(1))
          .getSingle();

      // Both phones add a set to the same exercise, offline, and both compute
      // the same next index.
      await devices.as('device-a', () => TrainingRepository(a).addSet(slot.id));
      await devices.as('device-b', () => TrainingRepository(b).addSet(slot.id));

      await devices.converge();

      for (final db in [a, b]) {
        final sets = await (db.select(db.setLogs)
              ..where((t) =>
                  t.workoutExerciseId.equals(slot.id) & t.deletedAt.isNull()))
            .get();
        final indexes = sets.map((s) => s.setIndex).toList();
        expect(
          indexes.toSet().length,
          indexes.length,
          reason: 'two rows on one index is what the unique index refuses',
        );
      }
      expect(await devices.rowsOf(b), await devices.rowsOf(a),
          reason: 'both devices must reach the same answer, not each their own');
    });

    test('§ 12 row 4 — both start a session: newer open, older completed',
        () async {
      await bothInStep();
      final regimeA = await activeRegime(a);
      final push1A = await sessionNamed(a, 'Push 1');
      final regimeB = await activeRegime(b);
      final push2B = await sessionNamed(b, 'Push 2');

      await devices.as('device-a', () async {
        await TrainingRepository(a)
            .startWorkout(regimeId: regimeA.id, sessionId: push1A.id);
      });
      await devices.as('device-b', () async {
        await TrainingRepository(b)
            .startWorkout(regimeId: regimeB.id, sessionId: push2B.id);
      });

      await devices.converge();

      for (final db in [a, b]) {
        final open = await (db.select(db.workouts)
              ..where((t) =>
                  t.status.equalsValue(WorkoutStatus.inProgress) &
                  t.deletedAt.isNull()))
            .get();
        expect(open.length, 1, reason: 'one session is open at a time');
        final all = await (db.select(db.workouts)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        expect(all.length, 2, reason: 'the older one is completed, not deleted');
      }
    });

    test('§ 12 row 5 — both activate a regime: LWW on the flag, both survive',
        () async {
      await bothInStep();

      await devices.as('device-b', () async {
        await createRegimeFromTemplate(
          b,
          regimeTemplates.firstWhere((t) => t.key == 'blank'),
        );
      });

      await devices.converge();

      for (final db in [a, b]) {
        final live =
            await (db.select(db.regimes)..where((t) => t.deletedAt.isNull()))
                .get();
        expect(live.length, 2, reason: 'the losing regime survives');
        expect(live.where((r) => r.isActive).length, 1);
        expect(
          live.map((r) => r.identityIndex).toSet().length,
          2,
          reason: 'and they do not share a hue',
        );
      }
      expect(await devices.rowsOf(b), await devices.rowsOf(a));
    });

    test('one phone activates while the other deletes: the flag still settles',
        () async {
      // **The active flag is one answer spread across every row.** Activating a
      // regime deactivates another, which is two rows moving for one decision,
      // and last-write-wins is defined on one row at a time. Resolving it
      // pairwise — each arriving row against whatever was active locally when
      // it landed — made the answer depend on arrival order, and two phones
      // pulling in different orders settled on opposite regimes. Nothing then
      // corrected them: the losing side's deactivation minted no version on
      // purpose, so both phones held one version of the row and two values of
      // the flag, and each looked up to date to the other forever.
      //
      // `sync_fuzz_test` seeds 41, 146, 335 and 531, all shrinking to this
      // shape: an activation on one phone against a delete on the other, which
      // promotes a successor and perturbs the order just enough.
      await bothInStep();

      await devices.as('device-a', () async {
        await createRegimeFromTemplate(
          a,
          regimeTemplates.firstWhere((t) => t.key == 'blank'),
          name: 'A side',
          activate: false,
        );
      });
      await devices.converge();

      final spare = await (a.select(a.regimes)
            ..where((t) => t.name.equals('A side')))
          .getSingle();
      await devices.as('device-a', () => RegimeRepository(a).setActiveRegime(spare.id));

      final onB = await (b.select(b.regimes)
            ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true))
            ..limit(1))
          .getSingle();
      await devices.as('device-b', () => RegimeRepository(b).deleteRegime(onB.id));

      await devices.converge();

      // Convergence is the assertion — `rowsOf` compares every column of every
      // row, so a flag that disagrees fails here whatever else is true.
      expect(await devices.rowsOf(b), await devices.rowsOf(a));

      for (final db in [a, b]) {
        final live =
            await (db.select(db.regimes)..where((t) => t.deletedAt.isNull()))
                .get();
        expect(live.where((r) => r.isActive).length, 1,
            reason: 'exactly one live regime is being trained');
        expect(await invariantViolations(db), isEmpty);
      }
    });

    test('§ 12 row 6 — both log today\'s bodyweight: LWW, loser tombstoned',
        () async {
      await bothInStep();
      final day = DateTime(2026, 8, 17);

      await devices.as('device-a', () => TrainingRepository(a).logBodyweight(day, 72.0));
      await devices.as('device-b', () => TrainingRepository(b).logBodyweight(day, 73.5));

      await devices.converge();

      for (final db in [a, b]) {
        final rows = await db.select(db.bodyweightLogs).get();
        expect(rows.length, 2, reason: 'nothing is hard-deleted');
        expect(rows.where((r) => r.deletedAt == null).length, 1);
      }
      expect(await devices.rowsOf(b), await devices.rowsOf(a));
    });
  });

  group('§ 9 — the rest of the twelve', () {
    test('both phones advance the cycle: two real cycles, renumbered',
        () async {
      await bothInStep();
      final regime = await activeRegime(a);

      // Each phone finishes a session offline, and each opens the next cycle.
      Future<void> trainOn(AppDatabase db, String day) async {
        final repo = TrainingRepository(db);
        final session = await sessionNamed(db, day);
        final id = await repo.startWorkout(
          regimeId: regime.id,
          sessionId: session.id,
        );
        await repo.completeWorkout(id);
      }

      await devices.as('device-a', () => trainOn(a, 'Push 1'));
      await devices.as('device-b', () => trainOn(b, 'Pull 1'));

      await devices.converge();

      for (final db in [a, b]) {
        final cycles = await (db.select(db.cycles)
              ..where((t) =>
                  t.regimeId.equals(regime.id) & t.deletedAt.isNull()))
            .get();
        final numbers = cycles.map((c) => c.cycleIndex).toList();
        expect(numbers.toSet().length, numbers.length,
            reason: 'a regime cannot hold the same cycle number twice');
        expect(cycles.where((c) => c.completedAt == null).length, 1,
            reason: 'nor two open cycles');
      }
      expect(await devices.rowsOf(b), await devices.rowsOf(a));
    });

    test('both phones rename a day to the same thing: one takes a suffix',
        () async {
      await bothInStep();

      await devices.as('device-a', () async {
        await RegimeRepository(a)
            .renameSession((await sessionNamed(a, 'Push 1')).id, 'Heavy');
      });
      await devices.as('device-b', () async {
        await RegimeRepository(b)
            .renameSession((await sessionNamed(b, 'Push 2')).id, 'Heavy');
      });

      await devices.converge();

      for (final db in [a, b]) {
        final live = await (db.select(db.sessions)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final names = live.map((s) => s.name.trim().toLowerCase()).toList();
        expect(names.toSet().length, names.length,
            reason: 'two live days in one regime cannot share a name');
        expect(names, contains('heavy'));
        expect(names.where((n) => n.startsWith('heavy')).length, 2,
            reason: 'both renames survive; one wears a suffix');
      }
    });

    test('§ 12 row 15 — a seventh regime lands tombstoned, and says so',
        () async {
      await bothInStep();
      final reported = <String>[];
      final sub = failures.listen((f) => reported.add(f.what));

      // Six live regimes hold all six identity slots on A.
      await devices.as('device-a', () async {
        for (var i = 1; i < identitySlots; i++) {
          await RegimeRepository(a).createRegime('Programme $i');
        }
      });
      // And B, offline, creates one more.
      await devices.as(
        'device-b',
        () => RegimeRepository(b).createRegime('One too many'),
      );

      await devices.push(a);
      await devices.push(b);
      await devices.pull(a);

      final live =
          await (a.select(a.regimes)..where((t) => t.deletedAt.isNull())).get();
      expect(live.length, identitySlots);
      expect(live.map((r) => r.identityIndex).toSet().length, identitySlots);
      expect(
        (await a.select(a.regimes).get()).length,
        identitySlots + 1,
        reason: 'the seventh arrives and is kept, it is simply not on the shelf',
      );
      expect(reported, isNotEmpty);
      await sub.cancel();
    });

    test('§ 12 row 8 — a set arrives under a workout the other phone deleted',
        () async {
      await bothInStep();
      final regime = await activeRegime(a);

      final workoutId = await devices.as('device-a', () async {
        final push1 = await sessionNamed(a, 'Push 1');
        return TrainingRepository(a)
            .startWorkout(regimeId: regime.id, sessionId: push1.id);
      });
      await devices.sync(a);
      await devices.sync(b);

      // A deletes the whole session; B, offline, adds a set inside it.
      await devices.as('device-a',
          () => TrainingRepository(a).deleteWorkout(workoutId));
      final slotId = await devices.as('device-b', () async {
        final slot = await (b.select(b.workoutExercises)
              ..where((t) => t.workoutId.equals(workoutId))
              ..limit(1))
            .getSingle();
        await TrainingRepository(b).addSet(slot.id);
        return slot.id;
      });

      await devices.converge();

      for (final db in [a, b]) {
        final sets = await (db.select(db.setLogs)
              ..where((t) =>
                  t.workoutExerciseId.equals(slotId) & t.deletedAt.isNull()))
            .get();
        expect(sets, isEmpty,
            reason: 'healOrphanedSnapshots tombstones what sits under a '
                'tombstoned parent — the set is kept, not orphaned');
      }
    });

    test('§ 12 row 11 — both train on the same day, and both sessions stand',
        () async {
      await bothInStep();
      final regime = await activeRegime(a);

      Future<void> trainOn(AppDatabase db, String day) async {
        final repo = TrainingRepository(db);
        final session = await sessionNamed(db, day);
        final id = await repo.startWorkout(
          regimeId: regime.id,
          sessionId: session.id,
        );
        await repo.completeWorkout(id);
      }

      await devices.as('device-a', () => trainOn(a, 'Push 1'));
      await devices.as('device-b', () => trainOn(b, 'Pull 1'));

      await devices.converge();

      for (final db in [a, b]) {
        final workouts = await (db.select(db.workouts)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        expect(workouts.length, 2,
            reason: 'training twice in a day is real, and legal');
      }
    });
  });

  group('tombstones and bad rows', () {
    test('§ 12 row 9 — a delete arrives as a tombstone, not a hard delete',
        () async {
      await bothInStep();
      final id = (await sessionNamed(a, 'Push 1')).id;

      await devices.as('device-a', () => RegimeRepository(a).deleteSession(id));
      await devices.push(a);
      await devices.pull(b);

      final row = await (b.select(b.sessions)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
    });

    test('§ 12 row 16 — a bad row is skipped and named, and the rest land',
        () async {
      await bothInStep();
      final reported = <String>[];
      final sub = failures.listen((f) => reported.add(f.what));

      // A row this build's CHECKs refuse: a bodyweight of zero is not a light
      // reading, it is a missing one, and it divides into every scored lift.
      await devices.as('device-a', () async {
        await TrainingRepository(a).logBodyweight(DateTime(2026, 8, 17), 72.0);
      });
      await devices.push(a);
      final row = devices.backend.table('bodyweight_logs').first;
      devices.backend.rows['bodyweight_logs']![row['id'] as String] = {
        ...row,
        'weight_kg': 0.0,
      };
      // And one good row behind it, to prove the batch carried on.
      await devices.as('device-a', () async {
        await TrainingRepository(a).logBodyweight(DateTime(2026, 8, 18), 71.5);
      });
      await devices.push(a);

      final report = await devices.pull(b);

      expect(report.skipped, 1);
      expect(report.applied, greaterThan(0));
      expect(reported, isNotEmpty);
      expect(
        await (b.select(b.bodyweightLogs)
              ..where((t) => t.dayKey.equals(20260818)))
            .getSingleOrNull(),
        isNotNull,
        reason: 'one bad row must never stop a restore',
      );
      await sub.cancel();
    });

    test('§ 12 row 13 — killed mid-pull: the cursor never moved', () async {
      await bothInStep();
      await devices.as('device-a', () async {
        await TrainingRepository(a).logBodyweight(DateTime(2026, 8, 17), 72.0);
      });
      await devices.push(a);

      // The account answers for the first tables and then the signal goes.
      devices.backend.failEverything =
          const SyncTransportFailure('dropped', transient: true);
      await expectLater(devices.pull(b), throwsA(isA<SyncTransportFailure>()));

      devices.backend.failEverything = null;
      final report = await devices.pull(b);
      expect(report.applied, greaterThan(0));
      expect(await devices.rowsOf(b), await devices.rowsOf(a));
    });

    test('§ 12 row 18 — a row from a newer build, and one from an older',
        () async {
      await bothInStep();
      await devices.as('device-a', () async {
        await TrainingRepository(a).logBodyweight(DateTime(2026, 8, 17), 72.0);
      });
      await devices.push(a);

      final id = devices.backend.table('bodyweight_logs').first['id'] as String;
      devices.backend.rows['bodyweight_logs']![id] = {
        ...devices.backend.rows['bodyweight_logs']![id]!,
        // A column this build has never heard of, from a build that has.
        'mood_score': 7,
      };

      final report = await devices.pull(b);

      expect(report.skipped, 0);
      expect(
        (await (b.select(b.bodyweightLogs)..where((t) => t.id.equals(id)))
                .getSingle())
            .weightKg,
        72.0,
      );
    });
  });

  group('the one pull anybody watches', () {
    test('the bar counts rows arriving and ends on all of them', () async {
      await devices.as('device-a', () async {
        await ensureStarterCatalog(devices.a);
        await createRegimeFromTemplate(
          devices.a,
          regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
        );
      });
      await devices.push(devices.a);
      final total = devices.backend.storedRows;

      final steps = <JobStep>[];
      await PullService(devices.b, devices.backend, batchSize: 50).pull(
        onProgress: steps.add,
        expectedRows: total,
      );

      expect(steps, isNotEmpty);
      expect(steps.every((s) => s.phase == JobPhase.pulling), isTrue);
      // Never backwards, and never past the end.
      var last = 0;
      for (final step in steps) {
        expect(step.rows, greaterThanOrEqualTo(last));
        expect(step.fraction, inInclusiveRange(0.0, 1.0));
        last = step.rows;
      }
      expect(steps.last.rows, total);
      expect(steps.last.fraction, 1.0);
    });

    test('no denominator leaves the bar indeterminate rather than inventing one',
        () async {
      await devices.as('device-a', () => ensureStarterCatalog(devices.a));
      await devices.push(devices.a);

      final steps = <JobStep>[];
      await PullService(devices.b, devices.backend).pull(onProgress: steps.add);

      expect(steps, isNotEmpty);
      expect(steps.every((s) => s.fraction == null), isTrue);
    });

    test('a background drain reports nothing at all', () async {
      await devices.as('device-a', () => ensureStarterCatalog(devices.a));
      await devices.push(devices.a);

      // Nothing to assert but the absence: a spinner on a job nobody is waiting
      // for is a spinner that teaches the user to wait (SYNC.md § 2).
      final report = await PullService(devices.b, devices.backend).pull();

      expect(report.applied, greaterThan(0));
    });
  });

  group('what the merge left behind', () {
    test('a pull that produced a shape the repairs fix says nothing', () async {
      // The sweep at the end of a pull is the only thing watching for a merge
      // producing a database no writer in the app could have written, and the
      // way a check like that dies is by crying wolf: a report on every sync
      // is a report nobody reads. So this is § 12 row 8 — one phone deletes a
      // workout the other was still adding sets to, which leaves live
      // snapshots under a tombstoned workout — run all the way through, with
      // the assertion being **silence**.
      //
      // The states with no healer behind them are all refused by an index or a
      // CHECK on the way in, so no merge can reach one today. The sweep is
      // what says so if that ever stops being true, and it cannot be tested by
      // building one: the schema will not let it exist.
      await bothInStep();

      final session = await sessionNamed(a, 'Push 1');
      await devices.as('device-a', () async {
        await TrainingRepository(a).startWorkout(
          regimeId: session.regimeId,
          sessionId: session.id,
        );
      });
      await devices.push(a);
      await devices.pull(b);

      // A tombstones the workout; B never hears about it until the pull.
      final workout = await (a.select(a.workouts)
            ..where((t) => t.status.equalsValue(WorkoutStatus.inProgress)))
          .getSingle();
      await devices.as(
        'device-a',
        () => TrainingRepository(a).deleteWorkout(workout.id),
      );
      await devices.push(a);

      final reported = <String>[];
      final sub = failures.listen((f) => reported.add(f.what));
      await devices.pull(b);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(await invariantViolations(b), isEmpty);
      expect(reported, isEmpty,
          reason: 'the repairs ran first; there is nothing left to announce');
    });
  });

  group('the pull that has nothing left to do', () {
    /// **The guard against a phone that never stops syncing.**
    ///
    /// The cursor compares `>=`, so the row stamped exactly on it arrives with
    /// every pull. Writing one back wakes every stream on its table, which
    /// wakes the engine, which pulls again. Nothing asserted this until now —
    /// the applier's short-circuit could be disabled outright and the whole
    /// suite stayed green, because every other test here pulls once.
    test('a second pull applies nothing and rewrites nothing', () async {
      await bothInStep();

      final again = await devices.pull(b);

      expect(again.applied, 0, reason: 'a rewritten row wakes the engine');
      expect(again.kept, 0);
      expect(again.skipped, 0);
      expect(again.unchanged, greaterThan(0),
          reason: 'the boundary row is re-read, recognised, and left alone');
    });
  });
}
