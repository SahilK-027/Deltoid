import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regimes are additive: creating one only moves the active flag. These are the
/// rules that make "I made a new regime and the old one disappeared" false.
void main() {
  late AppDatabase db;
  late RegimeRepository repo;
  late TrainingRepository training;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RegimeRepository(db);
    training = TrainingRepository(db);
    await ensureStarterCatalog(db);
  });

  tearDown(() => db.close());

  Future<List<Regime>> living() => (db.select(db.regimes)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
      .get();

  test('creating a regime keeps the ones before it', () async {
    final first = await repo.createRegime('PPL');
    final second = await repo.createRegime('Upper / Lower');

    final all = await living();
    expect(all.map((r) => r.id), [first, second]);
    expect(all.where((r) => r.isActive).map((r) => r.id), [second]);

    final summaries = await repo.regimeSummaries();
    expect(summaries.map((s) => s.regime.name), ['PPL', 'Upper / Lower']);
  });

  test('switching back makes exactly one regime active', () async {
    final first = await repo.createRegime('PPL');
    await repo.createRegime('Upper / Lower');

    await repo.setActiveRegime(first);

    final active = (await living()).where((r) => r.isActive).toList();
    expect(active, hasLength(1));
    expect(active.single.id, first);
  });

  test('summaries count sessions and logged workouts per regime', () async {
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    final regime = (await living()).single;
    final push1 = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();

    final id = await training.startWorkout(
        regimeId: regime.id, sessionId: push1.id);
    final detail = await training.workoutDetail(id);
    await training.updateSet(detail!.entries.first.sets.first.id,
        weight: const Value(20),
        reps: const Value(8),
        isDone: const Value(true));
    await training.completeWorkout(id);

    final summary = (await repo.regimeSummaries()).single;
    expect(summary.sessionCount, 6);
    expect(summary.workoutCount, 1);
  });

  test('deleting the active regime hands over to another one', () async {
    final first = await repo.createRegime('PPL');
    final second = await repo.createRegime('Upper / Lower');

    await repo.deleteRegime(second);

    final all = await living();
    expect(all.map((r) => r.id), [first]);
    expect(all.single.isActive, isTrue,
        reason: 'the app must never be left with no regime while one exists');
  });

  test('deleting a regime leaves its workouts in history', () async {
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    final regime = (await living()).single;
    final push1 = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();

    final id = await training.startWorkout(
        regimeId: regime.id, sessionId: push1.id);
    final detail = await training.workoutDetail(id);
    await training.updateSet(detail!.entries.first.sets.first.id,
        weight: const Value(22.5),
        reps: const Value(8),
        isDone: const Value(true));
    await training.completeWorkout(id);

    await repo.createRegime('Upper / Lower');
    await repo.deleteRegime(regime.id);

    final feed = await training.workoutFeed();
    expect(feed, hasLength(1));
    expect(feed.single.workout.id, id);
    expect(feed.single.sessionName, 'Push 1');
  });

  test('an exercise carries its own rest, and can be handed back the default',
      () async {
    // The column has existed since the first migration and could only be set
    // by nudging the ± on a timer that was already running — which meant the
    // one thing it is for, deciding that a heavy compound gets three minutes,
    // could not be done while planning the day.
    final regimeId = await repo.createRegime('PPL');
    final sessionId = await repo.addSession(regimeId, 'Push 1');
    final exercise = await (db.select(db.exercises)..limit(1)).getSingle();
    final slotId = await repo.addExerciseToSession(sessionId, exercise.id);

    Future<int?> stored() async => (await (db.select(db.sessionExercises)
              ..where((t) => t.id.equals(slotId)))
            .getSingle())
        .restSeconds;

    // Null is not "no rest": it is "use the default", which is what
    // `restTargetFor` reads when it finds nothing here.
    expect(await stored(), isNull);
    expect(
      await training.restTargetFor(
          exerciseId: exercise.id, sessionId: sessionId),
      120,
    );

    await repo.updateSessionExercise(slotId, restSeconds: const Value(180));
    expect(await stored(), 180);
    expect(
      await training.restTargetFor(
          exerciseId: exercise.id, sessionId: sessionId),
      180,
    );

    await repo.updateSessionExercise(slotId, restSeconds: const Value(null));
    expect(await stored(), isNull);
    expect(
      await training.restTargetFor(
          exerciseId: exercise.id, sessionId: sessionId),
      120,
    );

    // A write that says nothing about rest leaves it alone.
    await repo.updateSessionExercise(slotId, restSeconds: const Value(150));
    await repo.updateSessionExercise(slotId, targetSets: const Value(4));
    expect(await stored(), 150);
  });

  test('a removed exercise slot can be put back with its numbers intact',
      () async {
    final regimeId = await repo.createRegime('PPL');
    final sessionId = await repo.addSession(regimeId, 'Push 1');
    final exercise = await (db.select(db.exercises)..limit(1)).getSingle();
    final slotId = await repo.addExerciseToSession(sessionId, exercise.id);
    await repo.updateSessionExercise(slotId, targetSets: const Value(5));

    await repo.removeSessionExercise(slotId);
    expect(
      await (db.select(db.sessionExercises)..where((t) => t.deletedAt.isNull()))
          .get(),
      isEmpty,
    );

    await repo.restoreSessionExercise(slotId);
    final restored = await (db.select(db.sessionExercises)
          ..where((t) => t.deletedAt.isNull()))
        .getSingle();
    expect(restored.id, slotId);
    expect(restored.targetSets, 5);
  });

  test('an archived exercise keeps the workouts that used it', () async {
    final exercise = await (db.select(db.exercises)..limit(1)).getSingle();
    await repo.updateExercise(exercise.id, archived: const Value(true));

    final row = await (db.select(db.exercises)
          ..where((t) => t.id.equals(exercise.id)))
        .getSingle();
    expect(row.archived, isTrue);
    expect(row.deletedAt, isNull, reason: 'past logs point at this row');
  });

  test('load mode survives an edit to the catalog entry', () async {
    final exercise = await (db.select(db.exercises)..limit(1)).getSingle();
    await repo.updateExercise(exercise.id,
        name: const Value('Renamed'), loadMode: const Value(LoadMode.perSide));

    final row = await (db.select(db.exercises)
          ..where((t) => t.id.equals(exercise.id)))
        .getSingle();
    expect(row.name, 'Renamed');
    expect(row.loadMode, LoadMode.perSide);
  });

  group('bar kinds', () {
    test('the seeded catalog ships knowing which bar each lift uses', () async {
      final squat = await (db.select(db.exercises)
            ..where((t) => t.starterKey.equals('back_squat')))
          .getSingle();
      final skull = await (db.select(db.exercises)
            ..where((t) => t.starterKey.equals('skullcrusher')))
          .getSingle();
      final fly = await (db.select(db.exercises)
            ..where((t) => t.starterKey.equals('chest_fly')))
          .getSingle();

      expect(squat.barKind, BarKind.olympic);
      expect(skull.barKind, BarKind.ez);
      expect(fly.barKind, BarKind.none, reason: 'a machine has no bar');
    });

    test('the v3 backfill gives an upgraded catalog its bars', () async {
      // What the migration actually finds: every row carrying the column's
      // default, because the column did not exist when they were written.
      await db.update(db.exercises).write(
            const ExercisesCompanion(barKind: Value(BarKind.none)),
          );

      await backfillSeededBarKinds(db);

      final squat = await (db.select(db.exercises)
            ..where((t) => t.starterKey.equals('back_squat')))
          .getSingle();
      expect(squat.barKind, BarKind.olympic);
    });

    test('the backfill leaves a bar the user has already chosen alone',
        () async {
      final squat = await (db.select(db.exercises)
            ..where((t) => t.starterKey.equals('back_squat')))
          .getSingle();
      // Their gym, their bar: a squat done on the 15kg bar stays on it.
      await repo.updateExercise(
        squat.id,
        barKind: const Value(BarKind.trap),
      );

      await backfillSeededBarKinds(db);

      final after = await (db.select(db.exercises)
            ..where((t) => t.id.equals(squat.id)))
          .getSingle();
      expect(after.barKind, BarKind.trap);
    });

    test('an exercise the user made is never touched by the backfill',
        () async {
      final id = await repo.createExercise(
        name: 'Trap Bar Deadlift',
        muscle: MuscleGroup.back,
        equipment: Equipment.barbell,
        loadMode: LoadMode.total,
      );

      await backfillSeededBarKinds(db);

      final row = await (db.select(db.exercises)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.barKind, BarKind.none, reason: 'no starterKey, no guess');
    });
  
    test('a bar kind that is not a bar kind cannot be stored at all', () async {
      final squat = await (db.select(db.exercises)
            ..where((t) => t.starterKey.equals('back_squat')))
          .getSingle();

      // `standard` was a real member at v3 and was dropped at v4, and this used
      // to be a test that the re-mapping step ran — because a row carrying a
      // name no member answers to does not fail on that row. The enum is read
      // back through `textEnum`, which throws on an unknown string, and the
      // throw takes the whole result set with it: one bad exercise blanked the
      // catalog, the log and every history screen at once.
      //
      // The column refuses the value outright now, so there is no row to
      // re-map and no read that can fail. A future version that retires a
      // member still runs its re-mapping UPDATE — but before the table rebuild
      // that narrows this constraint, never after it, because rows written
      // under the old spelling were legal when they were written.
      await expectLater(
        db.customStatement(
          "UPDATE exercises SET bar_kind = 'standard' WHERE id = ?",
          [squat.id],
        ),
        throwsA(isA<SqliteException>()),
      );

      final after = await (db.select(db.exercises)
            ..where((t) => t.id.equals(squat.id)))
          .getSingle();
      expect(after.barKind, BarKind.olympic, reason: 'the row is untouched');
    });
  });

  // ── Identity slots ──────────────────────────────────────────────────────
  //
  // The mark on a regime is what History and Today are scanned by, so two live
  // regimes must never wear the same colour. There are six, which makes six the
  // number of regimes that can exist at once.

  test('every regime gets a colour of its own', () async {
    final ids = [
      for (var i = 0; i < identitySlots; i++) await repo.createRegime('R$i'),
    ];

    final all = await living();
    expect(all.map((r) => r.id), ids);
    expect(
      all.map((r) => r.identityIndex).toSet(),
      {for (var i = 0; i < identitySlots; i++) i},
    );
  });

  test('the seventh regime is refused rather than sharing a colour', () async {
    for (var i = 0; i < identitySlots; i++) {
      await repo.createRegime('R$i');
    }

    expect(
      () => repo.createRegime('One too many'),
      throwsA(isA<RegimeSlotsFullException>()),
    );
    expect((await living()).length, identitySlots);
  });

  test('a template regime takes a slot and is capped the same way', () async {
    final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    final a = await createRegimeFromTemplate(db, ppl, name: 'One');
    final b = await createRegimeFromTemplate(db, ppl, name: 'Two');

    final all = await living();
    final slots = {for (final r in all) r.id: r.identityIndex};
    expect(slots[a], isNot(slots[b]));

    for (var i = 2; i < identitySlots; i++) {
      await repo.createRegime('R$i');
    }
    expect(
      () => createRegimeFromTemplate(db, ppl, name: 'Surplus'),
      throwsA(isA<RegimeSlotsFullException>()),
    );
  });

  test('deleting a regime hands its colour back', () async {
    final ids = [
      for (var i = 0; i < identitySlots; i++) await repo.createRegime('R$i'),
    ];
    final freed = (await living()).firstWhere((r) => r.id == ids[2]);

    await repo.deleteRegime(ids[2]);
    final replacement = await repo.createRegime('Replacement');

    final all = await living();
    expect(all.length, identitySlots);
    expect(
      all.firstWhere((r) => r.id == replacement).identityIndex,
      freed.identityIndex,
    );
    // And still no two the same.
    expect(all.map((r) => r.identityIndex).toSet().length, identitySlots);
  });

  test('the backfill hands existing rows one slot each, oldest first', () async {
    // Simulates a v4 database coming forward: every row on the column default.
    //
    // `idx_regimes_identity_live` now refuses that state outright, so the only
    // way to build the database the backfill exists for is to stand the index
    // down while writing it — which is honest about where such a phone comes
    // from: a build that predates the column, or a file written by one.
    //
    // The index goes back *after* the backfill, not before, because SQLite
    // will not create a unique index over rows that already violate it. The
    // rebuild succeeding is itself the assertion that the backfill left a
    // state the shipped schema accepts.
    for (var i = 0; i < 3; i++) {
      await repo.createRegime('R$i');
    }
    await db.customStatement('DROP INDEX idx_regimes_identity_live');
    await db.update(db.regimes).write(const RegimesCompanion(
          identityIndex: Value(0),
        ));

    await backfillIdentityIndexes(db);

    await db.customStatement(
      'CREATE UNIQUE INDEX idx_regimes_identity_live '
      'ON regimes (identity_index) WHERE deleted_at IS NULL',
    );

    final all = await living();
    expect(all.map((r) => r.identityIndex), [0, 1, 2]);
  });

  // ── Unique names ────────────────────────────────────────────────────────
  //
  // A regime is identified on screen by its name and its colour. Two called
  // `PPL` is a history nobody can read.

  test('a second regime cannot take a name already in use', () async {
    await repo.createRegime('PPL');

    expect(
      () => repo.createRegime('PPL'),
      throwsA(isA<RegimeNameTakenException>()),
    );
    expect((await living()).length, 1);
  });

  test('the check ignores case and surrounding space', () async {
    await repo.createRegime('PPL');

    expect(
      () => repo.createRegime('  ppl '),
      throwsA(isA<RegimeNameTakenException>()),
    );
  });

  test('a template cannot be applied twice under its own name', () async {
    final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    await createRegimeFromTemplate(db, ppl);

    expect(
      () => createRegimeFromTemplate(db, ppl),
      throwsA(isA<RegimeNameTakenException>()),
    );
    // Under a name of its own it is an ordinary second regime.
    await createRegimeFromTemplate(db, ppl, name: 'PPL heavy');
    expect((await living()).length, 2);
  });

  test('a deleted regime releases its name', () async {
    final id = await repo.createRegime('PPL');
    await repo.deleteRegime(id);

    final second = await repo.createRegime('PPL');
    expect(second, isNot(id));
    expect((await living()).map((r) => r.name), ['PPL']);
  });

  test('renaming onto another regime is refused, onto itself is not', () async {
    final first = await repo.createRegime('PPL');
    final second = await repo.createRegime('Upper / Lower');

    expect(
      () => repo.updateRegime(second, name: const Value('PPL')),
      throwsA(isA<RegimeNameTakenException>()),
    );
    // Saving a regime's own name back is a no-op, not a collision.
    await repo.updateRegime(first, name: const Value('PPL'));
    expect((await living()).map((r) => r.name), ['PPL', 'Upper / Lower']);
  });

  group('how a movement is measured', () {
    Future<Exercise> byName(String name) =>
        (db.select(db.exercises)..where((t) => t.name.equals(name)))
            .getSingle();

    test('the plank ships as a hold and everything else as reps', () async {
      expect((await byName('Plank')).measureMode, MeasureMode.hold);
      expect((await byName('Barbell Bench Press')).measureMode,
          MeasureMode.reps);
    });

    test('a movement the user creates is reps unless they say otherwise',
        () async {
      final id = await repo.createExercise(
        name: 'Hollow hold',
        muscle: MuscleGroup.core,
        equipment: Equipment.bodyweight,
        loadMode: LoadMode.bodyweight,
      );
      final made =
          await (db.select(db.exercises)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(made.measureMode, MeasureMode.reps);

      await repo.updateExercise(id, measureMode: const Value(MeasureMode.hold));
      expect((await byName('Hollow hold')).measureMode, MeasureMode.hold);
    });

    test('the backfill only touches rows this app seeded', () async {
      // The v7 migration hands the seeded plank its hold. A movement the user
      // created carries no starter key and is nobody's to reinterpret, even
      // when it is called the same thing.
      final id = await repo.createExercise(
        name: 'Plank (rings)',
        muscle: MuscleGroup.core,
        equipment: Equipment.bodyweight,
        loadMode: LoadMode.bodyweight,
      );
      await backfillSeededMeasureModes(db);

      expect((await byName('Plank')).measureMode, MeasureMode.hold);
      final mine =
          await (db.select(db.exercises)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(mine.measureMode, MeasureMode.reps);
    });
  });

  group('a name is not optional', () {
    test('a regime cannot be created or renamed to whitespace', () async {
      expect(() => repo.createRegime('   '),
          throwsA(isA<BlankNameException>()));

      final id = await repo.createRegime('PPL');
      expect(
        () => repo.updateRegime(id, name: const Value(' ')),
        throwsA(isA<BlankNameException>()),
      );
      final live = await (db.select(db.regimes)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      expect(live.map((r) => r.name), ['PPL']);
    });

    test('a session cannot be added or renamed to whitespace', () async {
      final regimeId = await repo.createRegime('PPL');
      expect(() => repo.addSession(regimeId, ' '),
          throwsA(isA<BlankNameException>()));

      final sessionId = await repo.addSession(regimeId, 'Push 1');
      expect(() => repo.renameSession(sessionId, '\n'),
          throwsA(isA<BlankNameException>()));
      expect(
        (await (db.select(db.sessions)..where((t) => t.id.equals(sessionId)))
                .getSingle())
            .name,
        'Push 1',
      );
    });

    test('an exercise cannot be created or renamed to whitespace', () async {
      expect(
        () => repo.createExercise(
          name: '  ',
          muscle: MuscleGroup.chest,
          equipment: Equipment.barbell,
          loadMode: LoadMode.total,
        ),
        throwsA(isA<BlankNameException>()),
      );

      final id = await repo.createExercise(
        name: 'Larsen press',
        muscle: MuscleGroup.chest,
        equipment: Equipment.barbell,
        loadMode: LoadMode.total,
      );
      expect(
        () => repo.updateExercise(id, name: const Value('')),
        throwsA(isA<BlankNameException>()),
      );
    });
  });
}
