import 'package:drift/drift.dart';

import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../domain/enums.dart';
import '../../domain/sync_merge.dart';
import '../db/database.dart';
import '../db/table_spec.dart';
import '../repositories/repairs.dart';
import 'sync_backend.dart';

/// `app_settings` key holding how far this device has read the account.
///
/// Local bookkeeping about a server, like `device_id` beside it, and never
/// synced. It moves **only after the batch that earned it has committed**
/// ([SYNC.md § 15](SYNC.md#15-what-sync-may-never-do) rule 6): a cursor advanced
/// before the write loses every row in the batch it did not finish, silently and
/// for good.
const lastPullKey = 'last_pull_at';

/// What one pull did.
///
/// [unchanged] is the boundary row the `>=` cursor deliberately re-reads. It is
/// counted apart from [applied] because it is the difference between a pull that
/// did nothing and a pull that did nothing *twice*: a row rewritten with the
/// values it already has still wakes every stream watching that table, which
/// wakes the engine, which pulls again. Idempotent is not the same as inert.
typedef PullReport = ({int applied, int kept, int skipped, int unchanged});

/// Applies what the account holds that this device has not seen.
///
/// [SYNC.md § 7](SYNC.md#7-pull), with the deciding done in
/// `domain/sync_merge.dart` — this file is the input and the output: read the
/// scope, ask the domain, write the answer.
///
/// **Pull before push.** A conflict is resolved before it is propagated, and a
/// local row that wins one stays dirty so the push that follows sends it. That
/// ordering is the whole of what makes the two devices converge rather than
/// trade the same row forever.
///
/// **Three things this never does.** It never writes a pulled row through the
/// ordinary write path — that would stamp every applied row as locally owed and
/// push them all straight back
/// ([§ 17](SYNC.md#17-the-architecture)). It never hard-deletes: a tombstone
/// arrives as a row and stays one, because a hard delete has no `deleted_at` to
/// push and would be resurrected by the next pull from the other side. And it
/// never lets one bad row stop the rest — a row the local CHECKs refuse is
/// skipped, named through `core/failure.dart`, and the other twenty thousand
/// still arrive ([§ 13](SYNC.md#13-when-it-fails)).
class PullService {
  PullService(this._db, this._backend, {this.batchSize = 400});

  final AppDatabase _db;
  final SyncBackend _backend;
  final int batchSize;

  Future<PullReport> pull() async {
    final cursor = await _cursor();
    var applied = 0;
    var kept = 0;
    var skipped = 0;
    var unchanged = 0;
    DateTime? highest;

    // Parents before children, so a row never lands ahead of the row it points
    // at. The server declares no foreign keys, but this database does.
    for (final spec in tableSpecs(_db).where((s) => s.syncs)) {
      var after = cursor;
      final seen = <String>{};

      while (true) {
        final page = await _backend.since(spec.name, after, limit: batchSize);
        if (page.isEmpty) break;

        // The cursor compares `>=`, so the boundary row comes back on the next
        // page as well. Re-applying it would be harmless — everything here is
        // idempotent — but it would also never end, so the ids this pass has
        // already handled are dropped rather than re-decided.
        final fresh = page.where((row) => seen.add(_idOf(row))).toList();
        if (fresh.isNotEmpty) {
          final result = await _applyBatch(spec, fresh);
          applied += result.applied;
          kept += result.kept;
          skipped += result.skipped;
          unchanged += result.unchanged;
        }

        final last = _stampOf(page.last);
        if (last != null && (highest == null || last.isAfter(highest))) {
          highest = last;
        }
        if (page.length < batchSize) break;
        // A full page whose rows all share one stamp would ask for itself
        // forever. The ids above stop it re-applying anything, and this stops
        // it asking: one millisecond past the boundary, which is finer than the
        // clock any two of these rows were stamped by.
        after = last == null
            ? after
            : (fresh.isEmpty
                ? last.add(const Duration(milliseconds: 1))
                : last);
      }
    }

    // **After every table, not after every batch.** There is one cursor and the
    // tables are walked in turn, so advancing it while `set_logs` was still
    // unread would put the read past rows nothing had applied. Killed halfway,
    // the cursor has not moved and the whole pass is re-read — which costs
    // upserts that were idempotent anyway (§ 12 row 13).
    if (highest != null) await _advanceCursor(highest);

    // The same list a launch and a restore run, and deliberately the same list
    // rather than a third one written here. A pull is the one writer the local
    // CHECKs were added for: `healOrphanedSnapshots` is what answers § 12 row 8,
    // where one device deletes a workout the other was still adding sets to.
    //
    // **`seed: false`, and that is not an optimisation.** A pull that landed
    // only a bodyweight row onto a phone with no catalog would otherwise seed
    // one — 120 exercises under ids the account has never heard of, which is
    // the exact two-catalog split [§ 10](SYNC.md#10-adoption) exists to
    // prevent. Whether to seed is answered by the welcome screen and by
    // adoption, never by a batch of rows.
    if (applied > 0) await repairDatabase(_db, seed: false);

    return (
      applied: applied,
      kept: kept,
      skipped: skipped,
      unchanged: unchanged,
    );
  }

