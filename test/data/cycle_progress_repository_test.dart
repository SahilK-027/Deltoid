import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/cycle_progress.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The repository half of cycle progress. The arithmetic is proved without a
/// database in `test/domain/cycle_progress_test.dart`; what is proved here is
/// that the three raw statements read the columns they claim to, that a lift is
/// keyed on the session it was trained in, and that a cycle's dates come from
/// the days actually trained.
///
/// Raw SQL gives up compile-time column names, so a rename compiles and fails
/// on a device — the reason `query_conversion_test.dart` exists. Every column
/// `regimeProgress` selects is read by the expectations below.
final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

void main() {
  late AppDatabase db;
  late TrainingRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
  });

  tearDown(() => db.close());

  Future<Regime> activeRegime() =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
          .getSingle();

  /// Trains every session of the regime once, at [weight] on every set.
  ///
  /// One pass is one cycle: the cycle closes when the last session in
  /// programme order is completed.
  Future<void> trainCycle(double weight, {DateTime? at}) async {
    final regime = await activeRegime();
    final sessions = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    for (final s in sessions) {
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: s.id,
        at: at,
      );
      final detail = await repo.workoutDetail(id);
      for (final entry in detail!.entries) {
        for (final set in entry.sets) {
          await repo.updateSet(
            set.id,
            weight: Value(weight),
            reps: const Value(10),
            isDone: const Value(true),
          );
        }
      }
      await repo.completeWorkout(id);
    }
    // What the log screen does when the last session of a cycle is finished
    // (`regime_screen.dart`). The repository does not advance a cycle on its
    // own, so a test that trains six sessions and never calls this would score
    // every pass into cycle 1.
    await repo.closeCycleIfSatisfied(regime.id);
  }

  test('a regime with nothing logged has no cycles to score', () async {
    final progress = await repo.activeRegimeProgress();

    expect(progress, isNotNull);
    expect(progress!.regimeName, isNotEmpty);
    expect(progress.isActive, isTrue);
    expect(progress.progress.isEmpty, isTrue);
    expect(progress.progress.percent, isNull);
  });

  test('a regime that does not exist has no progress', () async {
    expect(await repo.regimeProgress('nothing'), isNull);
  });

  test('two cycles at the same weights are no progress at all', () async {
    await trainCycle(50);
    await trainCycle(50);

    final progress = (await repo.activeRegimeProgress())!.progress;

    // Two closed cycles and the third, open, one the second cycle's completion
    // opened.
    expect(progress.cycles.length, greaterThanOrEqualTo(2));
    expect(progress.cycles[0].value, closeTo(0, 1e-9));
    expect(progress.cycles[1].value, closeTo(0, 1e-9));
  });

  test('ten per cent more weight at the same reps is ten per cent stronger',
      () async {
    await trainCycle(50);
    await trainCycle(55);

    final progress = (await repo.activeRegimeProgress())!.progress;

    // A movement that takes a load moved by exactly the load. A bodyweight
    // movement did the same reps on both passes against the same assumed
    // bodyweight, because nothing was weighed in, so it is scored and has not
    // changed — where it used to go unscored for want of a bodyweight.
    final loadOf = {
      for (final e in await db.select(db.exercises).get()) e.id: e.loadMode,
    };
    bool takesLoad(LiftChange l) =>
        loadOf[l.lift.exerciseId] == LoadMode.total ||
        loadOf[l.lift.exerciseId] == LoadMode.perSide;

    final lifts = progress.cycles[1].lifts;
    final loaded = lifts.where(takesLoad).toList();
    final bodyweight = lifts.where((l) => !takesLoad(l)).toList();
    expect(loaded, isNotEmpty);
    expect(bodyweight, isNotEmpty);
    for (final l in loaded) {
      expect(l.percent, closeTo(10, 1e-9));
    }
    for (final l in bodyweight) {
      expect(l.percent, closeTo(0, 1e-9));
    }

    // The cycle's point is the mean over both kinds.
    expect(
      progress.cycles[1].value,
      closeTo(10 * loaded.length / lifts.length, 1e-9),
    );
    expect(progress.liftsImproved, loaded.length);
    expect(progress.liftsCompared, lifts.length);
  });

  test('a lift is a session and an exercise, not an exercise', () async {
    await trainCycle(50);

    final result = (await repo.activeRegimeProgress())!;
    final lifts = result.progress.latest!.lifts;

    // The template runs several movements in more than one session, and each
    // pairing is its own lift with its own baseline — CLAUDE.md rule 1.
    final byExercise = <String, Set<String>>{};
    for (final l in lifts) {
      (byExercise[l.lift.exerciseId] ??= {}).add(l.lift.sessionId);
    }
    expect(
      byExercise.values.any((sessions) => sessions.length > 1),
      isTrue,
      reason: 'a movement trained in two sessions should be two lifts',
    );

    // And every one of them can be named on screen.
    for (final l in lifts) {
      final label = result.labelOf(l.lift);
      expect(label.exerciseName, isNotEmpty);
      expect(label.sessionName, isNotEmpty);
    }
  });

  test('a cycle is dated by the days trained in it', () async {
    await trainCycle(50);

    final progress = (await repo.activeRegimeProgress())!.progress;
    final today = DateTime.now();
    final key = today.year * 10000 + today.month * 100 + today.day;

    expect(progress.cycles.first.startDayKey, key);
    expect(progress.cycles.first.endDayKey, key);
    // The cycle that closing the first one opened has no training in it yet, so
    // it has no dates rather than the dates of the row that created it.
    expect(progress.cycles.last.startDayKey, isNull);
    expect(progress.cycles.last.isOpen, isTrue);
  });

  test('a workout logged before the regime had a cycle is scored by nothing',
      () async {
    final regime = await activeRegime();
    final session = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..limit(1))
        .getSingle();

    // Backdated past every cycle this regime has had, so it belongs to none —
    // `cycleOpenOn` says so, and the read joins through `cycles`.
    final id = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: session.id,
      at: DateTime.now().subtract(const Duration(days: 30)),
    );
    await repo.completeWorkout(id);

    final progress = (await repo.activeRegimeProgress())!.progress;
    expect(progress.cycles.where((c) => c.isScored), isEmpty);
  });

  test('the timeline reads the days a regime was trained on', () async {
    final regime = await activeRegime();
    await trainCycle(50);

    final today = DateTime.now();
    final key = today.year * 10000 + today.month * 100 + today.day;
    final days = await repo.trainedDaysBetween(
      fromDayKey: key - 100,
      toDayKey: key + 100,
    );

    expect(days, isNotEmpty);
    expect(days.every((d) => d.regimeId == regime.id), isTrue);
    expect(days.every((d) => d.isDeload == false), isTrue);

    final weeks = computeTimelineWeeks(
      year: today.year,
      days: days,
    );
    expect(weeks.where((w) => w.regimeId == regime.id), isNotEmpty);
  });

  test('a window outside the log is empty rather than everything', () async {
    await trainCycle(50);

    expect(
      await repo.trainedDaysBetween(fromDayKey: 19900101, toDayKey: 19901231),
      isEmpty,
    );
  });

  test('the live regimes are the ones a card can be drawn for', () async {
    final regime = await activeRegime();

    final live = await repo.liveRegimes();
    expect(live.map((r) => r.id), [regime.id]);
    expect(live.single.name, regime.name);
    expect(live.single.isActive, isTrue);
    expect(live.single.identityIndex, regime.identityIndex);
  });
}
