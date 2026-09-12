import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/log_screen.dart';
import 'package:deltoid/features/log/widgets/set_row.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back is the way to put the keypad away — the pad has no button for it — so
/// it has to close the pad without leaving the session, and it has to save
/// what was typed there and then rather than on the 300ms write timer.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late TrainingRepository repo;
  late String workoutId;

  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    final regime = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
    final session = await (db.select(db.sessions)
          ..where((t) => t.name.equals('Push 1')))
        .getSingle();
    workoutId = await repo.startWorkout(
      regimeId: regime.id,
      sessionId: session.id,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // Never `pumpAndSettle`: a watched query that has not answered yet renders a
  // spinner, which never settles.
  Future<void> frames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('back closes the keypad, keeps the session, and saves the digits',
      (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: LogScreen(workoutId: workoutId),
        ),
      ),
    );
    await frames(tester, 40);

    final detail = await repo.workoutDetail(workoutId);
    final set = detail!.entries.first.sets.first;
    final row = tester.widget<SetRow>(
      find.byWidgetPredicate((w) => w is SetRow && w.set.id == set.id),
    );
    row.onEdit(set, SetField.weight);
    await frames(tester, 10);

    final pad = tester.widget<SetKeypad>(find.byType(SetKeypad));
    pad.onKey('6');
    pad.onKey('0');
    await frames(tester, 2);

    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    // Well inside the 300ms the write timer waits: only an immediate save
    // can have landed by now.
    await frames(tester, 5);

    expect(find.byType(SetKeypad), findsNothing, reason: 'the pad is still up');
    expect(find.byType(LogScreen), findsOneWidget,
        reason: 'back left the session instead of closing the pad');

    final saved = await repo.workoutDetail(workoutId);
    expect(saved!.entries.first.sets.first.weight, 60);
  });

  testWidgets('the keypad carries no button to put it away', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SetKeypad(
            field: SetField.weight,
            unit: WeightUnit.kg,
            buffer: ValueNotifier(''),
            onKey: (_) {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.keyboard_hide_outlined), findsNothing);
  });
}
