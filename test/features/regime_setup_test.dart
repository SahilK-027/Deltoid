import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/regime/regime_setup.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real create-regime flow: template sheet → name dialog → write.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ensureStarterCatalog(db);
  });

  tearDown(() => db.close());

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => createRegimeFlow(context, ref),
                  child: const Text('Create'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('picking a template and saving writes the regime', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push / Pull / Legs · 6 day'));
    await tester.pumpAndSettle();

    expect(find.text('Name this regime'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final regimes = await db.select(db.regimes).get();
    expect(regimes, hasLength(1));
    expect(regimes.single.isActive, isTrue);
    expect((await db.select(db.sessions).get()), hasLength(6));
    expect((await db.select(db.sessionExercises).get()), isNotEmpty);
  });

  testWidgets('a blank regime is created with the typed name', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start from scratch'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bench only');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final regimes = await db.select(db.regimes).get();
    expect(regimes.single.name, 'Bench only');
    expect(await db.select(db.sessions).get(), isEmpty);
  });

  testWidgets('cancelling the name dialog creates nothing', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push / Pull / Legs · 6 day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await db.select(db.regimes).get(), isEmpty);
  });
}
