import 'package:deltoid/core/providers.dart';
import 'package:deltoid/data/backup/backup_service.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/table_spec.dart';
import 'package:deltoid/data/repositories/phase_repository.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/units.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The registry both whole-row readers answer to.
///
/// Two readers can meet a row they do not fully recognise: the backup codec, on
/// a file written by an older build, and a pull
/// ([SYNC.md § 14](SYNC.md#14-two-builds-one-account)), on a server another
/// build wrote. It is one problem, so it gets one set of defaults and one set
/// of tests rather than a second list that has to agree with this one
/// forever.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    // `app_settings` carries exactly one backed-up key, and nothing writes it
    // until the unit is chosen — without this the settings row to probe does
    // not exist and the loop below has nothing to say about that table.
    await setWeightUnit(db, WeightUnit.lb);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );

    // Form videos are user-entered, so nothing exercises the JSON-list column
    // until one is given.
    final pullup = await (db.select(db.exercises)
          ..where((t) => t.name.equals('Pull-up')))
        .getSingle();
    await RegimeRepository(db).updateExercise(
      pullup.id,
      videos: const Value(['https://example.com/pull-up']),
    );
  });

  tearDown(() => db.close());

  /// One real session, so every table has a row to probe rather than only the
  /// templates.
  Future<void> logASession() async {
    final regime =
        await (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
            .getSingle();
    final push1 =
        await (db.select(db.sessions)..where((t) => t.name.equals('Push 1')))
            .getSingle();
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final detail = await repo.workoutDetail(id);
    for (final set in detail!.entries.first.sets) {
      await repo.updateSet(
        set.id,
        weight: const Value(22.5),
        reps: const Value(8),
        isDone: const Value(true),
      );
    }
    await repo.completeWorkout(id);
    await repo.logBodyweight(DateTime(2026, 7, 20), 72.4);
    await PhaseRepository(db).startPhase(
      PhaseKind.cut,
      from: DateTime(2026, 7, 1),
      plannedWeeks: 12,
    );
  }

  /// One serialised row per table, as both readers meet them: the export writes
  /// exactly this shape, and so does `toJson` on a row a pull decoded.
  Future<Map<String, Map<String, dynamic>>> aRowPerTable() async {
    final data = (await BackupService(db).buildPayload())['data'] as Map;
    return {
      for (final spec in tableSpecs(db))
        spec.name: Map<String, dynamic>.from(
          (data[spec.name] as List).first as Map,
        ),
    };
  }

  test('every column of every table has a default or has always been written',
      () async {
    await logASession();
    final rows = await aRowPerTable();

    for (final spec in tableSpecs(db)) {
      final row = rows[spec.name]!;

      // The probe below walks the *row*, so it only covers every column if the
      // row carries every column. `toJson` derives its keys from the Dart
      // getters and the schema from the SQL names; this is where a column that
      // serialises under some third name would show up.
      expect(
        row.keys.toSet(),
        spec.table.$columns.map((c) => jsonKeyOf(c.name)).toSet(),
        reason: 'the serialised ${spec.name} row is not its columns',
      );

      for (final key in row.keys) {
        final without = Map<String, dynamic>.from(row)..remove(key);
        var readable = true;
        try {
          spec.parse(without);
        } on Object {
          readable = false;
        }
        if (readable) continue;
        expect(
          _presentInEveryRowEverWritten[spec.name],
          contains(key),
          reason: '${spec.name}.$key has no default in `tableSpecs` and is not '
              'recorded as present in every row ever written. Give it one — '
              'RULES.md § 3 step 3 — or add it to '
              '`_presentInEveryRowEverWritten` and say why no writer can lack '
              'it.',
        );
      }
    }

    // A name left behind by a column that no longer exists would sit here
    // quietly excusing nothing.
    for (final spec in tableSpecs(db)) {
      final keys = spec.table.$columns.map((c) => jsonKeyOf(c.name)).toSet();
      expect(
        _presentInEveryRowEverWritten[spec.name]!.difference(keys),
        isEmpty,
        reason: '${spec.name} is excused columns it does not have',
      );
    }
  });

  test('a column the reader has never heard of is ignored, not an error',
      () async {
    await logASession();
    final rows = await aRowPerTable();

    for (final spec in tableSpecs(db)) {
      // What a row written by a *newer* build looks like from here: everything
      // this build knows, plus a column it does not. Dropping it is right —
      // refusing the row would mean one upgraded phone could stop the other
      // reading its own history. See SYNC.md § 14.
      final fromTheFuture = {
        ...rows[spec.name]!,
        'somethingAddedLater': 'whatever this turns out to mean',
        'anotherThing': 42,
      };
      expect(
        () => spec.parse(fromTheFuture),
        returnsNormally,
        reason: '${spec.name} refuses a row from a build that knows one more '
            'column than this one',
      );
    }
  });

  test('a JSON key and its column name convert both ways, for every column',
      () async {
    // The two mismatches between what drift writes and what Postgres wants are
    // both quiet ones: a key that does not match a column is not an error
    // anywhere, it is a value that never arrives. So the conversion is a pair
    // of pure functions checked against every column of every table rather than
    // ten hand-written maps.
    for (final spec in tableSpecs(db)) {
      for (final column in spec.table.$columns) {
        final key = jsonKeyOf(column.name);
        expect(
          columnNameOf(key),
          column.name,
          reason: '${spec.name}.${column.name} does not survive the round trip',
        );
        expect(key, isNot(contains('_')),
            reason: '${spec.name}.${column.name} keeps a separator in its JSON '
                'key, so it is not the getter drift serialises under');
      }
    }
  });

  test('only app_settings stays off the server', () async {
    // SYNC.md § 4: the ten tables carrying `SyncColumns`, and those only.
    // `app_settings` holds `device_id`, which is the tie-break — syncing it
    // would break the very thing it exists for.
    expect(
      [for (final spec in tableSpecs(db)) if (!spec.syncs) spec.name],
      ['app_settings'],
    );
    expect(tableSpecs(db).where((s) => s.syncs).length, 10);

    // And a syncable table is exactly one carrying the sync columns, which is
    // what makes that count a fact about the schema rather than a list somebody
    // kept up to date.
    for (final spec in tableSpecs(db)) {
      final columns = spec.table.$columns.map((c) => c.name).toSet();
      expect(
        columns.containsAll({'id', 'updated_at', 'deleted_at', 'device_id',
            'dirty'}),
        spec.syncs,
        reason: '${spec.name} disagrees with itself about whether it syncs',
      );
    }
  });
}

