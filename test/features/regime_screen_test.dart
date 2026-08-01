import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/regime/regime_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The programme editor, pumped against a real database.
///
/// It went blank on the device twice — once because the day tabs asked for an
/// infinite width, once on a regime with no days in it — and both times the
/// analyzer and every other test were perfectly happy. A screen that renders
/// nothing is a test this file should own.
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

  Future<void> pumpRegime(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const RegimeScreen(),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('with no regime at all: masthead, then the empty state', (
    tester,
  ) async {
    await pumpRegime(tester);

    expect(tester.takeException(), isNull);
    // The header is the screen, not a decoration on top of its content.
    expect(find.text('Regime'), findsOneWidget);
    expect(find.text('No regime yet'), findsOneWidget);
  });

  testWidgets('a regime with no days renders, and offers to add one', (
    tester,
  ) async {
    await RegimeRepository(db).createRegime('Bench only');
    await pumpRegime(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('BENCH ONLY'), findsOneWidget);
    expect(find.text('No days yet'), findsOneWidget);
  });

  testWidgets('a regime with days shows the tabs and the first day', (
    tester,
  ) async {
    final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    await createRegimeFromTemplate(db, ppl, name: 'PPL');
    await pumpRegime(tester);

    expect(tester.takeException(), isNull);
    // Every day is a tab, and `Add day +` is the last one.
    for (final s in ppl.sessions) {
      expect(find.text(s.name), findsWidgets);
    }
    expect(find.text('Add day  +'), findsOneWidget);
    // The count is the heading (§7).
    expect(find.textContaining('exercises'), findsWidgets);
  });

  testWidgets('switching tabs switches the day under them', (tester) async {
    final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    await createRegimeFromTemplate(db, ppl, name: 'PPL');
    await pumpRegime(tester);

    await tester.tap(find.text(ppl.sessions[1].name).first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
    expect(find.textContaining('exercises'), findsWidgets);
  });
}
