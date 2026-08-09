import 'dart:convert';

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

    final sets = await db.select(db.setLogs).get();
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

  test('a backup from an older schema still restores', () async {
    await logASession();
    final payload = await backup.buildPayload();
    payload['schemaVersion'] = 1;

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await BackupService(fresh).restore(jsonEncode(payload));

    expect((await fresh.select(fresh.workouts).get()).length, 1);
  });
}
