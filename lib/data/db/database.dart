import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Referenced by the generated code: enum columns, clientDefault callbacks and
// the JSON list converter all resolve against this library's imports.
import '../../core/ids.dart';
import '../../domain/enums.dart';
import '../seed/seeder.dart';
import 'converters.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Exercises,
    Regimes,
    Sessions,
    SessionExercises,
    Cycles,
    Workouts,
    WorkoutExercises,
    SetLogs,
    BodyweightLogs,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// In-memory instance for tests.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Adds a column only when it is not already there.
          //
          // `ALTER TABLE ... ADD COLUMN` on a column that exists is
          // `SqliteException(1): duplicate column name`, and the same is true
          // of a bare `CREATE INDEX` — which is how this app came out of a
          // launch with `index idx_bodyweight_day already exists` and no way
          // back in. A device that has run a *later* build of the schema and
          // then been given an earlier one arrives here with the structure in
          // place and the version stamp behind it, so every step below has to
          // survive being right twice.
          Future<void> addColumnIfMissing(
            TableInfo<Table, dynamic> table,
            GeneratedColumn<Object> column,
          ) async {
            final columns = await customSelect(
              'SELECT name FROM pragma_table_info(?)',
              variables: [Variable.withString(table.actualTableName)],
            ).get();
            final present = columns.any(
              (r) => r.read<String>('name') == column.name,
            );
            if (!present) await m.addColumn(table, column);
          }

          // v2: drop-set legs point at the set they dropped from, instead of
          // being inferred from sitting next to it.
          if (from < 2) {
            await addColumnIfMissing(setLogs, setLogs.parentSetId);
          }
          // v3: the bar a movement is loaded on.
          if (from < 3) {
            await addColumnIfMissing(exercises, exercises.barKind);
            // The column defaults to `none`, which is the honest answer for a
            // row nobody has been asked about — but this app seeded most of
            // this catalog and knows perfectly well what a back squat is
            // loaded on. Without this the upgrade lands with the plate view
            // switched off on all thirteen barbell movements.
            await backfillSeededBarKinds(this);
          }
          // v4: `standard` (a 10kg bar) was dropped in favour of `trap`, and the
          // EZ and women's bars were re-weighed against the ones actually in
          // the gym. The enum is stored as its *name*, so a row still saying
          // `standard` has no member to parse back into and throws on read —
          // the whole exercise table, not just that row. Nothing to preserve:
          // it says the movement is on a bar we no longer have a weight for,
          // and `none` is the answer that asks again rather than guessing.
          if (from < 4) {
            await customStatement(
              "UPDATE exercises SET bar_kind = 'none' "
              "WHERE bar_kind = 'standard'",
            );
          }
          // v5: a regime owns one of the identity hues instead of hashing its
          // id into the list. The column defaults to 0, which would put every
          // existing regime in orange, so hand them the slots in the order they
          // were created — oldest keeps the colour it is most likely to have
          // had, and nothing shares.
          if (from < 5) {
            await addColumnIfMissing(regimes, regimes.identityIndex);
            await backfillIdentityIndexes(this);
          }
          // v6: bodyweight is the one table with a row per *day* rather than
          // per session, so it is the one that reaches five figures on its own.
          // Every query the bodyweight screen makes is a range on the day, and
          // all of them were table scans.
          //
          // `IF NOT EXISTS`, for the reason given at the top of this block.
          if (from < 6) {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_bodyweight_day '
              'ON bodyweight_logs (day_key)',
            );
          }
          // v7: a set can be seconds held instead of reps. Additive and
          // defaulted to `reps`: nothing already logged changes meaning, and
          // an existing plank filed as reps stays a lie the user can correct
          // in one tap rather than one this migration guesses at.
          if (from < 7) {
            await addColumnIfMissing(exercises, exercises.measureMode);
            // Except the one row this app seeded and already knows the answer
            // for — the Plank has never been a count of reps.
            await backfillSeededMeasureModes(this);
          }
          // v8: reps that did not finish the range of motion, counted apart.
          // Nullable and read as "none", so every set already logged keeps
          // meaning exactly what it meant — there is nothing to backfill.
          if (from < 8) {
            await addColumnIfMissing(setLogs, setLogs.partialReps);
          }
        },
        beforeOpen: (details) async {
          // Tombstones and cascades depend on referential integrity being real.
          await customStatement('PRAGMA foreign_keys = ON');

          // Give the query planner statistics to plan with.
          //
          // Without them SQLite guesses how selective each table is, and on
          // this schema it guessed wrong in the one place it hurts most: the
          // weekly volume query — which re-runs *every time a set is ticked* —
          // was planned as `SCAN workout_exercises` over every snapshot row
          // ever written, to answer a question about the last seven days. Fifty
          // years of training made that 143ms of work per tick. With statistics
          // the planner starts from `idx_workouts_day` instead and the same
          // query is under a millisecond.
          //
          // `optimize` rather than `ANALYZE`: it only re-analyses tables whose
          // shape has actually moved, so it costs nothing on the launches where
          // nothing has changed and about 30ms on the one after a decade lands.
          // Every index it needed already existed — all that was missing was
          // the evidence to use them.
          await customStatement('PRAGMA optimize');
        },
      );

  static QueryExecutor _open() =>
      driftDatabase(name: 'deltoid', native: const DriftNativeOptions());
}
