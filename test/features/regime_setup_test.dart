import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
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

  Future<void> pumpHost(WidgetTester tester, {bool activate = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      createRegimeFlow(context, ref, activate: activate),
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

    // Nothing typed yet, so there is nothing to save — a blank name would
    // create a regime called "".
    expect(
      tester
          .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Save'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'Bench only');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final regimes = await db.select(db.regimes).get();
    expect(regimes.single.name, 'Bench only');
    expect(await db.select(db.sessions).get(), isEmpty);
  });

  testWidgets('closing the name sheet creates nothing', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push / Pull / Legs · 6 day'));
    await tester.pumpAndSettle();
    // Naming is a sheet now, not a dialog: the way out is its ✕, not a text
    // button paired with Save (THEME §5, §7).
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(await db.select(db.regimes).get(), isEmpty);
  });

  testWidgets('creating without activating leaves you on the old regime',
      (tester) async {
    // The whole point of a shelf of programmes: building next month's split
    // must not abandon the one you are mid-cycle on.
    final first = await RegimeRepository(db).createRegime('Current');
    await pumpHost(tester, activate: false);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push / Pull / Legs · 6 day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final regimes = await db.select(db.regimes).get();
    expect(regimes, hasLength(2));
    expect(regimes.where((r) => r.isActive).single.id, first);
  });
}
