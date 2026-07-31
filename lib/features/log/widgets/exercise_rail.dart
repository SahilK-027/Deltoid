import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/enums.dart';

/// Where you are in the workout, and how much of it is left.
///
/// Monogram tiles, not names and not bare numbers. Printing every name here
/// while the header below printed the current one again was the same words
/// twice on one screen — and the rail was the copy you couldn't read, since it
/// was ellipsised to fit. Plain numbers fixed the duplication but made the
/// tiles say nothing at all. Initials do both jobs: `BP` is recognisable once
/// you know the session, and it costs a fifth of the width of the name.
///
/// This is the reference's photo-thumbnail rail with the photo removed — it
/// falls back to exactly this when an exercise has no image, and every one of
/// ours does (§0: no exercise photography, ever).
///
/// Long-press any tile to drag the exercise into a different place in the
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
    const tab = 60.0;
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
      height: 68,
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
                    label: monogramFor(entry.exercise.name),
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
                height: 68,
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

/// Two initials from an exercise name: `Barbell Bench Press` → `BB`,
/// `Pull-up` → `PU`. Two words give one letter each; one word gives its first
/// two, which is what keeps `Squat` and `Sumo Deadlift` apart.
String monogramFor(String name) {
  final words = name
      .split(RegExp(r'[\s\-/]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length == 1 ? w : w.substring(0, 2)).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// One exercise: its initials, its state, and a 3px rule under the one you're
/// on.
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

    // The tile you are on lifts onto a surface; the rest sit on the page.
    // Completion is the corner tick, not an inverted tile — inverting it made
    // a finished exercise louder than the one being worked on.
    final Color fill;
    final Color ink;
    if (selected) {
      fill = c.surfaceHigh;
      ink = c.textPrimary;
    } else {
      fill = Colors.transparent;
      ink = skipped ? c.textTertiary : c.textSecondary;
    }

    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              width: 48,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    label,
                    style: context.t.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  // A finished exercise carries a tick in the corner rather
                  // than losing its initials to one.
                  if (complete)
                    Positioned(
                      right: -2,
                      top: -1,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 11,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            AnimatedContainer(
              duration: Motion.fast,
              height: 3,
              width: selected ? 28 : 0,
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
