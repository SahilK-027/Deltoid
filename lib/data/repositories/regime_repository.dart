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

/// Thrown when every identity hue is spoken for.
///
/// A colour per live regime is the rule the mark depends on, so the cap is a
/// refusal rather than a wrap-around: six programmes at a time, and the seventh
/// waits for one to be deleted.
class RegimeSlotsFullException implements Exception {
  const RegimeSlotsFullException();

  @override
  String toString() =>
      'RegimeSlotsFullException: all $identitySlots identity slots are taken';
}

/// Thrown when a name is nothing but whitespace.
///
/// A regime and an exercise are both identified on screen by their name and
/// nothing else, so an empty one is a row you cannot point at: History shows a
/// blank, the picker shows a blank, and the only way to tell two of them apart
/// is the order they happen to be in. The UI asks for a name; this is the rule
/// underneath, so a name can never be lost by a path that forgot to check.
class BlankNameException implements Exception {
  const BlankNameException(this.what);

  /// What was being named — `regime`, `session`, `exercise`.
  final String what;

  @override
  String toString() => 'BlankNameException: a $what needs a name';
}

/// Thrown when a name is already on a live regime.
///
/// A regime is identified on screen by its name and its colour, and nothing
/// else — History says "PPL", Today says "PPL". Two of them called `PPL` is a
/// history you cannot read, whichever one you meant.
class RegimeNameTakenException implements Exception {
  const RegimeNameTakenException(this.name);

  final String name;

