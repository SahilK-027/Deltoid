import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/enums.dart';
import '../db/database.dart';
import '../db/watch.dart';

/// One regime plus the two numbers that describe it in a list: how many
/// training days it holds, and how many sessions were logged under it.
class RegimeSummary {
  const RegimeSummary({
    required this.regime,
    required this.sessionCount,
    required this.workoutCount,
  });

  final Regime regime;
  final int sessionCount;
  final int workoutCount;
}

/// Edits to the programme itself: regimes, their sessions, and the exercise
/// slots inside them.
///
/// Kept separate from logging on purpose. Templates change rarely and
/// deliberately; workouts change constantly. Mixing the two is how apps end up
/// rewriting your history when you reorder a list.
class RegimeRepository {
  RegimeRepository(this.db);

  final AppDatabase db;

  // ── Regimes ───────────────────────────────────────────────────────────

  /// Switching regimes never edits the old one. Push/Pull/Legs history stays
  /// exactly as it was recorded, still attached to the programme it was run
  /// under, and can be charted alongside whatever comes next.
  Future<String> createRegime(String name, {bool activate = true}) async {
    final id = newId();
    await db.transaction(() async {
      if (activate) await _deactivateAll();
      await db.into(db.regimes).insert(
            RegimesCompanion.insert(
              id: Value(id),
              name: name,
              isActive: Value(activate),
            ),
          );
    });
    return id;
  }

