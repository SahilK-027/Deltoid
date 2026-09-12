import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/domain/plates.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/log/widgets/plate_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plate view reads as three columns — the drawing, the plates for one
/// side, the bar — and says what the rack cannot make per side, because a side
/// is what gets loaded.
void main() {
  Future<void> pump(WidgetTester tester, PlateLoad load) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(child: PlateView(load: load, unit: WeightUnit.kg)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('each plate for one side is a row, and the bar stands apart',
      (tester) async {
    await pump(
      tester,
      const PlateLoad(
        barKg: 20,
        perSide: [(kg: 25, count: 1), (kg: 5, count: 1)],
        remainderKg: 0,
      ),
    );

    expect(find.text('Each side'), findsNothing);
    expect(find.text('1 × 25'), findsOneWidget);
    expect(find.text('1 × 5'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
    expect(find.textContaining('has no plate'), findsNothing);
  });

  testWidgets('a load the rack cannot make says how much is missing a side',
      (tester) async {
    await pump(
      tester,
      const PlateLoad(
        barKg: 20,
        perSide: [(kg: 25, count: 1), (kg: 5, count: 1)],
        remainderKg: 3,
      ),
    );

    expect(find.text('1.5 kg each side has no plate'), findsOneWidget);
  });

  testWidgets('an empty bar drops the list and keeps only the bar',
      (tester) async {
    await pump(
      tester,
      const PlateLoad(barKg: 20, perSide: [], remainderKg: 0),
    );

    expect(find.text('Each side'), findsNothing);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
  });

  testWidgets('a third kind of plate starts a second column, not a third row',
      (tester) async {
    await pump(
      tester,
      const PlateLoad(
        barKg: 20,
        perSide: [
          (kg: 25, count: 2),
          (kg: 20, count: 1),
          (kg: 2.5, count: 1),
        ],
        remainderKg: 0,
      ),
    );

    final first = tester.getTopLeft(find.text('2 × 25'));
    final second = tester.getTopLeft(find.text('1 × 20'));
    final third = tester.getTopLeft(find.text('1 × 2.5'));
    expect(second.dx, first.dx, reason: 'the first two share a column');
    expect(second.dy, greaterThan(first.dy));
    expect(third.dx, greaterThan(first.dx), reason: 'the third moves across');
    expect(third.dy, first.dy, reason: 'and starts at the top');
  });

  testWidgets('a screen reader hears the whole load as one sentence',
      (tester) async {
    await pump(
      tester,
      const PlateLoad(
        barKg: 20,
        perSide: [(kg: 25, count: 2), (kg: 10, count: 1)],
        remainderKg: 0,
      ),
    );

    expect(
      find.bySemanticsLabel(
        '2 times 25 and 10 each side, on a 20 kg bar, 140 kg in all',
      ),
      findsOneWidget,
    );
  });

  testWidgets('every plate a load can hold has its own colour', (tester) async {
    late List<Color> colours;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(builder: (context) {
          colours = [
            for (final kg in const <double>[25, 20, 15, 10, 5, 2.5])
              plateColor(context, kg),
          ];
          return const SizedBox();
        }),
      ),
    );
    expect(colours.toSet(), hasLength(6),
        reason: 'two plates share a swatch in the list');
    expect(colours.last, DeltoidColors.dark.textSecondary,
        reason: 'the 2.5 is the grey of a change plate');
  });

  testWidgets('the bar sits on the line of the first plate', (tester) async {
    await pump(
      tester,
      const PlateLoad(
        barKg: 20,
        perSide: [(kg: 25, count: 1), (kg: 5, count: 1)],
        remainderKg: 0,
      ),
    );
    expect(
      tester.getTopLeft(find.text('20')).dy,
      closeTo(tester.getTopLeft(find.text('1 × 25')).dy, 1),
    );
  });

  testWidgets('an empty bar centres its weight on the drawing', (tester) async {
    await pump(
      tester,
      const PlateLoad(barKg: 20, perSide: [], remainderKg: 0),
    );
    final text = tester.getCenter(find.text('20')).dy;
    final view = tester.getCenter(find.byType(PlateView)).dy;
    expect(text, closeTo(view, 3));
  });
}
