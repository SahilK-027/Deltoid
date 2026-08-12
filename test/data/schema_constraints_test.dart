import 'dart:io';

import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/backup/backup_service.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The invariants the app used to hold on its own.
///
/// Every one of these was already enforced in Dart — a transaction, an upsert,
/// a deactivate-then-activate. That defence only covers writes that come
/// through the repository, and a restore or a merge does not. These prove the
/// database itself now refuses, so there is no route in that can get it wrong.
void main() {
  setUpAll(() {
    // The restore test opens a second database to stand in for a new phone.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // beforeOpen carries `PRAGMA foreign_keys = ON`.
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());

  Future<String> aRegime({bool active = false}) async {
    final id = newId();
    await db.into(db.regimes).insert(
        RegimesCompanion.insert(
            id: Value(id), name: 'R', isActive: Value(active)));
    return id;
  }

  Future<String> aWorkoutExercise(String regimeId) async {
    final workout = newId();
    await db.into(db.workouts).insert(WorkoutsCompanion.insert(
        id: Value(workout), regimeId: regimeId, dayKey: 20260101));
    final exercise = newId();
    await db.into(db.exercises).insert(ExercisesCompanion.insert(
          id: Value(exercise),
          name: 'Bench',
          muscle: MuscleGroup.chest,
          equipment: Equipment.barbell,
          loadMode: LoadMode.total,
        ));
    final we = newId();
    await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
        id: Value(we),
        workoutId: workout,
        exerciseId: exercise,
        orderIndex: 0));
    return we;
  }

  Future<String> aSet(String we, int index, {String? parent}) async {
    final id = newId();
    await db.into(db.setLogs).insert(SetLogsCompanion.insert(
          id: Value(id),
          workoutExerciseId: we,
          setIndex: index,
          parentSetId: Value(parent),
        ));
    return id;
  }

  test('a drop-set leg cannot name a head that does not exist', () async {
    final we = aWorkoutExercise(await aRegime());
    await expectLater(
      aSet(await we, 0, parent: 'no-such-set'),
      throwsA(isA<SqliteException>()),
    );
  });

  test('a drop-set leg pointing at a real head is fine', () async {
    final we = await aWorkoutExercise(await aRegime());
    final head = await aSet(we, 0);
    await aSet(we, 1, parent: head);
    expect(await db.setLogs.count().getSingle(), 2);
  });

  test('one live bodyweight row per day', () async {
    await db.into(db.bodyweightLogs).insert(BodyweightLogsCompanion.insert(
        id: Value(newId()), dayKey: 20260101, weightKg: 70));

    await expectLater(
      db.into(db.bodyweightLogs).insert(BodyweightLogsCompanion.insert(
          id: Value(newId()), dayKey: 20260101, weightKg: 71)),
      throwsA(isA<SqliteException>()),
    );
  });

  test('a tombstoned day does not block logging that day again', () async {
    final first = newId();
    await db.into(db.bodyweightLogs).insert(BodyweightLogsCompanion.insert(
        id: Value(first), dayKey: 20260101, weightKg: 70));
    await (db.update(db.bodyweightLogs)..where((t) => t.id.equals(first)))
        .write(BodyweightLogsCompanion(deletedAt: Value(nowMs())));

    // The whole reason the index is partial.
    await db.into(db.bodyweightLogs).insert(BodyweightLogsCompanion.insert(
        id: Value(newId()), dayKey: 20260101, weightKg: 71));
    expect(await db.bodyweightLogs.count().getSingle(), 2);
  });

  test('only one regime is active at a time', () async {
    await aRegime(active: true);
    await expectLater(aRegime(active: true), throwsA(isA<SqliteException>()));
  });

  test('any number of regimes may be inactive', () async {
    await aRegime();
    await aRegime();
    await aRegime(active: true);
    expect(await db.regimes.count().getSingle(), 3);
  });

  test('a regime cannot hold one cycle number twice', () async {
    final regime = await aRegime();
    await db.into(db.cycles).insert(
        CyclesCompanion.insert(id: Value(newId()), regimeId: regime, cycleIndex: 1));
    await expectLater(
      db.into(db.cycles).insert(CyclesCompanion.insert(
          id: Value(newId()), regimeId: regime, cycleIndex: 1)),
      throwsA(isA<SqliteException>()),
    );
  });

  test('two live sets cannot share a position under one exercise', () async {
    final we = await aWorkoutExercise(await aRegime());
    await aSet(we, 0);
    await expectLater(aSet(we, 0), throwsA(isA<SqliteException>()));
  });

  test('a deleted set frees its position', () async {
    final we = await aWorkoutExercise(await aRegime());
    final first = await aSet(we, 0);
    await (db.update(db.setLogs)..where((t) => t.id.equals(first)))
        .write(SetLogsCompanion(deletedAt: Value(nowMs())));
    await aSet(we, 0);
    expect(await db.setLogs.count().getSingle(), 2);
  });

  test('a restore accepts a drop group written leg-first', () async {
    final we = await aWorkoutExercise(await aRegime());
    final head = await aSet(we, 0);
    await aSet(we, 1, parent: head);

    final payload = await BackupService(db).buildPayload();
    // Within one table, a row that points at a row further down the file.
    // Safe only because the restore inserts through `db.batch`, which defers
    // foreign keys to the commit. This test is what says so.
    final data = Map<String, dynamic>.from(payload['data'] as Map);
    data['set_logs'] = (data['set_logs'] as List).reversed.toList();
    payload['data'] = data;

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await fresh.customSelect('SELECT 1').get();

    await BackupService(fresh).restore(null, decoded: payload);
    expect(await fresh.setLogs.count().getSingle(), 2);
  });

  test('every row is stamped with this install\'s device id', () async {
    final regime = await aRegime();
    final row = await (db.select(db.regimes)..where((t) => t.id.equals(regime)))
        .getSingle();

    expect(row.deviceId, isNotEmpty,
        reason: 'the column existed and nothing ever wrote it');
    expect(row.deviceId, currentDeviceId);
  });

  test('the device id survives reopening the same file', () async {
    final file = File(
        '${Directory.systemTemp.path}/deltoid_device_${newId()}.sqlite');
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);

    final first = AppDatabase.forTesting(NativeDatabase(file));
    await first.customSelect('SELECT 1').get();
    final minted = currentDeviceId;
    await first.close();

    final second = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(second.close);
    await second.customSelect('SELECT 1').get();

    expect(currentDeviceId, minted,
        reason: 'a device that re-mints on every launch describes the launch, '
            'not the phone');
  });

  test('the lock is waited on rather than failed on', () async {
    final row =
        await db.customSelect('PRAGMA busy_timeout').getSingle();
    expect(row.data.values.first, 5000);
  });

  test('a negative load is refused', () async {
    final we = await aWorkoutExercise(await aRegime());
    await expectLater(
      db.into(db.setLogs).insert(SetLogsCompanion.insert(
            id: Value(newId()),
            workoutExerciseId: we,
            setIndex: 0,
            weight: const Value(-60),
          )),
      throwsA(isA<SqliteException>()),
      reason: 'assistance is a LoadMode, not a minus sign',
    );
  });

  test('negative reps are refused', () async {
    final we = await aWorkoutExercise(await aRegime());
    await expectLater(
      db.into(db.setLogs).insert(SetLogsCompanion.insert(
            id: Value(newId()),
            workoutExerciseId: we,
            setIndex: 0,
            reps: const Value(-1),
          )),
      throwsA(isA<SqliteException>()),
    );
  });

  test('a zero weight is not a bodyweight reading', () async {
    await expectLater(
      db.into(db.bodyweightLogs).insert(BodyweightLogsCompanion.insert(
          id: Value(newId()), dayKey: 20260202, weightKg: 0)),
      throwsA(isA<SqliteException>()),
      reason: 'zero divides into every bodyweight-scored lift that day',
    );
  });

  test('zero is still a legal load and a legal rep count', () async {
    final we = await aWorkoutExercise(await aRegime());
    await db.into(db.setLogs).insert(SetLogsCompanion.insert(
          id: Value(newId()),
          workoutExerciseId: we,
          setIndex: 0,
          weight: const Value(0),
          reps: const Value(0),
        ));
    expect(await db.setLogs.count().getSingle(), 1);
  });
}
