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
    expect(find.textContaining('Everything is saved on this phone.'),
        findsOneWidget);
    expect(find.text('On this phone only'), findsOneWidget);
    expect(find.text('17 sets, in progress'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);
    expect(find.text('Try again now'), findsOneWidget);
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

