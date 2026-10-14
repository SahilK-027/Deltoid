import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'primitives.dart';

/// Puts a short list in a new order, by dragging it.
///
/// Not a pair of ⌃ / ⌄ buttons per row. The argument for those is that
/// `ReorderableDragStartListener` is an immediate vertical drag which, nested
/// in a scrollable, competes with the page and loses — true of a drag started
/// from anywhere on the row, and not true of one started from a handle:
/// the handle owns the vertical gesture, the rest of the row still scrolls, and
/// `ReorderableListView` brings its own auto-scroll to carry a row past the
/// fold. So the affordance is the thing every list in every other app uses.
///
/// The order is committed on Save, not per move: a reorder is one decision made
/// out of several movements, and writing each one would push a stream update
/// per drag into whatever is watching underneath.
Future<void> showReorderSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<({String id, String label})> items,
  required ValueChanged<List<String>> onCommit,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _ReorderSheet(
      title: title,
      subtitle: subtitle,
      items: items,
      onCommit: onCommit,
    ),
  );
}

class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.onCommit,
  });

  final String title;
  final String subtitle;
  final List<({String id, String label})> items;
  final ValueChanged<List<String>> onCommit;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final _order = [...widget.items];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      contentPadding: EdgeInsets.zero,
      footer: PrimaryButton(
        label: 'Save order',
        onPressed: () {
          widget.onCommit([for (final e in _order) e.id]);
          Navigator.of(context).pop();
        },
      ),
      children: [
        // Shrink-wrapped: a sheet is as tall as its content, and a
        // `ReorderableListView` inside one has no height of its own to inherit.
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: Space.md),
          itemCount: _order.length,
          onReorder: (from, to) => setState(() {
            // The framework reports the insertion slot, which is one past the
            // target when dragging downwards.
            if (to > from) to -= 1;
            _order.insert(to, _order.removeAt(from));
          }),
          proxyDecorator: (child, index, animation) => Material(
            color: c.surfaceHigh,
            child: child,
          ),
          itemBuilder: (context, i) => AppRow(
            key: ValueKey(_order[i].id),
            title: _order[i].label,
            // The number is the point of a re-order screen: it says what the
            // list will become, before it is committed.
            leading: SizedBox(
              width: 28,
              child: Text(
                '${i + 1}',
                style: context.t.labelLarge?.copyWith(color: c.textSecondary),
              ),
            ),
            trailing: ReorderableDragStartListener(
              index: i,
              child: Padding(
                // A 44pt target around a 24pt glyph — this is the one control
                // on the row and it is grabbed rather than tapped.
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: Space.md,
                ),
                child: Icon(Icons.drag_indicator_rounded, color: c.textTertiary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
