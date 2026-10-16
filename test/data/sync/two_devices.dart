import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/sync/pull.dart';
import 'package:deltoid/data/sync/push.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'fake_backend.dart';

/// Two phones and one account, which is the only rig that can test a merge.
///
/// [SYNC.md § 18](SYNC.md#18-the-phases) asks for exactly this: every row of
/// [§ 12](SYNC.md#12-every-edge-case-and-what-it-does) as a named test against
/// two in-memory databases and one fake backend.
///
/// **The device id is process-global** — `setCurrentDeviceId` is called once per
/// open and every write reads it — so a test writing to both phones in one
/// process has to say which phone it is being at the moment. [as] does that,
/// and it is not a detail: `deviceId` is what breaks a tie, and two databases
/// both stamping `device-a` would make ties resolve by accident.
class TwoDevices {
  TwoDevices() {
    // Two databases in one process is the whole point of this rig, and each has
    // its own private in-memory executor — the race the warning is about needs
    // one executor behind two instances.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    a = AppDatabase.forTesting(NativeDatabase.memory());
    b = AppDatabase.forTesting(NativeDatabase.memory());
  }

  late final AppDatabase a;
  late final AppDatabase b;
  final backend = FakeBackend();

  /// Runs [body] as the given phone, so every row it writes carries that
  /// phone's id.
  Future<T> as<T>(String device, Future<T> Function() body) async {
    setCurrentDeviceId(device);
    return body();
  }

  Future<PushReport> push(AppDatabase db, {int batchSize = 400}) =>
      PushService(db, backend, batchSize: batchSize).drain();

  Future<PullReport> pull(AppDatabase db, {int batchSize = 400}) =>
      PullService(db, backend, batchSize: batchSize).pull();

  /// A pull then a push, which is the order the engine runs them in: a conflict
  /// is resolved before it is propagated ([§ 7](SYNC.md#7-pull)).
  Future<void> sync(AppDatabase db) async {
    await pull(db);
    await push(db);
  }

  /// Syncs both phones until they hold the same rows, and says how many
  /// exchanges it took.
  ///
  /// **This is the check [SYNC.md § 18](SYNC.md#18-the-phases) asks for**: once
  /// both sides are quiet and have synced, they hold the same rows. It is also
  /// the only thing that can catch a rule that is deterministic on one device
  /// and disagrees with the other.
  ///
  /// More than one round is expected where both phones had to resolve the same
  /// collision: **a resolution is itself a write**, so each device produces a
  /// version the other has not seen, and the second exchange is what settles
  /// which of the two identical answers is the one on the account. It has to
  /// *stop*, though — a rule that keeps producing new versions would run to the
  /// limit here rather than looping forever on a phone.
  Future<int> converge({int limit = 6}) async {
    for (var round = 1; round <= limit; round++) {
      await sync(a);
      await sync(b);
      if (_sameRows(await rowsOf(a), await rowsOf(b))) return round;
    }
    throw StateError('two devices did not converge in $limit exchanges');
  }

  bool _sameRows(
    Map<String, List<Map<String, dynamic>>> a,
    Map<String, List<Map<String, dynamic>>> b,
  ) =>
      a.toString() == b.toString();

  /// Everything both phones hold, as maps, for a convergence check.
  Future<Map<String, List<Map<String, dynamic>>>> rowsOf(AppDatabase db) async {
    final tables = [
      'exercises',
      'regimes',
      'sessions',
      'session_exercises',
      'cycles',
      'workouts',
      'workout_exercises',
      'set_logs',
      'bodyweight_logs',
      'phases',
    ];
    return {
      for (final table in tables)
        table: [
          for (final row in await db
              .customSelect('SELECT * FROM $table ORDER BY id')
              .get())
            // `dirty` is a fact about a device's queue, not about the row, so
            // two phones holding the same history disagree about it while one
            // still owes a push. Everything else must match exactly.
            {...row.data}..remove('dirty'),
        ],
    };
  }

  Future<void> close() async {
    await a.close();
    await b.close();
  }
}
