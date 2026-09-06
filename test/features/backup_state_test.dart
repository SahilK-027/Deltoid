import 'package:deltoid/data/sync/sync_engine.dart';
import 'package:deltoid/data/sync/sync_state.dart';
import 'package:deltoid/features/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sentence under the account row: which state, for how long, and why.
///
/// [SYNC.md § 2](SYNC.md#2-the-three-states) asks for all three. **Pending is
/// normal** — a session logged in a basement gym is pending for an hour and
/// that is the design working — so the count alone says nothing and the date is
/// what carries the meaning.
void main() {
  SyncState pending({
    int owed = 3,
    DateTime? since,
    DateTime? lastPushAt,
  }) =>
      SyncState(
        status: SyncStatus.pending,
        owed: owed,
        lastPushAt: lastPushAt,
        owedSince: since,
      );

  test('nothing resolved yet says only what is certain', () {
    // Reading a loading `AsyncValue` as *nothing owed* would show `Backed up`
    // over a phone holding a session — SYNC.md § 19.
    expect(backupState(null, null), 'Signed in on this device.');
  });

  test('pending says how many and since when', () {
    final today = DateTime.now().subtract(const Duration(minutes: 30));
    final line = backupState(pending(since: today), null);

    expect(line, startsWith('3 changes waiting since '));
    expect(line, endsWith('.'));
  });

  test('one change is not 1 changes', () {
    expect(backupState(pending(owed: 1), null), '1 change waiting.');
  });

  test('why, but only when the last attempt actually failed', () {
    // Rows written a minute ago are pending because the debounce has not
    // elapsed, and explaining that would invent a problem to reassure about.
    expect(backupState(pending(), null), isNot(contains('connection')));
    expect(
      backupState(pending(), SyncTrouble.offline),
      contains("no connection"),
    );
    expect(
      backupState(pending(), SyncTrouble.refused),
      contains('refused the last attempt'),
    );
  });

  test('synced says when it last ran', () {
    final state = SyncState(
      status: SyncStatus.synced,
      owed: 0,
      lastPushAt: DateTime.utc(2026, 8, 12, 9, 14),
    );

    expect(backupState(state, null), startsWith('Backed up 12 Aug, '));
  });

  test('signed in and never pushed is not "backed up"', () {
    const state = SyncState(
      status: SyncStatus.synced,
      owed: 0,
      lastPushAt: null,
    );

    expect(backupState(state, null), 'Signed in on this device.');
  });
}
