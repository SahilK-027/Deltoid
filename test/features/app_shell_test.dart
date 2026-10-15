import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/monitoring_icon.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/history/history_screen.dart';
import 'package:deltoid/features/more/more_screen.dart';
import 'package:deltoid/features/progress/progress_screen.dart';
import 'package:deltoid/features/regime/regimes_screen.dart';
import 'package:deltoid/features/shell/app_shell.dart';
import 'package:deltoid/features/home/home_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The five-tab shell, pumped against a real database.
///
/// Harness rules are `more_screen_test.dart`'s: never `pumpAndSettle`, and the
/// container outlives the tree so drift's stream-closing timer lands outside
/// the harness's pending-timer check.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  const labels = ['Home', 'Regimes', 'Progress', 'History', 'More'];
  const screens = [
    HomeScreen,
    RegimesScreen,
    ProgressScreen,
    HistoryScreen,
    MoreScreen,
  ];

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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const AppShell(),
        ),
      ),
    );
    await settle(tester);
  }

  /// The bar's own label for [label]: a masthead can carry the same word, so
  /// the label is the one lowest on the screen.
  Element navLabel(WidgetTester tester, String label) {
    final hits = find.text(label).evaluate().toList()
      ..sort(
        (a, b) => tester
            .getCenter(find.byElementPredicate((e) => e == a))
            .dy
            .compareTo(
              tester.getCenter(find.byElementPredicate((e) => e == b)).dy,
            ),
      );
    return hits.last;
  }

  Offset centreOf(WidgetTester tester, Element e) =>
      tester.getCenter(find.byElementPredicate((x) => x == e));

  FontWeight? weightOf(Element e) => DefaultTextStyle.of(e).style.fontWeight;

  testWidgets('five tabs, in THEME order, Home selected on launch', (
    tester,
  ) async {
    await pump(tester);
    expect(tester.takeException(), isNull);

    final xs = [for (final l in labels) centreOf(tester, navLabel(tester, l)).dx];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Workouts'), findsNothing);

    expect(weightOf(navLabel(tester, 'Home')), FontWeight.w700);
    for (final l in labels.skip(1)) {
      expect(weightOf(navLabel(tester, l)), FontWeight.w500, reason: l);
    }
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pending_outlined), findsOneWidget);
    expect(find.byType(MonitoringIcon), findsOneWidget);
  });

  testWidgets('each tab opens its own screen and takes the selected style', (
    tester,
  ) async {
    await pump(tester);

    for (var i = labels.length - 1; i >= 0; i--) {
      await tester.tap(find.byElementPredicate(
        (e) => e == navLabel(tester, labels[i]),
      ));
      await settle(tester);
      expect(tester.takeException(), isNull);

      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.index, i, reason: labels[i]);
      expect(stack.children[i].runtimeType, screens[i], reason: labels[i]);
      for (var j = 0; j < labels.length; j++) {
        expect(
          weightOf(navLabel(tester, labels[j])),
          j == i ? FontWeight.w700 : FontWeight.w500,
          reason: '${labels[j]} with ${labels[i]} open',
        );
      }
    }

    // More's selected glyph is the filled circle.
    await tester.tap(find.byElementPredicate(
      (e) => e == navLabel(tester, 'More'),
    ));
    await settle(tester);
    expect(find.byIcon(Icons.pending), findsOneWidget);
    expect(find.byIcon(Icons.pending_outlined), findsNothing);
  });

  testWidgets('Progress is its masthead and nothing it does not hold', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const ProgressScreen(),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Progress'), findsOneWidget);
    // The eyebrow names cards the page does not hold yet.
    expect(find.text('CYCLES AND VOLUME'), findsNothing);
  });
}
