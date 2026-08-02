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

  /// The order the finger just put things in, held until the database agrees.
  ///
  /// Without it a drag ends by snapping back: `ReorderableListView` is built
  /// straight off the stream, so the frame after the drop still carries the old
  /// order, and the tab jumps home and then jumps again when the write lands.
  /// Two jumps to express one move, both of them backwards.
  List<String>? _pending;

  @override
  void didUpdateWidget(ExerciseRail old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _revealCurrent();
    // The write has come back around: whatever the stream now says is the
    // truth, and the optimistic copy is spent.
    if (_pending != null && !_sameOrder(old.entries, widget.entries)) {
      _pending = null;
    }
  }

  static bool _sameOrder(List<ExerciseEntry> a, List<ExerciseEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].workoutExercise.id != b[i].workoutExercise.id) return false;
    }
    return true;
  }

  /// What to draw: the finger's order while one is in flight, the database's
  /// otherwise.
  List<ExerciseEntry> get _entries {
    final pending = _pending;
    if (pending == null) return widget.entries;
    final byId = {
      for (final e in widget.entries) e.workoutExercise.id: e,
    };
    final ordered = [for (final id in pending) ?byId[id]];
    // An exercise added or removed under a drag invalidates the guess.
    return ordered.length == widget.entries.length ? ordered : widget.entries;
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
    const tab = _Tab.slot;
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
    final ids = [for (final e in _entries) e.workoutExercise.id];
    ids.insert(to, ids.removeAt(from));
    setState(() => _pending = ids);
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
            child: Stack(
              children: [
                ReorderableListView.builder(
              scrollController: _scroll,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(left: Space.gutter),
              itemCount: _entries.length,
              onReorder: _handleReorder,
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                child: Opacity(opacity: 0.9, child: child),
              ),
                  itemBuilder: (context, i) {
                    final entry = _entries[i];
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
                // Nothing said the rail kept going. A tile cut by a fade at
                // the edge is the only thing that reads as "there is more
                // over here" without adding a control to press.
                //
                // Narrow and short of opaque. At 32dp running to full `bg` it
                // stopped reading as an edge and started reading as a drop
                // shadow under the `+` beside it — a smudge on a flat theme
                // that has no shadows in it anywhere (THEME §1).
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 18,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            c.bg.withValues(alpha: 0),
                            c.bg.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
/// `Pull-up` → `PU`, `Skullcrusher (EZ)` → `SK`.
///
/// A parenthesised qualifier is dropped before anything else — it names the
/// equipment, not the movement, and `Skullcrusher (EZ)` took its second letter
/// from the bracket and came out as `S(`. Punctuation goes too, so a stray
/// hyphen can't become an initial. One word gives its first two letters, which
/// is what keeps `Squat` apart from `Sumo Deadlift`.
String monogramFor(String name) {
  final words = name
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  // A leading number is a measurement, not a name: `45° Cable Rear Delt` is a
  // cable row, not a `4C`.
  if (words.length > 1) {
    words.removeWhere((w) => int.tryParse(w) != null);
  }
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

  /// The tile, and the gap to the next one. Left-aligned inside the slot, so
  /// the difference between the two is the gap and nothing else — and the
  /// scroll that keeps the current tab on screen measures in these.
  static const tile = 48.0;
  static const slot = tile + Space.sm;

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
      // Inactive tiles carry a dull fill of their own. Transparent ones left
      // the rail looking like it ended at the last label, so there was no way
      // to tell more exercises were sitting off the right edge until you
      // happened to scroll — and a tile half-cut by the edge is the only thing
      // that says "keep going" without a control to press.
      fill = c.surfaceHigh.withValues(alpha: 0.5);
      ink = skipped || complete ? c.textTertiary : c.textSecondary;
    }

    // Left-aligned inside the tab, not centred. A 48dp tile centred in a 60dp
    // slot starts 6dp inside the rail's padding, so the first tile sat 6dp to
    // the right of the exercise name under it and of every other thing on the
    // page — the one edge on this screen you can actually see is not straight.
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: slot,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: Motion.fast,
                  width: tile,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    label,
                    style: context.t.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                // Outside the tile, not over the initials. Sitting on top of
                // them turned `CF` into an unreadable blob, and the letters
                // are the only thing identifying the exercise.
                if (complete)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.bg, width: 2),
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
            const SizedBox(height: Space.xs),
            // Centred under the tile, which is no longer centred in the slot.
            SizedBox(
              width: tile,
              child: Center(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  height: 3,
                  width: selected ? 28 : 0,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
