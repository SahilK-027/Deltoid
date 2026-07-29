import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/enums.dart';
import '../db/database.dart';

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
        formVideoUrls: videos,
        notes: notes,
        archived: archived,
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }
}
