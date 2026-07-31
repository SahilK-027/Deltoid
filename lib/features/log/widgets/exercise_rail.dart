import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/enums.dart';

/// Where you are in the workout, and how much of it is left.
///
/// Numbered rather than named. The rail used to print every exercise's name
/// while the header below printed the current one again — the same words twice
/// on one screen, and the rail was the copy you couldn't read properly because
/// it was ellipsised to fit. The name belongs to the header; this belongs to
/// navigation, and a number does that in a fifth of the width.
///
/// Long-press any tab to drag the exercise into a different place in the
/// session.
class ExerciseRail extends StatefulWidget {
  const ExerciseRail({
    super.key,
    required this.entries,
    required this.current,
    required this.onSelect,
    required this.onAdd,
    required this.onReorder,
  });

  final List<ExerciseEntry> entries;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  /// New order of `workoutExercise.id`, after a drag.
  final ValueChanged<List<String>> onReorder;

  @override
  State<ExerciseRail> createState() => _ExerciseRailState();
}

class _ExerciseRailState extends State<ExerciseRail> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(ExerciseRail old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _revealCurrent();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  /// Keeps the active tab on screen when the page changes, including when the
  /// keypad's "Next" walks past the end of an exercise on its own.
  void _revealCurrent() {
    if (!_scroll.hasClients) return;
    const tab = 52.0;
    final target = (widget.current * tab) -
        (_scroll.position.viewportDimension / 2) +
        (tab / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: Motion.base,
      curve: Motion.curve,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _handleReorder(int from, int to) {
    // ReorderableListView reports the insertion slot, which is one past the
    // target when dragging forwards.
    if (to > from) to -= 1;
    final ids = [for (final e in widget.entries) e.workoutExercise.id];
    ids.insert(to, ids.removeAt(from));
    widget.onReorder(ids);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _scroll,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(left: Space.gutter),
              itemCount: widget.entries.length,
              onReorder: _handleReorder,
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                child: Opacity(opacity: 0.9, child: child),
              ),
              itemBuilder: (context, i) {
                final entry = widget.entries[i];
                final skipped =
                    entry.workoutExercise.skipReason != SkipReason.none;
                final total = entry.sets.length;
                final done = entry.sets.where((s) => s.isDone).length;
                final complete = total > 0 && done == total && !skipped;

                return ReorderableDelayedDragStartListener(
                  key: ValueKey(entry.workoutExercise.id),
                  index: i,
                  child: _Tab(
                    label: '${i + 1}',
                    selected: i == widget.current,
                    complete: complete,
                    skipped: skipped,
                    onTap: () => widget.onSelect(i),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: Space.gutter),
            child: Pressable(
              onTap: widget.onAdd,
              child: SizedBox(
                width: 40,
                height: 52,
                child: Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One exercise: its number, its state, and a 3px rule under the one you're on.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.complete,
    required this.skipped,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool complete;
  final bool skipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // A finished exercise reads as finished from the rail without being
    // counted again: filled disc, dark tick. The state was a 14px grey
    // check before, which is invisible on a bench.
    final Color fill;
    final Color ink;
    if (selected) {
      fill = c.surfaceHigh;
      ink = c.textPrimary;
    } else if (complete) {
      fill = c.accent;
      ink = c.onAccent;
    } else {
      fill = Colors.transparent;
      ink = skipped ? c.textTertiary : c.textSecondary;
    }

    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: complete && !selected
                  ? Icon(Icons.check_rounded, size: 18, color: ink)
                  : Text(
                      label,
                      style: context.t.bodySmall?.copyWith(
                        color: ink,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        decoration:
                            skipped ? TextDecoration.lineThrough : null,
                      ),
                    ),
            ),
            const SizedBox(height: Space.xs),
            AnimatedContainer(
              duration: Motion.fast,
              height: 3,
              width: selected ? 24 : 0,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
