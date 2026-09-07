import 'dart:io';
import 'dart:math';

import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/pull.dart';
import 'package:deltoid/data/sync/push.dart';
import 'package:deltoid/data/sync/sync_backend.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/sync/fake_backend.dart';
import 'invariant_oracle.dart';

/// Two phones, one account, random operations on both, syncing at random
/// points.
///
/// [SYNC.md § 18](SYNC.md#18-the-phases) asks for exactly this, in the shape
/// `model_fuzz_test.dart` established, and says why: **it is the only thing that
/// can find a collision that document merely anticipated.** § 12 is a list of
/// cases somebody thought of; this is the part that does not depend on having
/// thought of them.
///
/// Three assertions, and they are different in kind:
///
/// * **The oracle, on both databases, after every operation.** A merge that
///   leaves two rows on one position, or a live set under a dead slot, is
///   caught at the operation that did it rather than at the end of the run.
/// * **Convergence.** Once both sides are quiet and have synced, they hold the
///   same rows. Not eventually and not approximately — the same rows.
/// * **Nothing logged is lost.** Every set either device ever created is still
///   a row on both of them afterwards, live or tombstoned
///   ([§ 15](SYNC.md#15-what-sync-may-never-do) rule 2). A merge is allowed to
///   re-slot, re-flag and re-number; it is not allowed to make work disappear.
///
/// **No model.** `model_fuzz_test.dart` conserves values against a deliberately
/// simple model, and that is the right oracle for one device: it knows what the
/// database should hold because it watched every operation. Here the other
/// phone is also writing, and what the merge rules *should* produce is precisely
/// what is under test — a model that predicted it would be a second copy of
/// `sync_merge.dart`, and two copies of one mistake agree.
///
/// Size, as everywhere else in this directory:
///
/// ```
/// SYNC_FUZZ_SEEDS=100 SYNC_FUZZ_OPS=400 flutter test test/integrity/sync_fuzz_test.dart
/// ```

// ── The operations ────────────────────────────────────────────────────────

enum SyncOp {
  startWorkout,
  tickSet,
  addSet,
  removeSet,
  addExercise,
  removeExercise,
  completeWorkout,
  deleteWorkout,
  editProgramme,
  renameSession,
  reorderSessions,
  logBodyweight,
  deleteBodyweight,
  advanceCycle,
  createRegime,
  activateRegime,
  deleteRegime,

  /// Pull then push, which is the order the engine runs them in.
  sync,

  /// A sync with no signal. Rows stay dirty and the next one carries them —
  /// [SYNC.md § 13](SYNC.md#13-when-it-fails).
  syncOffline,
}

/// One step: which phone, doing what.
///
/// Data rather than a closure, so a failing run prints as something that can be
/// pasted back in. Targets are raw integers resolved modulo whatever live list
/// they index, which is what lets the shrinker drop a step from the middle and
/// still have the rest address something.
class Step {
  const Step(this.device, this.kind, this.picks);

  /// 0 is phone A, 1 is phone B.
  final int device;
  final SyncOp kind;
  final List<int> picks;

  static Step random(Random r) => Step(
        r.nextInt(2),
        // Weighted towards syncing, because a merge only happens where two
        // offline edits meet: too rare and every operation lands alone, too
        // frequent and neither phone is ever behind.
        r.nextInt(4) == 0
            ? (r.nextInt(6) == 0 ? SyncOp.syncOffline : SyncOp.sync)
            : SyncOp.values[r.nextInt(SyncOp.values.length - 2)],
        [for (var i = 0; i < 4; i++) r.nextInt(1 << 20)],
      );

  @override
  String toString() => 'Step($device, SyncOp.${kind.name}, $picks)';
}

// ── The rig ───────────────────────────────────────────────────────────────

class Phones {
  Phones() {
    a = AppDatabase.forTesting(NativeDatabase.memory());
    b = AppDatabase.forTesting(NativeDatabase.memory());
  }

  late final AppDatabase a;
  late final AppDatabase b;
  final backend = FakeBackend();

  /// Every set id either phone has ever created. Nothing here may stop being a
  /// row.
  final createdSets = <String>{};

