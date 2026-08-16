import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

import 'invariant_oracle.dart';

/// A seeded random-operation harness, driving the real database against a model
/// too stupid to be wrong in the same direction.
///
/// `invariant_oracle.dart` judges what
/// must be true of *any* database; this file judges what must be true of *this*
/// one, given the operations that were actually performed. The two are asserted
/// after every single operation, so a failure names the operation that caused
/// it rather than the run that contained it.
///
/// **What the model is, and what it deliberately is not.** It is plain maps and
/// lists. It does not predict prefill, set shapes, cycle scheduling or any other
/// number the repository computes — a model that could would be a second copy of
/// the repository, and two copies of the same mistake agree. What it predicts is
/// **conservation**: a value that was written stays written until an operation
/// that names it changes it, and nothing else in the database moves. So rows the
/// app creates are *adopted* — read once, at the moment they are created — and
/// from then on every read must return exactly what the model remembers. That is
/// the property that catches a programme edit rewriting a logged set, a delete
/// taking a neighbour with it, and a restore that does not round-trip.
///
/// **Replay.** Every run is a seed. The seed and the whole operation sequence are
/// printed on failure, and the sequence is then shrunk by replaying it with
/// operations removed until the shortest still-failing one is found.
///
/// **Size.** The committed run is small enough to sit in the suite. The long run
/// § 3b asks for is the same code with two environment variables:
///
/// ```
/// FUZZ_SEEDS=200 FUZZ_OPS=5000 flutter test test/integrity/model_fuzz_test.dart
/// ```

// ── The operations ────────────────────────────────────────────────────────

enum OpKind {
  startWorkout,
  startBackdatedWorkout,
  tickSet,
  untickSet,
  addSet,
  removeSet,
  addExercise,
  removeExercise,
  replaceExercise,
  skipExercise,
  completeWorkout,
  abandonWorkout,
  deleteWorkout,
  backdateWorkout,
  editProgramme,
  logBodyweight,
  deleteBodyweight,
  advanceCycle,
  backupRestore,
}

/// One operation, as data rather than as a closure, so a failing run can be
/// printed, edited and replayed.
///
/// Targets are raw integers resolved modulo the live list they index. That is
/// what makes shrinking work: drop an operation from the middle and the ones
/// after it still address *something*, rather than pointing at ids that the
/// shorter run never created.
class Op {
  const Op(this.kind, this.picks, this.value);

  final OpKind kind;
  final List<int> picks;
  final double value;

  static Op random(Random r) => Op(
        OpKind.values[r.nextInt(OpKind.values.length)],
        [for (var i = 0; i < 4; i++) r.nextInt(1 << 20)],
        r.nextDouble(),
      );

  @override
  String toString() => 'Op(OpKind.${kind.name}, $picks, $value)';
}

// ── The model ─────────────────────────────────────────────────────────────

class MSet {
  MSet(this.id);

  final String id;
  double? weight;
  int? reps;
  bool done = false;

  @override
  String toString() => '$id(w=$weight,r=$reps,done=$done)';
}

class MExercise {
  MExercise(this.id);

  /// The `workout_exercises` row id, not the catalog exercise.
  final String id;
  final List<MSet> sets = [];
  SkipReason skip = SkipReason.none;
}

class MWorkout {
  MWorkout(this.id, this.dayKey);

  final String id;
  int dayKey;
  WorkoutStatus status = WorkoutStatus.inProgress;
  final List<MExercise> exercises = [];
}

// ── The harness ───────────────────────────────────────────────────────────

class Harness {
  Harness(this.db)
      : repo = TrainingRepository(db),
        regimes = RegimeRepository(db);

  final AppDatabase db;
  final TrainingRepository repo;
  final RegimeRepository regimes;

  /// Live workouts only. A deleted one leaves the model when it leaves the app,
  /// and its rows are then checked as tombstones rather than as values.
  final Map<String, MWorkout> workouts = {};

  /// Every set id the model has ever adopted and then lost — deleted set,
  /// removed exercise, deleted workout. All of them must still be on disk with
  /// a `deleted_at`, because soft delete is the rule and a hard delete here
  /// would be a lost log.
  final Set<String> tombstonedSets = {};

  final Map<int, double> bodyweights = {};

  /// Backup/restores proposed so far, and how many of them actually run. See
  /// [OpKind.backupRestore].
  int _backups = 0;
  final int _backupEvery = _env('FUZZ_BACKUP_EVERY', 1);

