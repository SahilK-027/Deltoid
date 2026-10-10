import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/enums.dart';
import '../db/database.dart';
import '../db/renumber.dart';
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
/// nothing else, so an empty name yields a row that cannot be identified:
/// History shows a
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
/// history that cannot be read, whichever was intended.
class RegimeNameTakenException implements Exception {
  const RegimeNameTakenException(this.name);

  final String name;

  @override
  String toString() => 'RegimeNameTakenException: $name is already in use';
}

/// Thrown when a name is already on a live session of the same regime.
///
/// The same argument as [RegimeNameTakenException], one level down, and it
/// matters more here: the whole app turns on *which session* a number came
/// from. The prefill disclosure says "borrowed from Push 1 on 3 March", History
/// filters by the day's name, and the progress chart draws one line per session
/// with the name as its only label. Two live `Push 1`s in one regime makes every
/// one of those sentences ambiguous, and nothing else on screen tells them
/// apart.
///
/// Across regimes is fine and common — two programmes may each have a `Push 1`,
/// which is why `LoggedSession` carries the regime name beside it.
class SessionNameTakenException implements Exception {
  const SessionNameTakenException(this.name);

  final String name;

  @override
  String toString() => 'SessionNameTakenException: $name is already in use';
}

/// Edits to the programme itself: regimes, their sessions, and the exercise
/// slots inside them.
///
/// Kept separate from logging on purpose. Templates change rarely and
/// deliberately; workouts change constantly. Mixing the two is how apps end up
/// rewriting recorded history when a list is reordered.
class RegimeRepository {
  RegimeRepository(this.db);

  final AppDatabase db;

  // ── Regimes ───────────────────────────────────────────────────────────

