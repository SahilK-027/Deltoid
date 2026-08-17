import 'package:deltoid/core/providers.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/table_spec.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/push.dart';
import 'package:deltoid/data/sync/sync_backend.dart';
import 'package:deltoid/domain/units.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

/// The drain, against a server that only exists in this process.
///
/// [SYNC.md § 6](SYNC.md#6-push) is four rules and every one of them is here:
/// what goes, in what order, how `dirty` is cleared, and what a retry costs.
/// The one worth the most is the third — a row edited while its own push was in
/// flight is still owed, and clearing it on the response strands that edit on
/// the phone forever, invisibly, because nothing downstream ever looks at a row
/// that is not dirty.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late FakeBackend backend;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    backend = FakeBackend();
    await setWeightUnit(db, WeightUnit.kg);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
  });

  tearDown(() => db.close());

  Future<String> logASession() async {
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
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );
    }
    await repo.completeWorkout(id);
    await repo.logBodyweight(DateTime(2026, 7, 20), 72.4);
    return id;
  }

  /// How many rows the phone still owes, across every syncable table.
  Future<int> owed() async {
    final sql = tableSpecs(db)
        .where((s) => s.syncs)
        .map((s) => '(SELECT COUNT(*) FROM ${s.name} WHERE dirty = 1)')
        .join(' + ');
    return db
        .customSelect('SELECT $sql AS owed')
        .map((row) => row.read<int>('owed'))
        .getSingle();
  }

  test('every dirty row leaves, and nothing is owed afterwards', () async {
    await logASession();
    expect(await owed(), greaterThan(0));

    final report = await PushService(db, backend).drain();

    expect(await owed(), 0);
    expect(report.rows, backend.storedRows);
    for (final spec in tableSpecs(db).where((s) => s.syncs)) {
      final local = await db
          .customSelect('SELECT COUNT(*) AS n FROM ${spec.name}')
          .map((row) => row.read<int>('n'))
          .getSingle();
      expect(
        backend.table(spec.name).length,
        local,
        reason: '${spec.name} did not all arrive',
      );
    }
  });

  test('app_settings never leaves, whatever is in it', () async {
    await logASession();
    await PushService(db, backend).drain();

    expect(backend.rows.keys, isNot(contains('app_settings')));
    // The device id is the reason — SYNC.md § 4.
    expect(
      backend.rows.values.expand((t) => t.values).every(
            (row) => !row.containsKey('key'),
          ),
      isTrue,
    );
  });

  test('parents go before children', () async {
    await logASession();
    await PushService(db, backend).drain();

    final order = backend.calls.map((c) => c.table).toList();
    final registry =
        tableSpecs(db).where((s) => s.syncs).map((s) => s.name).toList();

    // The tables that had anything to send, in the order they first sent it,
    // against the order the registry puts them in — parents first, which is the
    // order a restore already depends on.
    final sent = order.toSet().toList();
    expect(
      sent,
      orderedEquals(registry.where(sent.contains)),
      reason: 'a child reached the server before its parent',
    );
    // And no table is returned to after the next one has started, so the order
    // holds at every intermediate point rather than only at the first row.
    expect(
      order,
      orderedEquals([...order]..sort((a, b) =>
          registry.indexOf(a).compareTo(registry.indexOf(b)))),
    );
  });

  test('the wire is snake case, and carries neither column the server adds',
      () async {
    await logASession();
    await PushService(db, backend).drain();

    final workout = backend.table('workouts').first;
    expect(workout.keys, contains('updated_at'));
    expect(workout.keys, contains('tz_offset_minutes'));
    expect(workout.keys, contains('device_id'));
    expect(workout.keys, isNot(contains('updatedAt')));

    // Nothing sent carries either column the server adds: `user_id` defaults to
    // `auth.uid()` and `server_updated_at` is stamped by a trigger, precisely so
    // the two values a client must not be trusted with are two it never sends.
    for (final call in backend.calls) {
      for (final row in call.rows) {
        expect(row.keys, isNot(contains('user_id')));
        expect(row.keys, isNot(contains(serverUpdatedAtColumn)));
      }
    }

    // The JSON-list column is text on both sides, not an array — SYNC.md § 17.
    final exercise = backend
        .table('exercises')
        .firstWhere((row) => (row['form_video_urls'] as String).isNotEmpty);
    expect(exercise['form_video_urls'], isA<String>());
  });

  test('a row edited while its push was in flight stays owed', () async {
    final workoutId = await logASession();
    final note = 'edited mid-flight';

    backend.onStored = (table, rows) async {
      if (table != 'workouts') return;
      backend.onStored = null;
      // The row is on the server; the user is still typing on the phone.
      await repo.setWorkoutNotes(workoutId, note);
    };

    await PushService(db, backend).drain();

    final row = await (db.select(db.workouts)
          ..where((t) => t.id.equals(workoutId)))
        .getSingle();
    expect(row.notes, note);
    expect(
      row.dirty,
      isTrue,
      reason: 'clearing dirty on the response would strand that edit forever',
    );

    // And the next drain carries it, rather than it sitting there.
    await PushService(db, backend).drain();
    expect(backend.table('workouts').first['notes'], note);
    expect(await owed(), 0);
  });

  test('killed after the server committed: dirty stays, and the retry is free',
      () async {
    await logASession();

    backend.onStored = (table, rows) async {
      if (table != 'exercises') return;
      backend.onStored = null;
      // The rows landed and the response never arrived — edge case 12.
      throw const SyncTransportFailure('dropped', transient: true);
    };

    await expectLater(
      PushService(db, backend).drain(),
      throwsA(isA<SyncTransportFailure>()),
    );
    expect(backend.table('exercises'), isNotEmpty);
    expect(await owed(), greaterThan(0));

    final before = backend.storedRows;
    await PushService(db, backend).drain();
    expect(await owed(), 0);
    // Upserts on `id`, so the retry re-sent rows and duplicated none of them.
    expect(backend.storedRows, greaterThanOrEqualTo(before));
    expect(
      backend.table('exercises').length,
      await db
          .customSelect('SELECT COUNT(*) AS n FROM exercises')
          .map((row) => row.read<int>('n'))
          .getSingle(),
    );
  });

  test('a queue longer than one batch is drained in pages', () async {
    await logASession();
    final total = await owed();

    await PushService(db, backend, batchSize: 7).drain();

    expect(await owed(), 0);
    expect(backend.calls.length, greaterThan(total ~/ 7));
    expect(backend.calls.every((c) => c.rows.length <= 7), isTrue);
  });

  test('nothing owed sends nothing at all', () async {
    await logASession();
    await PushService(db, backend).drain();
    backend.calls.clear();

    final report = await PushService(db, backend).drain();

    expect(report.rows, 0);
    expect(backend.calls, isEmpty);
  });

  test('the last push is stamped only when something moved', () async {
    Future<String?> stamp() async => (await (db.select(db.appSettings)
              ..where((t) => t.key.equals(lastPushKey)))
            .getSingleOrNull())
        ?.value;

    await PushService(db, backend).drain();
    expect(await stamp(), isNotNull, reason: 'the seeded catalog is owed');

    final first = await stamp();
    await PushService(db, backend).drain();
    expect(await stamp(), first, reason: 'a drain that moved nothing is not a push');
  });
}