  /// The wall clock, because the repository stamps its rows off the same one
  /// and a model with a clock of its own would disagree with every `day_key` it
  /// did not choose. Backdated dates are offsets from here, so a run is still a
  /// function of its seed in everything but the date it is run on.
  DateTime get now => DateTime.now();

  List<MWorkout> get live =>
      workouts.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  static T? pick<T>(List<T> xs, int n) => xs.isEmpty ? null : xs[n % xs.length];

  Future<void> seed() async {
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
  }

  Future<Regime?> activeRegime() => (db.select(db.regimes)
        ..where((t) => t.isActive.equals(true) & t.deletedAt.isNull()))
      .getSingleOrNull();

  Future<List<Session>> sessions(String regimeId) => (db.select(db.sessions)
        ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
      .get();

  Future<List<Exercise>> catalog() => (db.select(db.exercises)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.id)]))
      .get();

  /// Copies a freshly created workout into the model exactly as the app wrote
  /// it. The model asserts nothing about what prefill decided; it asserts that
  /// what prefill decided is still there later.
  Future<void> adoptWorkout(String workoutId, int dayKey) async {
    final w = MWorkout(workoutId, dayKey);
    workouts[workoutId] = w;
    final detail = await repo.workoutDetail(workoutId);
    if (detail == null) return;
    for (final entry in detail.entries) {
      final e = MExercise(entry.workoutExercise.id);
      e.skip = entry.workoutExercise.skipReason;
      for (final s in entry.sets) {
        e.sets.add(MSet(s.id)
          ..weight = s.weight
          ..reps = s.reps
          ..done = s.isDone);
      }
      w.exercises.add(e);
    }
  }

  Future<void> adoptExercise(MWorkout w, String workoutExerciseId) async {
    final rows = await (db.select(db.setLogs)
          ..where((t) =>
              t.workoutExerciseId.equals(workoutExerciseId) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
        .get();
    final e = MExercise(workoutExerciseId);
    for (final s in rows) {
      e.sets.add(MSet(s.id)
        ..weight = s.weight
        ..reps = s.reps
        ..done = s.isDone);
    }
    w.exercises.add(e);
  }

  void forget(MExercise e) {
    tombstonedSets.addAll(e.sets.map((s) => s.id));
  }

  void forgetWorkout(MWorkout w) {
    for (final e in w.exercises) {
      forget(e);
    }
    workouts.remove(w.id);
  }

  MWorkout? get openWorkout {
    for (final w in live) {
      if (w.status == WorkoutStatus.inProgress) return w;
    }
    return null;
  }

  /// Leaves at least one live set in the database, creating one if the run has
  /// not.
  ///
  /// The durability test tears a transaction that deletes every set, and a
  /// random walk can perfectly well arrive at a state with no sets in it —
  /// every workout completed or deleted, every set tombstoned. The tear then
  /// destroys nothing and the rollback proves nothing, which is a vacuous test
  /// rather than a passing one. Two of six shards landed there.
  Future<void> ensureSomethingToLose() async {
    bool hasSets() =>
        workouts.values.any((w) => w.exercises.any((e) => e.sets.isNotEmpty));
    if (hasSets()) return;

    final regime = await activeRegime();
    if (regime == null) return;
    final ss = await sessions(regime.id);
    if (ss.isEmpty) return;

    var w = openWorkout;
    if (w == null) {
      final id =
          await repo.startWorkout(regimeId: regime.id, sessionId: ss.first.id);
      if (!workouts.containsKey(id)) await adoptWorkout(id, dayKeyOf(now));
      w = workouts[id];
      if (w == null) return;
    }
    if (w.exercises.isEmpty) {
      final all = await catalog();
      if (all.isEmpty) return;
      final weId = await repo.addExerciseToWorkout(w.id, all.first.id);
      await adoptExercise(w, weId);
    }
    final e = w.exercises.first;
    if (e.sets.isEmpty) {
      final id = await repo.addSet(e.id);
      final row = await (db.select(db.setLogs)..where((t) => t.id.equals(id)))
          .getSingle();
      e.sets.add(MSet(id)
        ..weight = row.weight
        ..reps = row.reps
        ..done = row.isDone);
    }
  }

  /// Runs [op], or returns false when it does not apply to the current state.
  ///
  /// A skipped operation is not a failure and is not recorded: the generator
  /// proposes blindly and the state decides. What must never be skipped is a
  /// *rejected* operation — an exception out of a repository call is a failure,
  /// with the single exception documented at its call site.
  Future<bool> apply(Op op) async {
    final regime = await activeRegime();
    if (regime == null) return false;
    final open = openWorkout;

    switch (op.kind) {
      case OpKind.startWorkout:
      case OpKind.startBackdatedWorkout:
        // A running log is the app's own precondition: `startWorkout` throws
        // rather than open a second one, and that rule has its own test.
        if (open != null) return false;
        final ss = await sessions(regime.id);
        final session = pick(ss, op.picks[0]);
        if (session == null) return false;
        final backdated = op.kind == OpKind.startBackdatedWorkout;
        final at = backdated ? now.subtract(Duration(days: 1 + op.picks[1] % 40)) : null;
        final id = await repo.startWorkout(
          regimeId: regime.id,
          sessionId: session.id,
          at: at,
        );
        if (workouts.containsKey(id)) return false;
        await adoptWorkout(id, dayKeyOf(at ?? now));
        return true;

      case OpKind.tickSet:
      case OpKind.untickSet:
        if (open == null) return false;
        final e = pick(open.exercises, op.picks[0]);
        if (e == null) return false;
        final s = pick(e.sets, op.picks[1]);
        if (s == null) return false;
        if (op.kind == OpKind.untickSet) {
          await repo.updateSet(s.id, isDone: const Value(false));
          s.done = false;
          return true;
        }
        // A tick carries the numbers with it, exactly as the log screen does.
        final weight = (20 + (op.picks[2] % 60) * 2.5);
        final reps = 1 + op.picks[3] % 12;
        await repo.updateSet(
          s.id,
          weight: Value(weight),
          reps: Value(reps),
          isDone: const Value(true),
        );
        s
          ..weight = weight
          ..reps = reps
          ..done = true;
        return true;

      case OpKind.addSet:
        if (open == null) return false;
        final e = pick(open.exercises, op.picks[0]);
        if (e == null) return false;
        final id = await repo.addSet(e.id);
        final row = await (db.select(db.setLogs)..where((t) => t.id.equals(id)))
            .getSingle();
        e.sets.add(MSet(id)
          ..weight = row.weight
          ..reps = row.reps
          ..done = row.isDone);
        return true;

      case OpKind.removeSet:
        if (open == null) return false;
        final e = pick(open.exercises, op.picks[0]);
        if (e == null || e.sets.isEmpty) return false;
        final s = e.sets[op.picks[1] % e.sets.length];
        await repo.deleteSet(s.id);
        e.sets.remove(s);
        tombstonedSets.add(s.id);
        return true;

      case OpKind.addExercise:
        if (open == null) return false;
        final all = await catalog();
        final already = <String>{
          for (final row in await (db.select(db.workoutExercises)
                    ..where((t) =>
                        t.workoutId.equals(open.id) & t.deletedAt.isNull()))
                  .get())
            row.exerciseId,
        };
        final free = [for (final x in all) if (!already.contains(x.id)) x];
        final chosen = pick(free, op.picks[0]);
        if (chosen == null) return false;
        final weId = await repo.addExerciseToWorkout(open.id, chosen.id);
        await adoptExercise(open, weId);
        return true;

      case OpKind.removeExercise:
        if (open == null || open.exercises.isEmpty) return false;
        final e = open.exercises[op.picks[0] % open.exercises.length];
        await repo.removeExerciseFromWorkout(e.id);
        open.exercises.remove(e);
        forget(e);
        return true;

      case OpKind.replaceExercise:
        if (open == null || open.exercises.isEmpty) return false;
        final e = open.exercises[op.picks[0] % open.exercises.length];
        final all = await catalog();
        final already = <String>{
          for (final row in await (db.select(db.workoutExercises)
                    ..where((t) =>
                        t.workoutId.equals(open.id) & t.deletedAt.isNull()))
                  .get())
            row.exerciseId,
        };
        final free = [for (final x in all) if (!already.contains(x.id)) x];
        final chosen = pick(free, op.picks[1]);
        if (chosen == null) return false;
        final weId = await repo.replaceExerciseInWorkout(e.id, chosen.id);
        if (weId.isEmpty) return false;
        final at = open.exercises.indexOf(e);
        open.exercises.remove(e);
        forget(e);
        await adoptExercise(open, weId);
        // A swap keeps the slot's place on the log screen's horizontal axis.
        final adopted = open.exercises.removeLast();
        open.exercises.insert(at, adopted);
        return true;

      case OpKind.skipExercise:
        if (open == null || open.exercises.isEmpty) return false;
        final e = open.exercises[op.picks[0] % open.exercises.length];
        final reason =
            SkipReason.values[op.picks[1] % SkipReason.values.length];
        await repo.setSkipReason(e.id, reason);
        e.skip = reason;
        return true;

      case OpKind.completeWorkout:
        if (open == null) return false;
        await repo.completeWorkout(open.id);
        final row = await (db.select(db.workouts)
              ..where((t) => t.id.equals(open.id)))
            .getSingle();
        open.status = row.status;
        // Finishing tombstones the sets that were never ticked, so an unfilled
        // row does not become history full of nulls. Written out here as a
        // rule of the app rather than read back off the database, because a
        // model that asked the database what happened would agree with it
        // whatever it did — including tombstoning a set that *was* ticked.
        for (final e in open.exercises) {
          final undone = [for (final s in e.sets) if (!s.done) s];
          for (final s in undone) {
            e.sets.remove(s);
            tombstonedSets.add(s.id);
          }
        }
        if (row.deletedAt != null) forgetWorkout(open);
        return true;

      case OpKind.abandonWorkout:
        if (open == null) return false;
        await repo.abandonWorkout(open.id);
        forgetWorkout(open);
        return true;

      case OpKind.deleteWorkout:
        final w = pick(live, op.picks[0]);
        if (w == null) return false;
        await repo.deleteWorkout(w.id);
        forgetWorkout(w);
        return true;

      case OpKind.backdateWorkout:
        final candidates = [
          for (final w in live)
            if (w.status != WorkoutStatus.inProgress) w,
        ];
        final w = pick(candidates, op.picks[0]);
        if (w == null) return false;
        final to = now.subtract(Duration(days: 1 + op.picks[1] % 60));
        await repo.setWorkoutDate(w.id, to);
        w.dayKey = dayKeyOf(to);
        return true;

      case OpKind.editProgramme:
        final ss = await sessions(regime.id);
        final session = pick(ss, op.picks[0]);
        if (session == null) return false;
        final slots = await (db.select(db.sessionExercises)
              ..where((t) =>
                  t.sessionId.equals(session.id) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
        switch (op.picks[1] % 3) {
          case 0:
            final all = await catalog();
            final already = {for (final s in slots) s.exerciseId};
            final free = [for (final x in all) if (!already.contains(x.id)) x];
            final chosen = pick(free, op.picks[2]);
            if (chosen == null) return false;
            await regimes.addExerciseToSession(session.id, chosen.id);
          case 1:
            final slot = pick(slots, op.picks[2]);
            if (slot == null) return false;
            await regimes.removeSessionExercise(slot.id);
          default:
            if (slots.length < 2) return false;
            await regimes.reorderSessionExercises(
              [for (final s in slots.reversed) s.id],
            );
        }
        return true;

      case OpKind.logBodyweight:
        final day = now.subtract(Duration(days: op.picks[0] % 30));
        final kg = 60 + (op.picks[1] % 400) / 10;
        await repo.logBodyweight(day, kg);
        bodyweights[dayKeyOf(day)] = kg;
        return true;

      case OpKind.deleteBodyweight:
        if (bodyweights.isEmpty) return false;
        final keys = bodyweights.keys.toList()..sort();
        final key = keys[op.picks[0] % keys.length];
        await repo.deleteBodyweight(key);
        bodyweights.remove(key);
        return true;

      case OpKind.advanceCycle:
        await repo.advanceCycle(regime.id);
        return true;

      case OpKind.backupRestore:
        // The one operation whose cost grows with the history behind it: it
        // rewrites every row every time, so a run long enough to be called a
        // soak spends nearly all of itself here. Thinning it is how the
        // operation count gets an order of magnitude higher for the same
        // afternoon — and the round trip is no less exercised by happening
        // every tenth time over ten times as many operations.
        if (++_backups % _backupEvery != 0) return false;
        // Round-tripped through JSON, not through the in-memory map, because a
        // field that only survives as a Dart object is a field that does not
        // survive a phone.
        final service = BackupService(db);
        final payload = await service.buildPayload();
        await service.restore(jsonEncode(payload));
        return true;
    }
  }

  // ── The comparison ──────────────────────────────────────────────────────

  /// Every value the model tracks, read straight off the tables.
  ///
  /// Deliberately not through the repository: a read path and a write path that
  /// share a bug agree with each other, and the whole point of the model is to
  /// have an opinion that was not computed by the code under test.
  Future<void> verify(String after) async {
    await expectInvariants(db, after: after);

    final rows = await (db.select(db.workouts)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    expect(
      rows.map((w) => w.id).toSet(),
      workouts.keys.toSet(),
      reason: 'live workouts disagree after $after',
    );

    for (final w in rows) {
      final m = workouts[w.id]!;
      expect(w.status, m.status, reason: 'status of ${w.id} after $after');
      expect(w.dayKey, m.dayKey, reason: 'dayKey of ${w.id} after $after');

      final wes = await (db.select(db.workoutExercises)
            ..where((t) => t.workoutId.equals(w.id) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(
        wes.map((e) => e.id).toList(),
        m.exercises.map((e) => e.id).toList(),
        reason: 'slots of ${w.id} after $after',
      );

      for (var i = 0; i < wes.length; i++) {
        final me = m.exercises[i];
        expect(wes[i].skipReason, me.skip,
            reason: 'skip reason of ${me.id} after $after');

        final sets = await (db.select(db.setLogs)
              ..where((t) =>
                  t.workoutExerciseId.equals(me.id) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
            .get();
        expect(
          sets.map((s) => s.id).toSet(),
          me.sets.map((s) => s.id).toSet(),
          reason: 'set ids of ${me.id} after $after',
        );
        final byId = {for (final s in sets) s.id: s};
        for (final ms in me.sets) {
          final s = byId[ms.id]!;
          expect(s.weight, ms.weight, reason: 'weight of ${ms.id} after $after');
          expect(s.reps, ms.reps, reason: 'reps of ${ms.id} after $after');
          expect(s.isDone, ms.done, reason: 'isDone of ${ms.id} after $after');
        }
      }
    }

    // Soft delete: every row the app took away is still on disk, tombstoned.
    if (tombstonedSets.isNotEmpty) {
      final ids = tombstonedSets.toList();
      final found = await (db.select(db.setLogs)..where((t) => t.id.isIn(ids)))
          .get();
      expect(found.length, ids.length,
          reason: 'a deleted set was hard-deleted, after $after');
      for (final s in found) {
        expect(s.deletedAt, isNotNull,
            reason: 'set ${s.id} is live again, after $after');
      }
    }

    final bw = await (db.select(db.bodyweightLogs)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    expect(
      {for (final b in bw) b.dayKey: b.weightKg},
      bodyweights,
      reason: 'bodyweights disagree after $after',
    );
  }
}

// ── Running, replaying, shrinking ─────────────────────────────────────────

/// Executes [ops] against a fresh database, returning the failure or null.
///
/// Returns rather than throws so the shrinker can ask "does this shorter
/// sequence still fail" without a `try` around every candidate.
Future<String?> runSequence(List<Op> ops, {List<Op>? applied}) async {
  resetStampsForTesting();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final h = Harness(db);
  try {
    await h.seed();
    await h.verify('seeding');
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (await h.apply(op)) {
        applied?.add(op);
        await h.verify('op $i ${op.kind.name}');
      }
    }
    return null;
  } on TestFailure catch (e) {
    return e.message ?? '$e';
  } catch (e, st) {
    return '$e\n$st';
  } finally {
    await db.close();
  }
}

/// The shortest prefix-free subsequence that still fails.
///
/// Greedy single-operation removal, repeated until a pass changes nothing. A
/// full delta-debug would be smaller on pathological cases; this one is a dozen
/// lines and turns a 500-operation run into something a person can read, which
/// is the whole requirement.
Future<List<Op>> shrink(List<Op> failing) async {
  var best = failing;
  var changed = true;
  while (changed && best.length > 1) {
    changed = false;
    for (var i = 0; i < best.length; i++) {
      final candidate = [...best]..removeAt(i);
      if (await runSequence(candidate) != null) {
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
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  final seeds = _env('FUZZ_SEEDS', 8);
  final opsPerSeed = _env('FUZZ_OPS', 120);
  final firstSeed = _env('FUZZ_SEED', 1);

  group('the model and the database agree', () {
    for (var s = firstSeed; s < firstSeed + seeds; s++) {
      final seed = s;
      test('seed $seed, $opsPerSeed operations', () async {
        final r = Random(seed);
        final ops = [for (var i = 0; i < opsPerSeed; i++) Op.random(r)];
        final applied = <Op>[];
        final failure = await runSequence(ops, applied: applied);
        // The evidence § 3b asks for is a number, so the number is printable.
        // Off by default because a green suite should be quiet.
        if (_env('FUZZ_REPORT', 0) == 1) {
          // ignore: avoid_print
          print('seed $seed: ${applied.length}/${ops.length} operations '
              'applied${failure == null ? '' : ', FAILED'}');
        }
        if (failure == null) return;

        final shortest = await shrink(applied);
        fail([
          'FUZZ FAILURE',
          '  seed: $seed  (rerun: FUZZ_SEED=$seed FUZZ_SEEDS=1 '
              'FUZZ_OPS=$opsPerSeed flutter test '
              'test/integrity/model_fuzz_test.dart)',
          '  applied ${applied.length} of ${ops.length} generated operations',
          '  shrunk to ${shortest.length}:',
          for (final op in shortest) '    $op',
          '',
          failure,
        ].join('\n'));
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  });

  // ── Durability ──────────────────────────────────────────────────────────
  //
  // On a real file, because an in-memory sqlite is always
  // `journal_mode = memory` and a durability claim read off one is worth
  // nothing.
  //
  // A `kill -9` cannot be staged from inside the test process: `flutter test`
  // runs on `flutter_tester`, and spawning it to run a script boots an engine
  // and hangs. What *can* be staged is the state a kill
  // leaves on disk — a transaction that never committed, and a connection that
  // was never closed — which is the thing the invariants have to survive.
  group('the database survives an unclean shutdown', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('deltoid_fuzz');
    });

    tearDown(() => dir.delete(recursive: true));

    test('a transaction torn in half leaves nothing behind', () async {
      final file = File('${dir.path}/deltoid.sqlite');
      resetStampsForTesting();
      var db = AppDatabase.forTesting(NativeDatabase(file));
      var h = Harness(db);
      await h.seed();

      final r = Random(_env('FUZZ_CRASH_SEED', 7));
      for (var i = 0; i < _env('FUZZ_CRASH_OPS', 40); i++) {
        if (await h.apply(Op.random(r))) {
          await h.verify('crash-run op $i');
        }
      }
      await h.ensureSomethingToLose();
      await h.verify('ensuring there is something to lose');
      final before = h.workouts.keys.toSet();

      // The half-written state: several rows land, then the transaction throws.
      // What must reach the file is nothing at all.
      //
      // **Both statements have to be ones SQLite accepts.** The first draft
      // wrote a `day_key` of 19700101, which the CHECK against `started_at`
      // refuses — so the transaction died on its own poison at statement one,
      // the delete never ran, and the test proved only that a constraint
      // works. The tear has to be legal on the way in and destructive once
      // committed, or there is nothing for the rollback to take back.
      final open = h.openWorkout ?? h.live.firstOrNull;
      if (open != null) {
        await expectLater(
          db.transaction(() async {
            await (db.update(db.workouts)..where((t) => t.id.equals(open.id)))
                .write(const WorkoutsCompanion(notes: Value('half-written')));
            await db.delete(db.setLogs).go();
            throw StateError('battery');
          }),
          throwsA(isA<StateError>()),
        );
        // The delete really would have been felt: the sets it took are the
        // ones the model is about to check for.
        expect(
          h.workouts.values.any((w) => w.exercises.any((e) => e.sets.isNotEmpty)),
          isTrue,
          reason: 'the torn transaction deleted nothing, so it proves nothing',
        );
      }
      await h.verify('a rolled-back transaction');

      // Reopened without ever having been closed — the file as a kill leaves
      // it, journal and all. The model carries across untouched, which is the
      // assertion: whatever recovery sqlite performed on open changed nothing
      // that had been committed.
      db = AppDatabase.forTesting(NativeDatabase(file));
      h = Harness(db)
        ..workouts.addAll(h.workouts)
        ..tombstonedSets.addAll(h.tombstonedSets)
        ..bodyweights.addAll(h.bodyweights);
      await h.verify('reopening the file');
      expect(h.workouts.keys.toSet(), before);
      await db.close();
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
