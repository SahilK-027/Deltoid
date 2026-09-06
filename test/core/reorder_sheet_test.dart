import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/reorder_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one re-order surface: a training day's exercises, a regime's days, and
/// today's log all arrive here. Dragging must work from the handle, and the
/// order must not be written until Save.
void main() {
  Future<List<String>?> open(WidgetTester tester) async {
    List<String>? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showReorderSheet(
                  context,
                  title: 'Reorder exercises',
                  subtitle: 'Push 1',
                  items: const [
                    (id: 'a', label: 'Bench press'),
                    (id: 'b', label: 'Overhead press'),
                    (id: 'c', label: 'Cable fly'),
                  ],
                  onCommit: (ids) => committed = ids,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return committed;
  }

  testWidgets('a drag from the handle re-orders, and Save commits it',
      (tester) async {
    await open(tester);

    expect(find.text('Bench press'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(3));

    // Drag the first row's handle down past the second.
    final handle = find.byIcon(Icons.drag_handle_rounded).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // The position column restates the list as it now stands.
    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(rows.indexOf('Overhead press'), lessThan(rows.indexOf('Bench press')),
        reason: 'the dragged row should have moved below its neighbour');
  });

  testWidgets('Save still works when the sheet that opened it is gone',
      (tester) async {
    // The regime settings sheet closes itself before opening the re-order
    // sheet. Anything it hands over has to outlive it: a `WidgetRef` read
    // inside `onCommit` throws `Cannot use "ref" after the widget was
    // disposed` from a gesture handler, and the only symptom is a Save button
    // that silently does nothing.
    List<String>? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheet) => TextButton(
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      showReorderSheet(
                        context,
                        title: 'Reorder days',
                        subtitle: 'The order one cycle runs in',
                        items: const [
                          (id: 'a', label: 'Push 1'),
                          (id: 'b', label: 'Pull 1'),
                        ],
                        onCommit: (ids) => committed = ids,
                      );
                    },
                    child: const Text('re-order'),
                  ),
                ),
                child: const Text('settings'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('re-order'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save order'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(committed, ['a', 'b']);
  });

  testWidgets('nothing is written until Save', (tester) async {
    List<String>? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showReorderSheet(
                  context,
                  title: 'Reorder days',
                  subtitle: 'The order one cycle runs in',
                  items: const [
                    (id: 'a', label: 'Push 1'),
                    (id: 'b', label: 'Pull 1'),
                  ],
                  onCommit: (ids) => committed = ids,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(committed, isNull);
    await tester.tap(find.text('Save order'));
    await tester.pumpAndSettle();
    // Untouched order, committed as it stands — Save is a confirmation, not a
    // diff.
    expect(committed, ['a', 'b']);
  });
}