/// The columns a reader may require, because no writer has ever left one out.
///
/// **This is the schema as it stood when the backup format was fixed**, and
/// every column added since is absent from it on purpose — each one carries a
/// default in `tableSpecs` instead, spread under the row so an older one lands
/// anyway. `barKind` — on the catalog row, and since schema 4 on the day's slot
/// and the logged row as well — `measureMode`, `identityIndex`, `muscle`,
/// `partialReps` and `tzOffsetMinutes` are the ones, and the last is derived
/// from the row rather than constant.
///
/// Adding a name here is a claim that no row anywhere lacks the column. That is
/// only ever true of a column that predates the first export, which is why this
/// list should not grow: it is a record, not a place to put a column you did not
/// want to write a default for.
///
/// Derived by hand from `tables.dart` — it is every non-nullable column of each
/// table, less the six defaults above. Nullable columns are absent because a
/// missing key and a null both come back null, so they need nothing.
const _presentInEveryRowEverWritten = <String, Set<String>>{
  'app_settings': {'key', 'value'},
  'exercises': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'name', 'muscle', 'equipment', 'loadMode', 'formVideoUrls', 'archived',
  },
  'regimes': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'name', 'isActive', 'deloadEnabled', 'deloadAfterCycles',
    'deloadSetDelta', 'deloadWeightPct', 'createdAt',
  },
  'sessions': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'regimeId', 'name', 'orderIndex',
  },
  'session_exercises': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'sessionId', 'exerciseId', 'orderIndex', 'targetSets',
  },
  'cycles': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'regimeId', 'cycleIndex', 'startedAt', 'isDeload',
  },
  'workouts': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'regimeId', 'dayKey', 'startedAt', 'isDeload', 'status',
  },
  'workout_exercises': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'workoutId', 'exerciseId', 'orderIndex', 'targetSets', 'skipReason',
  },
  'set_logs': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'workoutExerciseId', 'setIndex', 'setType', 'isDone',
  },
  'bodyweight_logs': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'dayKey', 'weightKg',
  },
  // The table arrived whole at schema 7, so every row ever written carries
  // every column; the nullable ones read as null without a default.
  'phases': {
    'id', 'updatedAt', 'deviceId', 'dirty', //
    'kind', 'dayKey',
  },
};
