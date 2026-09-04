import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Which bar, and when the answer is allowed to change.**
///
/// Bar weight used to be one number on the catalog row, read live by the plate
/// diagram every time it drew. Two things were wrong with that at once: the
/// same movement cannot be loaded differently in two training days, and
/// changing it silently redrew the plates of every session ever logged.
///
/// So there are two columns. `session_exercises.bar_kind` is the decision, per
/// day, null meaning "follow the catalog". `workout_exercises.bar_kind` is the
/// snapshot of what was used, and it is the reason March stays March — the
/// same rule as `workout_exercises.muscle`, which this is modelled on.
///
/// The walkthrough these tests are written from:
///
/// | Action                     | Day 1 default | Day 1 week 1 log | Day 2 |
/// | -------------------------- | ------------- | ---------------- | ----- |
/// | Start                      | catalog       | —                | catalog |
/// | Week 1: bar set to women's | women's       | women's          | catalog |
/// | Week 2: bar back to olympic| olympic       | women's          | catalog |
void main() {
  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  late AppDatabase db;
  late TrainingRepository repo;
  late RegimeRepository regimes;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    regimes = RegimeRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  Future<Regime> activeRegime() async =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
          .getSingle();

  Future<Session> sessionNamed(String name) async =>
      (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();

  /// The movement that appears in both push days, which is what makes "per
  /// day" provable rather than merely stated.
  Future<Exercise> shared() async => (db.select(db.exercises)
        ..where((t) => t.starterKey.equals('incline_db_press')))
      .getSingle();

  Future<SessionExercise> slotOf(String sessionId, String exerciseId) async =>
      (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(sessionId) &
                t.exerciseId.equals(exerciseId) &
                t.deletedAt.isNull()))
          .getSingle();

  /// The bar a workout actually recorded for one movement.
  Future<BarKind?> loggedBar(String workoutId, String exerciseId) async =>
      (await (db.select(db.workoutExercises)
                ..where((t) =>
                    t.workoutId.equals(workoutId) &
                    t.exerciseId.equals(exerciseId) &
                    t.deletedAt.isNull()))
              .getSingle())
          .barKind;

  test('a workout records the bar it was trained on', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    for (final entry in detail!.entries) {
      expect(
        entry.workoutExercise.barKind,
        entry.exercise.barKind,
        reason: 'with no override, the day follows the catalog — and the row '
            'writes down the answer rather than pointing at it',
      );
    }
  });

  test('the bar is per day: Push 2 keeps its own', () async {
    // RULES § 1's shape, one column over. Incline press is in both push days
    // on purpose, and each keeps its own progression — the bar is part of that.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final push2 = await sessionNamed('Push 2');
    final exercise = await shared();
    final catalog = exercise.barKind;

    final slot1 = await slotOf(push1.id, exercise.id);
    await regimes.setSessionExerciseBarKind(slot1.id, BarKind.womens);

    expect((await slotOf(push1.id, exercise.id)).barKind, BarKind.womens);
    expect(
      (await slotOf(push2.id, exercise.id)).barKind,
      isNull,
      reason: 'Push 2 has its own slot and nothing has been decided about it',
    );

    // And the day that was not touched still starts on the catalog's bar.
    final second =
        await repo.startWorkout(regimeId: regime.id, sessionId: push2.id);
    expect(await loggedBar(second, exercise.id), catalog);
  });

  test('changing the bar moves the default forward and leaves the past alone',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final exercise = await shared();

    // Week 1. The bar is named while the session is open, which is when you
    // are standing over it — so today's row takes it too.
    final week1 =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final slot = await slotOf(push1.id, exercise.id);
    await regimes.setSessionExerciseBarKind(slot.id, BarKind.womens);

    expect(await loggedBar(week1, exercise.id), BarKind.womens);
    await repo.completeWorkout(week1);

    // Week 2 opens on the number that was settled on.
    final week2 =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    expect(await loggedBar(week2, exercise.id), BarKind.womens);

    // Changed back mid-session. Week 2's own row follows, because it is open.
    await regimes.setSessionExerciseBarKind(slot.id, BarKind.olympic);
    expect(await loggedBar(week2, exercise.id), BarKind.olympic);

    // And week 1 is exactly where it was left.
    expect(
      await loggedBar(week1, exercise.id),
      BarKind.womens,
      reason: 'a finished session holds what was actually on the bar',
    );
  });

  test('clearing the override hands the day back to the catalog', () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final exercise = await shared();
    final catalog = exercise.barKind;

    final slot = await slotOf(push1.id, exercise.id);
    await regimes.setSessionExerciseBarKind(slot.id, BarKind.trap);
    expect((await slotOf(push1.id, exercise.id)).barKind, BarKind.trap);

    final open =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    expect(await loggedBar(open, exercise.id), BarKind.trap);

    // Null is not `none`: it is the absence of an answer here, and the catalog
    // is asked again.
    await regimes.setSessionExerciseBarKind(slot.id, null);
    expect((await slotOf(push1.id, exercise.id)).barKind, isNull);
    expect(
      await loggedBar(open, exercise.id),
      catalog,
      reason: 'the open session says what the day now says',
    );
  });

  test('an exercise added mid-session has no slot, and takes the catalog',
      () async {
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final curl = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Barbell Curl')))
        .getSingle();
    await repo.addExerciseToWorkout(id, curl.id);

    expect(await loggedBar(id, curl.id), curl.barKind);
    expect(
      await repo.slotIdFor(sessionId: push1.id, exerciseId: curl.id),
      isNull,
      reason: 'nothing in the template to hold a per-day bar, which is what '
          'keeps the settings row off the menu for it',
    );

    // And an exercise that *is* in the template has one to open.
    final exercise = await shared();
    expect(
      await repo.slotIdFor(sessionId: push1.id, exerciseId: exercise.id),
      isNotNull,
    );
  });

  test('a swap takes the replacement\'s bar, not the bar it displaced',
      () async {
    // The slot a swap inherits is a position, not an answer about how the new
    // movement is loaded.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);

    final detail = await repo.workoutDetail(id);
    final displaced = detail!.entries.first;

    final curl = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Barbell Curl')))
        .getSingle();
    await repo.replaceExerciseInWorkout(
        displaced.workoutExercise.id, curl.id);

    expect(await loggedBar(id, curl.id), curl.barKind);
  });

  test('a completed workout is untouched by a later change to its day',
      () async {
    // The acceptance criterion stated on its own, because it is the one that
    // cannot be walked back if it is wrong.
    final regime = await activeRegime();
    final push1 = await sessionNamed('Push 1');
    final exercise = await shared();

    final done =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final before = await loggedBar(done, exercise.id);
    await repo.completeWorkout(done);

    final slot = await slotOf(push1.id, exercise.id);
    await regimes.setSessionExerciseBarKind(slot.id, BarKind.trap);

    expect(await loggedBar(done, exercise.id), before);
  });
}