  /// One page, in one transaction.
  ///
  /// Read the batch and close, call the network holding nothing, write the
  /// result and close — the network call is the caller's, above, and nothing
  /// here awaits a socket ([§ 17](SYNC.md#17-the-architecture)).
  Future<PullReport> _applyBatch(
    TableSpec spec,
    List<Map<String, dynamic>> page,
  ) async {
    var applied = 0;
    var kept = 0;
    var skipped = 0;
    var unchanged = 0;

    await _db.transaction(() async {
      // `set_logs.parent_set_id` points into its own table, so a drop-set leg
      // can arrive ahead of its head inside one page. Deferring moves the
      // question to the commit, where the answer is known — the same line the
      // restore needs for the same reason.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');

      for (final wire in page) {
        final row = jsonRow(wire);
        try {
          switch (await _applyRow(spec, row)) {
            case _Outcome.applied:
              applied++;
            case _Outcome.keptLocal:
              kept++;
            case _Outcome.unchanged:
              unchanged++;
          }
        } on Object catch (error, stack) {
          // **One bad row never stops a restore** — § 15 rule 9. Named rather
          // than counted, because a row that cannot land is a row the user's
          // other phone believes is backed up.
          skipped++;
          reportFailure(
            error,
            stack,
            what: 'One ${_label(spec.name)} row from your account could not be '
                'saved on this phone.',
          );
        }
      }
    });

    return (
      applied: applied,
      kept: kept,
      skipped: skipped,
      unchanged: unchanged,
    );
  }

  Future<_Outcome> _applyRow(TableSpec spec, Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final local = await _localRow(spec, id);

    if (local != null) {
      // **This row is already here, and untouched since.** The cursor compares
      // `>=`, so the row stamped exactly on it arrives with every pull — and
      // writing it back would wake every stream on that table, which wakes the
      // engine, which pulls again. A phone that had finished syncing would
      // never stop.
      //
      // `updatedAt` and `deviceId` together identify a version: no local edit
      // can produce the same pair, because every one of them stamps both.
      if ((local['dirty'] as int? ?? 0) == 0 &&
          local['updated_at'] == row['updatedAt'] &&
          local['device_id'] == row['deviceId']) {
        return _Outcome.unchanged;
      }

      final verdict = resolveRow(
        localDirty: (local['dirty'] as int? ?? 0) == 1,
        local: _stampOfLocal(local),
        remote: (
          updatedAt: row['updatedAt'] as int,
          deviceId: row['deviceId'] as String,
        ),
      );
      // The local row is a newer unpushed edit. It stays dirty, and the push
      // that follows this pull is what tells the account about it.
      if (verdict == RowVerdict.keepLocal) return _Outcome.keptLocal;
    }

    // **A pulled row is not a local write.** It keeps the server's `updatedAt`
    // and the writing device's `deviceId`, and it lands settled — anything else
    // pushes every applied row straight back and the two phones trade the same
    // rows forever, each arrival reading as news.
    var resolved = {...row, 'dirty': false};

    // Unless resolving a collision changed it. Then this device holds a version
    // the account does not, and the only thing that can tell the account is the
    // dirty flag.
    resolved = await _resolveCollisions(spec, resolved, hadLocal: local != null);

    await _db.into(spec.table).insertOnConflictUpdate(spec.parse(resolved));
    return _Outcome.applied;
  }

