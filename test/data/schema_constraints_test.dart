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

  /// Identity slots are unique among live regimes, so a helper that put every
  /// regime on slot 0 would fail the tests that need two of them for reasons
  /// that have nothing to do with what they assert. Dealt out in order unless
  /// a test names the slot, because in those the slot is the thing under test.
  /// Reset per test: there are only [identitySlots] of them and the CHECK
  /// bounds the column to that range.
  var nextSlot = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    nextSlot = 0;
    // beforeOpen carries `PRAGMA foreign_keys = ON`.
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());

  Future<String> aRegime({bool active = false, int? slot}) async {
    final id = newId();
    await db.into(db.regimes).insert(
        RegimesCompanion.insert(
            id: Value(id),
            name: 'R',
            isActive: Value(active),
            identityIndex: Value(slot ?? nextSlot++)));
    return id;
  }

  /// The day every workout these tests build is logged on.
  ///
  /// All three date columns come from it, because since the day-key CHECK any
  /// other combination is refused and the refusal has nothing to do with what
  /// most of these tests are about.
  final logged = DateTime(2026, 1, 1, 9);

  Future<String> aWorkoutExercise(String regimeId) async {
    final workout = newId();
    await db.into(db.workouts).insert(WorkoutsCompanion.insert(
        id: Value(workout),
        regimeId: regimeId,
        dayKey: dayKeyOf(logged),
        startedAt: Value(logged.millisecondsSinceEpoch),
        tzOffsetMinutes: tzOffsetOf(logged)));
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

  /// A second slot under the same workout as [we].
  ///
  /// Not a second [aWorkoutExercise]: that opens a workout, and only one may be
  /// open at a time. A drop group crossing slots is the interesting shape, and
  /// it needs two slots on one day rather than two days.
  Future<String> aSiblingSlot(String we) async {
    final row = await (db.select(db.workoutExercises)
          ..where((t) => t.id.equals(we)))
        .getSingle();
    final exercise = newId();
    await db.into(db.exercises).insert(ExercisesCompanion.insert(
          id: Value(exercise),
          name: 'Row',
          muscle: MuscleGroup.back,
          equipment: Equipment.barbell,
          loadMode: LoadMode.total,
        ));
    final sibling = newId();
    await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
        id: Value(sibling),
        workoutId: row.workoutId,
        exerciseId: exercise,
        orderIndex: 1));
    return sibling;
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

  test('a drop leg cannot name a head in another exercise', () async {
    // The column was a real reference, so the head had to exist — but nothing
    // said *where*. A leg under Bench could name a head under Row, or a head in
    // last March's workout, and SQLite took it. `addDropLeg` and `setSetType`
    // always pass a head from the same slot; a restore does not go through
    // either. INVARIANTS.md § 14.
    final bench = await aWorkoutExercise(await aRegime());
    final row = await aSiblingSlot(bench);
    final head = await aSet(bench, 0);

    await expectLater(
      aSet(row, 0, parent: head),
      throwsA(isA<SqliteException>()),
    );
  });

  test('a drop leg cannot name a head in another workout', () async {
    // The same rule reaching further: the slot id is unique across the whole
    // table, so a head in a workout from any other day fails on the same
    // comparison. This is the shape a merge produces rather than a hand edit.
    final regime = await aRegime();
    final march = await aWorkoutExercise(regime);
    final head = await aSet(march, 0);
    // The first workout steps aside — only one may be open at a time.
    await db.update(db.workouts).write(
          WorkoutsCompanion(deletedAt: Value(nowMs())),
        );
    final july = await aWorkoutExercise(regime);

    await expectLater(
      aSet(july, 0, parent: head),
      throwsA(isA<SqliteException>()),
    );
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

  test('two live regimes cannot share a hue', () async {
    // The identity mark is what History and Today are scanned by, so two
    // programmes wearing one hue is the failure the column exists to prevent —
    // and `nextIdentitySlot` only defends the writes that come through it. The
    // route in is a file: `identity_index` defaults to 0 and the CHECK bounds
    // the range only, so a hand-edited or merged export carrying the key twice
    // restored two regimes onto one colour. INVARIANTS.md § 20.
    await aRegime(slot: 3);
    await expectLater(aRegime(slot: 3), throwsA(isA<SqliteException>()));
  });

  test('a deleted regime hands its hue back', () async {
    // Why the index is partial. `deleteRegime` tombstones, and the slot is
    // documented as returning to the pool — an unscoped index would keep it
    // held by a programme that is gone from every screen.
    final first = await aRegime(slot: 2);
    await (db.update(db.regimes)..where((t) => t.id.equals(first)))
        .write(RegimesCompanion(deletedAt: Value(nowMs())));

    await aRegime(slot: 2);
    expect(
      await (db.select(db.regimes)..where((t) => t.deletedAt.isNull()))
          .get()
          .then((r) => r.length),
      1,
    );
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

  test('a regime cannot hold two open cycles', () async {
    // The index that existed was on `(regime_id, cycle_index)`, which lets two
    // cycles be open at once as long as they are numbered differently — and
    // `healDuplicateOpenCycles` exists because a build once did exactly that.
    // The healer repairs the phones that already went wrong; this refuses the
    // row, which is what a pull applier will need.
    final regime = await aRegime();
    await db.into(db.cycles).insert(CyclesCompanion.insert(
        id: Value(newId()), regimeId: regime, cycleIndex: 1));

    await expectLater(
      db.into(db.cycles).insert(CyclesCompanion.insert(
          id: Value(newId()), regimeId: regime, cycleIndex: 2)),
      throwsA(isA<SqliteException>()),
      reason: 'the first cycle has no completed_at, so it is still open',
    );
  });

  test('closing a cycle makes room for the next one', () async {
    // The guard that the refusal above is scoped to *open* cycles rather than
    // to cycles: a programme that could not open its second cycle would be a
    // worse bug than the one being fixed.
    final regime = await aRegime();
    final first = newId();
    await db.into(db.cycles).insert(CyclesCompanion.insert(
        id: Value(first), regimeId: regime, cycleIndex: 1));
    await (db.update(db.cycles)..where((t) => t.id.equals(first)))
        .write(CyclesCompanion(completedAt: Value(nowMs())));

    await db.into(db.cycles).insert(CyclesCompanion.insert(
        id: Value(newId()), regimeId: regime, cycleIndex: 2));
    expect(await db.cycles.count().getSingle(), 2);
  });

  test('a tombstoned open cycle frees the slot', () async {
    // `healDuplicateOpenCycles` repairs by tombstoning the duplicates, so the
    // index has to be scoped `deleted_at IS NULL` or the healer's own write
    // would be refused by the rule it exists to restore.
    final regime = await aRegime();
    final first = newId();
    await db.into(db.cycles).insert(CyclesCompanion.insert(
        id: Value(first), regimeId: regime, cycleIndex: 1));
    await (db.update(db.cycles)..where((t) => t.id.equals(first)))
        .write(CyclesCompanion(deletedAt: Value(nowMs())));

    await db.into(db.cycles).insert(CyclesCompanion.insert(
        id: Value(newId()), regimeId: regime, cycleIndex: 2));
    expect(
      await (db.select(db.cycles)..where((t) => t.deletedAt.isNull()))
          .get()
          .then((r) => r.length),
      1,
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
          id: Value(newId()),
          regimeId: regime,
          dayKey: dayKeyOf(logged),
          startedAt: Value(logged.millisecondsSinceEpoch),
          tzOffsetMinutes: tzOffsetOf(logged)));
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
      // One regime for the whole test. There are only [identitySlots] hues and
      // no two live regimes may wear one, so a regime per workout status runs
      // out of colours long before it runs out of statuses — and nothing here
      // is about the regime, which is only an FK target.
      final regime = await aRegime();
      final we = await aWorkoutExercise(regime);
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
              regimeId: regime,
              dayKey: dayKeyOf(logged),
              startedAt: Value(logged.millisecondsSinceEpoch),
              tzOffsetMinutes: tzOffsetOf(logged),
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
        final workout = newId();
        await db.into(db.workouts).insert(WorkoutsCompanion.insert(
              id: Value(workout),
              regimeId: regime,
              dayKey: dayKeyOf(logged),
              startedAt: Value(logged.millisecondsSinceEpoch),
              tzOffsetMinutes: tzOffsetOf(logged),
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
            dayKey: dayKeyOf(logged),
            startedAt: Value(logged.millisecondsSinceEpoch),
            tzOffsetMinutes: tzOffsetOf(logged),
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

  group('a workout names one day', () {
    /// One instant, written three ways. UTC so the machine running the test has
    /// no say in it: `2026-03-15 02:30Z` is `2026-03-14 21:30` five hours west
    /// and `2026-03-15 08:00` five and a half hours east, so the *same*
    /// `started_at` legitimately belongs to either calendar day and only the
    /// offset says which.
    final instant = DateTime.utc(2026, 3, 15, 2, 30).millisecondsSinceEpoch;

    // Made once per test rather than inside the helper, so the helper stays a
    // plain call `expectLater` can be handed.
    late String regimeId;
    setUp(() async => regimeId = await aRegime());

    Future<void> logged({
      required int dayKey,
      required int offsetMinutes,
      int? startedAt,
    }) =>
        db.into(db.workouts).insert(WorkoutsCompanion.insert(
              id: Value(newId()),
              regimeId: regimeId,
              dayKey: dayKey,
              startedAt: Value(startedAt ?? instant),
              tzOffsetMinutes: offsetMinutes,
            ));

    test('the day west of the line is that instant in New York', () async {
      await logged(dayKey: 20260314, offsetMinutes: -300);
      expect(await db.workouts.count().getSingle(), 1);
    });

    test('the day east of it is the same instant in Delhi', () async {
      await logged(dayKey: 20260315, offsetMinutes: 330);
      expect(await db.workouts.count().getSingle(), 1);
    });

    test('New York cannot file that instant under the 15th', () async {
      await expectLater(
        logged(dayKey: 20260315, offsetMinutes: -300),
        throwsA(isA<SqliteException>()),
        reason: 'the heatmap rings it on one day and history files it under '
            'another, and it is reachable from neither reliably',
      );
    });

    test('Delhi cannot file that instant under the 14th', () async {
      await expectLater(
        logged(dayKey: 20260314, offsetMinutes: 330),
        throwsA(isA<SqliteException>()),
      );
    });

    test('the last minute of the local day still belongs to it', () async {
      // 04:59Z is 23:59 in New York on the 14th; one minute later is midnight.
      await logged(
        dayKey: 20260314,
        offsetMinutes: -300,
        startedAt: DateTime.utc(2026, 3, 15, 4, 59).millisecondsSinceEpoch,
      );
      expect(await db.workouts.count().getSingle(), 1);
    });

    test('the first minute of the next one does not', () async {
      await expectLater(
        logged(
          dayKey: 20260314,
          offsetMinutes: -300,
          startedAt: DateTime.utc(2026, 3, 15, 5).millisecondsSinceEpoch,
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('an offset no place on earth keeps is refused', () async {
      // Nothing runs further east than +14:00, and an out-of-range offset is
      // the shape a hand-edited file takes when it tries to talk the CHECK
      // into accepting a mismatched pair.
      await expectLater(
        logged(dayKey: 20260315, offsetMinutes: 900),
        throwsA(isA<SqliteException>()),
      );
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
          id: Value(workout),
          regimeId: regime,
          dayKey: dayKeyOf(logged),
          startedAt: Value(logged.millisecondsSinceEpoch),
          tzOffsetMinutes: tzOffsetOf(logged)));
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
            id: Value(newId()),
            regimeId: await aRegime(),
            dayKey: 0,
            tzOffsetMinutes: tzOffsetOf(logged))),
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
              // Two seconds into 1970 at UTC, so the only thing wrong with
              // this row is the one thing under test.
              dayKey: 19700101,
              startedAt: const Value(2000),
              tzOffsetMinutes: 0,
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
