import 'dart:math' as math;

import '../db/database.dart';
import '../db/table_spec.dart';
import '../db/watch.dart';
import 'push.dart';

/// Which of [SYNC.md § 2](SYNC.md#2-the-three-states)'s three this install is
/// in.
///
/// There is no state representing synchronisation in progress. A progress
/// indicator on a background job
/// nobody is waiting for is a spinner that teaches the user to wait — so this
/// is derived from what is on disk and nothing keeps it in step, because there
/// is no second copy of the answer.
enum SyncStatus {
  /// Never connected, or declined at first launch.
  local,

  /// Signed in, nothing owed.
  synced,

  /// Signed in, rows owed — offline, or a push that failed.
  ///
  /// A normal state rather than an error. A session logged without network
  /// access is pending
  /// for an hour and that is the design working. The only thing that makes it
  /// worth mentioning is how long it has been true.
  pending,
}

/// The state, and the two numbers a screen needs to say more than its name.
class SyncState {
  const SyncState({
    required this.status,
    required this.owed,
    required this.lastPushAt,
    this.owedSince,
  });

  /// What a build with no configuration, or a phone that declined, is in.
  static const local = SyncState(
    status: SyncStatus.local,
    owed: 0,
    lastPushAt: null,
  );

  final SyncStatus status;

  /// Rows this device still owes the server. Zero unless [status] is
  /// [SyncStatus.pending].
  final int owed;

  /// When the last drain finished, or null if none has on this install.
  final DateTime? lastPushAt;

  /// When the oldest thing still owed was written, or null when nothing is.
  ///
  /// The complete answer to how long ([SYNC.md § 2](SYNC.md#2-the-three-states)).
  /// Pending is normal — a session logged in a basement gym is pending for an
  /// hour and that is the design working — and the only thing that makes it
  /// worth mentioning is how long it has been true. A screen that says *3
  /// changes waiting* says nothing; one that says *since Tuesday* says
  /// something has gone wrong.
  final DateTime? owedSince;
}

/// What is on disk, watched: how much is owed and when the last push landed.
///
/// Through [WatchTables.watchQuery] rather than a watched `customSelect`. The
/// question sync wants is *is anything owed*, which is exactly the shape that
/// tempts a `customSelect('SELECT 1', readsFrom: …)` sentinel — and that fires
/// once and then goes silent forever, with no error anywhere
/// ([SYNC.md § 19](SYNC.md#19-traps)).
Stream<SyncState> watchSyncState(AppDatabase db, {required bool signedIn}) {
  final specs = tableSpecs(db).where((s) => s.syncs).toList();
  if (!signedIn) {
    // Still watched rather than a single value: the account can be signed into
    // from Settings without this stream being rebuilt from scratch, and a
    // stream that ends would leave the row it feeds frozen.
    return Stream.value(SyncState.local);
  }

  final owedSql = specs
      .map((s) => '(SELECT COUNT(*) FROM ${s.name} WHERE dirty = 1)')
      .join(' + ');
  // MIN over MINs: each inner one rides the same partial index the count does,
  // so the oldest thing owed costs no more than counting it.
  final oldestSql = specs
      .map((s) => 'SELECT MIN(updated_at) AS t FROM ${s.name} WHERE dirty = 1')
      .join(' UNION ALL ');

  return db.watchQuery(
    [...specs.map((s) => s.table), db.appSettings],
    () async {
      // One statement over nine partial indexes, each of them empty whenever
      // that table owes nothing — so the common answer costs nine index probes
      // rather than a scan of 168k set logs, on a query re-run every time a set
      // is ticked.
      final counted = await db
          .customSelect(
            'SELECT $owedSql AS owed, '
            '(SELECT MIN(t) FROM ($oldestSql)) AS oldest',
          )
          .getSingle();
      final owed = counted.read<int>('owed');
      final oldest = counted.read<int?>('oldest');

      final stamp = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(lastPushKey)))
          .getSingleOrNull();
      final lastPushAt = switch (int.tryParse(stamp?.value ?? '')) {
        final ms? => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        _ => null,
      };

      return SyncState(
        status: owed == 0 ? SyncStatus.synced : SyncStatus.pending,
        owed: owed,
        lastPushAt: lastPushAt,
        owedSince:
            oldest == null ? null : DateTime.fromMillisecondsSinceEpoch(oldest),
      );
    },
  );
}

/// One line of *on this phone only*: a logged session, the bodyweight log, or
/// the programme, with how many of its rows the account has not received.
class WaitingItem {
  const WaitingItem.session({
    required String this.workoutId,
    required this.sessionName,
    required int this.dayKey,
    required this.inProgress,
    required this.count,
  }) : kind = WaitingKind.session;

  const WaitingItem.bodyweight(this.count)
      : kind = WaitingKind.bodyweight,
        workoutId = null,
        sessionName = null,
        dayKey = null,
        inProgress = false;

  /// Sessions discarded or deleted on this phone whose removal the account
  /// has not heard about yet. One line for all of them, counted in sessions:
  /// listed by name beside the session being logged, a discarded `Push 1 ·
  /// today` read as the same session twice.
  const WaitingItem.removed(this.count)
      : kind = WaitingKind.removed,
        workoutId = null,
        sessionName = null,
        dayKey = null,
        inProgress = false;

