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

/// The header's mark for training the account has not received yet.
///
/// It appears only when something is owed *and* the last attempt to send it
/// failed. Owed alone is every set for the few seconds the push waits, and a
/// mark that blinked on each of them would be noise over the log.
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

  Future<void> pump(
    WidgetTester tester, {
    required SyncState state,
    SyncTrouble? trouble,
    List<(String, int)> owed = const [],
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncStateProvider.overrideWith((ref) => Stream.value(state)),
          syncTroubleProvider.overrideWith((ref) => Stream.value(trouble)),
          owedByTableProvider.overrideWith((ref) => Stream.value(owed)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(body: Center(child: BackupMark())),
        ),
      ),
    );
    // Two streams resolve, then the provider combining them rebuilds.
    await tester.pumpAndSettle();
  }

  testWidgets('owed but not yet failed shows nothing', (tester) async {
    await pump(tester, state: pending);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('nothing owed shows nothing, whatever the last attempt was',
      (tester) async {
    await pump(tester, state: synced, trouble: SyncTrouble.offline);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('owed with no connection shows the mark, and it opens onto '
      'what is waiting', (tester) async {
    await pump(
      tester,
      state: pending,
      trouble: SyncTrouble.offline,
      owed: const [('workouts', 1), ('set_logs', 12)],
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cloud_off_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Not backed up yet'), findsWidgets);
    expect(find.textContaining('Everything is saved on this phone.'),
        findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Sets'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
