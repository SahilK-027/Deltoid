import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/push.dart';
import 'package:deltoid/data/sync/sync_state.dart';
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

  test('what is owed is listed table by table, and empties as it lands',
      () async {
    await ensureStarterCatalog(db);
    final owed = await db
        .customSelect('SELECT COUNT(*) AS n FROM exercises WHERE dirty = 1')
        .map((row) => row.read<int>('n'))
        .getSingle();

    final stream = watchOwedByTable(db);
    expect(await stream.first, [('exercises', owed)]);

    await db.customStatement('UPDATE exercises SET dirty = 0');
    expect(await watchOwedByTable(db).first, isEmpty);
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