  /// Rows a pull refused. Zero, always: a skipped row means the applier built
  /// something this schema will not take, and in a fuzz with no corrupted rows
  /// that is a bug rather than a bad file.
  int skipped = 0;

  AppDatabase db(int device) => device == 0 ? a : b;
  String idOf(int device) => device == 0 ? 'device-a' : 'device-b';

  static T? pick<T>(List<T> xs, int n) => xs.isEmpty ? null : xs[n % xs.length];

  Future<void> seed() async {
    setCurrentDeviceId(idOf(0));
    await ensureStarterCatalog(a);
    await createRegimeFromTemplate(
      a,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    await PushService(a, backend).drain();
    skipped += (await PullService(b, backend).pull()).skipped;
  }

  Future<void> syncOne(int device) async {
    final target = db(device);
    skipped += (await PullService(target, backend).pull()).skipped;
    await PushService(target, backend).drain();
  }

  /// Syncs both phones until they hold the same rows.
  ///
  /// More than one exchange is expected wherever both phones resolved the same
  /// collision: **a resolution is itself a write**, so each device produces a
  /// version the other has not seen. It has to *stop*, though — a rule that
  /// keeps producing new versions would run to this limit here rather than
  /// looping forever on a phone, which is the failure this is really watching
  /// for.
  Future<int> converge({int limit = 8}) async {
    for (var round = 1; round <= limit; round++) {
      await syncOne(0);
      await syncOne(1);
      if (await _rowsOf(a) == await _rowsOf(b)) return round;
    }
    throw StateError(
      'the two phones did not converge in $limit exchanges\n${await _diff()}',
    );
  }

  /// The first rows that disagree, side by side.
  ///
  /// A failure that says only *they differ* costs an hour of bisecting by hand;
  /// this says which table, which row, and which column, which is usually the
  /// whole diagnosis.
  Future<String> _diff() async {
    final out = StringBuffer();
    for (final table in _syncedTables) {
      final rowsA = await _byId(a, table);
      final rowsB = await _byId(b, table);
      for (final id in {...rowsA.keys, ...rowsB.keys}) {
        final left = rowsA[id];
        final right = rowsB[id];
        if (left.toString() == right.toString()) continue;
        out.writeln('  $table $id');
        if (left == null || right == null) {
          out.writeln('    A: ${left ?? 'missing'}');
          out.writeln('    B: ${right ?? 'missing'}');
          continue;
        }
        for (final column in left.keys) {
          if (left[column] == right[column]) continue;
          out.writeln('    $column: A=${left[column]}  B=${right[column]}');
        }
      }
      if (out.isNotEmpty) return out.toString();
    }
    return '  (no difference found — the comparison itself is wrong)';
  }

  Future<Map<String, Map<String, dynamic>>> _byId(
    AppDatabase db,
    String table,
  ) async {
    final rows = await db.customSelect('SELECT * FROM $table').get();
    return {
      for (final row in rows)
        row.data['id'] as String: {...row.data}..remove('dirty'),
    };
  }

  /// Every row on a phone, as one comparable string per table.
  ///
  /// `dirty` is dropped: it is a fact about a device's queue, not about the
  /// row, and two phones holding the same history disagree about it while one
  /// still owes a push.
  Future<String> _rowsOf(AppDatabase db) async {
    final out = StringBuffer();
    for (final table in _syncedTables) {
      final rows =
          await db.customSelect('SELECT * FROM $table ORDER BY id').get();
      out.writeln(table);
      for (final row in rows) {
        out.writeln(({...row.data}..remove('dirty')).toString());
      }
    }
    return out.toString();
  }

  Future<void> close() async {
    await a.close();
    await b.close();
  }
}

const _syncedTables = [
  'exercises',
  'regimes',
  'sessions',
  'session_exercises',
  'cycles',
  'workouts',
  'workout_exercises',
  'set_logs',
  'bodyweight_logs',
];

/// A small pool, so two phones collide on purpose.
///
/// A fuzz that drew names and days from a wide range would produce two
/// histories that never meet, and the whole point is the case where they do:
/// `sessions_name_live`, `bodyweight_day_live` and the position indexes are
/// only reachable when both devices reach for the same slot.
const _names = ['Heavy', 'Light', 'Volume'];

// ── The operations, against whatever is live right now ────────────────────
//
// Targets are read off the database rather than remembered, because the other
// phone is writing too: anything a step remembered between operations would be
// stale exactly when a merge had just happened, which is the only interesting
// moment in this file.

Future<bool> applyStep(Phones phones, Step step) async {
  final db = phones.db(step.device);
  setCurrentDeviceId(phones.idOf(step.device));
  final repo = TrainingRepository(db);
  final regimes = RegimeRepository(db);
  final picks = step.picks;

  Future<Regime?> activeRegime() => (db.select(db.regimes)
        ..where((t) => t.isActive.equals(true) & t.deletedAt.isNull()))
      .getSingleOrNull();

  Future<List<Session>> sessionsOf(String regimeId) => (db.select(db.sessions)
        ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
      .get();

  Future<Workout?> openWorkout() => (db.select(db.workouts)
        ..where((t) =>
            t.status.equalsValue(WorkoutStatus.inProgress) &
            t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.startedAt)])
        ..limit(1))
      .getSingleOrNull();

