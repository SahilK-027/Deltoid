import 'package:deltoid/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Every rule broken by the current contents of [db], empty when it is sound.
///
/// Returns rather than throws, so a caller can decide whether a violation is a
/// failure or the thing it is asserting — the tests that build a broken state
/// on purpose need the list, not an exception.
Future<List<InvariantViolation>> invariantViolations(AppDatabase db) async {
  final found = <InvariantViolation>[];
  for (final entry in _rules.entries) {
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

/// Fails the test if anything in [db] breaks a structural rule.
///
/// [after] names what was just done, so a failure in a long sequence says which
/// operation left the database wrong rather than only that it is.
Future<void> expectInvariants(AppDatabase db, {String? after}) async {
  final found = await invariantViolations(db);
  expect(
    found,
    isEmpty,
    reason: [
      if (after != null) 'after $after:',
      for (final v in found) '  $v',
    ].join('\n'),
  );
}

/// The rule names, for a test that wants to assert the oracle covers something.
Iterable<String> get invariantRuleNames => _rules.keys;
