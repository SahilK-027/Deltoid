import 'database.dart';
import 'table_spec.dart';

/// One judge of the whole database, callable after any mutation.
///
/// The structural rules were all asserted somewhere before this file existed —
/// four tombstone counts and a live-cycle count inside one test's private
/// helper, the unique positions and the single-open rows as partial indexes,
/// `day_key` against `started_at` as a CHECK. What did not exist was a single
/// thing that could be *called*, and that is the whole difference: a fuzz
/// harness cannot run "the index would have refused it" after every operation,
/// and neither can a restore, a heal, or any path that writes rows the schema
/// did not vet.
///
/// So every rule here is re-derived in SQL rather than delegated to the
/// constraint that normally enforces it. That is deliberate duplication. A
/// partial index only refuses statements it sees; it says nothing about a file
/// that arrived already wrong — a restore of an export written by an older
/// build, a heal that ran with the index stood down, and after SYNC.md a row
/// another device pushed. The oracle is the opinion that survives all three.
///
/// It reads and never writes. Every query is a `COUNT(*)` of rows that must not
/// exist, so a violation is reported as a number and a name rather than as an
/// exception from four layers down.
///
/// **The model is not in here.** This asserts what must be true of *any*
/// database, whatever operations produced it. What a specific sequence of
/// operations should have produced is the fuzz harness's own oracle, and mixing
/// the two would make this file a second copy of the repository.
///
/// **In `lib/` rather than in `test/`, because the three writers named above
/// all ship.** A rule that only runs in CI judges the databases the tests
/// build and never the one on the phone; the restore and the pull applier call
/// it now, which is the only reason any of this is worth writing twice.

/// A rule that was broken, named so a failure says which one.
class InvariantViolation {
  InvariantViolation(this.rule, this.count, this.detail);

  /// Short name of the rule, as a sentence about the data.
  final String rule;

  /// How many rows break it.
  final int count;

  /// One offending row, for the failure message. Null when the count query
  /// carries nothing worth naming.
  final String? detail;

  @override
  String toString() =>
      '$rule — $count row(s)${detail == null ? '' : ' (e.g. $detail)'}';
}

