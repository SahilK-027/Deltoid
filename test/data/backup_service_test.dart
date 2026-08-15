import 'dart:convert';
import 'dart:io';

import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/backup/backup_service.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late BackupService backup;

  setUpAll(() {
    // These tests deliberately open a second database to stand in for a new
    // phone; the multiple-instance warning is expected here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    backup = BackupService(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );

    // Form videos are user-entered, so the round trip has to be given one
    // before it can prove the JSON-list column survives.
    final pullup = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Pull-up')))
        .getSingle();
    await RegimeRepository(db).updateExercise(
      pullup.id,
      videos: const Value(['https://example.com/pull-up']),
    );
  });

  tearDown(() => db.close());

  /// Logs one real session so the export has history, not just templates.
  Future<void> logASession() async {
    final regime =
        await (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
            .getSingle();
    final push1 =
        await (db.select(db.sessions)..where((t) => t.name.equals('Push 1')))
            .getSingle();
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);
    for (final set in detail!.entries.first.sets) {
      await repo.updateSet(
        set.id,
        weight: const Value(22.5),
        reps: const Value(8),
        isDone: const Value(true),
      );
    }
    await repo.completeWorkout(id);
    await repo.logBodyweight(DateTime(2026, 7, 20), 72.4);
  }

  test('export captures every table', () async {
    await logASession();
    final payload = await backup.buildPayload();

    expect(payload['format'], backupFormatVersion);
    expect(payload['schemaVersion'], db.schemaVersion);

    final counts = payload['counts'] as Map;
    expect(counts['exercises'], greaterThan(20));
    expect(counts['regimes'], 1);
    expect(counts['sessions'], 6);
    expect(counts['workouts'], 1);
    // Every set row the session created, tombstones included: finishing a
    // workout marks the untouched blanks deleted rather than removing them, and
    // a backup that dropped the tombstones would resurrect them on restore.
    expect(counts['set_logs'], 18);
    final liveSets = await (db.select(db.setLogs)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    expect(liveSets, hasLength(3));
    expect(counts['bodyweight_logs'], 1);
  });

  test('restoring into an empty database reproduces it exactly', () async {
    await logASession();
    final json = jsonEncode(await backup.buildPayload());
    final before = await backup.buildPayload();

    // A brand new device.
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    final freshBackup = BackupService(fresh);
    await fresh.customStatement('PRAGMA foreign_keys = ON');

    final result = await freshBackup.restore(json);
    expect(result.rowsWritten, greaterThan(0));

    final after = await freshBackup.buildPayload();
    expect(after['counts'], before['counts']);
    expect(after['data'], before['data']);
  });

  test('restore replaces rather than merges', () async {
    await logASession();
    final json = jsonEncode(await backup.buildPayload());

    // A second session logged after the export must not survive the restore.
    await logASession();
    expect((await db.select(db.workouts).get()).length, 2);

    await backup.restore(json);
    expect((await db.select(db.workouts).get()).length, 1);
  });

  test('enum and list columns survive the round trip', () async {
    await logASession();
    final json = jsonEncode(await backup.buildPayload());
    await backup.restore(json);

    final pullup = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Pull-up')))
        .getSingle();
    expect(pullup.loadMode, LoadMode.bodyweightPlus);
    expect(pullup.muscle, MuscleGroup.back);
    expect(pullup.formVideoUrls, isNotEmpty);
    expect(pullup.formVideoUrls.first, startsWith('https://'));

    // Ordered, and only the rows that were actually logged. `logASession`
    // fills the first exercise and leaves the rest blank, and finishing
    // tombstones those blanks rather than deleting them — so an unordered
    // `.first` was a coin toss between a set with 22.5 in it and one of the
    // fifteen tombstones with nothing in it, which failed about one run in
    // five. Restoring re-inserts every row, so physical order is not stable
    // across the round trip this test exists to check.
    final sets = await (db.select(db.setLogs)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
        .get();
    expect(sets, isNotEmpty);
    expect(sets.first.setType, SetType.working);
    expect(sets.first.weight, 22.5);

    final bodyweight = await db.select(db.bodyweightLogs).getSingle();
    expect(bodyweight.weightKg, 72.4);
  });

  test('a file written before a column existed still restores', () async {
    await logASession();
    final payload = await backup.buildPayload();

    // Exactly what an older export looks like: the column is simply not there.
    // `Exercise.fromJson` is generated against today's columns and reads every
    // one of them, so without a default this throws — with the user's only
    // copy of their history in the file picker.
    final data = payload['data']! as Map<String, dynamic>;
    data['exercises'] = (data['exercises']! as List)
        .cast<Map<String, dynamic>>()
        .map((row) => {...row}..remove('barKind'))
        .toList();

    await backup.restore(jsonEncode(payload));

    final restored = await db.select(db.exercises).get();
    expect(restored, isNotEmpty);
    expect(
      restored.every((e) => e.barKind == BarKind.none),
      isTrue,
      reason: 'a bar nobody named is no bar, not a guess',
    );
  });

  test('a logged row without a muscle snapshot restores, and stays honest',
      () async {
    await logASession();
    final payload = await backup.buildPayload();

    final data = payload['data']! as Map<String, dynamic>;
    data['workout_exercises'] = (data['workout_exercises']! as List)
        .cast<Map<String, dynamic>>()
        .map((row) => {...row}..remove('muscle'))
        .toList();

    await backup.restore(jsonEncode(payload));

    final restored = await db.select(db.workoutExercises).get();
    expect(restored, isNotEmpty);
    expect(
      restored.every((e) => e.muscle == null),
      isTrue,
      reason: 'null means "logged before the column existed, ask the catalog" '
          '— defaulting to `other` would file the sets under no region and '
          'drop them from every chart',
    );
  });

  test('the bar a movement is loaded on survives the round trip', () async {
    await logASession();
    final bench = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Flat Barbell Bench Press')))
        .getSingleOrNull();
    // The seed catalog decides the name; if it changes, take any exercise.
    final target = bench ?? (await db.select(db.exercises).get()).first;
    await RegimeRepository(db)
        .updateExercise(target.id, barKind: const Value(BarKind.ez));

    await backup.restore(jsonEncode(await backup.buildPayload()));

    final after = await (db.select(db.exercises)
          ..where((t) => t.id.equals(target.id)))
        .getSingle();
    expect(after.barKind, BarKind.ez);
  });

  test('a malformed file is rejected before anything is deleted', () async {
    await logASession();
    final before = (await db.select(db.workouts).get()).length;

    expect(() => backup.inspect('not json at all'), throwsFormatException);
    expect(() => backup.inspect('{"hello":"world"}'), throwsFormatException);
    await expectLater(backup.restore('{"hello":"world"}'), throwsFormatException);

    expect((await db.select(db.workouts).get()).length, before);
  });

  test('the streamed file is exactly the payload, and restores', () async {
    await logASession();

    final file = File(
      '${Directory.systemTemp.createTempSync('deltoid').path}/backup.json',
    );
    addTearDown(() => file.parent.deleteSync(recursive: true));

    var lastFraction = 0.0;
    var lastRows = 0;
    await backup.writeBackup(file, onProgress: (step) {
      lastRows = step.rows;
      lastFraction = step.fraction ?? lastFraction;
    });

    // Written a page at a time, so the shape has to be assembled by hand — and
    // the thing that keeps that honest is that it must equal what `jsonEncode`
    // of the whole payload would have produced.
    final streamed = jsonDecode(file.readAsStringSync());
    final built = jsonDecode(jsonEncode(await backup.buildPayload()));
    // `exportedAt` is stamped as each is made, so it is the one key that may
    // differ.
    (streamed as Map).remove('exportedAt');
    (built as Map).remove('exportedAt');
    expect(streamed, built);

    expect(lastRows, greaterThan(0));
    expect(lastFraction, closeTo(1.0, 0.001));

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    final service = BackupService(fresh);
    await service.restore(
      null,
      decoded: await service.decodeStream(file.openRead()),
    );
    expect((await fresh.select(fresh.workouts).get()).length, 1);
  });

  group('an export reads a moving table without losing its place', () {
    // Its own database, holding one populated table. The seam below fires at
    // every page boundary the export crosses, and the shared fixture's starter
    // catalog would trip it long before `bodyweight_logs` is reached — the
    // injected row would land while the export was still on `exercises`, and
    // the table under test would be stable by the time it was read. An empty
    // table returns a short page and no boundary, so here only the rows below
    // can fire it.
    late AppDatabase own;

    /// A bodyweight row with a chosen id, written straight to the table.
    ///
    /// The id is the whole point, so it is not `newId()`: these tests need to
    /// place a row on a known side of a page boundary. `dayKey` only has to be
    /// unique — one live row per day is a partial index.
    Future<void> weighIn(String id, int day) =>
        own.into(own.bodyweightLogs).insert(
              BodyweightLogsCompanion.insert(
                dayKey: 20260100 + day,
                weightKg: 80,
                id: Value(id),
                deviceId: const Value('this-phone'),
              ),
            );

    /// Every `bodyweight_logs` id in the file [service] writes, in file order.
    Future<List<String>> exportedIds(BackupService service) async {
      final file = File(
        '${Directory.systemTemp.createTempSync('deltoid').path}/moving.json',
      );
      addTearDown(() => file.parent.deleteSync(recursive: true));
      await service.writeBackup(file);
      final rows = (jsonDecode(file.readAsStringSync())
          as Map)['data']['bodyweight_logs'] as List;
      return [for (final r in rows) (r as Map)['id'] as String];
    }

    setUp(() async {
      own = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(own.close);
      for (var i = 0; i < 4; i++) {
        await weighIn('id-${(i + 1) * 2}', i + 1);
      }
    });

    test('a row arriving behind the cursor is not written twice', () async {
      // `id-1` sorts before every seeded row, so under offset paging it shifts
      // all of them one place *forward* and the row on the boundary is read a
      // second time. A duplicate id is refused by the restore's primary key,
      // so this is the loud half of the hole — but it means an export taken at
      // the wrong moment produces a file that cannot be restored at all.
      //
      // An id below every existing one is not hypothetical once sync lands: a
      // row merged from the other phone was created there, earlier, and UUID v7
      // carries that earlier time in its leading bits.
      var injected = false;
      final service = BackupService(own, pageSize: 2, betweenPages: () async {
        if (injected) return;
        injected = true;
        await weighIn('id-1', 9);
      });

      final ids = await exportedIds(service);

      expect(injected, isTrue, reason: 'the seam never fired; no boundary');
      expect(ids.toSet().length, ids.length, reason: 'a row was written twice');
    });

    test('a row leaving behind the cursor does not take a neighbour', () async {
      // The silent half, and the one that matters more. A delete behind the
      // cursor shifts every later row one place *back*, so the row sitting on
      // the boundary is stepped over and is absent from the file with nothing
      // said.
      //
      // Nothing in the app hard-deletes outside the restore's `clear()`
      // closures (entry 30), which is the only reason this is not reachable
      // today. That is a property of a different file, and the export should
      // not be resting on it.
      var injected = false;
      final service = BackupService(own, pageSize: 2, betweenPages: () async {
        if (injected) return;
        injected = true;
        await (own.delete(own.bodyweightLogs)
              ..where((t) => t.id.equals('id-2')))
            .go();
      });

      final ids = await exportedIds(service);

      expect(injected, isTrue, reason: 'the seam never fired; no boundary');
      // `id-2` is gone by the time the file closes, so it is allowed to be
      // missing. Every row that outlived the export has to be in there.
      expect(ids, containsAll(['id-4', 'id-6', 'id-8']));
    });
  });

  test('an empty database still writes a file that restores', () async {
    final empty = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(empty.close);
    final service = BackupService(empty);

    final file = File(
      '${Directory.systemTemp.createTempSync('deltoid').path}/empty.json',
    );
    addTearDown(() => file.parent.deleteSync(recursive: true));
    await service.writeBackup(file);

    // The separators are written by hand, so the degenerate cases — no rows at
    // all, and a table between two others that is empty — are where a stray
    // comma would land.
    final decoded = await service.decodeStream(file.openRead());
    expect(service.summarise(decoded).totalRows, 0);
    await service.restore(null, decoded: decoded);
  });

  test('a file restores from its bytes without ever being one string',
      () async {
    await logASession();
    final bytes = utf8.encode(jsonEncode(await backup.buildPayload()));

    // In chunks, as a file arrives off disk — and split mid-character, because
    // a naive chunked decode cuts the app's own `·` in half and throws.
    Stream<List<int>> inChunks() async* {
      const size = 64;
      for (var i = 0; i < bytes.length; i += size) {
        yield bytes.sublist(i, (i + size).clamp(0, bytes.length));
      }
    }

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    final service = BackupService(fresh);

    final decoded = await service.decodeStream(inChunks());
    final result = await service.restore(null, decoded: decoded);

    expect(result.rowsWritten, greaterThan(0));
    expect((await fresh.select(fresh.workouts).get()).length, 1);
    // The `·` in the template's own name is the character that caught the
    // Latin-1 read; it has to survive this path too.
    final regime = await (fresh.select(fresh.regimes)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
    expect(regime.name, contains('·'));
  });

  test('a stream that is not a backup is refused', () async {
    Stream<List<int>> streamOf(String s) => Stream.value(utf8.encode(s));

    await expectLater(
      backup.decodeStream(streamOf('not json at all')),
      throwsFormatException,
    );
    await expectLater(
      backup.decodeStream(streamOf('[1,2,3]')),
      throwsFormatException,
    );
  });

  test('a backup from a newer app version is refused', () {
    final future = jsonEncode({
      'format': backupFormatVersion + 1,
      'data': <String, dynamic>{},
      'counts': <String, dynamic>{},
    });
    expect(() => backup.inspect(future), throwsFormatException);
  });

  test('inspect reports what the file holds without touching the database',
      () async {
    await logASession();
    final json = jsonEncode(await backup.buildPayload());

    final summary = backup.inspect(json);
    expect(summary.counts['workouts'], 1);
    expect(summary.totalRows, greaterThan(30));
    expect((await db.select(db.workouts).get()).length, 1);
  });

  test('exercise history is still queryable after a restore', () async {
    await logASession();
    final json = jsonEncode(await backup.buildPayload());

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await BackupService(fresh).restore(json);

    final freshRepo = TrainingRepository(fresh);
    final incline = await (fresh.select(fresh.exercises)
          ..where((t) => t.name.equals('Incline DB Press')))
        .getSingle();
    final past = await freshRepo.pastPerformances(incline.id);

    expect(past, hasLength(1));
    expect(past.first.sessionName, 'Push 1');
    expect(past.first.sets.first.weight, 22.5);
  });

  test('a backup from a newer schema is refused rather than half-applied',
      () async {
    await logASession();
    final payload = await backup.buildPayload();
    // A file written by a build that knows a column, or an enum value, this
    // one does not. Restoring it clears every table first, so the failure
    // would land after the old data was gone.
    payload['schemaVersion'] = db.schemaVersion + 1;
    final json = jsonEncode(payload);

    expect(() => backup.inspect(json), throwsA(isA<FormatException>()));
    await expectLater(backup.restore(json), throwsA(isA<FormatException>()));
    // Nothing was cleared on the way to refusing.
    expect((await db.select(db.workouts).get()).length, 1);
  });

  // A restore from a *lower* schema stamp used to be tested here. At schema 1
  // there is no lower number to stamp, and what that test was really reaching
  // for — a row that arrives without a column this build reads — is covered
  // properly by 'a file written before a column existed still restores'.

  /// INVARIANTS.md 4 and 6 — a restore replaces the database entirely or
  /// changes nothing, and it lands every row the file claims to carry.
  ///
  /// Both are about the same moment: `restore` empties every table before it
  /// inserts anything, so from the first `clear()` until the commit the only
  /// copy of the history is the file being read. A file that turns out to be
  /// wrong halfway through must take the whole restore back with it, and a
  /// file that is quietly *short* must not be accepted as complete.
  group('a restore is all of the file or none of it', () {
    /// A workout id and the row counts, to compare against after a failure.
    Future<(String, Map<String, int>)> census() async {
      final workout = (await db.select(db.workouts).get()).first;
      return (
        workout.id,
        {
          'workouts': (await db.select(db.workouts).get()).length,
          'setLogs': (await db.select(db.setLogs).get()).length,
          'exercises': (await db.select(db.exercises).get()).length,
          'bodyweight': (await db.select(db.bodyweightLogs).get()).length,
        },
      );
    }

    test('a row violating a CHECK leaves the pre-restore database intact',
        () async {
      await logASession();
      final (workoutId, before) = await census();

      final payload = await backup.buildPayload();
      // `CHECK (cycle_index >= 1)`. A hand-edited export, or — once 5b lands —
      // a merged one. The row is legal JSON and illegal SQL, which is the only
      // way to reach the middle of the transaction.
      final cycles = payload['data']['cycles'] as List;
      (cycles.first as Map)['cycleIndex'] = 0;

      await expectLater(backup.restore(jsonEncode(payload)), throwsA(anything));

      final (workoutIdAfter, after) = await census();
      expect(after, before, reason: 'the clear was not rolled back');
      expect(workoutIdAfter, workoutId);
    });

    test('a file whose body is shorter than its header is refused', () async {
      await logASession();
      await repo.logBodyweight(DateTime(2026, 3, 1), 80);
      final (workoutId, before) = await census();

      final payload = await backup.buildPayload();
      // A leaf table, so dropping a row models a short body without also
      // breaking a foreign key and failing for the wrong reason. This is
      // exactly what entry 5's export race produces: the header counted the
      // rows before the pages were read, and one row never made it out.
      final rows = payload['data']['bodyweight_logs'] as List;
      expect(rows, isNotEmpty, reason: 'the fixture must have a row to drop');
      rows.removeLast();

      await expectLater(backup.restore(jsonEncode(payload)), throwsA(anything));

      final (workoutIdAfter, after) = await census();
      expect(after, before);
      expect(workoutIdAfter, workoutId);
    });

    test('a body longer than its header is accepted', () async {
      // The guard must be `restored < declared`, not `!=`. The header is
      // counted before the pages are read, so a set logged mid-export makes
      // the body honestly longer — and refusing that would reject good files.
      await logASession();

      final payload = await backup.buildPayload();
      final rows = payload['data']['bodyweight_logs'] as List;
      final declared = rows.length;
      rows.add({
        'id': 'extra-row',
        'dayKey': 20260301,
        'weightKg': 80.0,
        'updatedAt': 1,
        'deviceId': 'other-phone',
        'dirty': true,
      });

      await backup.restore(jsonEncode(payload));

      expect((await db.select(db.bodyweightLogs).get()).length, declared + 1);
    });

    test('a file with two regimes on one hue is refused', () async {
      // The route INVARIANTS § 20 names. The backfill at the end of the
      // restore only runs when a row *lacks* `identityIndex`, so a file that
      // carries the key on every regime is taken at its word — and a file
      // carrying it twice with the same value landed two programmes on one
      // colour, which RULES § 2 says must never happen. No app path writes
      // such a file; a hand edit or a merge does.
      await createRegimeFromTemplate(
        db,
        regimeTemplates.firstWhere((t) => t.key == 'blank'),
        name: 'Second',
        // Inactive, so `logASession` still finds the seeded PPL regime and its
        // Push 1 rather than an empty programme with no sessions in it.
        activate: false,
      );
      await logASession();
      final (workoutId, before) = await census();

      final payload = await backup.buildPayload();
      final regimes = payload['data']['regimes'] as List;
      expect(regimes.length, 2, reason: 'the fixture must hold two regimes');
      final hue = (regimes.first as Map)['identityIndex'];
      expect(hue, isNotNull, reason: 'a file that omits the key is backfilled');
      (regimes.last as Map)['identityIndex'] = hue;

      await expectLater(backup.restore(jsonEncode(payload)), throwsA(anything));

      final (workoutIdAfter, after) = await census();
      expect(after, before, reason: 'the clear was not rolled back');
      expect(workoutIdAfter, workoutId);
    });

    test('a file with a drop leg pointing into another exercise is refused',
        () async {
      // `parent_set_id` was a reference to `set_logs (id)` and nothing more, so
      // the head had to exist but could sit under any slot in the file. The app
      // cannot write one — `addDropLeg` walks one slot's list — and this is the
      // route INVARIANTS § 14 names for it.
      await logASession();
      final (workoutId, before) = await census();

      final payload = await backup.buildPayload();
      final sets = (payload['data']['set_logs'] as List).cast<Map>();
      final head = sets.first;
      final elsewhere = sets.firstWhere(
        (s) => s['workoutExerciseId'] != head['workoutExerciseId'],
        orElse: () => throw StateError('the fixture must span two slots'),
      );
      elsewhere['parentSetId'] = head['id'];

      await expectLater(backup.restore(jsonEncode(payload)), throwsA(anything));

      final (workoutIdAfter, after) = await census();
      expect(after, before, reason: 'the clear was not rolled back');
      expect(workoutIdAfter, workoutId);
    });

    test('a file with a workout on two days at once is refused', () async {
      // The route INVARIANTS § 9 names. `day_key` is what the heatmap and the
      // calendar ring; `started_at` is what History pages by. A row where they
      // disagree is drawn on one day and filed under another.
      await logASession();
      final (workoutId, before) = await census();

      final payload = await backup.buildPayload();
      final workouts = (payload['data']['workouts'] as List).cast<Map>();
      final day = workouts.first['dayKey'] as int;
      workouts.first['dayKey'] = day - 1;

      await expectLater(backup.restore(jsonEncode(payload)), throwsA(anything));

      final (workoutIdAfter, after) = await census();
      expect(after, before, reason: 'the clear was not rolled back');
      expect(workoutIdAfter, workoutId);
    });

    test('a file written before the zone offset existed still restores',
        () async {
      // Backup files outlive reinstalls — that is what they are for — so a file
      // written before `tz_offset_minutes` has no key for it, and the column is
      // required. [impliedTzOffset] supplies the one the file's own two date
      // columns imply, and the pair survives the round trip unchanged.
      await logASession();

      final payload = await backup.buildPayload();
      final workouts = (payload['data']['workouts'] as List).cast<Map>();
      final was = {
        for (final w in workouts) w['id'] as String: w['dayKey'] as int,
      };
      for (final w in workouts) {
        w.remove('tzOffsetMinutes');
      }

      await backup.restore(jsonEncode(payload));

      final restored = await db.select(db.workouts).get();
      expect(restored, hasLength(was.length));
      for (final w in restored) {
        expect(w.dayKey, was[w.id], reason: 'the day the file named');
      }
    });

    test('a pre-offset file keeps the day it names, not this zone', () async {
      // A file written west of here and restored on this phone: `started_at` is
      // an absolute instant and survives, but the day *this* zone derives from
      // it is the following one. The file's day wins — it is the day the user
      // saw — and the offset is fitted to it. Unlike the refusal above there is
      // no offset in the file for the day key to contradict.
      //
      // 02:30 UTC on the 15th is still the 14th anywhere at or west of
      // UTC-02:31, so the least move that lands it back on the 14th is
      // -02:31 = **-151 minutes**, which puts it at 23:59 on the 14th. That is
      // a hand-computed golden and it does not depend on the zone this test
      // runs in: the nudge is measured from wherever the machine sits and
      // stops at the same minute either way.
      await logASession();

      final payload = await backup.buildPayload();
      final workouts = (payload['data']['workouts'] as List).cast<Map>();
      expect(workouts, hasLength(1), reason: 'one session, one instant');
      workouts.first
        ..remove('tzOffsetMinutes')
        ..['startedAt'] = DateTime.utc(2026, 3, 15, 2, 30).millisecondsSinceEpoch
        ..['dayKey'] = 20260314;

      await backup.restore(jsonEncode(payload));

      final restored = await db.select(db.workouts).getSingle();
      expect(restored.dayKey, 20260314);
      expect(restored.tzOffsetMinutes, -151);
    });

    test('a pre-offset file no offset can rescue is refused', () async {
      // Three days is further than any zone reaches, so no value inside
      // ±(12, 14) hours reconciles the pair and the file is refused whole. It
      // was already claiming two days; the column only made that visible.
      await logASession();
      final (workoutId, before) = await census();

      final payload = await backup.buildPayload();
      for (final w in (payload['data']['workouts'] as List).cast<Map>()) {
        w.remove('tzOffsetMinutes');
        w['dayKey'] = _dayBefore(w['dayKey'] as int, 3);
      }

      await expectLater(backup.restore(jsonEncode(payload)), throwsA(anything));

      final (workoutIdAfter, after) = await census();
      expect(after, before, reason: 'the clear was not rolled back');
      expect(workoutIdAfter, workoutId);
    });
  });
}

/// [days] before [key], as a day key — calendar arithmetic, so it holds at a
/// month boundary where subtracting from the integer does not.
int _dayBefore(int key, int days) =>
    dayKeyOf(daysBefore(dateFromDayKey(key), days));