  const WaitingItem.programme(this.count)
      : kind = WaitingKind.programme,
        workoutId = null,
        sessionName = null,
        dayKey = null,
        inProgress = false;

  final WaitingKind kind;
  final String? workoutId;

  /// The training day's name, or null for a workout logged outside one.
  final String? sessionName;
  final int? dayKey;
  final bool inProgress;

  /// Sets for a session — or 1 when only the session's own details changed —
  /// entries for bodyweight, and rows for the programme. The header's badge is
  /// the sum, so it counts the same things the sheet lists.
  final int count;
}

enum WaitingKind { session, removed, bodyweight, programme }

/// The most recent finished session the account holds in full.
class BackedUpSession {
  const BackedUpSession({required this.sessionName, required this.dayKey});

  final String? sessionName;
  final int dayKey;
}

/// What *on this phone only* and *newest session on your account* are made of.
class OwedSummary {
  const OwedSummary({required this.waiting, required this.last});

  static const empty = OwedSummary(waiting: [], last: null);

  final List<WaitingItem> waiting;
  final BackedUpSession? last;

  /// The badge: the counts of every line added up.
  int get count => waiting.fold(0, (sum, item) => sum + item.count);
}

/// What the account has not received yet, grouped the way the app talks about
/// training rather than the way the database stores it.
///
/// A set, the exercise it sits in and the workout around it are three tables
/// and one thing to a person, so every dirty row under a workout is folded into
/// that workout's line, counted by its sets. Everything that is neither a
/// logged session nor bodyweight — exercises, regimes, days, planned exercises,
/// cycles — is the programme. Each part starts from `dirty = 1`, which the
/// partial indexes answer without a scan, so this is cheap to re-run on every
/// write, the same bet [watchSyncState] makes.
Stream<OwedSummary> watchOwedSummary(AppDatabase db) {
  final specs = tableSpecs(db).where((s) => s.syncs).toList();
  const programmeTables = [
    'exercises',
    'regimes',
    'sessions',
    'session_exercises',
    'cycles',
  ];
  final programmeSql = programmeTables
      .map((t) => '(SELECT COUNT(*) FROM $t WHERE dirty = 1)')
      .join(' + ');

  return db.watchQuery([...specs.map((s) => s.table)], () async {
    final sessions = await db.customSelect('''
      WITH owed(workout_id, sets) AS (
        SELECT we.workout_id, 1 FROM set_logs sl
          JOIN workout_exercises we ON we.id = sl.workout_exercise_id
          WHERE sl.dirty = 1
        UNION ALL
        SELECT workout_id, 0 FROM workout_exercises WHERE dirty = 1
        UNION ALL
        SELECT id, 0 FROM workouts WHERE dirty = 1
      )
      SELECT w.id, w.day_key, w.status, w.deleted_at, s.name AS session_name,
             SUM(owed.sets) AS sets
        FROM owed
        JOIN workouts w ON w.id = owed.workout_id
        LEFT JOIN sessions s ON s.id = w.session_id
        GROUP BY w.id
        ORDER BY w.started_at DESC
    ''').get();

    final others = await db.customSelect(
      'SELECT (SELECT COUNT(*) FROM bodyweight_logs WHERE dirty = 1) AS bw, '
      '($programmeSql) AS programme',
    ).getSingle();

    // The newest finished session with nothing of it still owed.
    final last = await db.customSelect('''
      SELECT w.day_key, s.name AS session_name
        FROM workouts w
        LEFT JOIN sessions s ON s.id = w.session_id
        WHERE w.status = 'completed' AND w.deleted_at IS NULL
          AND w.dirty = 0
          AND NOT EXISTS (
            SELECT 1 FROM workout_exercises we
              WHERE we.workout_id = w.id AND we.dirty = 1)
          AND NOT EXISTS (
            SELECT 1 FROM set_logs sl
              JOIN workout_exercises we ON we.id = sl.workout_exercise_id
              WHERE we.workout_id = w.id AND sl.dirty = 1)
        ORDER BY w.started_at DESC
        LIMIT 1
    ''').getSingleOrNull();

    final bodyweight = others.read<int>('bw');
    final programme = others.read<int>('programme');
    // A tombstone and everything under it is one removal, not a session.
    final live = [
      for (final row in sessions)
        if (row.read<int?>('deleted_at') == null) row,
    ];
    final removed = sessions.length - live.length;
    return OwedSummary(
      waiting: [
        for (final row in live)
          WaitingItem.session(
            workoutId: row.read<String>('id'),
            sessionName: row.read<String?>('session_name'),
            dayKey: row.read<int>('day_key'),
            inProgress: row.read<String>('status') == 'inProgress',
            count: math.max(1, row.read<int>('sets')),
          ),
        if (removed > 0) WaitingItem.removed(removed),
        if (bodyweight > 0) WaitingItem.bodyweight(bodyweight),
        if (programme > 0) WaitingItem.programme(programme),
      ],
      last: last == null
          ? null
          : BackedUpSession(
              sessionName: last.read<String?>('session_name'),
              dayKey: last.read<int>('day_key'),
            ),
    );
  });
}