  /// Switching regimes never edits the one being left. Push/Pull/Legs history
  /// stays exactly as it was recorded, still attached to the programme it was
  /// run under, and can be charted alongside whatever comes next.
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
              // The flag is local; this is what the other phone reads. A regime
              // created inactive has never been activated, so it stays null and
              // is not a candidate — see [resolveActiveRegime].
              activatedAt: Value(activate ? nowMs() : null),
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
      final stamp = nowMs();
      await (db.update(db.regimes)..where((t) => t.id.equals(regimeId))).write(
        RegimesCompanion(
          isActive: const Value(true),
          // The activation, as a fact about this row rather than as the absence
          // of one on every other row. It is what the other phone merges and
          // what both phones then derive the flag from.
          activatedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Removes a regime from the programme list without touching training.
  ///
  /// Workouts hold their own snapshots and stay in History exactly as they were
  /// logged; what disappears is the split and its cycle counter.
  ///
  /// Its cycles are removed with it, a cycle existing only to number this
  /// regime's weeks. Its sessions deliberately are not, even though nothing
  /// outside
  /// this regime reads them: `loggedSessions` filters `sessions.deletedAt`, so
  /// tombstoning them removes every one from History's session filter and
  /// takes away the only way to page a retired programme's history. That
  /// asymmetry is deliberate, and it is a stop rather than a tidy-up.
  Future<void> deleteRegime(String regimeId) async {
    await db.transaction(() async {
      final stamp = nowMs();
      await (db.update(db.regimes)..where((t) => t.id.equals(regimeId))).write(
        RegimesCompanion(
          isActive: const Value(false),
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );
      await (db.update(db.cycles)..where((t) => t.regimeId.equals(regimeId)))
          .write(
        CyclesCompanion(
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
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

      final promoted = nowMs();
      await (db.update(db.regimes)..where((t) => t.id.equals(fallback.id)))
          .write(
        RegimesCompanion(
          isActive: const Value(true),
          // Deliberate, so it is stamped: the successor is this phone's choice,
          // not something the other one can be left to infer. Without it the
          // other phone sees only a tombstone, finds no candidate and shows no
          // active programme at all.
          activatedAt: Value(promoted),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(promoted),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Every regime with the two numbers that decide whether it is safe to
  /// delete: how big it is, and how much was trained under it.
  ///
  /// Drift rather than raw: both counts are grouped by regime, so
  /// the row count is the number of programmes ever created, a single
  /// figures — and the `IN (…)` lists are one parameter per regime rather than
  /// per workout counted.
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
  /// Rewriting every regime in the table, tombstoned ones included, re-stamps
  /// and dirties six rows to turn one flag off. Harmless while the writes stay
  /// on this phone; as a push, switching programmes would ship the whole shelf
  /// every time.
  Future<void> _deactivateAll() async {
    await (db.update(db.regimes)..where((t) => t.isActive.equals(true))).write(
      RegimesCompanion(
        isActive: const Value(false),
        deviceId: Value(currentDeviceId),
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
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  // ── Sessions ──────────────────────────────────────────────────────────

  /// One past the highest position, in a transaction.
  ///
  /// Not the number of live rows: a deleted session is tombstoned and nothing
  /// renumbers behind it, so counting hands the new row a position a surviving
  /// one still holds — and two rows on one `orderIndex` leave the programme's
  /// order to whichever way SQLite breaks the tie.
  Future<String> addSession(String regimeId, String name) async {
    if (name.trim().isEmpty) throw const BlankNameException('session');
    final id = newId();
    await db.transaction(() async {
      if (await isSessionNameTaken(regimeId, name)) {
        throw SessionNameTakenException(name);
      }
      final existing = await (db.select(db.sessions)
            ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull()))
          .get();
      await db.into(db.sessions).insert(
            SessionsCompanion.insert(
              id: Value(id),
              regimeId: regimeId,
              name: name,
              orderIndex: nextPosition([for (final s in existing) s.orderIndex]),
            ),
          );
    });
    return id;
  }

  /// Whether a live session of [regimeId] already answers to this name.
  ///
  /// Trimmed and case-insensitive, matching [isNameTaken] and matching the
  /// index that backs it — `idx_sessions_name_live` keys on
  /// `lower(trim(name))`, so the two cannot disagree about what a duplicate is.
  Future<bool> isSessionNameTaken(
    String regimeId,
    String name, {
    String? exceptId,
  }) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return false;

    final live = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull()))
        .get();
    return live.any(
      (s) => s.id != exceptId && s.name.trim().toLowerCase() == wanted,
    );
  }

  /// Every live session name in a regime, trimmed and lowercased — what a
  /// prompt checks its field against while it is being typed.
  Future<Set<String>> liveSessionNames(
    String regimeId, {
    String? exceptId,
  }) async {
    final live = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regimeId) & t.deletedAt.isNull()))
        .get();
    return {
      for (final s in live)
        if (s.id != exceptId) s.name.trim().toLowerCase(),
    };
  }

  Future<void> renameSession(String sessionId, String name) async {
    if (name.trim().isEmpty) throw const BlankNameException('session');
    await db.transaction(() async {
      final session = await (db.select(db.sessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();
      if (session == null) return;
      if (await isSessionNameTaken(
        session.regimeId,
        name,
        exceptId: sessionId,
      )) {
        throw SessionNameTakenException(name);
      }
      await (db.update(db.sessions)..where((t) => t.id.equals(sessionId)))
          .write(
        SessionsCompanion(
          name: Value(name),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Soft delete — past workouts keep pointing at the session, so history
  /// survives a programme change.
  ///
  /// Its slots are removed with it, because a `session_exercises` row exists
  /// only to describe the session; its workouts are not, because they record
  /// what
  /// was done. A row that *describes* goes with its parent and a row that
  /// *records* stays: that distinction is the whole of the cascade, and widening
  /// it here would delete training rather than a template.
  Future<void> deleteSession(String sessionId) async {
    final stamp = nowMs();
    await db.transaction(() async {
      await (db.update(db.sessionExercises)
            ..where((t) => t.sessionId.equals(sessionId)))
          .write(
        SessionExercisesCompanion(
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );
      await (db.update(db.sessions)..where((t) => t.id.equals(sessionId)))
          .write(
        SessionsCompanion(
          deletedAt: Value(stamp),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(stamp),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Two passes through free ground — see [renumber]. A single pass writes a
  /// position a surviving row still holds, and `idx_sessions_position_live`
  /// refuses it mid-transaction.
  Future<void> reorderSessions(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    await db.transaction(() async {
      final live = await (db.select(db.sessions)
            ..where((t) => t.id.isIn(orderedIds) & t.deletedAt.isNull()))
          .get();
      if (live.isEmpty) return;
      final scope = await (db.select(db.sessions)
            ..where((t) =>
                t.regimeId.equals(live.first.regimeId) & t.deletedAt.isNull()))
          .get();

      await renumber(
        orderedIds,
        scope: {for (final s in scope) s.id: s.orderIndex},
        write: (id, orderIndex) async {
          await (db.update(db.sessions)..where((t) => t.id.equals(id))).write(
            SessionsCompanion(
              orderIndex: Value(orderIndex),
              deviceId: Value(currentDeviceId),
              updatedAt: Value(nowMs()),
              dirty: const Value(true),
            ),
          );
        },
      );
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
              orderIndex: nextPosition([for (final s in existing) s.orderIndex]),
            ),
          );
    });
    return id;
  }

  Future<void> removeSessionExercise(String id) async {
    await (db.update(db.sessionExercises)..where((t) => t.id.equals(id))).write(
      SessionExercisesCompanion(
        deletedAt: Value(nowMs()),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Undo for [removeSessionExercise]. The row was only tombstoned, so putting
  /// a slot back is clearing the stamp rather than rebuilding it — which also
  /// keeps its set target and rep range.
  ///
  /// It comes back at the end, not where it was. The position it held is free
  /// ground the moment it is tombstoned — `idx_session_exercises_position_live`
  /// is scoped `WHERE deleted_at IS NULL` — so an append behind it is entitled
  /// to take it, and one that appends past the highest live index takes exactly
  /// that one when the removed slot was the last. Carrying the tombstoned
  /// position back makes the undo throw on the index rather than restore
  /// anything; see [TrainingRepository.applySessionChanges], which revives the
  /// same way.
  Future<void> restoreSessionExercise(String id) async {
    await db.transaction(() async {
      final row = await (db.select(db.sessionExercises)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return;
      final live = await (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(row.sessionId) & t.deletedAt.isNull()))
          .get();

      await (db.update(db.sessionExercises)..where((t) => t.id.equals(id)))
          .write(
        SessionExercisesCompanion(
          deletedAt: const Value(null),
          orderIndex: Value(nextPosition(live.map((s) => s.orderIndex))),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    });
  }

  Future<void> updateSessionExercise(
    String id, {
    Value<int> targetSets = const Value.absent(),
    Value<int?> targetRepLow = const Value.absent(),
    Value<int?> targetRepHigh = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    /// Null means "use the default from Settings". A rest is per slot because
    /// a heavy compound wants three minutes and a cable fly wants sixty
    /// seconds, and re-dialling that on every exercise is the kind of friction
    /// that gets an app closed mid-session.
    Value<int?> restSeconds = const Value.absent(),
    /// Null means "follow the regime". An exercise that is already light does
    /// not need the same cut as a heavy compound.
    Value<int?> deloadSetDelta = const Value.absent(),
    Value<int?> deloadWeightPct = const Value.absent(),
  }) async {
    await (db.update(db.sessionExercises)..where((t) => t.id.equals(id))).write(
      SessionExercisesCompanion(
        targetSets: targetSets,
        targetRepLow: targetRepLow,
        targetRepHigh: targetRepHigh,
        notes: notes,
        restSeconds: restSeconds,
        deloadSetDelta: deloadSetDelta,
        deloadWeightPct: deloadWeightPct,
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Which bar this movement is loaded on within this training day.
  ///
  /// Null clears the override and hands the answer back to the catalog row.
  ///
  /// It also updates the session currently open, and only that one.
  /// The slot carries the decision to every future run of this day; a workout
  /// already in progress is the current run, and the bar just specified is the
  /// one in use. Completed workouts are not modified:
  /// they hold what was actually used, which is the whole reason the snapshot
  /// column exists ([WorkoutExercises.barKind]).
  ///
  /// The open workout is matched on its session and its exercise rather than on
  /// the slot: a `workout_exercises` row points at the exercise and the
  /// workout, never at the template row it was copied from.
  ///
  /// One limitation follows from this, and no column addresses it. A
  /// day may run the same movement twice — the picker marks a repeat rather
  /// than refusing it — and those two slots can hold two different bars. Today's
  /// rows cannot be told apart by slot, so naming a bar on either occurrence
  /// writes it to both of today's rows. The slots themselves keep their own
  /// answers, so next week opens correctly; it is only the session already in
  /// progress that cannot distinguish them.
  ///
  /// "In progress" is also literal rather than "today": a session of this day
  /// left open from a previous week is still open, and is patched with it. That
  /// is the right answer — it has not been recorded as anything yet — but it is
  /// worth knowing it is the rule being applied.
  Future<void> setSessionExerciseBarKind(
    String slotId,
    BarKind? barKind,
  ) async {
    final slot = await (db.select(db.sessionExercises)
          ..where((t) => t.id.equals(slotId)))
        .getSingleOrNull();
    if (slot == null) return;

    await db.transaction(() async {
      await (db.update(db.sessionExercises)..where((t) => t.id.equals(slotId)))
          .write(
        SessionExercisesCompanion(
          barKind: Value(barKind),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );

      // Cleared rather than set: with no override the day follows the catalog,
      // and today's row should say the same thing the day now says.
      final effective = barKind ??
          (await (db.select(db.exercises)
                    ..where((t) => t.id.equals(slot.exerciseId)))
                  .getSingleOrNull())
              ?.barKind;
      if (effective == null) return;

      final open = await (db.select(db.workouts)
            ..where((t) =>
                t.sessionId.equals(slot.sessionId) &
                t.status.equalsValue(WorkoutStatus.inProgress) &
                t.deletedAt.isNull()))
          .get();
      if (open.isEmpty) return;

      await (db.update(db.workoutExercises)
            ..where((t) =>
                t.workoutId.isIn([for (final w in open) w.id]) &
                t.exerciseId.equals(slot.exerciseId) &
                t.deletedAt.isNull()))
          .write(
        WorkoutExercisesCompanion(
          barKind: Value(effective),
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Two passes through free ground, for the reason [reorderSessions] gives.
  Future<void> reorderSessionExercises(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    await db.transaction(() async {
      final live = await (db.select(db.sessionExercises)
            ..where((t) => t.id.isIn(orderedIds) & t.deletedAt.isNull()))
          .get();
      if (live.isEmpty) return;
      final scope = await (db.select(db.sessionExercises)
            ..where((t) =>
                t.sessionId.equals(live.first.sessionId) &
                t.deletedAt.isNull()))
          .get();

      await renumber(
        orderedIds,
        scope: {for (final s in scope) s.id: s.orderIndex},
        write: (id, orderIndex) async {
          await (db.update(db.sessionExercises)..where((t) => t.id.equals(id)))
              .write(
            SessionExercisesCompanion(
              orderIndex: Value(orderIndex),
              deviceId: Value(currentDeviceId),
              updatedAt: Value(nowMs()),
              dirty: const Value(true),
            ),
          );
        },
      );
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
    int bodyweightPct = 100,
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
            bodyweightPct: Value(bodyweightPct),
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
    Value<int> bodyweightPct = const Value.absent(),
    Value<List<String>> videos = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<bool> archived = const Value.absent(),
  }) async {
    if (name.present && name.value.trim().isEmpty) {
      throw const BlankNameException('exercise');
    }
    await db.transaction(() async {
      await (db.update(db.exercises)..where((t) => t.id.equals(id))).write(
        ExercisesCompanion(
          name: name,
          muscle: muscle,
          equipment: equipment,
          loadMode: loadMode,
          barKind: barKind,
          measureMode: measureMode,
          bodyweightPct: bodyweightPct,
          formVideoUrls: videos,
          notes: notes,
          archived: archived,
          deviceId: Value(currentDeviceId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
      if (barKind.present) {
        await _followCatalogBarInOpenWorkouts(id, barKind.value);
      }
      if (muscle.present) {
        await _followCatalogMuscleInOpenWorkouts(id, muscle.value);
      }
    });
  }

  /// The muscle equivalent of [_followCatalogBarInOpenWorkouts], simpler
  /// because a day cannot override the muscle. The session in progress counts
  /// toward the muscle just named; completed workouts keep the one they were
  /// logged with, which is what `WorkoutExercises.muscle` exists to preserve.
  Future<void> _followCatalogMuscleInOpenWorkouts(
    String exerciseId,
    MuscleGroup muscle,
  ) async {
    final open = await (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.inProgress) &
              t.deletedAt.isNull()))
        .get();
    if (open.isEmpty) return;

    await (db.update(db.workoutExercises)
          ..where((t) =>
              t.workoutId.isIn([for (final w in open) w.id]) &
              t.exerciseId.equals(exerciseId) &
              t.deletedAt.isNull()))
        .write(
      WorkoutExercisesCompanion(
        muscle: Value(muscle),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  /// Carries a catalog bar change into every workout still in progress, for
  /// the reason [setSessionExerciseBarKind] gives: the open session is the
  /// current run, and the bar just named is the one in use. Without this the
  /// plate view went on breaking weights over the bar the session opened
  /// with, however many times the exercise was corrected.
  ///
  /// Only rows that follow the catalog are patched. A workout whose day names
  /// its own bar for this movement keeps it, since the catalog was never its
  /// answer; a workout from no template, or a movement added mid-session, has
  /// no slot and so has only the catalog to follow. Completed workouts are not
  /// touched.
  Future<void> _followCatalogBarInOpenWorkouts(
    String exerciseId,
    BarKind barKind,
  ) async {
    final open = await (db.select(db.workouts)
          ..where((t) =>
              t.status.equalsValue(WorkoutStatus.inProgress) &
              t.deletedAt.isNull()))
        .get();
    if (open.isEmpty) return;

    final overridden = <String>{
      for (final slot in await (db.select(db.sessionExercises)
            ..where((t) =>
                t.exerciseId.equals(exerciseId) &
                t.barKind.isNotNull() &
                t.deletedAt.isNull()))
          .get())
        slot.sessionId,
    };
    final following = [
      for (final w in open)
        if (w.sessionId == null || !overridden.contains(w.sessionId)) w.id,
    ];
    if (following.isEmpty) return;

    await (db.update(db.workoutExercises)
          ..where((t) =>
              t.workoutId.isIn(following) &
              t.exerciseId.equals(exerciseId) &
              t.deletedAt.isNull()))
        .write(
      WorkoutExercisesCompanion(
        barKind: Value(barKind),
        deviceId: Value(currentDeviceId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }
}
