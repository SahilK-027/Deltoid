import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/features/regime/exercise_catalog_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalog, and the one thing about it that is a gesture rather than a
/// query: the muscle on a row is the filter.
///
/// Same two harness rules as `regime_screen_test.dart` — never `pumpAndSettle`
/// against a watched query, and the container outlives the tree.
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

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const ExerciseCatalogScreen(),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The chips in the strip above the list are the same widget as the chips on
  /// the rows, so a row's chip is found by the muscle it names *and* by sitting
  /// inside an `AppRow`.
  Finder rowChip(MuscleGroup m) => find.descendant(
    of: find.byType(AppRow),
    matching: find.widgetWithText(AppChip, m.label),
  );

  testWidgets('every row wears its muscle as a chip', (tester) async {
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(rowChip(MuscleGroup.chest), findsWidgets);
  });

  testWidgets('tapping a row chip filters to that muscle, and tapping the '
      'same one again clears it', (tester) async {
    await pump(tester);

    final backs = tester
        .widgetList<AppChip>(rowChip(MuscleGroup.back))
        .length;
    expect(backs, greaterThan(0));

    await tester.tap(rowChip(MuscleGroup.back).first);
    await settle(tester);

    expect(tester.takeException(), isNull);
    // Nothing filed under another muscle survives the filter.
    expect(rowChip(MuscleGroup.chest), findsNothing);
    expect(rowChip(MuscleGroup.back), findsWidgets);

    await tester.tap(rowChip(MuscleGroup.back).first);
    await settle(tester);

    // A second tap is the way back out — the chip is a toggle, not a mode.
    expect(rowChip(MuscleGroup.chest), findsWidgets);
  });

  testWidgets('a row chip does not open the exercise', (tester) async {
    await pump(tester);

    await tester.tap(rowChip(MuscleGroup.back).first);
    await settle(tester);

    // The exercise screen would have pushed its own scaffold over this one.
    expect(find.byType(ExerciseCatalogScreen), findsOneWidget);
    expect(find.text('Exercises'), findsOneWidget);
  });
}