  Future<void> setActiveRegime(String regimeId) async {
    await db.transaction(() async {
      await _deactivateAll();
      await (db.update(db.regimes)..where((t) => t.id.equals(regimeId))).write(
        RegimesCompanion(
          isActive: const Value(true),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Removes a regime from the programme list without touching training.
  ///
  /// Workouts hold their own snapshots and stay in History exactly as they were
  /// logged; what disappears is the split, its sessions and its cycle counter.
  Future<void> deleteRegime(String regimeId) async {
    await db.transaction(() async {
      final stamp = nowMs();
      await (db.update(db.regimes)..where((t) => t.id.equals(regimeId))).write(
        RegimesCompanion(
          isActive: const Value(false),
          deletedAt: Value(stamp),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );

      // Deleting the active one must never leave the app with no regime while
      // others exist — Today would show the first-launch screen to someone who
      // has three programmes.
      final active = await (db.select(db.regimes)
            ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();
      if (active != null) return;

      final fallback = await (db.select(db.regimes)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(1))
          .getSingleOrNull();
      if (fallback == null) return;

      await (db.update(db.regimes)..where((t) => t.id.equals(fallback.id)))
          .write(
        RegimesCompanion(
          isActive: const Value(true),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Every regime with the two numbers that decide whether it is safe to
  /// delete: how big it is, and how much was trained under it.
  Future<List<RegimeSummary>> regimeSummaries() async {
    final regimes = await (db.select(db.regimes)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    if (regimes.isEmpty) return const [];

    final ids = regimes.map((r) => r.id).toList();

    final sessionCount = db.sessions.id.count();
    final sessionRows = await (db.selectOnly(db.sessions)
          ..addColumns([db.sessions.regimeId, sessionCount])
          ..where(db.sessions.regimeId.isIn(ids) & db.sessions.deletedAt.isNull())
          ..groupBy([db.sessions.regimeId]))
        .get();
    final sessions = {
      for (final r in sessionRows)
        r.read(db.sessions.regimeId)!: r.read(sessionCount) ?? 0,
    };

    final workoutCount = db.workouts.id.count();
    final workoutRows = await (db.selectOnly(db.workouts)
          ..addColumns([db.workouts.regimeId, workoutCount])
          ..where(db.workouts.regimeId.isIn(ids) &
              db.workouts.deletedAt.isNull() &
              db.workouts.status.equalsValue(WorkoutStatus.completed))
          ..groupBy([db.workouts.regimeId]))
        .get();
    final workouts = {
      for (final r in workoutRows)
        r.read(db.workouts.regimeId)!: r.read(workoutCount) ?? 0,
    };

    return [
      for (final r in regimes)
        RegimeSummary(
          regime: r,
          sessionCount: sessions[r.id] ?? 0,
          workoutCount: workouts[r.id] ?? 0,
        ),
    ];
  }

  Stream<List<RegimeSummary>> watchRegimeSummaries() {
    return db.watchQuery(
      [db.regimes, db.sessions, db.workouts],
      regimeSummaries,
    );
  }

  Future<void> _deactivateAll() async {
    await db.update(db.regimes).write(
          RegimesCompanion(
            isActive: const Value(false),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
  }

  Future<void> updateRegime(
    String regimeId, {
    Value<String> name = const Value.absent(),
    Value<bool> deloadEnabled = const Value.absent(),
    Value<int> deloadAfterCycles = const Value.absent(),
    Value<int> deloadSetDelta = const Value.absent(),
    Value<int> deloadWeightPct = const Value.absent(),
  }) async {
    await (db.update(db.regimes)..where((t) => t.id.equals(regimeId))).write(
      RegimesCompanion(
        name: name,
        deloadEnabled: deloadEnabled,
        deloadAfterCycles: deloadAfterCycles,
        deloadSetDelta: deloadSetDelta,
        deloadWeightPct: deloadWeightPct,
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  // ── Sessions ──────────────────────────────────────────────────────────

  Future<String> addSession(String regimeId, String name) async {
    final existing = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull()))
        .get();
    final id = newId();
    await db.into(db.sessions).insert(
          SessionsCompanion.insert(
            id: Value(id),
            regimeId: regimeId,
            name: name,
            orderIndex: existing.length,
          ),
        );
    return id;
  }

  Future<void> renameSession(String sessionId, String name) async {
    await (db.update(db.sessions)..where((t) => t.id.equals(sessionId))).write(
      SessionsCompanion(
        name: Value(name),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Soft delete — past workouts keep pointing at the session, so history
  /// survives a programme change.
  Future<void> deleteSession(String sessionId) async {
    await (db.update(db.sessions)..where((t) => t.id.equals(sessionId))).write(
      SessionsCompanion(
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> reorderSessions(List<String> orderedIds) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (db.update(db.sessions)..where((t) => t.id.equals(orderedIds[i])))
            .write(
          SessionsCompanion(
            orderIndex: Value(i),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
      }
    });
  }

  // ── Exercise slots ────────────────────────────────────────────────────

  Future<String> addExerciseToSession(String sessionId, String exerciseId) async {
    final existing = await (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull()))
        .get();
    final id = newId();
    await db.into(db.sessionExercises).insert(
          SessionExercisesCompanion.insert(
            id: Value(id),
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: existing.length,
          ),
        );
    return id;
  }

  Future<void> removeSessionExercise(String id) async {
    await (db.update(db.sessionExercises)..where((t) => t.id.equals(id))).write(
      SessionExercisesCompanion(
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Undo for [removeSessionExercise]. The row was only tombstoned, so putting
  /// a slot back is clearing the stamp rather than rebuilding it — which also
  /// keeps its set target and rep range.
  Future<void> restoreSessionExercise(String id) async {
    await (db.update(db.sessionExercises)..where((t) => t.id.equals(id))).write(
      SessionExercisesCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> updateSessionExercise(
    String id, {
    Value<int> targetSets = const Value.absent(),
    Value<int?> targetRepLow = const Value.absent(),
    Value<int?> targetRepHigh = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) async {
    await (db.update(db.sessionExercises)..where((t) => t.id.equals(id))).write(
      SessionExercisesCompanion(
        targetSets: targetSets,
        targetRepLow: targetRepLow,
        targetRepHigh: targetRepHigh,
        notes: notes,
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> reorderSessionExercises(List<String> orderedIds) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (db.update(db.sessionExercises)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(
          SessionExercisesCompanion(
            orderIndex: Value(i),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
      }
    });
  }

  // ── Exercise catalog ──────────────────────────────────────────────────

  Future<String> createExercise({
    required String name,
    required MuscleGroup muscle,
    required Equipment equipment,
    required LoadMode loadMode,
    BarKind barKind = BarKind.none,
    List<String> videos = const [],
    String? notes,
  }) async {
    final id = newId();
    await db.into(db.exercises).insert(
          ExercisesCompanion.insert(
            id: Value(id),
            name: name,
            muscle: muscle,
            equipment: equipment,
            loadMode: loadMode,
            barKind: Value(barKind),
            formVideoUrls: Value(videos),
            notes: Value(notes),
          ),
        );
    return id;
  }

  Future<void> updateExercise(
    String id, {
    Value<String> name = const Value.absent(),
    Value<MuscleGroup> muscle = const Value.absent(),
    Value<Equipment> equipment = const Value.absent(),
    Value<LoadMode> loadMode = const Value.absent(),
    Value<BarKind> barKind = const Value.absent(),
    Value<List<String>> videos = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<bool> archived = const Value.absent(),
  }) async {
    await (db.update(db.exercises)..where((t) => t.id.equals(id))).write(
      ExercisesCompanion(
        name: name,
        muscle: muscle,
        equipment: equipment,
        loadMode: loadMode,
        barKind: barKind,
        formVideoUrls: videos,
        notes: notes,
        archived: archived,
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }
}