/// Every structural rule, as SQL that returns the rows breaking it.
///
/// Each entry is `name` -> a query selecting offending rows with a `detail`
/// column. Nothing here filters by regime or workout: the oracle judges the
/// database, not a scope.
const _rules = <String, String>{
  // ── Tombstone cascade ─────────────────────────────────────────────────
  //
  // A tombstoned row takes the rows that only exist to *describe* it, and
  // never the rows that *record what was done*. `session_exercises` describe a
  // session; `workouts` record training under it, and a deleted programme
  // keeps its history — which is why `workouts` under a dead `regimes` is
  // absent from this list by design rather than by omission.
  'live sets under a dead slot': '''
    SELECT s.id AS detail FROM set_logs s
    JOIN workout_exercises we ON we.id = s.workout_exercise_id
    WHERE s.deleted_at IS NULL AND we.deleted_at IS NOT NULL
  ''',
  'live snapshots under a dead workout': '''
    SELECT we.id AS detail FROM workout_exercises we
    JOIN workouts w ON w.id = we.workout_id
    WHERE we.deleted_at IS NULL AND w.deleted_at IS NOT NULL
  ''',
  'live slots under a dead session': '''
    SELECT se.id AS detail FROM session_exercises se
    JOIN sessions ss ON ss.id = se.session_id
    WHERE se.deleted_at IS NULL AND ss.deleted_at IS NOT NULL
  ''',
  'live cycles under a dead regime': '''
    SELECT c.id AS detail FROM cycles c
    JOIN regimes r ON r.id = c.regime_id
    WHERE c.deleted_at IS NULL AND r.deleted_at IS NOT NULL
  ''',
  // The qualifier is load-bearing. `deleteRegime` tombstones its cycles and
  // keeps its workouts, so every deleted programme leaves live workouts naming
  // dead cycles on purpose. Under a *live* regime there is no such licence:
  // the cycle is the counter the deload is scheduled off.
  'live workouts naming a dead cycle': '''
    SELECT w.id AS detail FROM workouts w
    JOIN cycles c ON c.id = w.cycle_id
    JOIN regimes r ON r.id = c.regime_id
    WHERE w.deleted_at IS NULL AND c.deleted_at IS NOT NULL
      AND r.deleted_at IS NULL
  ''',

  // ── One position, one live row ────────────────────────────────────────
  //
  // Deletes are tombstones and nothing renumbers behind them, so any "append
  // at the live count" lands on a position a surviving row still holds. Two
  // rows on one index leaves the order to whichever way SQLite breaks the tie
  // — and on the log screen that is which page a swipe arrives at.
  'two live sessions share a position': '''
    SELECT regime_id || '#' || order_index AS detail FROM sessions
    WHERE deleted_at IS NULL
    GROUP BY regime_id, order_index HAVING COUNT(*) > 1
  ''',
  'two live session slots share a position': '''
    SELECT session_id || '#' || order_index AS detail FROM session_exercises
    WHERE deleted_at IS NULL
    GROUP BY session_id, order_index HAVING COUNT(*) > 1
  ''',
  'two live workout slots share a position': '''
    SELECT workout_id || '#' || order_index AS detail FROM workout_exercises
    WHERE deleted_at IS NULL
    GROUP BY workout_id, order_index HAVING COUNT(*) > 1
  ''',
  'two live sets share a position': '''
    SELECT workout_exercise_id || '#' || set_index AS detail FROM set_logs
    WHERE deleted_at IS NULL
    GROUP BY workout_exercise_id, set_index HAVING COUNT(*) > 1
  ''',

  // ── One live row where only one may exist ─────────────────────────────
  'a regime holds two open cycles': '''
    SELECT regime_id AS detail FROM cycles
    WHERE completed_at IS NULL AND deleted_at IS NULL
    GROUP BY regime_id HAVING COUNT(*) > 1
  ''',
  // Global, not per regime: `openWorkout` returns the newest, so a second one
  // anywhere makes the older unreachable while still carrying its sets.
  'two workouts are in progress at once': '''
    SELECT id AS detail FROM workouts
    WHERE status = 'inProgress' AND deleted_at IS NULL
      AND (SELECT COUNT(*) FROM workouts
           WHERE status = 'inProgress' AND deleted_at IS NULL) > 1
  ''',
  'two regimes are active at once': '''
    SELECT id AS detail FROM regimes
    WHERE is_active = 1 AND deleted_at IS NULL
      AND (SELECT COUNT(*) FROM regimes
           WHERE is_active = 1 AND deleted_at IS NULL) > 1
  ''',
  'two live regimes wear one identity': '''
    SELECT CAST(identity_index AS TEXT) AS detail FROM regimes
    WHERE deleted_at IS NULL
    GROUP BY identity_index HAVING COUNT(*) > 1
  ''',
  'two live cycles share an index': '''
    SELECT regime_id || '#' || cycle_index AS detail FROM cycles
    WHERE deleted_at IS NULL
    GROUP BY regime_id, cycle_index HAVING COUNT(*) > 1
  ''',
  'a day carries two bodyweights': '''
    SELECT CAST(day_key AS TEXT) AS detail FROM bodyweight_logs
    WHERE deleted_at IS NULL
    GROUP BY day_key HAVING COUNT(*) > 1
  ''',

  // ── A session is logged on one day ────────────────────────────────────
  //
  // `day_key` is what the heatmap groups on and `started_at` is what History
  // pages by. A row where they disagree is ringed on Tuesday, filed under
  // Monday, and reliably reachable from neither. The arithmetic is the CHECK's
  // own, in seconds, because SQLite truncates toward zero.
  'a workout claims two different days': '''
    SELECT id AS detail FROM workouts
    WHERE day_key <> CAST(strftime(
      '%Y%m%d', started_at / 1000 + tz_offset_minutes * 60, 'unixepoch'
    ) AS INTEGER)
  ''',
};

/// How far ahead of this phone's clock a row may be stamped before it is
/// treated as wrong rather than merely early.
///
/// It cannot be zero, and not only for network skew. `nowMs` is clamped to a
/// mark that `AppDatabase` leases five minutes past the clock at every open, so
/// a row written seconds after a launch is legitimately in the future. Rows
/// from another device add whatever the two clocks disagree by.
///
/// A day is far past both and still far short of the failure this is for, which
/// is not a minute of drift but a phone that stamped the year 2099 — after a
/// flat battery, a manual change, a hand-edited file. That row wins every
/// conflict it is ever part of, against every device, until real time catches
/// up with it, and `resolveRow` never revisits a verdict. Nothing in the app
/// could see it before this rule existed.
const stampSkewToleranceMs = 24 * 60 * 60 * 1000;

/// The rules about the five columns `SyncColumns` adds, one name each.
///
/// Written as constants because [invariantRuleNames] has to answer without a
/// database, and the SQL behind them cannot: it is one `UNION ALL` per syncable
/// table, built from `tableSpecs` so a table added later is judged without
/// anyone remembering to add it here.
const stampAtOrBeforeEpoch = 'a row is stamped at or before the epoch';
const stampBeyondAnyClock =
    'a row is stamped further ahead than any clock explains';
const rowNamesNoDevice = 'a row names no device';

