import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/session_diff.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// `WorkoutExercise` and `SetLog` are snapshots — INVARIANTS.md § 19.
///
/// The invariant was held by inspection: someone walked every writer of the two
/// tables and found none of them reachable from a programme edit. That is a
/// reading of the code as it was on the day it was read, and it is the rule
/// [CLAUDE.md](CLAUDE.md) puts second, so it should not depend on anyone
/// remembering to walk it again.
///
/// This is the executable form. Log a session, freeze the two tables, run every
/// mutator the programme side has, and assert nothing moved — not a value, not
/// an `updated_at`, not a `dirty` flag. **Byte-identical**, because a
/// snapshot rewritten with the same numbers is still a row a sync push would
/// send and still a rule that has stopped holding.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late RegimeRepository regimes;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    regimes = RegimeRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
  });

  tearDown(() => db.close());

  /// Both snapshot tables as JSON, ordered so the comparison is about content
  /// rather than about the order rows come back in.
  Future<List<Map<String, dynamic>>> frozen() async {
    final slots = await db.select(db.workoutExercises).get();
    final sets = await db.select(db.setLogs).get();
    final rows = [
      for (final r in slots) {'#': 'we', ...r.toJson()},
      for (final r in sets) {'#': 'sl', ...r.toJson()},
    ]..sort((a, b) => '${a['#']}${a['id']}'.compareTo('${b['#']}${b['id']}'));
    return rows;
  }

  test('a logged workout is byte-identical after every programme edit',
      () async {
    final regime =
        await (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
            .getSingle();
    final push1 =
        await (db.select(db.sessions)..where((t) => t.name.equals('Push 1')))
            .getSingle();

    final workoutId =
        await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(workoutId);
    for (final entry in detail!.entries) {
      for (final set in entry.sets) {
        await repo.updateSet(
          set.id,
          weight: const Value(40),
          reps: const Value(8),
          isDone: const Value(true),
        );
      }
    }
    await repo.completeWorkout(workoutId);

    final before = await frozen();
    expect(before, isNotEmpty);

    // The slots and movements the workout actually snapshotted, so every edit
    // below lands on the programme rows this history came from rather than on
    // something unrelated.
    final slots = await (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(push1.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    expect(slots.length, greaterThan(2));
    final loggedExerciseId = slots.first.exerciseId;

    // Every writer on the programme side of the line, in one pass.
    //
    // `updateExercise` first and on the movement the workout logged: renaming
    // and refiling a movement is the edit this invariant exists for — March's
    // volume must not be re-attributed because a bicep curl was refiled to
    // shoulders in July.
    await regimes.updateExercise(
      loggedExerciseId,
      name: const Value('Renamed mid-history'),
      muscle: const Value(MuscleGroup.calves),
      equipment: const Value(Equipment.machine),
      loadMode: const Value(LoadMode.total),
      barKind: const Value(BarKind.ez),
      measureMode: const Value(MeasureMode.hold),
      videos: const Value(['https://example.com/v']),
      notes: const Value('a note'),
      archived: const Value(true),
    );

    await regimes.updateSessionExercise(
      slots.first.id,
      targetSets: const Value(9),
      targetRepLow: const Value(1),
      targetRepHigh: const Value(2),
      notes: const Value('slot note'),
      deloadSetDelta: const Value(-3),
      deloadWeightPct: const Value(50),
    );
    await regimes.removeSessionExercise(slots.last.id);
    await regimes.restoreSessionExercise(slots.last.id);
    await regimes.reorderSessionExercises(
      slots.reversed.map((s) => s.id).toList(),
    );

    final added = await regimes.createExercise(
      name: 'Something new',
      muscle: MuscleGroup.calves,
      equipment: Equipment.machine,
      loadMode: LoadMode.total,
    );
    await regimes.addExerciseToSession(push1.id, added);

    // The one on the training side of the line, and the one whose doc claims
    // this invariant by name: writing today's improvisation back into the
    // template.
    await repo.applySessionChanges(
      sessionId: push1.id,
      changes: [
        SessionChange(
          kind: SessionChangeKind.added,
          exerciseIds: [added],
          label: 'Added Something new',
        ),
        SessionChange(
          kind: SessionChangeKind.removed,
          exerciseIds: [slots[1].exerciseId],
          label: 'Removed one',
        ),
        SessionChange(
          kind: SessionChangeKind.reordered,
          exerciseIds: slots.reversed.map((s) => s.exerciseId).toList(),
          label: 'Reordered',
        ),
      ],
    );

    await regimes.renameSession(push1.id, 'Push 1 renamed');
    final otherSession = await regimes.addSession(regime.id, 'Extra day');
    final sessionIds = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    await regimes
        .reorderSessions(sessionIds.reversed.map((s) => s.id).toList());
    await regimes.deleteSession(otherSession);

    await regimes.updateRegime(
      regime.id,
      name: const Value('Renamed programme'),
      deloadEnabled: const Value(false),
      deloadAfterCycles: const Value(3),
      deloadSetDelta: const Value(-2),
      deloadWeightPct: const Value(60),
    );
    final second = await regimes.createRegime('A second programme');
    await regimes.setActiveRegime(second);

    // Last, because it takes the programme the history came from. A deleted
    // programme keeps its workouts — INVARIANTS.md § 1's exception list — so
    // the snapshots must still be here, and unchanged.
    await regimes.deleteRegime(regime.id);
    await regimes.deleteSession(push1.id);

    expect(await frozen(), before);
  });
}