  /// The row as it is on this phone, or null.
  ///
  /// Read as a raw map rather than a typed row: the applier is generic over the
  /// registry, and the three columns it needs — `dirty`, `updated_at`,
  /// `device_id` — are on every syncable table by definition.
  Future<Map<String, dynamic>?> _localRow(TableSpec spec, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM ${spec.name} WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Stamp _stampOfLocal(Map<String, dynamic> row) => (
        updatedAt: row['updated_at'] as int,
        deviceId: row['device_id'] as String,
      );

  Future<DateTime?> _cursor() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(lastPullKey)))
        .getSingleOrNull();
    final value = row?.value;
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> _advanceCursor(DateTime to) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: lastPullKey,
            value: to.toUtc().toIso8601String(),
          ),
        );
  }

  String _idOf(Map<String, dynamic> wire) => wire['id'] as String;

  DateTime? _stampOf(Map<String, dynamic> wire) {
    final value = wire[serverUpdatedAtColumn];
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  String _label(String table) => table.replaceAll('_', ' ');

  // ---------------------------------------------------------------------------
  // Collisions — SYNC.md § 9. Two *different* rows claiming one slot, which
  // last-write-wins cannot resolve because the conflict is not between two
  // versions of one row.
  //
  // Every resolution below writes through the same rule: **no merge may ever
  // delete logged work.** Re-slot, re-flag or re-number. The deciding is in
  // `domain/sync_merge.dart` and tested there; what is here is the scope query
  // and the write.
  // ---------------------------------------------------------------------------

  /// A pulled row this device had to change, stamped as **its own write**.
  ///
  /// The counterpart to [SYNC.md § 17](SYNC.md#17-the-architecture)'s rule that
  /// a pulled row is never re-stamped: a row that arrived and was then re-slotted
  /// is no longer the account's row, it is a version only this phone holds. It
  /// therefore takes this phone's `deviceId`, a fresh `updatedAt` and `dirty`.
  ///
  /// **The stamp is not decoration.** `updatedAt` and `deviceId` together are
  /// what identify a version, and the applier skips a row whose pair already
  /// matches locally. Keeping the server's pair on a row whose values had
  /// changed made two different rows indistinguishable, and the second one was
  /// silently never applied — the other phone tombstoned a duplicate bodyweight
  /// and this one went on showing it, with each device sure it agreed with the
  /// other.
  Map<String, dynamic> _ours(
    Map<String, dynamic> row,
    Map<String, dynamic> changes,
  ) =>
      {
        ...row,
        ...changes,
        'updatedAt': nowMs(),
        'deviceId': currentDeviceId,
        'dirty': true,
      };

  Future<Map<String, dynamic>> _resolveCollisions(
    TableSpec spec,
    Map<String, dynamic> row, {
    required bool hadLocal,
  }) async {
    // A tombstone claims nothing. Every unique index in § 9 is partial on
    // `deleted_at IS NULL`, so a deleted row stands on no slot at all.
    if (row['deletedAt'] != null) return row;

    return switch (spec.name) {
      'sessions' => await _resolveSession(row),
      'session_exercises' => await _resolvePosition(
          row,
          table: 'session_exercises',
          parent: 'session_id',
          position: 'order_index',
          key: 'orderIndex',
        ),
      'workout_exercises' => await _resolvePosition(
          row,
          table: 'workout_exercises',
          parent: 'workout_id',
          position: 'order_index',
          key: 'orderIndex',
        ),
      'set_logs' => await _resolvePosition(
          row,
          table: 'set_logs',
          parent: 'workout_exercise_id',
          position: 'set_index',
          key: 'setIndex',
        ),
      'regimes' => await _resolveRegime(row),
      'cycles' => await _resolveCycle(row),
      'workouts' => await _resolveWorkout(row),
      'bodyweight_logs' => await _resolveBodyweight(row),
      _ => row,
    };
  }

  /// Two rows appending to one parent both computed `max + 1`.
  ///
  /// The commonest collision there is, and four of § 9's indexes are this one
  /// rule. Both live: the row created later — the greater id, since ids are
  /// UUID v7 — takes the next free position, which is the same slot a thumb
  /// appending right then would have been given.
  Future<Map<String, dynamic>> _resolvePosition(
    Map<String, dynamic> row, {
    required String table,
    required String parent,
    required String position,
    required String key,
  }) async {
    final id = row['id'] as String;
    final parentId = row[jsonKeyOf(parent)];
    final scope = await _db
        .customSelect(
          'SELECT id, $position AS pos FROM $table '
          'WHERE $parent = ? AND deleted_at IS NULL AND id != ?',
          variables: [Variable<String>(parentId as String), Variable<String>(id)],
        )
        .get();

    final wanted = row[key] as int;
    final occupant = scope.where((r) => r.read<int>('pos') == wanted).toList();
    if (occupant.isEmpty) return row;

    final occupantId = occupant.first.read<String>('id');
    final move = resolveSlot(
      incomingId: id,
      occupantId: occupantId,
      liveIndexes: scope.map((r) => r.read<int>('pos')),
    );

    if (move.moveId == id) return _ours(row, {key: move.toIndex});

    await _restamp(table, occupantId, {position: move.toIndex});
    return row;
  }

  /// A day whose name a sibling already answers to, and a day that moved.
  Future<Map<String, dynamic>> _resolveSession(Map<String, dynamic> row) async {
    final positioned = await _resolvePosition(
      row,
      table: 'sessions',
      parent: 'regime_id',
      position: 'order_index',
      key: 'orderIndex',
    );

    final id = positioned['id'] as String;
    final siblings = await _db
        .customSelect(
          'SELECT id, name FROM sessions '
          'WHERE regime_id = ? AND deleted_at IS NULL AND id != ?',
          variables: [
            Variable<String>(positioned['regimeId'] as String),
            Variable<String>(id),
          ],
        )
        .get();

    final name = (positioned['name'] as String).trim();
    final taken = {
      for (final r in siblings) r.read<String>('name').trim().toLowerCase(),
    };
    if (!taken.contains(name.toLowerCase())) return positioned;

    final occupantId = siblings
        .firstWhere(
          (r) => r.read<String>('name').trim().toLowerCase() == name.toLowerCase(),
        )
        .read<String>('id');

    // The same ordering as a slot: the day created later is the one that gets
    // the suffix, and both devices agree which that is.
    if (id.compareTo(occupantId) > 0) {
      return _ours(positioned, {'name': disambiguateName(name, taken)});
    }
    await _restamp('sessions', occupantId, {
      'name': disambiguateName(name, {...taken, name.toLowerCase()}),
    });
    return positioned;
  }

  /// The flag is the conflict, not the row — and the hue is a slot like any
  /// other, except that there are only six and they can genuinely run out.
  Future<Map<String, dynamic>> _resolveRegime(Map<String, dynamic> row) async {
    var resolved = row;
    final id = row['id'] as String;

    if (resolved['isActive'] == true) {
      final active = await _db
          .customSelect(
            'SELECT id, updated_at, device_id FROM regimes '
            'WHERE is_active = 1 AND deleted_at IS NULL AND id != ?',
            variables: [Variable<String>(id)],
          )
          .get();
      if (active.isNotEmpty) {
        final other = active.first;
        final remoteWins = remoteKeepsActive(
          local: (
            updatedAt: other.read<int>('updated_at'),
            deviceId: other.read<String>('device_id'),
          ),
          remote: (
            updatedAt: resolved['updatedAt'] as int,
            deviceId: resolved['deviceId'] as String,
          ),
        );
        if (remoteWins) {
          // Both programmes survive; one of them is simply not the one being
          // trained.
          await _restamp('regimes', other.read<String>('id'), {'is_active': 0});
        } else {
          resolved = _ours(resolved, {'isActive': false});
        }
      }
    }

    final taken = await _db
        .customSelect(
          'SELECT id, identity_index FROM regimes '
          'WHERE deleted_at IS NULL AND id != ?',
          variables: [Variable<String>(id)],
        )
        .get();
    final wanted = resolved['identityIndex'] as int;
    final holder =
        taken.where((r) => r.read<int>('identity_index') == wanted).toList();
    if (holder.isEmpty) return resolved;

    final slots = {for (final r in taken) r.read<int>('identity_index')};
    final free = freeIdentitySlot(slots);

    if (free == null) {
      // Six live regimes already hold all six slots, and no re-slotting makes a
      // seventh fit — see [freeIdentitySlot]. It lands tombstoned rather than
      // being refused: the programme, and every session, workout and set under
      // it, still arrive.
      reportFailure(
        StateError('no free identity slot for regime $id'),
        StackTrace.current,
        what: 'A programme from your account could not fit on this phone — you '
            'already have $identitySlots.',
      );
      return _ours(resolved, {'deletedAt': nowMs()});
    }

    final holderId = holder.first.read<String>('id');
    if (id.compareTo(holderId) > 0) {
      return _ours(resolved, {'identityIndex': free});
    }
    await _restamp('regimes', holderId, {'identity_index': free});
    return resolved;
  }

  /// Two devices both advanced the cycle: two "cycle 7", and two open cycles.
  Future<Map<String, dynamic>> _resolveCycle(Map<String, dynamic> row) async {
    var resolved = row;
    final id = row['id'] as String;
    final regimeId = row['regimeId'] as String;

    final siblings = await _db
        .customSelect(
          'SELECT id, cycle_index, started_at, completed_at FROM cycles '
          'WHERE regime_id = ? AND deleted_at IS NULL AND id != ?',
          variables: [Variable<String>(regimeId), Variable<String>(id)],
        )
        .get();

    final wanted = resolved['cycleIndex'] as int;
    final sameNumber =
        siblings.where((r) => r.read<int>('cycle_index') == wanted).toList();
    if (sameNumber.isNotEmpty) {
      // Both are real cycles — the loser renumbers rather than disappearing.
      final free =
          freeCycleIndex(siblings.map((r) => r.read<int>('cycle_index')));
      final holderId = sameNumber.first.read<String>('id');
      if (id.compareTo(holderId) > 0) {
        resolved = _ours(resolved, {'cycleIndex': free});
      } else {
        await _restamp('cycles', holderId, {'cycle_index': free});
      }
    }

    if (resolved['completedAt'] != null) return resolved;
    final open =
        siblings.where((r) => r.read<int?>('completed_at') == null).toList();
    if (open.isEmpty) return resolved;

    // The same answer `healDuplicateOpenCycles` already writes: the newer stays
    // open, the older is completed.
    final other = open.first;
    final stays = staysOpen(
      a: (id: id, startedAt: resolved['startedAt'] as int),
      b: (
        id: other.read<String>('id'),
        startedAt: other.read<int>('started_at')
      ),
    );
    if (stays == id) {
      await _restamp('cycles', other.read<String>('id'), {
        'completed_at': nowMs(),
      });
      return resolved;
    }
    return _ours(resolved, {'completedAt': nowMs()});
  }

  /// Both phones had a session in progress. The older is **completed**, never
  /// discarded — its sets are real work.
  Future<Map<String, dynamic>> _resolveWorkout(Map<String, dynamic> row) async {
    if (row['status'] != WorkoutStatus.inProgress.name) return row;
    final id = row['id'] as String;

    final open = await _db
        .customSelect(
          "SELECT id, started_at FROM workouts "
          "WHERE status = 'inProgress' AND deleted_at IS NULL AND id != ?",
          variables: [Variable<String>(id)],
        )
        .get();
    if (open.isEmpty) return row;

    final other = open.first;
    final stays = staysOpen(
      a: (id: id, startedAt: row['startedAt'] as int),
      b: (
        id: other.read<String>('id'),
        startedAt: other.read<int>('started_at')
      ),
    );
    if (stays == id) {
      await _restamp('workouts', other.read<String>('id'), {
        'status': WorkoutStatus.completed.name,
        'ended_at': nowMs(),
      });
      return row;
    }
    return _ours(row, {
      'status': WorkoutStatus.completed.name,
      'endedAt': nowMs(),
    });
  }

  /// One person, one morning, one scale.
  Future<Map<String, dynamic>> _resolveBodyweight(
    Map<String, dynamic> row,
  ) async {
    final id = row['id'] as String;
    final sameDay = await _db
        .customSelect(
          'SELECT id, updated_at, device_id FROM bodyweight_logs '
          'WHERE day_key = ? AND deleted_at IS NULL AND id != ?',
          variables: [
            Variable<int>(row['dayKey'] as int),
            Variable<String>(id),
          ],
        )
        .get();
    if (sameDay.isEmpty) return row;

    final other = sameDay.first;
    final remoteWins = remoteWinsTheDay(
      local: (
        updatedAt: other.read<int>('updated_at'),
        deviceId: other.read<String>('device_id'),
      ),
      remote: (
        updatedAt: row['updatedAt'] as int,
        deviceId: row['deviceId'] as String,
      ),
    );

    if (remoteWins) {
      await _restamp('bodyweight_logs', other.read<String>('id'), {
        'deleted_at': nowMs(),
      });
      return row;
    }
    // There is no second slot to move a reading to, so the loser is tombstoned
    // rather than re-slotted — and a tombstone is still a row.
    return _ours(row, {'deletedAt': nowMs()});
  }

  /// The registry by name, for the one thing a raw statement cannot do.
  late final Map<String, TableSpec> _byName = {
    for (final spec in tableSpecs(_db)) spec.name: spec,
  };

  /// Writes a local row the merge had to move, **and stamps it**.
  ///
  /// The counterpart to everything above: a pulled row is not a local write and
  /// gets no stamp, but a row this device re-slotted *is* one. The account has
  /// never seen this version, and `dirty` is the only thing that can tell it.
  /// The other device computes the same resolution from the same values, so the
  /// two versions agree before either is sent.
  ///
  /// **`updates` names the table it wrote.** A `customUpdate` with an empty set
  /// changes rows and wakes nothing: every screen watching that table keeps
  /// showing the row where it used to be, until something else happens to write
  /// there. A merge is precisely the write nobody is looking at when it lands.
  Future<void> _restamp(
    String table,
    String id,
    Map<String, Object?> columns,
  ) async {
    final sets = [
      ...columns.keys.map((c) => '$c = ?'),
      'updated_at = ?',
      'device_id = ?',
      'dirty = 1',
    ].join(', ');
    await _db.customUpdate(
      'UPDATE $table SET $sets WHERE id = ?',
      variables: [
        for (final value in columns.values) Variable(value),
        Variable<int>(nowMs()),
        Variable<String>(currentDeviceId),
        Variable<String>(id),
      ],
      updates: {_byName[table]!.table},
    );
  }
}

enum _Outcome { applied, keptLocal, unchanged }