/// The sync-column rules, as SQL over every table that carries those columns.
///
/// **These are about the columns a merge decides on, and nothing else looks at
/// them.** The structural rules above judge shapes the app's own writers could
/// produce; `updated_at` and `device_id` are only ever compared — by
/// `resolveRow`, on a phone that has no way to say the number it is reading is
/// absurd. A schema CHECK cannot help: `updated_at > 0` would refuse a row from
/// a build that wrote zero, and "not absurdly in the future" is a question
/// about now, which a CHECK is not allowed to ask.
Map<String, String> _syncRules(AppDatabase db) {
  final tables = [
    for (final spec in tableSpecs(db))
      if (spec.syncs) spec.name,
  ];

  String union(String predicate) => [
        for (final table in tables)
          "SELECT '$table#' || id AS detail FROM $table WHERE $predicate",
      ].join(' UNION ALL ');

  return {
    // Zero is what a column with no default holds, and a row stamped at zero
    // loses every conflict it is ever in — including against the version it was
    // written to replace.
    stampAtOrBeforeEpoch: union('updated_at <= 0'),
    stampBeyondAnyClock: union(
      "updated_at > CAST(strftime('%s', 'now') AS INTEGER) * 1000 "
      '+ $stampSkewToleranceMs',
    ),
    // The tie-break `resolveRow` falls to when two devices stamp one
    // millisecond. Empty on both sides compares equal, so each device keeps its
    // own copy and neither ever learns the other has one — the exact split
    // sync exists to prevent, and silent.
    rowNamesNoDevice: union("device_id = ''"),
  };
}

/// The rules a repair can put right, and which repair does it.
///
/// **Not a lesser class of wrong.** Every rule here describes a database the
/// app should never be in; the difference is only whether `repairDatabase`
/// knows a move that fixes it without asking. That distinction is what lets a
/// restore refuse a file whole instead of clearing every table and then
/// discovering it cannot put anything back — see the two checks in
/// `backup_service.dart`.
///
/// A backup file really does carry these. `healOrphanedSnapshots` exists
/// because discarding a session used to tombstone the workout and leave its
/// snapshots alive underneath, and a tombstone is a column rather than a
/// foreign key, so nothing in the schema refuses one on the way in. Refusing
/// those files would be refusing histories the app has always been able to
/// straighten out on the next launch.
const healableInvariants = <String, String>{
  'live sets under a dead slot': 'healOrphanedSnapshots',
  'live snapshots under a dead workout': 'healOrphanedSnapshots',
  'live cycles under a dead regime': 'healCyclesUnderDeadRegimes',
  'live workouts naming a dead cycle': 'healWorkoutsNamingDeadCycles',
  'a regime holds two open cycles': 'healDuplicateOpenCycles',
};

/// The rules that are real but must never cost a history.
///
/// A restore refuses a file it cannot put back. These are the faults where
/// refusing costs more than the fault does: a backup whose rows were stamped by
/// a phone with a broken clock is still that person's entire training log, and
/// handing it back is worth more than the merges it may go on to win. No repair
/// fixes them either — clamping a stamp down to now is a defensible move and it
/// is not one to make silently, inside a restore, on rows the user has not been
/// told about.
///
/// So they are reported wherever they are found and refuse nothing. Everything
/// that reads this list should say why in the same breath.
const advisoryInvariants = <String>{
  stampAtOrBeforeEpoch,
  stampBeyondAnyClock,
  rowNamesNoDevice,
};

/// The rules worth refusing a file over: what no repair fixes and what is not
/// merely advice.
Set<String> get unhealableInvariantNames => _ruleNames
    .difference(healableInvariants.keys.toSet())
    .difference(advisoryInvariants);

Set<String> get _ruleNames => {..._rules.keys, ...advisoryInvariants};

/// Every rule broken by the current contents of [db], empty when it is sound.
///
/// Returns rather than throws, so a caller can decide whether a violation is a
/// failure or the thing it is asserting — the tests that build a broken state
/// on purpose need the list, not an exception.
///
/// [only] narrows to a named subset, for the caller that has to decide before
/// the repairs have run.
Future<List<InvariantViolation>> invariantViolations(
  AppDatabase db, {
  Set<String>? only,
}) async {
  final found = <InvariantViolation>[];
  for (final entry in {..._rules, ..._syncRules(db)}.entries) {
    if (only != null && !only.contains(entry.key)) continue;
    final rows = await db.customSelect(entry.value).get();
    if (rows.isNotEmpty) {
      found.add(InvariantViolation(
        entry.key,
        rows.length,
        rows.first.read<String?>('detail'),
      ));
    }
  }
  return found;
}

/// The rule names, for a test that wants to assert the oracle covers something.
Iterable<String> get invariantRuleNames => _ruleNames;
