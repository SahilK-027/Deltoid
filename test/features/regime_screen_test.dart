import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/regime/regime_screen.dart';
import 'package:deltoid/features/regime/regimes_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Regime index and the programme editor behind it, pumped against a real
/// database.
///
/// The editor went blank on the device twice — once because the day tabs asked
/// for an infinite width, once on a regime with no days in it — and both times
/// the analyzer and every other test were perfectly happy. A screen that
/// renders nothing is a test this file should own.
///
/// Two harness rules, both learned the hard way here:
///
/// * **Never `pumpAndSettle`.** A watched query that has not answered yet
///   renders a `CircularProgressIndicator`, which never settles, so the pump
///   runs until the harness gives up. Pump a fixed number of frames instead.
/// * **The container outlives the widget tree.** `flutter_test` tears the tree
///   down at the end of the body and then asserts no timer is pending — and a
///   `ProviderScope` disposed there cancels drift's query streams, which close
///   on a zero-duration timer. Owning the container here and disposing it in
///   `tearDown` puts that timer outside the check.
void main() {
  late AppDatabase db;

  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ensureStarterCatalog(db);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(Brightness.dark), home: home),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpIndex(WidgetTester tester) =>
      pump(tester, const RegimesScreen());

  Future<void> pumpEditor(WidgetTester tester, String regimeId) =>
      pump(tester, RegimeEditorScreen(regimeId: regimeId));

  testWidgets('index with nothing in it: masthead, empty box, catalog', (
    tester,
  ) async {
    await pumpIndex(tester);

    expect(tester.takeException(), isNull);
    // The header is the screen, not a decoration on top of its content.
    expect(find.text('Regimes'), findsOneWidget);
    // No `Active regime` heading with nothing to put under it.
    expect(find.text('Active regime'), findsNothing);
    expect(find.text('Regime library'), findsOneWidget);
    // The catalog is not a property of any one regime, so it is here even when
    // there is no regime at all.
    expect(find.text('Exercise catalog'), findsOneWidget);
  });

  testWidgets('the active regime is stated by its section, not by a pill', (
    tester,
  ) async {
    final repo = RegimeRepository(db);
    await repo.createRegime('Bench only');
    await repo.createRegime('PPL', activate: false);
    await pumpIndex(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Active regime'), findsOneWidget);
    expect(find.text('Regime library'), findsOneWidget);
    expect(find.text('Bench only'), findsOneWidget);
    expect(find.text('PPL'), findsOneWidget);
    // A badge on one row and not the others is what bent the column.
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('a regime with no days renders, and offers to add one', (
    tester,
  ) async {
    final id = await RegimeRepository(db).createRegime('Bench only');
    await pumpEditor(tester, id);

    expect(tester.takeException(), isNull);
    // Pushed, so the regime's name is the bar's title (THEME §5).
    expect(find.text('Bench only'), findsOneWidget);
    expect(find.text('No days yet'), findsOneWidget);
  });

  testWidgets('a regime with days shows the tabs and the first day', (
    tester,
  ) async {
    final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    final id = await createRegimeFromTemplate(db, ppl, name: 'PPL');
    await pumpEditor(tester, id);

    expect(tester.takeException(), isNull);
    // Every day is a tab, and `Add day` is the last one.
    for (final s in ppl.sessions) {
      expect(find.text(s.name), findsWidgets);
    }
    expect(find.text('Add day'), findsOneWidget);
    // The count is the heading (§7).
    expect(find.textContaining('exercises'), findsWidgets);
  });

  testWidgets('an inactive regime opens without a cycle line', (tester) async {
    final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    final id = await createRegimeFromTemplate(db, ppl, name: 'PPL');
    await RegimeRepository(db).createRegime('Something else');
    await pumpEditor(tester, id);

    expect(tester.takeException(), isNull);
    expect(find.text('Add day'), findsOneWidget);
    // The cycle belongs to the programme being trained, not to this one.
    expect(find.textContaining('Cycle '), findsNothing);
  });

  testWidgets('switching tabs switches the day under them', (tester) async {
    final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    final id = await createRegimeFromTemplate(db, ppl, name: 'PPL');
    await pumpEditor(tester, id);

    await tester.tap(find.text(ppl.sessions[1].name).first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
    expect(find.textContaining('exercises'), findsWidgets);
  });
}
