import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/enums.dart';

/// Horizontal strip of every exercise in the workout.
///
/// With one exercise per page, this is the only thing telling you where you are
/// and how much is left — it replaces the "scroll and count the cards" job the
/// vertical list used to do implicitly.
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

  /// Keeps the active chip on screen when the page changes, including when the
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
      height: 46,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: widget.entries.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          if (i == widget.entries.length) {
            return Center(
              child: _Chip(
                onTap: widget.onAdd,
                background: Colors.transparent,
                border: c.border,
                child: Icon(Icons.add, size: 18, color: c.textSecondary),
              ),
            );
          }

          final entry = widget.entries[i];
          final key = _keys.putIfAbsent(i, GlobalKey.new);
          final isCurrent = i == widget.current;
          final skipped = entry.workoutExercise.skipReason != SkipReason.none;
          final total = entry.sets.length;
          final done = entry.sets.where((s) => s.isDone).length;
          final complete = total > 0 && done == total;

          return Center(
            key: key,
            child: _Chip(
              onTap: () => widget.onSelect(i),
              background: isCurrent ? c.accent : c.surface,
              border: isCurrent ? c.accent : c.border,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (complete && !isCurrent) ...[
                    Icon(Icons.check, size: 14, color: c.positive),
                    const SizedBox(width: Space.xs),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      entry.exercise.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.titleSmall?.copyWith(
                        color: isCurrent
                            ? c.onAccent
                            : (skipped ? c.textTertiary : c.textSecondary),
                        decoration:
                            skipped ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (!skipped && total > 0) ...[
                    const SizedBox(width: Space.sm),
                    Text(
                      '$done/$total',
                      style: context.t.labelSmall?.copyWith(
                        color: isCurrent ? c.onAccent : c.textTertiary,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.child,
    required this.onTap,
    required this.background,
    required this.border,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: border),
        ),
        child: child,
      ),
    );
  }
}
