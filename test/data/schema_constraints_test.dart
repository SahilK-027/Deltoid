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

  test('the database is not in a journal mode that can lose a committed '
      'transaction', () async {
    // Read off a file, never off `db`: an in-memory database is always
    // `memory`, which is precisely one of the two modes this refuses. The
    // premise being checked is about the file the phone keeps, and the only
    // honest place to read it is a file.
    final file =
        File('${Directory.systemTemp.path}/deltoid_journal_${newId()}.sqlite');
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);

    final onDisk = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(onDisk.close);

    final row = await onDisk
        .customSelect('SELECT * FROM pragma_journal_mode()')
        .getSingle();
    final mode = (row.data.values.first as String).toLowerCase();

    // `memory` keeps the rollback journal in RAM and `off` writes none at all:
    // under either, a power cut mid-transaction leaves a half-applied
    // transaction on disk with nothing to undo it. The other four each keep a
    // journal the next open can recover from, which is what every durability
    // claim in INVARIANTS.md rests on.
    expect(mode, anyOf('delete', 'truncate', 'persist', 'wal'),
        reason: 'nothing in lib/ sets journal_mode, so this is whatever the '
            'packaged sqlite3 defaults to — read it rather than assume it');

    // And the reason the check cannot be pointed at the shared test database.
    final inMemory =
        await db.customSelect('SELECT * FROM pragma_journal_mode()').getSingle();
    expect((inMemory.data.values.first as String).toLowerCase(), 'memory',
        reason: 'if this ever stops being true, the test above could be '
            'written against `db` and still look like it proved something');
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

  // ── What a row is allowed to say ────────────────────────────────────────
  //
  // Every check below was reachable through a restore or a merged row and
  // through nothing else — which is exactly the writer that does not pass the
  // repository, and exactly the writer a server becomes.

  group('an enum column holds an enum value', () {
    test('a set type nobody has heard of is refused', () async {
      final we = await aWorkoutExercise(await aRegime());
      await aSet(we, 0);
      await expectLater(
        db.customStatement("UPDATE set_logs SET set_type = 'myo'"),
        throwsA(isA<SqliteException>()),
        reason: 'textEnum throws on read, and takes the whole result set with '
            'it — one bad row blanks the log, history and the chart at once',
      );
    });

    test('a workout status nobody has heard of is refused', () async {
      final regime = await aRegime();
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: Value(newId()), regimeId: regime, dayKey: 20260101));
      await expectLater(
        db.customStatement("UPDATE workouts SET status = 'paused'"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('every member of every enum is accepted', () async {
      // The checks are written out by hand, so this is what catches a member
      // added to the enum and not to the column.
      // One exercise, one set each: `aWorkoutExercise` opens a workout, and
      // only one may be open at a time now.
      final we = await aWorkoutExercise(await aRegime());
      for (var i = 0; i < SetType.values.length; i++) {
        await db.into(db.setLogs).insert(SetLogsCompanion.insert(
              id: Value(newId()),
              workoutExerciseId: we,
              setIndex: i,
              setType: Value(SetType.values[i]),
            ));
      }
      // The exercise above opened a workout to hang itself off. Only one may be
      // open at a time, so it steps aside before the statuses are walked.
      await db.update(db.workouts).write(
            WorkoutsCompanion(deletedAt: Value(nowMs())),
          );

      for (final status in WorkoutStatus.values) {
        // Only one may be `inProgress` at a time, so each is tombstoned behind
        // the next.
        final id = newId();
        await db.into(db.workouts).insert(WorkoutsCompanion.insert(
              id: Value(id),
              regimeId: await aRegime(),
              dayKey: 20260101,
              status: Value(status),
            ));
        await (db.update(db.workouts)..where((t) => t.id.equals(id)))
            .write(WorkoutsCompanion(deletedAt: Value(nowMs())));
      }
      for (final muscle in MuscleGroup.values) {
        for (final equipment in Equipment.values) {
          await db.into(db.exercises).insert(ExercisesCompanion.insert(
                id: Value(newId()),
                name: 'x',
                muscle: muscle,
                equipment: equipment,
                loadMode: LoadMode.total,
              ));
        }
      }
      for (final mode in LoadMode.values) {
        for (final bar in BarKind.values) {
          for (final measure in MeasureMode.values) {
            await db.into(db.exercises).insert(ExercisesCompanion.insert(
                  id: Value(newId()),
                  name: 'x',
                  muscle: MuscleGroup.chest,
                  equipment: Equipment.barbell,
                  loadMode: mode,
                  barKind: Value(bar),
                  measureMode: Value(measure),
                ));
          }
        }
      }
      for (final reason in SkipReason.values) {
        final regime = await aRegime();
        final workout = newId();
        await db.into(db.workouts).insert(WorkoutsCompanion.insert(
              id: Value(workout),
              regimeId: regime,
              dayKey: 20260101,
              // Finished, because only one session may be open at a time.
              status: const Value(WorkoutStatus.completed),
            ));
        final exercise = newId();
        await db.into(db.exercises).insert(ExercisesCompanion.insert(
              id: Value(exercise),
              name: 'Bench',
              muscle: MuscleGroup.chest,
              equipment: Equipment.barbell,
              loadMode: LoadMode.total,
            ));
        await db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
                id: Value(newId()),
                workoutId: workout,
                exerciseId: exercise,
                orderIndex: 0,
                skipReason: Value(reason)));
      }
    });
  });

  group('one session is open at a time', () {
    Future<String> aWorkout(String regime, {required WorkoutStatus status}) async {
      final id = newId();
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
            id: Value(id),
            regimeId: regime,
            dayKey: 20260101,
            status: Value(status),
          ));
      return id;
    }

    test('a second open workout is refused', () async {
      final regime = await aRegime();
      await aWorkout(regime, status: WorkoutStatus.inProgress);
      await expectLater(
        aWorkout(regime, status: WorkoutStatus.inProgress),
        throwsA(isA<SqliteException>()),
        reason: 'the older one would be hidden behind the newer for good — '
            'unreachable, in progress forever, and counted by nothing',
      );
    });

    test('a second open workout under another regime is refused too', () async {
      await aWorkout(await aRegime(), status: WorkoutStatus.inProgress);
      await expectLater(
        aWorkout(await aRegime(), status: WorkoutStatus.inProgress),
        throwsA(isA<SqliteException>()),
      );
    });

    test('any number of finished workouts is fine', () async {
      final regime = await aRegime();
      await aWorkout(regime, status: WorkoutStatus.completed);
      await aWorkout(regime, status: WorkoutStatus.completed);
      await aWorkout(regime, status: WorkoutStatus.inProgress);
      expect(await db.workouts.count().getSingle(), 3);
    });

    test('a discarded session frees the slot', () async {
      final regime = await aRegime();
      final open = await aWorkout(regime, status: WorkoutStatus.inProgress);
      await (db.update(db.workouts)..where((t) => t.id.equals(open))).write(
        WorkoutsCompanion(
          status: const Value(WorkoutStatus.abandoned),
          deletedAt: Value(nowMs()),
        ),
      );
      await aWorkout(regime, status: WorkoutStatus.inProgress);
      expect(await db.workouts.count().getSingle(), 2);
    });
  });

  group('a position is unique among live rows', () {
    Future<String> aSession(String regime, int order, {String name = 'Push'}) async {
      final id = newId();
      await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: Value(id), regimeId: regime, name: name, orderIndex: order));
      return id;
    }

    test('two live sessions cannot share a position', () async {
      final regime = await aRegime();
      await aSession(regime, 0, name: 'Push');
      await expectLater(
        aSession(regime, 0, name: 'Pull'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('the same position under another regime is fine', () async {
      await aSession(await aRegime(), 0);
      await aSession(await aRegime(), 0);
      expect(await db.sessions.count().getSingle(), 2);
    });

    test('a deleted session frees its position', () async {
      final regime = await aRegime();
      final first = await aSession(regime, 0, name: 'Push');
      await (db.update(db.sessions)..where((t) => t.id.equals(first)))
          .write(SessionsCompanion(deletedAt: Value(nowMs())));
      await aSession(regime, 0, name: 'Pull');
      expect(await db.sessions.count().getSingle(), 2);
    });

    test('two live slots cannot share a position in a workout', () async {
      final regime = await aRegime();
      final workout = newId();
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: Value(workout), regimeId: regime, dayKey: 20260101));
      final exercise = newId();
      await db.into(db.exercises).insert(ExercisesCompanion.insert(
            id: Value(exercise),
            name: 'Bench',
            muscle: MuscleGroup.chest,
            equipment: Equipment.barbell,
            loadMode: LoadMode.total,
          ));
      Future<void> slot(int order) =>
          db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
              id: Value(newId()),
              workoutId: workout,
              exerciseId: exercise,
              orderIndex: order));

      await slot(0);
      await expectLater(slot(0), throwsA(isA<SqliteException>()));
    });
  });

  group('a day answers to one name in its regime', () {
    Future<String> named(String regime, String name) async {
      final id = newId();
      await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: Value(id),
          regimeId: regime,
          name: name,
          orderIndex: await db.sessions.count().getSingle()));
      return id;
    }

    test('the same name twice in one regime is refused', () async {
      final regime = await aRegime();
      await named(regime, 'Push 1');
      await expectLater(
        named(regime, 'Push 1'),
        throwsA(isA<SqliteException>()),
        reason: 'the prefill disclosure names the day it borrowed from, and '
            'two of them makes that sentence ambiguous',
      );
    });

    test('case and surrounding space are not a difference', () async {
      final regime = await aRegime();
      await named(regime, 'Push 1');
      await expectLater(
        named(regime, '  push 1 '),
        throwsA(isA<SqliteException>()),
      );
    });

    test('two regimes may each have a Push 1', () async {
      await named(await aRegime(), 'Push 1');
      await named(await aRegime(), 'Push 1');
      expect(await db.sessions.count().getSingle(), 2);
    });
  });

  group('a number that cannot mean anything', () {
    test('a deload at 0% of last week is refused', () async {
      await expectLater(
        db.into(db.regimes).insert(RegimesCompanion.insert(
            id: Value(newId()),
            name: 'R',
            deloadWeightPct: const Value(0))),
        throwsA(isA<SqliteException>()),
        reason: 'a light week prefilled at nothing at all',
      );
    });

    test('a deload that adds sets is refused', () async {
      await expectLater(
        db.into(db.regimes).insert(RegimesCompanion.insert(
            id: Value(newId()), name: 'R', deloadSetDelta: const Value(2))),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a deload every zero cycles is refused', () async {
      await expectLater(
        db.into(db.regimes).insert(RegimesCompanion.insert(
            id: Value(newId()),
            name: 'R',
            deloadAfterCycles: const Value(0))),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a rep range that runs backwards is refused', () async {
      final regime = await aRegime();
      final session = newId();
      await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: Value(session), regimeId: regime, name: 'Push', orderIndex: 0));
      final exercise = newId();
      await db.into(db.exercises).insert(ExercisesCompanion.insert(
            id: Value(exercise),
            name: 'Bench',
            muscle: MuscleGroup.chest,
            equipment: Equipment.barbell,
            loadMode: LoadMode.total,
          ));
      await expectLater(
        db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
              id: Value(session),
              sessionId: session,
              exerciseId: exercise,
              orderIndex: 0,
              targetRepLow: const Value(8),
              targetRepHigh: const Value(5),
            )),
        throwsA(isA<SqliteException>()),
        reason: '8-5 reads as a range, sorts as a range and prints as one',
      );
    });

    test('a day that is not a day is refused', () async {
      await expectLater(
        db.into(db.workouts).insert(WorkoutsCompanion.insert(
            id: Value(newId()), regimeId: await aRegime(), dayKey: 0)),
        throwsA(isA<SqliteException>()),
        reason: 'dateFromDayKey does arithmetic on this — 0 is year zero, and '
            'the calendar scrolls silently to it',
      );
    });

    test('a session that ended before it started is refused', () async {
      await expectLater(
        db.into(db.workouts).insert(WorkoutsCompanion.insert(
              id: Value(newId()),
              regimeId: await aRegime(),
              dayKey: 20260101,
              startedAt: const Value(2000),
              endedAt: const Value(1000),
            )),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a set cannot be a leg of itself', () async {
      final we = await aWorkoutExercise(await aRegime());
      final id = newId();
      await db.into(db.setLogs).insert(SetLogsCompanion.insert(
          id: Value(id), workoutExerciseId: we, setIndex: 0));
      await expectLater(
        (db.update(db.setLogs)..where((t) => t.id.equals(id)))
            .write(SetLogsCompanion(parentSetId: Value(id))),
        throwsA(isA<SqliteException>()),
        reason: 'a drop group with no head to draw and no end to walk to',
      );
    });

    test('a bodyweight nobody has is refused', () async {
      await expectLater(
        db.into(db.bodyweightLogs).insert(BodyweightLogsCompanion.insert(
            id: Value(newId()), dayKey: 20260101, weightKg: 850)),
        throwsA(isA<SqliteException>()),
        reason: 'it is interpolated into every pull-up either side of it',
      );
    });

    test('a name that is nothing but space is refused by the column too',
        () async {
      await expectLater(
        db.into(db.sessions).insert(SessionsCompanion.insert(
            id: Value(newId()),
            regimeId: await aRegime(),
            name: '   ',
            orderIndex: 0)),
        throwsA(isA<SqliteException>()),
        reason: 'BlankNameException guards the repository; this guards the '
            'writer that does not go through it',
      );
    });
  });
}