  Future<List<WorkoutExercise>> slotsOf(String workoutId) =>
      (db.select(db.workoutExercises)
            ..where((t) => t.workoutId.equals(workoutId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();

  Future<List<SetLog>> setsOf(String slotId) => (db.select(db.setLogs)
        ..where((t) =>
            t.workoutExerciseId.equals(slotId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
      .get();

  switch (step.kind) {
    case SyncOp.sync:
      await phones.syncOne(step.device);
      return true;

    case SyncOp.syncOffline:
      phones.backend.failEverything =
          const SyncTransportFailure('no signal', transient: true);
      try {
        await phones.syncOne(step.device);
      } on SyncTransportFailure {
        // The ordinary state of a phone in a basement. Rows stay dirty and the
        // next sync carries them, which is the thing being exercised.
      } finally {
        phones.backend.failEverything = null;
      }
      return true;

    case SyncOp.startWorkout:
      // The app refuses a second open log, and that rule has its own test.
      if (await openWorkout() != null) return false;
      final regime = await activeRegime();
      if (regime == null) return false;
      final session = Phones.pick(await sessionsOf(regime.id), picks[0]);
      if (session == null) return false;
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: session.id,
      );
      for (final slot in await slotsOf(id)) {
        phones.createdSets.addAll([for (final s in await setsOf(slot.id)) s.id]);
      }
      return true;

    case SyncOp.tickSet:
      final open = await openWorkout();
      if (open == null) return false;
      final slot = Phones.pick(await slotsOf(open.id), picks[0]);
      if (slot == null) return false;
      final set = Phones.pick(await setsOf(slot.id), picks[1]);
      if (set == null) return false;
      await repo.updateSet(
        set.id,
        weight: Value(20 + (picks[2] % 40) * 2.5),
        reps: Value(1 + picks[3] % 12),
        isDone: const Value(true),
      );
      return true;

    case SyncOp.addSet:
      final open = await openWorkout();
      if (open == null) return false;
      final slot = Phones.pick(await slotsOf(open.id), picks[0]);
      if (slot == null) return false;
      phones.createdSets.add(await repo.addSet(slot.id));
      return true;

    case SyncOp.removeSet:
      final open = await openWorkout();
      if (open == null) return false;
      final slot = Phones.pick(await slotsOf(open.id), picks[0]);
      if (slot == null) return false;
      final set = Phones.pick(await setsOf(slot.id), picks[1]);
      if (set == null) return false;
      await repo.deleteSet(set.id);
      return true;

    case SyncOp.addExercise:
      final open = await openWorkout();
      if (open == null) return false;
      final taken = {for (final s in await slotsOf(open.id)) s.exerciseId};
      final free = [
        for (final x in await (db.select(db.exercises)
                  ..where((t) => t.deletedAt.isNull())
                  ..orderBy([(t) => OrderingTerm(expression: t.id)]))
                .get())
          if (!taken.contains(x.id)) x,
      ];
      final chosen = Phones.pick(free, picks[0]);
      if (chosen == null) return false;
      final slotId = await repo.addExerciseToWorkout(open.id, chosen.id);
      phones.createdSets.addAll([for (final s in await setsOf(slotId)) s.id]);
      return true;

    case SyncOp.removeExercise:
      final open = await openWorkout();
      if (open == null) return false;
      final slot = Phones.pick(await slotsOf(open.id), picks[0]);
      if (slot == null) return false;
      await repo.removeExerciseFromWorkout(slot.id);
      return true;

    case SyncOp.completeWorkout:
      final open = await openWorkout();
      if (open == null) return false;
      await repo.completeWorkout(open.id);
      return true;

    case SyncOp.deleteWorkout:
      final live = await (db.select(db.workouts)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      final workout = Phones.pick(live, picks[0]);
      if (workout == null) return false;
      await repo.deleteWorkout(workout.id);
      return true;

    case SyncOp.editProgramme:
      final regime = await activeRegime();
      if (regime == null) return false;
      final session = Phones.pick(await sessionsOf(regime.id), picks[0]);
      if (session == null) return false;
      final slots = await (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(session.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      switch (picks[1] % 3) {
        case 0:
          final taken = {for (final s in slots) s.exerciseId};
          final free = [
            for (final x in await (db.select(db.exercises)
                      ..where((t) => t.deletedAt.isNull())
                      ..orderBy([(t) => OrderingTerm(expression: t.id)]))
                    .get())
              if (!taken.contains(x.id)) x,
          ];
          final chosen = Phones.pick(free, picks[2]);
          if (chosen == null) return false;
          await regimes.addExerciseToSession(session.id, chosen.id);
        case 1:
          final slot = Phones.pick(slots, picks[2]);
          if (slot == null) return false;
          await regimes.removeSessionExercise(slot.id);
        default:
          if (slots.length < 2) return false;
          await regimes.reorderSessionExercises(
            [for (final s in slots.reversed) s.id],
          );
      }
      return true;

    case SyncOp.renameSession:
      final regime = await activeRegime();
      if (regime == null) return false;
      final sessions = await sessionsOf(regime.id);
      final session = Phones.pick(sessions, picks[0]);
      if (session == null) return false;
      final name = _names[picks[1] % _names.length];
      // The app refuses a duplicate through this door; the merge is the door
      // that cannot, which is what `sessions_name_live` is for.
      if (await regimes.isSessionNameTaken(regime.id, name,
          exceptId: session.id)) {
        return false;
      }
      await regimes.renameSession(session.id, name);
      return true;

    case SyncOp.reorderSessions:
      final regime = await activeRegime();
      if (regime == null) return false;
      final sessions = await sessionsOf(regime.id);
      if (sessions.length < 2) return false;
      await regimes.reorderSessions([for (final s in sessions.reversed) s.id]);
      return true;

    case SyncOp.logBodyweight:
      // A five-day window, so two phones land on one day often.
      final day = DateTime.now().subtract(Duration(days: picks[0] % 5));
      await repo.logBodyweight(day, 60 + (picks[1] % 300) / 10);
      return true;

    case SyncOp.deleteBodyweight:
      final rows = await (db.select(db.bodyweightLogs)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
          .get();
      final row = Phones.pick(rows, picks[0]);
      if (row == null) return false;
      await repo.deleteBodyweight(row.dayKey);
      return true;

    case SyncOp.advanceCycle:
      final regime = await activeRegime();
      if (regime == null) return false;
      await repo.advanceCycle(regime.id);
      return true;

    case SyncOp.createRegime:
      // Named after the device, so two phones never collide on the *name* —
      // this operation is here for `regimes_identity_live`, and a name clash
      // would stop it before it reached the slot.
      final name = '${phones.idOf(step.device)} ${picks[0] % 1000}';
      if (await regimes.isNameTaken(name)) return false;
      if (await regimes.nextIdentitySlot() == null) return false;
      await regimes.createRegime(name, activate: picks[1].isEven);
      return true;

    case SyncOp.activateRegime:
      final live = await (db.select(db.regimes)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      final regime = Phones.pick(live, picks[0]);
      if (regime == null || regime.isActive) return false;
      await regimes.setActiveRegime(regime.id);
      return true;

    case SyncOp.deleteRegime:
      final live = await (db.select(db.regimes)
            ..where((t) => t.deletedAt.isNull() & t.isActive.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      final regime = Phones.pick(live, picks[0]);
      if (regime == null) return false;
      await regimes.deleteRegime(regime.id);
      return true;
  }
}

// ── Running, replaying, shrinking ─────────────────────────────────────────

/// Runs [steps] against a fresh pair of phones, returning the failure or null.
Future<String?> runSteps(List<Step> steps, {List<Step>? applied}) async {
  resetStampsForTesting();
  final phones = Phones();
  try {
    await phones.seed();
    await expectInvariants(phones.a, after: 'seeding A');
    await expectInvariants(phones.b, after: 'seeding B');

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (!await applyStep(phones, step)) continue;
      applied?.add(step);
      await expectInvariants(phones.a, after: 'step $i $step, on A');
      await expectInvariants(phones.b, after: 'step $i $step, on B');
    }

    final rounds = await phones.converge();
    await expectInvariants(phones.a, after: 'converging ($rounds rounds)');
    await expectInvariants(phones.b, after: 'converging ($rounds rounds)');

    expect(phones.skipped, 0,
        reason: 'a pull refused a row it had built itself');

    // Nothing logged is lost. Every set either phone ever created is still a
    // row on both — live if it survived, tombstoned if it was deleted or left
    // unticked, but a row.
    for (final db in [phones.a, phones.b]) {
      final ids = {
        for (final row in await db.customSelect('SELECT id FROM set_logs').get())
          row.read<String>('id'),
      };
      final lost = phones.createdSets.difference(ids);
      expect(lost, isEmpty, reason: 'sets vanished from a phone: $lost');
    }
    return null;
  } on TestFailure catch (e) {
    return e.message ?? '$e';
  } catch (e, st) {
    return '$e\n$st';
  } finally {
    await phones.close();
  }
}

/// The shortest subsequence that still fails. Greedy single-step removal, the
/// same shape `model_fuzz_test.dart` uses and for the same reason: it turns a
/// run nobody can read into one somebody can.
Future<List<Step>> shrink(List<Step> failing) async {
  var best = failing;
  var changed = true;
  while (changed && best.length > 1) {
    changed = false;
    for (var i = 0; i < best.length; i++) {
      final candidate = [...best]..removeAt(i);
      if (await runSteps(candidate) != null) {
        best = candidate;
        changed = true;
        break;
      }
    }
  }
  return best;
}

int _env(String name, int fallback) =>
    int.tryParse(Platform.environment[name] ?? '') ?? fallback;

void main() {
  setUpAll(() {
    // Two databases in one process is the whole point of this file, and each
    // has its own private executor — the race the warning is about needs one
    // executor behind two instances.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  final seeds = _env('SYNC_FUZZ_SEEDS', 6);
  final stepsPerSeed = _env('SYNC_FUZZ_OPS', 60);
  final firstSeed = _env('SYNC_FUZZ_SEED', 1);

  group('two phones on one account converge, and lose nothing', () {
    for (var s = firstSeed; s < firstSeed + seeds; s++) {
      final seed = s;
      test('seed $seed, $stepsPerSeed steps', () async {
        final r = Random(seed);
        final steps = [for (var i = 0; i < stepsPerSeed; i++) Step.random(r)];
        final applied = <Step>[];
        final failure = await runSteps(steps, applied: applied);
        if (failure == null) return;

        final shortest = await shrink(applied);
        fail([
          'SYNC FUZZ FAILURE',
          '  seed: $seed  (rerun: SYNC_FUZZ_SEED=$seed SYNC_FUZZ_SEEDS=1 '
              'SYNC_FUZZ_OPS=$stepsPerSeed flutter test '
              'test/integrity/sync_fuzz_test.dart)',
          '  applied ${applied.length} of ${steps.length} generated steps',
          '  shrunk to ${shortest.length}:',
          for (final step in shortest) '    $step',
          '',
          failure,
        ].join('\n'));
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  });
}
