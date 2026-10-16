import 'dart:convert';
import 'dart:io';

import 'package:deltoid/core/providers.dart';
import 'package:deltoid/data/backup/backup_service.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/phase_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/adoption.dart';
import 'package:deltoid/data/sync/catalog_dedup.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/units.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'two_devices.dart';

/// The three shapes at sign-in, and what each one does to two histories.
///
/// [SYNC.md § 10](SYNC.md#10-adoption). `phone` is the phone being signed in;
/// `other` is the phone whose history is already on the account. The rule
/// nothing here is allowed to break: **whichever side is not kept is written to
/// a backup file first, automatically, before anything is overwritten.**
void main() {
  late TwoDevices devices;
  late Directory backups;

  /// The phone whose history is already on the account, and the phone being
  /// signed in.
  late AppDatabase other;
  late AppDatabase phone;

  AdoptionService adoptionOf(AppDatabase db) => AdoptionService(
    db,
    devices.backend,
    backup: BackupService(db),
    directory: () async => backups,
  );

  setUp(() {
    devices = TwoDevices();
    other = devices.a;
    phone = devices.b;
    backups = Directory.systemTemp.createTempSync('deltoid-adoption');
  });

  tearDown(() async {
    await devices.close();
    backups.deleteSync(recursive: true);
  });

  /// A phone with a catalog, a regime and one finished session on it.
  Future<void> train(
    AppDatabase db,
    String device, {
    required DateTime day,
    double weight = 60,
  }) async {
    await devices.as(device, () async {
      await setWeightUnit(db, WeightUnit.kg);
      await ensureStarterCatalog(db);
      final live = await (db.select(
        db.regimes,
      )..where((t) => t.isActive.equals(true))).getSingleOrNull();
      if (live == null) {
        await createRegimeFromTemplate(
          db,
          regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
        );
      }

      final repo = TrainingRepository(db);
      final regime = await (db.select(
        db.regimes,
      )..where((t) => t.isActive.equals(true))).getSingle();
      final session =
          await (db.select(db.sessions)
                ..where((t) => t.regimeId.equals(regime.id))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
                ..limit(1))
              .getSingle();
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: session.id,
      );
      final detail = await repo.workoutDetail(id);
      for (final set in detail!.entries.first.sets) {
        await repo.updateSet(
          set.id,
          weight: Value(weight),
          reps: const Value(8),
          isDone: const Value(true),
        );
      }
      await repo.completeWorkout(id);
      // Re-dated after the fact, so the two histories are on different days
      // and the prompt's *most recently* has something to say. `day_key` is
      // tied to `started_at` by a CHECK and moves with it.
      await db.customUpdate(
        'UPDATE workouts SET started_at = ?, ended_at = ?, day_key = ?, '
        'tz_offset_minutes = ? WHERE id = ?',
        variables: [
          Variable(day.millisecondsSinceEpoch),
          Variable(day.millisecondsSinceEpoch),
          Variable(day.year * 10000 + day.month * 100 + day.day),
          Variable(day.timeZoneOffset.inMinutes),
          Variable(id),
        ],
      );
    });
  }

  /// Just installed: a catalog, nothing trained.
  Future<void> install(AppDatabase db, String device) =>
      devices.as(device, () async {
        await setWeightUnit(db, WeightUnit.kg);
        await ensureStarterCatalog(db);
      });

  Future<int> liveWorkouts(AppDatabase db) => db
      .customSelect(
        'SELECT COUNT(*) AS n FROM workouts WHERE deleted_at IS NULL',
      )
      .map((row) => row.read<int>('n'))
      .getSingle();

  Future<List<File>> filesIn(Directory dir) async =>
      dir.listSync().whereType<File>().toList();

  group('the shape', () {
    test('nothing local, data on the account, is a pull', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await install(phone, 'device-b');

      final survey = await adoptionOf(phone).survey();
      expect(survey.shape, AdoptionShape.pull);
      expect(survey.accountSessions, 1);
      expect(survey.phoneSessions, 0);
    });

    test('training local, an empty account, is a push', () async {
      await train(phone, 'device-b', day: DateTime(2026, 8, 1));

      final survey = await adoptionOf(phone).survey();
      expect(survey.shape, AdoptionShape.push);
    });

    test('training on both sides is asked, never resolved', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await train(phone, 'device-b', day: DateTime(2026, 8, 1));

      final adoption = adoptionOf(phone);
      final survey = await adoption.survey();

      expect(survey.shape, AdoptionShape.ask);
      expect(survey.accountSessions, 1);
      expect(survey.phoneSessions, 1);
      expect(survey.accountLatest, DateTime(2026, 3, 3));
      expect(survey.phoneLatest, DateTime(2026, 8, 1));
      await expectLater(adoption.adopt(AdoptionShape.ask), throwsArgumentError);
    });

    test(
      'a catalog is not a history — an install has nothing to lose',
      () async {
        await install(phone, 'device-b');
        await train(other, 'device-a', day: DateTime(2026, 3, 3));
        await devices.push(other);

        expect((await adoptionOf(phone).survey()).shape, AdoptionShape.pull);
      },
    );

    test(
      'a phase is not a history — a cut declared on an install is a pull',
      () async {
        await install(phone, 'device-b');
        await devices.as(
          'device-b',
          () => PhaseRepository(phone).startPhase(
            PhaseKind.cut,
            from: DateTime(2026, 9, 3),
          ),
        );
        await train(other, 'device-a', day: DateTime(2026, 3, 3));
        await devices.push(other);

        expect((await adoptionOf(phone).survey()).shape, AdoptionShape.pull,
            reason: 'SYNC.md § 10: phases are not training for the three '
                'shapes, and nothing about them is a question at sign-in');
      },
    );

    test('the survey writes nothing on either side', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await train(phone, 'device-b', day: DateTime(2026, 8, 1));

      final before = await devices.rowsOf(phone);
      final stored = devices.backend.storedRows;
      await adoptionOf(phone).survey();

      expect((await devices.rowsOf(phone)).toString(), before.toString());
      expect(devices.backend.storedRows, stored);
      expect(await filesIn(backups), isEmpty);
    });
  });

  group('the first two shapes', () {
    test('a pull adopts the account and seeds no second catalog', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      // A phone that has not been opened yet: the welcome screen defers the
      // seed, which is the whole reason this order is safe.
      await devices.as('device-b', () => setWeightUnit(phone, WeightUnit.kg));

      await adoptionOf(phone).adopt(AdoptionShape.pull);

      expect(await liveWorkouts(phone), 1);
      final keys = await phone
          .customSelect(
            'SELECT starter_key AS k, COUNT(*) AS n FROM exercises '
            'GROUP BY starter_key HAVING n > 1',
          )
          .get();
      expect(keys, isEmpty, reason: 'the catalog arrived twice');
    });

    test(
      'a pull onto an empty account still leaves a catalog to train from',
      () async {
        await devices.as('device-b', () => setWeightUnit(phone, WeightUnit.kg));

        await adoptionOf(phone).adopt(AdoptionShape.pull);

        final count = await phone
            .customSelect('SELECT COUNT(*) AS n FROM exercises')
            .map((row) => row.read<int>('n'))
            .getSingle();
        expect(count, greaterThan(0));
      },
    );

    test(
      'a push sends a history written before there was an account',
      () async {
        await train(phone, 'device-b', day: DateTime(2026, 8, 1));
        // A phone that has never been signed in has been clearing `dirty` for
        // nobody. Nothing is owed and everything still has to go.
        await phone.customStatement('UPDATE workouts SET dirty = 0');
        await phone.customStatement('UPDATE set_logs SET dirty = 0');

        await adoptionOf(phone).adopt(AdoptionShape.push);

        expect(devices.backend.table('workouts').length, 1);
        expect(devices.backend.table('set_logs'), isNotEmpty);
      },
    );
  });

  group('keep the account', () {
    test("the phone's history is on disk before it is cleared", () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await train(phone, 'device-b', day: DateTime(2026, 8, 1), weight: 100);
      final mine = await phone
          .customSelect('SELECT id FROM workouts')
          .map((row) => row.read<String>('id'))
          .getSingle();

      final backup = await adoptionOf(
        phone,
      ).adopt(AdoptionShape.ask, choice: AdoptionChoice.keepAccount);

      expect(backup, isNotNull);
      final payload =
          jsonDecode(await backup!.readAsString()) as Map<String, dynamic>;
      final saved = (payload['data'] as Map)['workouts'] as List;
      expect(saved.single['id'], mine);
    });

    test('the account is what is left, and the phone is not in it', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      final theirs = await other
          .customSelect('SELECT id FROM workouts')
          .map((row) => row.read<String>('id'))
          .getSingle();
      await train(phone, 'device-b', day: DateTime(2026, 8, 1), weight: 100);

      await adoptionOf(
        phone,
      ).adopt(AdoptionShape.ask, choice: AdoptionChoice.keepAccount);

      final left = await phone
          .customSelect('SELECT id FROM workouts')
          .map((row) => row.read<String>('id'))
          .get();
      expect(left, [theirs]);
      // And the catalog came from the account rather than being seeded again.
      final duplicated = await phone
          .customSelect(
            'SELECT starter_key AS k, COUNT(*) AS n FROM exercises '
            'WHERE starter_key IS NOT NULL GROUP BY starter_key HAVING n > 1',
          )
          .get();
      expect(duplicated, isEmpty);
    });
  });

  group('keep this phone', () {
    test("the account's history is on disk before it is tombstoned", () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      final theirs = await other
          .customSelect('SELECT id FROM workouts')
          .map((row) => row.read<String>('id'))
          .getSingle();
      await train(phone, 'device-b', day: DateTime(2026, 8, 1), weight: 100);

      final backup = await adoptionOf(
        phone,
      ).adopt(AdoptionShape.ask, choice: AdoptionChoice.keepPhone);

      expect(backup, isNotNull);
      final payload =
          jsonDecode(await backup!.readAsString()) as Map<String, dynamic>;
      final saved = (payload['data'] as Map)['workouts'] as List;
      expect(saved.single['id'], theirs);
      // Written in the file's own dialect, not the wire's, so it restores like
      // any other backup.
      expect(saved.single, isNot(contains('server_updated_at')));
      expect(saved.single, contains('startedAt'));
    });

    test("the account's history does not come back on the next pull", () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await train(phone, 'device-b', day: DateTime(2026, 8, 1), weight: 100);
      final mine = await phone
          .customSelect('SELECT id FROM workouts')
          .map((row) => row.read<String>('id'))
          .getSingle();

      await adoptionOf(
        phone,
      ).adopt(AdoptionShape.ask, choice: AdoptionChoice.keepPhone);
      await devices.sync(phone);

      expect(await liveWorkouts(phone), 1);
      final live = await phone
          .customSelect('SELECT id FROM workouts WHERE deleted_at IS NULL')
          .map((row) => row.read<String>('id'))
          .getSingle();
      expect(live, mine);
      // And the other phone hears about it rather than pushing it all back.
      await devices.sync(other);
      expect(await liveWorkouts(other), 1);
    });
  });

  group('merge', () {
    test('both histories survive, and nothing is backed up', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await train(phone, 'device-b', day: DateTime(2026, 8, 1), weight: 100);

      final backup = await adoptionOf(
        phone,
      ).adopt(AdoptionShape.ask, choice: AdoptionChoice.merge);

      expect(backup, isNull);
      expect(await filesIn(backups), isEmpty);
      expect(await liveWorkouts(phone), 2);
    });

    test('two seeded catalogs fold into one, and the logs follow', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await train(phone, 'device-b', day: DateTime(2026, 8, 1), weight: 100);

      // What the logged rows pointed at, and what they said the day they were
      // logged. The second must not move.
      final before = await phone
          .customSelect('SELECT id, exercise_id, muscle FROM workout_exercises')
          .get();
      final muscles = {
        for (final row in before)
          row.read<String>('id'): row.read<String?>('muscle'),
      };

      await adoptionOf(
        phone,
      ).adopt(AdoptionShape.ask, choice: AdoptionChoice.merge);

      final duplicated = await phone
          .customSelect(
            'SELECT starter_key AS k, COUNT(*) AS n FROM exercises '
            'WHERE starter_key IS NOT NULL AND deleted_at IS NULL '
            'GROUP BY starter_key HAVING n > 1',
          )
          .get();
      expect(duplicated, isEmpty, reason: 'the catalog is still doubled');

      // Every logged row points at a live exercise, and its snapshot of what
      // that movement trained is exactly what it was.
      final after = await phone
          .customSelect(
            'SELECT we.id AS id, we.muscle AS muscle, e.deleted_at AS gone '
            'FROM workout_exercises we '
            'JOIN exercises e ON e.id = we.exercise_id',
          )
          .get();
      // Both histories are here now, which is what a union means. What must
      // not have changed is what the phone's own rows say.
      expect(after.length, greaterThanOrEqualTo(before.length));
      final seen = <String>{};
      for (final row in after) {
        expect(row.read<int?>('gone'), isNull);
        final id = row.read<String>('id');
        if (!muscles.containsKey(id)) continue;
        seen.add(id);
        expect(row.read<String?>('muscle'), muscles[id]);
      }
      expect(seen, muscles.keys.toSet());
    });

    test('both phones end up holding the same rows', () async {
      await train(other, 'device-a', day: DateTime(2026, 3, 3));
      await devices.push(other);
      await train(phone, 'device-b', day: DateTime(2026, 8, 1), weight: 100);

      await adoptionOf(
        phone,
      ).adopt(AdoptionShape.ask, choice: AdoptionChoice.merge);
      // The other phone runs the same dedup over the same union and must reach
      // the same answer, or each tombstones the other's survivor.
      await devices.sync(other);
      await dedupeCatalog(other);

      expect(await devices.converge(), lessThanOrEqualTo(6));
    });
  });
}
