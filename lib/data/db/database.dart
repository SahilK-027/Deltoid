import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Referenced by the generated code: enum columns, clientDefault callbacks and
// the JSON list converter all resolve against this library's imports.
import '../../core/ids.dart';
import '../../domain/enums.dart';
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
  int get schemaVersion => 2;

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
        },
        beforeOpen: (details) async {
          // Tombstones and cascades depend on referential integrity being real.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _open() =>
      driftDatabase(name: 'deltoid', native: const DriftNativeOptions());
}
