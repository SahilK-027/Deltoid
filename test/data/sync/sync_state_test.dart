import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/table_spec.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/push.dart';
import 'package:deltoid/data/sync/sync_state.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

/// The three states, derived rather than remembered.
///
/// [SYNC.md § 17](SYNC.md#17-the-architecture): count the rows still owed, read
/// the stamp, and that is the whole of it. Nothing keeps this in step because
/// there is no second copy of the answer — which is the same reason there is no
/// state for *syncing right now*.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('what is owed is grouped the way the app names it', () async {
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    final repo = TrainingRepository(db);
    final regime = await (db.select(db.regimes)).getSingle();
    final push1 = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: push1.id);
    final sets = (await repo.workoutDetail(id))!.entries.first.sets;

    // Everything above has been sent; only what follows is owed.
    for (final spec in tableSpecs(db).where((s) => s.syncs)) {
      await db.customStatement('UPDATE ${spec.name} SET dirty = 0');
    }
    for (final set in sets.take(2)) {
      await repo.updateSet(set.id, weight: const Value(60), reps: const Value(5));
    }
    await db.customStatement(
      "INSERT INTO bodyweight_logs (id, updated_at, device_id, dirty, "
      "day_key, weight_kg) VALUES ('bw', 0, 'd', 1, 20260924, 82.4)",
    );

    final summary = await watchOwedSummary(db).first;
    final session = summary.waiting.first;
    expect(session.kind, WaitingKind.session);
    expect(session.sessionName, 'Push 1');
    expect(session.count, 2, reason: 'a session is counted by its sets');
    expect(session.inProgress, isTrue);
    expect(summary.waiting.last.kind, WaitingKind.bodyweight);
    expect(summary.count, 3);
    expect(summary.last, isNull, reason: 'nothing finished has been sent');
  });

  test('signed out is Local, whatever is owed', () async {
    await ensureStarterCatalog(db);

    final state = await watchSyncState(db, signedIn: false).first;

    expect(state.status, SyncStatus.local);
    expect(state.owed, 0);
  });

  test('rows owed is Pending, and says how many', () async {
    await ensureStarterCatalog(db);
    final owed = await db
        .customSelect('SELECT COUNT(*) AS n FROM exercises WHERE dirty = 1')
        .map((row) => row.read<int>('n'))
        .getSingle();

    final state = await watchSyncState(db, signedIn: true).first;

    expect(state.status, SyncStatus.pending);
    expect(state.owed, owed);
    expect(state.lastPushAt, isNull);
  });

  test('pending says since when, off the oldest thing owed', () async {
    await ensureStarterCatalog(db);
    // Two ages, so the answer is the older one and not simply the last write.
    await db.customStatement(
      'UPDATE exercises SET updated_at = 5000, dirty = 1',
    );
    await db.customStatement(
      "UPDATE exercises SET updated_at = 1000 WHERE starter_key = "
      "(SELECT starter_key FROM exercises WHERE starter_key IS NOT NULL "
      'ORDER BY id LIMIT 1)',
    );

    final state = await watchSyncState(db, signedIn: true).first;

    expect(state.status, SyncStatus.pending);
    expect(state.owedSince, DateTime.fromMillisecondsSinceEpoch(1000));
  });

  test('nothing owed is nothing to date', () async {
    await ensureStarterCatalog(db);
    await db.customStatement('UPDATE exercises SET dirty = 0');

    final state = await watchSyncState(db, signedIn: true).first;

    expect(state.status, SyncStatus.synced);
    expect(state.owedSince, isNull);
  });

  test('the state follows a drain without being told about it', () async {
    await ensureStarterCatalog(db);
    final states = watchSyncState(db, signedIn: true);
    final settled = states.firstWhere((s) => s.status == SyncStatus.synced);

    await PushService(db, FakeBackend()).drain();

    final state = await settled.timeout(const Duration(seconds: 5));
    expect(state.owed, 0);
    expect(state.lastPushAt, isNotNull);
  });

  test('a write after a push puts it back to Pending', () async {
    await ensureStarterCatalog(db);
    await PushService(db, FakeBackend()).drain();
    expect((await watchSyncState(db, signedIn: true).first).status,
        SyncStatus.synced);

    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );

    final state = await watchSyncState(db, signedIn: true).first;
    expect(state.status, SyncStatus.pending);
    expect(state.owed, greaterThan(0));
    // The stamp does not move backwards: `Pending` still knows when the last
    // drain landed, which is what phase 6 says *for how long* against.
    expect(state.lastPushAt, isNotNull);
  });
}
