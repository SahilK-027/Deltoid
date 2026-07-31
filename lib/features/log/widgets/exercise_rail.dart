import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/enums.dart';

/// Horizontal strip of every exercise in the workout.
///
/// With one exercise per page, this is the only thing telling you where you are
/// and how much is left — it replaces the "scroll and count the cards" job the
/// vertical list used to do implicitly.
///
/// Drawn as tabs with an underline rather than the thumbnails the language
/// specifies: this app has no exercise photography, and a rail of two-letter
/// monograms would take the same room while telling you less than the name
/// does. The underline carries the state that the pill and its accent fill used
/// to.
class ExerciseRail extends StatefulWidget {
  const ExerciseRail({
    super.key,
    required this.entries,
    required this.current,
    required this.onSelect,
    required this.onAdd,
  });

  final List<ExerciseEntry> entries;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  State<ExerciseRail> createState() => _ExerciseRailState();
}

class _ExerciseRailState extends State<ExerciseRail> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};

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
    final key = _keys[widget.current];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: Motion.base,
      curve: Motion.curve,
      alignment: 0.5,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: widget.entries.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: Space.lg),
        itemBuilder: (context, i) {
          if (i == widget.entries.length) {
            return _Tab(
              onTap: widget.onAdd,
              selected: false,
              child: Icon(Icons.add_rounded, size: 18, color: c.textSecondary),
            );
          }

          final entry = widget.entries[i];
          final key = _keys.putIfAbsent(i, GlobalKey.new);
          final isCurrent = i == widget.current;
          final skipped = entry.workoutExercise.skipReason != SkipReason.none;
          final total = entry.sets.length;
          final done = entry.sets.where((s) => s.isDone).length;
          final complete = total > 0 && done == total;

          return _Tab(
            key: key,
            onTap: () => widget.onSelect(i),
            selected: isCurrent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (complete && !skipped) ...[
                  Icon(Icons.check_rounded, size: 14, color: c.textSecondary),
                  const SizedBox(width: Space.xs),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    entry.exercise.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.titleMedium?.copyWith(
                      color: isCurrent
                          ? c.textPrimary
                          : (skipped ? c.textTertiary : c.textSecondary),
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                // Only the exercises you are not looking at need their progress
                // spelled out. The current one has `Set n of m` in the header
                // directly below, and saying it twice in two lines is the kind
                // of restatement that makes a screen feel automated.
                if (!isCurrent && !skipped && total > 0 && !complete) ...[
                  const SizedBox(width: Space.sm),
                  Text(
                    '$done/$total',
                    style: context.t.labelSmall?.copyWith(
                      color: c.textTertiary,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A tab: content, then a 3px rule under it. White under the exercise you are
/// on, a grey step under the rest — the same underline the rest of the app uses
/// to mean "this one".
class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.child,
    required this.onTap,
    required this.selected,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: child,
          ),
          AnimatedContainer(
            duration: Motion.fast,
            height: 3,
            width: selected ? 28 : 16,
            decoration: BoxDecoration(
              color: selected ? c.accent : c.surfaceHighest,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
        ],
      ),
    );
  }
}
