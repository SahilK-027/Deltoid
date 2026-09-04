import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Referenced by the generated code: enum columns, clientDefault callbacks and
// the JSON list converter all resolve against this library's imports.
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../domain/enums.dart';
import 'converters.dart';
import 'migrations.dart';
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

  /// The ladder is running again, one step per change from here on.
  ///
  /// It carried a v2..v8 ladder once, each step migrating a database shape that
  /// only ever existed on a test device, and that was thrown away with nothing
  /// released: those were upgrade paths from states no install would ever be in.
  ///
  /// It starts over at 2 because sync is what makes a reinstall an unacceptable
  /// upgrade path — see `migrations.dart`, and
  /// [RULES.md § 3](RULES.md#3-schema-and-migrations) for the protocol a change
  /// follows now.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) => upgradeSchema(this, m, from, to),
        beforeOpen: (details) async {
          // Tombstones and cascades depend on referential integrity being real.
          await customStatement('PRAGMA foreign_keys = ON');

          // Wait for the lock rather than failing on it.
          //
          // Zero — the default — is right for exactly one writer, which is
          // what a single connection on drift's background isolate gives us
          // today. A sync opening its own connection makes contention real,
          // and the failure mode of a zero timeout is an immediate
          // SQLITE_BUSY thrown at whichever screen happened to be writing.
          await customStatement('PRAGMA busy_timeout = 5000');

          // A reader and a writer at once, which is what sync makes ordinary.
          //
          // Under the `delete` journal the packaged sqlite3 defaults to, a
          // reader and a writer are serialised completely — so a push draining
          // `dirty` across a hundred thousand rows and a thumb ticking a set
          // take turns, and with the timeout above that turn is a screen
          // waiting on a background job for up to five seconds
          // ([SYNC.md § 16](SYNC.md#16-still-to-decide)). WAL lets them
          // overlap: a writer no longer blocks readers.
          //
          // **No durability is given up.** `synchronous` is left at the
          // packaged default of `FULL`, which under WAL fsyncs the log on
          // every commit — a set that returned from its transaction survives a
          // power cut, and the file is never corrupt either way. `NORMAL` is
          // the setting that would trade the first of those for speed, and
          // this deliberately does not take it: the one thing this app must
          // never do is lose a set the user watched it accept.
          // `connection_pragmas_test` asserts the value rather than trusting
          // this paragraph, because the default is the whole mechanism and a
          // default is exactly what a later line can quietly move.
          //
          // Decided in the first phase on purpose, so every later test runs on
          // the mode the phone runs on. It is a property of the file, so this
          // sets it once and re-asserts it for free on every launch after.
          //
          // Leaves `-wal` and `-shm` files beside the database — safe today
          // because nothing copies the database file (a backup writes JSON),
          // and something to revisit the moment anything does.
          await customStatement('PRAGMA journal_mode = WAL');

          // Before anything can write a row that carries it.
          await _ensureDeviceId();

          // And before anything can stamp one. See `nowMs`: the clamp that
          // keeps last-write-wins honest across a clock that moves backwards
          // is only as good as the mark it starts from, and a mark that starts
          // at zero protects one run of the app.
          await _seedStampFloor();

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

  /// This install's identity, minted once and kept for the life of the
  /// database file.
  ///
  /// In `app_settings` rather than in a column default, because it has to
  /// survive a restore: the backup carries the rows a device wrote, and a
  /// device that changed identity every launch would make `deviceId` describe
  /// the launch instead of the phone.
  Future<void> _ensureDeviceId() async {
    final existing = await (select(appSettings)
          ..where((t) => t.key.equals(deviceIdKey)))
        .getSingleOrNull();
    if (existing != null) {
      setCurrentDeviceId(existing.value);
      return;
    }
    final minted = newId();
    await into(appSettings).insert(
      AppSettingsCompanion.insert(key: deviceIdKey, value: minted),
    );
    setCurrentDeviceId(minted);
  }

  /// Raises the stamp clamp to the highest mark this install may have used,
  /// and writes down a new one covering the session about to start.
  ///
  /// In `app_settings` beside `device_id`, and for the same reasons: it
  /// describes the phone rather than the launch, and it has to survive a
  /// restore. It is a floor, so a mark restored from an older export is
  /// harmless — the wall clock is almost always ahead of it and wins.
  ///
  /// See `stampLeaseMs` for why it is written here and at `close` rather than
  /// on every stamp.
  Future<void> _seedStampFloor() async {
    final stored = await (select(appSettings)
          ..where((t) => t.key.equals(lastStampKey)))
        .getSingleOrNull();
    final mark = int.tryParse(stored?.value ?? '') ?? 0;
    seedStampFloor(mark);
    await _writeStampFloor(
      DateTime.now().toUtc().millisecondsSinceEpoch + stampLeaseMs,
      atLeast: mark,
    );
  }

  /// Writes [stamp], unless the mark is already at or past it.
  ///
  /// Monotonic on purpose: every caller is claiming "no stamp below this will
  /// ever be handed out again", and a lower claim cannot unsay a higher one.
  Future<void> _writeStampFloor(int stamp, {required int atLeast}) async {
    if (stamp <= atLeast) return;
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: lastStampKey, value: '$stamp'),
    );
  }

  /// Writes down where the session actually reached before letting go.
  ///
  /// The lease written at open covers a kill; this covers everything past it,
  /// which on a long session is most of it. Failing is survivable and must not
  /// stop the close — the lease is still on disk and still a floor — so it is
  /// reported rather than thrown.
  @override
  Future<void> close() async {
    try {
      final stored = await (select(appSettings)
            ..where((t) => t.key.equals(lastStampKey)))
          .getSingleOrNull();
      await _writeStampFloor(
        stampMark,
        atLeast: int.tryParse(stored?.value ?? '') ?? 0,
      );
    } on Object catch (error, stack) {
      reportFailure(
        error,
        stack,
        what: 'The clock this phone stamps your training with could not be '
            'saved.',
      );
    }
    await super.close();
  }

  static QueryExecutor _open() =>
      driftDatabase(name: 'deltoid', native: const DriftNativeOptions());
}
