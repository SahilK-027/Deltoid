import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/sync_providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/sync/sync_engine.dart';
import 'package:deltoid/data/sync/sync_state.dart';
import 'package:deltoid/features/account/backup_mark.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The header's backup button.
///
/// Always drawn with an account, green while online and yellow without a
/// connection. The number appears only while it is yellow: online, a set is
/// owed for the seconds the push debounces, and a count that blinked with each
/// set would be noise over the log.
void main() {
  const pending = SyncState(
    status: SyncStatus.pending,
    owed: 3,
    lastPushAt: null,
  );
  const synced = SyncState(
    status: SyncStatus.synced,
    owed: 0,
    lastPushAt: null,
  );
  const summary = OwedSummary(
    waiting: [
      WaitingItem.session(
        workoutId: 'w',
        sessionName: 'Push 1',
        dayKey: 20260101,
        inProgress: true,
        count: 17,
      ),
      WaitingItem.bodyweight(1),
    ],
    last: null,
  );

  Future<void> pump(
    WidgetTester tester, {
    required SyncState state,
    bool online = true,
    SyncTrouble? trouble,
    OwedSummary owed = OwedSummary.empty,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncStateProvider.overrideWith((ref) => Stream.value(state)),
          syncTroubleProvider.overrideWith((ref) => Stream.value(trouble)),
          onlineProvider.overrideWith((ref) => Stream.value(online)),
          owedSummaryProvider.overrideWith((ref) => Stream.value(owed)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(body: Center(child: BackupMark())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without an account there is no button', (tester) async {
    await pump(tester, state: SyncState.local);
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('online and backed up is green, with no number',
      (tester) async {
    await pump(tester, state: synced);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('a set waiting a few seconds online stays green',
      (tester) async {
    await pump(tester, state: pending, owed: summary);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(find.text('18'), findsNothing);
  });

  testWidgets('no connection is yellow, counted, and opens onto what is '
      'only on this phone', (tester) async {
    await pump(tester, state: pending, online: false, owed: summary);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('18'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cloud_off_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsWidgets);
    // The whole sentence, wrapping: in the sheet's one-line subtitle it was
    // cut off halfway through.
    final sentence = tester.widget<Text>(
      find.text(
        'Everything is saved on this phone. It is backed up to your account '
        'when the phone is online again. 3 changes waiting.',
      ),
    );
    expect(sentence.maxLines, isNull);
    expect(sentence.overflow, isNot(TextOverflow.ellipsis));
    expect(find.text('On this phone only'), findsOneWidget);
    expect(find.text('17 sets, in progress'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);
    expect(find.text('Try again now'), findsOneWidget);
  });

  testWidgets('backed up: the title is the state, and the time is a sentence '
      'under it', (tester) async {
    final at = DateTime.now().subtract(const Duration(minutes: 5));
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    await pump(
      tester,
      state: SyncState(status: SyncStatus.synced, owed: 0, lastPushAt: at),
    );

    await tester.tap(find.byIcon(Icons.cloud_done_outlined));
    await tester.pumpAndSettle();

    // No clock in the title: beside the file backup's time on Settings it
    // read as a second, unexplained one.
    expect(find.text('Backed up'), findsOneWidget);
    expect(find.textContaining('Backed up $time'), findsNothing);
    expect(
      find.text(
        'Everything is saved on this phone and on your account. '
        'Last backed up at $time.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the newest session held is not called last backed up', (
    tester,
  ) async {
    // Two facts, two phrases: when the account last received anything, and
    // which session is the newest it holds. Sharing one phrase put a time
    // from today over a session from yesterday.
    final at = DateTime.now().subtract(const Duration(minutes: 5));
    await pump(
      tester,
      state: SyncState(status: SyncStatus.synced, owed: 0, lastPushAt: at),
      owed: const OwedSummary(
        waiting: [],
        last: BackedUpSession(sessionName: 'Leg 2', dayKey: 20260101),
      ),
    );

    await tester.tap(find.byIcon(Icons.cloud_done_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Newest session on your account'), findsOneWidget);
    expect(find.text('Last backed up'), findsNothing);
    expect(find.textContaining('Last backed up at '), findsOneWidget);
  });

  testWidgets('offline: the sheet says how much is waiting', (tester) async {
    await pump(tester, state: pending, online: false, owed: summary);

    await tester.tap(find.byIcon(Icons.cloud_off_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Everything is saved on this phone. It is backed up to your account '
        'when the phone is online again. 3 changes waiting.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed attempt with the interface up is yellow too',
      (tester) async {
    await pump(
      tester,
      state: pending,
      trouble: SyncTrouble.offline,
      owed: summary,
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });
}