  @override
  String toString() => 'RegimeNameTakenException: $name is already in use';
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
    if (name.trim().isEmpty) throw const BlankNameException('regime');
    final id = newId();
    await db.transaction(() async {
      if (await isNameTaken(name)) throw RegimeNameTakenException(name);
      final slot = await nextIdentitySlot();
      if (slot == null) throw const RegimeSlotsFullException();
      if (activate) await _deactivateAll();
      await db.into(db.regimes).insert(
            RegimesCompanion.insert(
              id: Value(id),
              name: name,
              isActive: Value(activate),
              identityIndex: Value(slot),
            ),
          );
    });
    return id;
  }

  /// Whether a live regime already answers to this name.
  ///
  /// Trimmed and case-insensitive: `ppl` and `PPL ` are the same programme to
  /// everyone except a string comparison. [exceptId] lets a rename keep its own
  /// name — saving `PPL` on the regime already called `PPL` is a no-op, not a
  /// collision. Deleted regimes don't hold a name; they are gone from every
  /// screen that shows one.
  Future<bool> isNameTaken(String name, {String? exceptId}) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return false;

    final query = db.select(db.regimes)..where((t) => t.deletedAt.isNull());
    final live = await query.get();
    return live.any(
      (r) => r.id != exceptId && r.name.trim().toLowerCase() == wanted,
    );
  }

  /// Every live regime's name, trimmed and lowercased — what a prompt checks
  /// its field against while it is being typed.
  Future<Set<String>> liveNames({String? exceptId}) async {
    final query = db.select(db.regimes)..where((t) => t.deletedAt.isNull());
    final live = await query.get();
    return {
      for (final r in live)
        if (r.id != exceptId) r.name.trim().toLowerCase(),
    };
  }

  /// The lowest identity hue no live regime is wearing, or null when all
  /// [identitySlots] are taken.
  ///
  /// Lowest-free rather than next-in-sequence: deleting the green one and
  /// creating another should give the new regime green back, not walk the
  /// counter off the end of a palette that has six colours in it.
  Future<int?> nextIdentitySlot() async {
    final taken = await liveIdentitySlots();
    for (var i = 0; i < identitySlots; i++) {
      if (!taken.contains(i)) return i;
    }
    return null;
  }

  Future<Set<int>> liveIdentitySlots() async {
    final query = db.select(db.regimes)..where((t) => t.deletedAt.isNull());
    final live = await query.get();
    return {for (final r in live) r.identityIndex};
  }

  /// How many regimes can still be created. Watched by the Regimes screen so
  /// the `New` action can say why it is off before it is tapped.
  Stream<int> watchFreeIdentitySlots() {
    final query = db.select(db.regimes)..where((t) => t.deletedAt.isNull());
    return query.watch().map((live) {
      final taken = {for (final r in live) r.identityIndex};
      var free = 0;
      for (var i = 0; i < identitySlots; i++) {
        if (!taken.contains(i)) free++;
      }
      return free;
    });
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

  /// Only the row that is actually active.
  ///
  /// This used to rewrite every regime in the table, tombstoned ones included —
  /// six rows re-stamped and marked dirty to turn one flag off. Harmless while
  /// the writes stay on this phone; once they are a push, switching programmes
  /// would ship the whole shelf every time.
  Future<void> _deactivateAll() async {
    await (db.update(db.regimes)..where((t) => t.isActive.equals(true))).write(
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
    // A rename is the other way two regimes end up with one name, and it is
    // the easier one to reach: the create flow at least asks for a new name.
    if (name.present && name.value.trim().isEmpty) {
      throw const BlankNameException('regime');
    }
    if (name.present && await isNameTaken(name.value, exceptId: regimeId)) {
      throw RegimeNameTakenException(name.value);
    }
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

  /// One past the highest position, in a transaction.
  ///
  /// Not the number of live rows: a deleted session is tombstoned and nothing
  /// renumbers behind it, so counting handed the new row a position a surviving
  /// one still held — and two rows on one `orderIndex` leave the programme's
  /// order to whichever way SQLite breaks the tie.
  Future<String> addSession(String regimeId, String name) async {
    if (name.trim().isEmpty) throw const BlankNameException('session');
    final id = newId();
    await db.transaction(() async {
      final existing = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull()))
          .get();
      await db.into(db.sessions).insert(
            SessionsCompanion.insert(
              id: Value(id),
              regimeId: regimeId,
              name: name,
              orderIndex: _nextIndex([for (final s in existing) s.orderIndex]),
            ),
          );
    });
    return id;
  }

  static int _nextIndex(List<int> taken) =>
      taken.fold<int>(-1, (m, i) => i > m ? i : m) + 1;

  Future<void> renameSession(String sessionId, String name) async {
    if (name.trim().isEmpty) throw const BlankNameException('session');
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

  /// Appended past the highest position rather than at the live count — see
  /// [addSession] for why the two are not the same number.
  Future<String> addExerciseToSession(String sessionId, String exerciseId) async {
    final id = newId();
    await db.transaction(() async {
      final existing = await (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull()))
          .get();
      await db.into(db.sessionExercises).insert(
            SessionExercisesCompanion.insert(
              id: Value(id),
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: _nextIndex([for (final s in existing) s.orderIndex]),
            ),
          );
    });
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
    /// Null means "follow the regime". An exercise that is already light does
    /// not need the same cut as a heavy compound, and the columns carried that
    /// distinction long before anything could set them.
    Value<int?> deloadSetDelta = const Value.absent(),
    Value<int?> deloadWeightPct = const Value.absent(),
  }) async {
    await (db.update(db.sessionExercises)..where((t) => t.id.equals(id))).write(
      SessionExercisesCompanion(
        targetSets: targetSets,
        targetRepLow: targetRepLow,
        targetRepHigh: targetRepHigh,
        notes: notes,
        deloadSetDelta: deloadSetDelta,
        deloadWeightPct: deloadWeightPct,
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
    MeasureMode measureMode = MeasureMode.reps,
    List<String> videos = const [],
    String? notes,
  }) async {
    if (name.trim().isEmpty) throw const BlankNameException('exercise');
    final id = newId();
    await db.into(db.exercises).insert(
          ExercisesCompanion.insert(
            id: Value(id),
            name: name,
            muscle: muscle,
            equipment: equipment,
            loadMode: loadMode,
            barKind: Value(barKind),
            measureMode: Value(measureMode),
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
    Value<MeasureMode> measureMode = const Value.absent(),
    Value<List<String>> videos = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<bool> archived = const Value.absent(),
  }) async {
    if (name.present && name.value.trim().isEmpty) {
      throw const BlankNameException('exercise');
    }
    await (db.update(db.exercises)..where((t) => t.id.equals(id))).write(
      ExercisesCompanion(
        name: name,
        muscle: muscle,
        equipment: equipment,
        loadMode: loadMode,
        barKind: barKind,
        measureMode: measureMode,
        formVideoUrls: videos,
        notes: notes,
        archived: archived,
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }
}
