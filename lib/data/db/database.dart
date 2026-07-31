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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v2: drop-set legs point at the set they dropped from, instead of
          // being inferred from sitting next to it.
          if (from < 2) {
            await m.addColumn(setLogs, setLogs.parentSetId);
          }
          // v3: the bar a movement is loaded on.
          if (from < 3) {
            await m.addColumn(exercises, exercises.barKind);
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
        },
        beforeOpen: (details) async {
          // Tombstones and cascades depend on referential integrity being real.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _open() =>
      driftDatabase(name: 'deltoid', native: const DriftNativeOptions());
}
