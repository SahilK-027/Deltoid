import 'dart:convert';

import 'package:deltoid/core/progress.dart';
import 'package:deltoid/data/backup/backup_service.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../seed_years.dart' show buildSeedPayload;

/// The seed generator writes a backup file, and a backup file the importer
/// rejects is a generator nobody finds out is broken until they are standing in
/// a gym with an empty app. This restores what it produces.
void main() {
  late AppDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a generated year restores through the real importer', () async {
    final json = jsonEncode(buildSeedPayload(years: 1, seed: 7));

    final result = await BackupService(db).restore(json);

    expect(result.rowsWritten, greaterThan(1000));
    expect(await db.select(db.workouts).get(), isNotEmpty);
    expect(await db.select(db.setLogs).get(), isNotEmpty);
  });

  test('a file bigger than one batch restores whole, and reports progress',
      () async {
    // The importer writes in chunks of 500. A file with more rows than that in
    // one table is the case that would break silently if the chunking were
    // off by one — and the only case that takes long enough on a phone to need
    // the progress callback that stops it looking hung.
    final json = jsonEncode(buildSeedPayload(years: 2, seed: 3));
    final counts = <String, int>{};

    final fractions = <double>[];
    final result = await BackupService(db).restore(
      json,
      onProgress: (step) {
        if (step.phase != JobPhase.writing) return;
        counts[step.detail] = step.rows;
        if (step.fraction != null) fractions.add(step.fraction!);
      },
    );

    expect(counts, isNotEmpty, reason: 'progress was never reported');
    expect(counts.values.last, result.rowsWritten);
    // A bar that goes backwards is worse than no bar.
    expect(fractions, isNotEmpty);
    expect(
      List.of(fractions)..sort(),
      fractions,
      reason: 'progress went backwards',
    );
    expect(fractions.every((f) => f >= 0 && f <= 1), isTrue);

    final sets = await db.select(db.setLogs).get();
    expect(sets.length, greaterThan(500));
    expect(
      (jsonDecode(json) as Map)['counts']['set_logs'],
      sets.length,
      reason: 'a chunk went missing',
    );
  });

  test('nobody deadlifts 900kg after fifty years', () async {
    // Progression used to be a fixed increment per session, which is fine for
    // a month and absurd for a decade: it produced barbell numbers no human
    // has lifted and lateral raises heavier than the bar. Loads approach a
    // ceiling instead, so a long history plateaus like a real one.
    await BackupService(db).restore(
      jsonEncode(buildSeedPayload(years: 50, seed: 5)),
    );

    final rows = await (db.select(db.setLogs).join([
      innerJoin(
        db.workoutExercises,
        db.workoutExercises.id.equalsExp(db.setLogs.workoutExerciseId),
      ),
      innerJoin(
        db.exercises,
        db.exercises.id.equalsExp(db.workoutExercises.exerciseId),
      ),
    ])).get();

    for (final row in rows) {
      final weight = row.readTable(db.setLogs).weight;
      if (weight == null) continue;
      final exercise = row.readTable(db.exercises);
      // Generous on purpose: this is a guard against a decade of linear
      // increments, not a judgement on anyone's leg press. A 220kg leg press
      // is a real number; a 900kg deadlift is a bug.
      final limit = exercise.loadMode == LoadMode.perSide ? 50.0 : 260.0;
      expect(
        weight,
        lessThanOrEqualTo(limit),
        reason: '${exercise.name} reached $weight kg',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the data it writes is the shape the app reads', () async {
    await BackupService(db).restore(
      jsonEncode(buildSeedPayload(years: 1, seed: 7)),
    );
    final repo = TrainingRepository(db);

    // History pages, the chart has points, and prefill resolves — the three
    // reads every screen this data exists to fill goes through.
    final feed = await repo.workoutFeed(limit: 20);
    expect(feed, hasLength(20));

    final exerciseId =
        (await db.select(db.workoutExercises).get()).first.exerciseId;
    expect(await repo.exerciseProgress(exerciseId), isNotEmpty);
  });

  test('each session slot progresses on its own numbers', () async {
    // The one rule the app exists for: the same movement in two sessions must
    // not share a progression. If the generator collapsed them, the dataset
    // would hide exactly the bug it is meant to help catch.
    await BackupService(db).restore(
      jsonEncode(buildSeedPayload(years: 2, seed: 11)),
    );

    final rows = await (db.select(db.workoutExercises).join([
      innerJoin(db.workouts, db.workouts.id.equalsExp(db.workoutExercises.workoutId)),
      innerJoin(db.setLogs,
          db.setLogs.workoutExerciseId.equalsExp(db.workoutExercises.id)),
    ])).get();

    // Group the heaviest logged weight by session + exercise.
    final heaviest = <String, double>{};
    for (final row in rows) {
      final set = row.readTable(db.setLogs);
      final weight = set.weight;
      if (weight == null) continue;
      final key = '${row.readTable(db.workouts).sessionId}'
          ':${row.readTable(db.workoutExercises).exerciseId}';
      final current = heaviest[key] ?? 0;
      heaviest[key] = weight > current ? weight : current;
    }

    // Movements trained in more than one session should differ between them:
    // separate progressions drift apart, a shared one cannot.
    final byExercise = <String, Set<double>>{};
    for (final entry in heaviest.entries) {
      final exerciseId = entry.key.split(':').last;
      byExercise.putIfAbsent(exerciseId, () => {}).add(entry.value);
    }
    final shared = byExercise.values.where((v) => v.length > 1);
    expect(shared, isNotEmpty,
        reason: 'no movement appeared in two sessions with its own numbers');
  });
}
