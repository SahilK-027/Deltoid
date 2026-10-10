import 'package:deltoid/data/sync/sync_state.dart';
import 'package:deltoid/features/account/backup_mark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// The second sentence of the backup sheet: how much is waiting and since
/// when, or when the account last received anything.
///
/// [SYNC.md § 2](SYNC.md#2-the-three-states) asks for how long as well as how
/// many. **Pending is normal** — a session logged in a basement gym is pending
/// for an hour and that is the design working — so the count alone says
/// nothing and the date is what carries the meaning.
void main() {
  SyncState pending({int owed = 3, DateTime? since}) => SyncState(
    status: SyncStatus.pending,
    owed: owed,
    lastPushAt: null,
    owedSince: since,
  );

  SyncState synced(DateTime? lastPushAt) =>
      SyncState(status: SyncStatus.synced, owed: 0, lastPushAt: lastPushAt);

  group('what is waiting', () {
    test('nothing resolved yet claims nothing', () {
      // Reading a loading `AsyncValue` as *nothing owed* would show
      // `Backed up` over a phone holding a session — SYNC.md § 19.
      expect(backupWaitingLine(null), isNull);
    });

    test('pending says how many and since when', () {
      final since = DateTime.now().subtract(const Duration(minutes: 30));
      expect(
        backupWaitingLine(pending(since: since)),
        '3 changes waiting since ${DateFormat('HH:mm').format(since)}.',
      );
    });

    test('a wait from another day gives the day, not the hour', () {
      final since = DateTime.now().subtract(const Duration(days: 3));
      expect(
        backupWaitingLine(pending(since: since)),
        '3 changes waiting since ${DateFormat('d MMM').format(since)}.',
      );
    });

    test('one change is not 1 changes', () {
      expect(backupWaitingLine(pending(owed: 1)), '1 change waiting.');
    });

    test('a phone with nothing waiting has no such line', () {
      expect(backupWaitingLine(synced(DateTime.now())), isNull);
    });
  });

  group('when the account last received anything', () {
    test('today is a time', () {
      final at = DateTime.now().subtract(const Duration(minutes: 5));
      expect(
        lastBackedUpLine(synced(at)),
        'Last backed up at ${DateFormat('HH:mm').format(at)}.',
      );
    });

    test('another day is the day and the time', () {
      final at = DateTime(2026, 8, 12, 9, 14);
      expect(lastBackedUpLine(synced(at)), 'Last backed up on 12 Aug at 09:14.');
    });

    test('signed in and never sent has no time to give', () {
      expect(lastBackedUpLine(synced(null)), isNull);
      expect(lastBackedUpLine(null), isNull);
    });
  });
}
