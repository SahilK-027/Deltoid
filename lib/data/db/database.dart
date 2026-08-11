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

  /// One, and it stays one until the app is in someone's hands.
  ///
  /// This carried a v2..v8 ladder of upgrade steps, each one migrating a
  /// database shape that only ever existed on a test device. Nothing has been
  /// released, so nothing out there is at any of those versions: the steps were
  /// upgrade paths from states no install will ever be in, and every schema
  /// change since would have had to keep working forever to serve them.
  ///
  /// The ladder starts again — properly, one step per released change — the
  /// day a build reaches a phone that is not ours. Until then a schema change
  /// is an edit to `tables.dart`, a regenerate, and a reinstall.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
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
