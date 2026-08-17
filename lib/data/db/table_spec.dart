import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import 'database.dart';

/// One table, described once, for every path that reads or writes whole rows.
///
/// There are two such paths and there will not be a third: the backup codec,
/// which restores a file written by some other build, and the sync pull
/// applier, which applies a row written by some other build.
/// [SYNC.md § 14](SYNC.md#14-two-builds-one-account) says both must read a row
/// with one column more, or one fewer, than the reader knows — and **the way to
/// make that true is to share the code, not to remember the rule.** Two lists of
/// defaults that must agree forever will not.
///
/// So the half both need lives here: the table's name, the table itself, the
/// parser with its defaults spread underneath, and whether the table syncs at
/// all. `BackupService` keeps what is only a file's problem — its pager, its
/// counts, its `clear`, its whitelist — and builds its codecs from this list.
class TableSpec {
  const TableSpec({
    required this.name,
    required this.table,
    required this.parse,
    required this.syncs,
  });

  /// The SQL table name, which is also the wire format on both paths.
  final String name;

  /// The table itself, so a whole file can be written in batches rather than a
  /// row at a time.
  final TableInfo<Table, dynamic> table;

  /// JSON row → something `Batch.insertAll` can write.
  ///
  /// Explicit per table rather than a generic loop over `TableInfo`, because
  /// reconstructing a row from JSON needs the generated `fromJson` for its data
  /// class — the generic `map()` reads database rows, not serialised ones, and
  /// would quietly mangle enum and converter columns.
  ///
  /// **A column added after v1 gets its default spread under `row` here**, or a
  /// row written before that column existed dies on a null cast. The test in
  /// `test/data/table_spec_test.dart` walks every column of every table and
  /// asks each parser what it does with the column missing, so this is checked
  /// rather than remembered.
  final Insertable<dynamic> Function(Map<String, dynamic> row) parse;

  /// Whether this table's rows ever reach a server.
  ///
  /// Only `app_settings` says no, and it says no for good:
  /// [SYNC.md § 4](SYNC.md#4-what-the-server-holds). It holds `device_id`, the
  /// unit preference and the theme — which phone you are on and how that phone
  /// should look — and syncing `device_id` would break the tie-break it exists
  /// for.
  final bool syncs;
}

/// Every table, parents before children.
///
/// The order is load-bearing on both paths: a restore inserts down this list
/// and clears back up it, and a push walks it forwards so foreign keys hold
/// server-side at every intermediate point.
List<TableSpec> tableSpecs(AppDatabase db) => [
      // Points at nothing and nothing points at it, so it may sit anywhere;
      // first because it is the smallest and a restore that fails on it should
      // fail before it has written a decade of sets.
      TableSpec(
        name: 'app_settings',
        table: db.appSettings,
        parse: AppSetting.fromJson,
        syncs: false,
      ),
      TableSpec(
        name: 'exercises',
        table: db.exercises,
        // `fromJson` is generated against *today's* columns and reads every one
        // of them unconditionally, so a row written before a column existed
        // dies on a null cast — with the user's only copy of their history in
        // the picker.
        parse: (row) => Exercise.fromJson({
          'barKind': BarKind.none.name,
          'measureMode': MeasureMode.reps.name,
          ...row,
        }),
        syncs: true,
      ),
      TableSpec(
        name: 'regimes',
        table: db.regimes,
        // A file written before v5 has no identity slot in it, and
        // `Regime.fromJson` casts the missing key straight to int. Everything
        // lands on 0 here and the slots are dealt out properly once the restore
        // is written — see the backfill at the end of `BackupService.restore`.
        parse: (row) => Regime.fromJson({'identityIndex': 0, ...row}),
        syncs: true,
      ),
      TableSpec(
        name: 'sessions',
        table: db.sessions,
        parse: Session.fromJson,
        syncs: true,
      ),
      TableSpec(
        name: 'session_exercises',
        table: db.sessionExercises,
        parse: SessionExercise.fromJson,
        syncs: true,
      ),
      TableSpec(
        name: 'cycles',
        table: db.cycles,
        parse: Cycle.fromJson,
        syncs: true,
      ),
      TableSpec(
        name: 'workouts',
        table: db.workouts,
        // A row written before the zone offset existed has no key for it, and
        // it cannot land without one — see [impliedTzOffset].
        parse: (row) => Workout.fromJson({
          'tzOffsetMinutes':
              impliedTzOffset(row['startedAt'] as int, row['dayKey'] as int),
          ...row,
        }),
        syncs: true,
      ),
      TableSpec(
        name: 'workout_exercises',
        table: db.workoutExercises,
        // A row written before the muscle snapshot existed has no key for it,
        // and null is the honest value: the row predates the column, so readers
        // fall back to the catalog rather than being told it was `other`.
        parse: (row) => WorkoutExercise.fromJson({'muscle': null, ...row}),
        syncs: true,
      ),
      TableSpec(
        name: 'set_logs',
        table: db.setLogs,
        // Partials arrived at v8. Nullable, so a row written before it simply
        // has no key here and every restored set reads as all-full — which is
        // what those sets meant when they were logged.
        parse: (row) => SetLog.fromJson({'partialReps': null, ...row}),
        syncs: true,
      ),
      TableSpec(
        name: 'bodyweight_logs',
        table: db.bodyweightLogs,
        parse: BodyweightLog.fromJson,
        syncs: true,
      ),
    ];

