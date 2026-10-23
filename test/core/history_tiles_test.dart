import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';

/// History's two marks: the calendar-page tile and the deload icon that names
/// itself on tap.
void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  group('RevealPill', () {
    testWidgets('shows its icon alone until tapped', (tester) async {
      await tester.pumpWidget(host(
        const RevealPill('Deload', icon: Icons.trending_down, color: Colors.orange),
      ));
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
      expect(find.text('Deload'), findsNothing);
    });

    testWidgets('names itself for two seconds, then folds back', (tester) async {
      await tester.pumpWidget(host(
        const RevealPill('Deload', icon: Icons.trending_down, color: Colors.orange),
      ));
      await tester.tap(find.byType(RevealPill));
      await tester.pumpAndSettle();
      expect(find.text('Deload'), findsOneWidget);

      // pumpAndSettle has already run the 220 ms the label takes to open.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Deload'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Deload'), findsNothing);
    });

    testWidgets('a second tap restarts the hold', (tester) async {
      await tester.pumpWidget(host(
        const RevealPill('Deload', icon: Icons.trending_down, color: Colors.orange),
      ));
      await tester.tap(find.byType(RevealPill));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(find.byType(RevealPill));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Deload'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Deload'), findsNothing);
    });

    testWidgets('claims the tap from the row it sits in', (tester) async {
      var opened = 0;
      await tester.pumpWidget(host(
        GestureDetector(
          onTap: () => opened++,
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: RevealPill(
              'Deload',
              icon: Icons.trending_down,
              color: Colors.orange,
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(RevealPill));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(find.text('Deload'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a screen reader hears the word while only the icon shows',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        const RevealPill('Deload', icon: Icons.trending_down, color: Colors.orange),
      ));
      expect(find.bySemanticsLabel('Deload'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('leaves no timer behind when disposed mid-hold', (tester) async {
      await tester.pumpWidget(host(
        const RevealPill('Deload', icon: Icons.trending_down, color: Colors.orange),
      ));
      await tester.tap(find.byType(RevealPill));
      await tester.pump();
      await tester.pumpWidget(host(const SizedBox()));
      // A live timer at the end of a test fails it; reaching here clean is the
      // assertion.
    });

    testWidgets('appears without the slide when motion is reduced',
        (tester) async {
      await tester.pumpWidget(host(
        const RevealPill('Deload', icon: Icons.trending_down, color: Colors.orange),
        reduceMotion: true,
      ));
      await tester.tap(find.byType(RevealPill));
      await tester.pump();
      expect(find.byType(AnimatedSize), findsNothing);
      expect(find.text('Deload'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('DateTile', () {
    testWidgets('draws the weekday over the day at a fixed size', (tester) async {
      await tester.pumpWidget(host(
        const DateTile(day: '23', weekday: 'Fri', hue: Colors.blue),
      ));
      expect(find.text('23'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);

      final size = tester.getSize(find.byType(DateTile));
      expect(size.width, DateTile.width);
      // The page plus the tabs rising above it.
      expect(size.height, greaterThan(DateTile.pageHeight));
      expect(
        tester.getTopLeft(find.text('Fri')).dy,
        lessThan(tester.getTopLeft(find.text('23')).dy),
      );
    });

    testWidgets('a two-digit day fits without overflow', (tester) async {
      await tester.pumpWidget(host(
        const DateTile(day: '28', weekday: 'Wed', hue: Colors.orange),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