/// The zone offset a workout written before `tz_offset_minutes` existed implies.
///
/// The column arrived alongside the CHECK that ties `day_key` to `started_at`,
/// so a row without one cannot be inserted at all — and since nothing reads the
/// offset for its own sake, *any* value that reconciles the two columns the row
/// already carries is a correct one.
///
/// This phone's offset at that instant is the honest first guess, and for the
/// case that actually happens — a file written on this phone, in this zone — it
/// is not a guess at all but the very offset that produced the day key.
/// Restored after a move across zones it will not reconcile, and refusing the
/// whole file over a column the file predates would be the wrong answer, so it
/// is nudged by the fewest whole minutes that put the instant back on the day
/// the row names.
///
/// A row the two columns of which no real offset can reconcile lands outside
/// the ±(12, 14) hours the CHECK allows and the restore refuses the file. That
/// is the right answer too: such a row was already claiming two days.
int impliedTzOffset(int startedAt, int dayKey) {
  const minute = Duration.millisecondsPerMinute;
  const day = Duration.millisecondsPerDay;

  final device =
      DateTime.fromMillisecondsSinceEpoch(startedAt).timeZoneOffset.inMinutes;
  // Wall clock as an instant: the day key read as if it were UTC, which is the
  // same arithmetic the CHECK does.
  final dayStart =
      DateTime.utc(dayKey ~/ 10000, (dayKey ~/ 100) % 100, dayKey % 100)
          .millisecondsSinceEpoch;
  final local = startedAt + device * minute;

  if (local >= dayStart && local < dayStart + day) return device;
  if (local < dayStart) return device + ((dayStart - local) / minute).ceil();
  return device - ((local - dayStart - day) / minute).floor() - 1;
}

/// A drift JSON key → the SQL column name drift gave it.
///
/// Drift derives a column's SQL name from its getter by exactly this rule, and
/// serialises the row under the *getter* name — so `updatedAt` on the wire is
/// `updated_at` in Postgres, and `tzOffsetMinutes` is `tz_offset_minutes`.
///
/// A pair of pure functions and a test that walks every column of every table
/// asserting the round trip, rather than ten hand-written maps. Ten maps are ten
/// chances to type a column into silence: a key that does not match any column
/// is not an error anywhere, it is a value that never arrives.
String columnNameOf(String jsonKey) => jsonKey.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m[0]!.toLowerCase()}',
    );

/// And back: `updated_at` → `updatedAt`, for a row read off the server.
String jsonKeyOf(String columnName) => columnName.replaceAllMapped(
      RegExp('_([a-z])'),
      (m) => m[1]!.toUpperCase(),
    );

/// A drift row's `toJson` → what PostgREST is handed.
///
/// Keys only. The values are already what the wire wants: drift serialises an
/// int column to an int, a bool to a bool, and a `JsonTypeConverter` column to
/// its *SQL* form — which is why `exercises.form_video_urls` is `text`
/// server-side and arrives as a string containing JSON rather than an array
/// ([SYNC.md § 17](SYNC.md#17-the-architecture)).
///
/// `user_id` is not added here. The server column defaults to `auth.uid()`, so
/// the one value a client must never be trusted to assert is one it never
/// sends; `server_updated_at` is stamped by a trigger for the same reason.
Map<String, dynamic> wireRow(Map<String, dynamic> json) => {
      for (final entry in json.entries) columnNameOf(entry.key): entry.value,
    };

/// And back, for a row read off the server.
///
/// The two columns the server adds are dropped: neither exists locally
/// ([SYNC.md § 4](SYNC.md#4-what-the-server-holds)), and drift's `fromJson`
/// ignores keys it does not know — but a pull reads `server_updated_at` for its
/// cursor before the row is parsed, and leaving it in the map invites a reader
/// to think the column landed somewhere.
Map<String, dynamic> jsonRow(Map<String, dynamic> wire) => {
      for (final entry in wire.entries)
        if (entry.key != 'user_id' && entry.key != serverUpdatedAtColumn)
          jsonKeyOf(entry.key): entry.value,
    };

/// The server's clock, and the only column name that exists at one end only.
const serverUpdatedAtColumn = 'server_updated_at';
