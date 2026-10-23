part of '../log_screen.dart';

/// What to do about a session with sets still open.
///
/// Three answers, not two. A two-button confirm built out of a paragraph of
/// text runs the counts, the exercise list and the caveat together in one
/// message and offers only "Finish anyway" and "Keep logging" — with no way to
/// throw the session away from here at all, short of un-ticking every set to
/// reach the "nothing logged" prompt.
Future<_FinishChoice?> _confirmEarlyFinish(
  BuildContext context, {
  required int done,
  required int total,
  required List<({String name, int done, int total})> unfinished,
}) {
  return showAppSheet<_FinishChoice>(
    context,
    builder: (sheet) {
      final c = sheet.c;
      return AppSheet(
        title: 'Finish with sets left?',
        subtitle: '${setsOfTotal(done, total)} logged',
        footer: Column(
          children: [
            PrimaryButton(
              label: 'Finish session',
              onPressed: () => Navigator.of(sheet).pop(_FinishChoice.finish),
            ),
            const SizedBox(height: Space.sm),
            SecondaryButton(
              label: 'Keep logging',
              onPressed: () =>
                  Navigator.of(sheet).pop(_FinishChoice.keepLogging),
            ),
          ],
        ),
        children: [
          ListCard(
            children: [
              for (final e in unfinished)
                AppRow(
                  title: e.name,
                  trailing: Text(
                    '${e.done} of ${e.total}',
                    style: sheet.t.labelLarge?.copyWith(color: c.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(
            // Not "empty", which costs a set: a row with a weight typed into
            // it but never ticked is thrown away too, and "empty" promises
            // otherwise. Unticked is the rule everywhere else —
            // `completeWorkout` tombstones on `isDone`, not on blankness.
            'Any set you did not tick is discarded. The session is saved with '
            'exactly what you did.',
            style: sheet.t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          Center(
            child: Pressable(
              onTap: () => Navigator.of(sheet).pop(_FinishChoice.discard),
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Text(
                  'Discard this session',
                  style: sheet.t.titleMedium?.copyWith(color: c.negative),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// A run of rows that share one index chip.
///
/// A plain set is a group of one. Consecutive drop sets are a group of several:
/// they belong to the set above them, so they get a single `D` chip with a
/// spine running down beside them and a `+` at its foot to add another.
class _SetGroupData {
  const _SetGroupData(this.sets, this.positions, this.label, this.isDrop);

  final List<SetLog> sets;

  /// Each set's index in the exercise, needed to line a row up with its ghost.
  final List<int> positions;

  final String label;
  final bool isDrop;
}

/// Splits an exercise's sets into rows-with-a-chip and their drop legs.
///
/// A leg is a set whose `parentSetId` names the set above it. Grouping by
/// adjacency instead — every run of consecutive `drop` rows — could not tell
/// one drop set with two legs from two drop sets side by side, so converting
/// two sets in a row merged them into one.
/// Which set of how many, for one exercise: the number on the log's header and
/// the number in the lock-screen line.
///
/// **One computation, because it is one fact** (RULES § 6). Warm-ups are not
/// set 1 and a drop run is one set rather than three, so counting rows shifts
/// every number away from the programme it came from — and two screens
/// counting rows differently is how the header and the notification end up
/// disagreeing about which set you are on.
///
/// Returns `(position, counted)`, where position is the set now being worked
/// and never runs past the last one.
(int, int) setPosition(List<SetLog> sets) {
  final counted = _groupSets(
    sets,
  ).where((g) => g.sets.first.setType != SetType.warmup).toList();
  final done = counted.where((g) => g.sets.every((s) => s.isDone)).length;
  return (math.min(done + 1, counted.length), counted.length);
}

List<_SetGroupData> _groupSets(List<SetLog> sets) {
  final at = {for (var i = 0; i < sets.length; i++) sets[i].id: i};

  /// A row that carries a chip of its own.
  ///
  /// Adjacency is not part of this. Legs were collected by walking forward from
  /// the head and stopping at the first row that was not its child, so a leg
  /// that ended up anywhere else — an orphan whose head was deleted, a leg of a
  /// leg — was skipped by the loop below *and* by the head that never reached
  /// it, and vanished from the table while still sitting in the database.
  bool isHead(SetLog s) {
    final parent = s.parentSetId;
    if (parent == null) return true;
    final i = at[parent];
    return i == null || sets[i].parentSetId != null;
  }

  final legsOf = <String, List<int>>{};
  for (var i = 0; i < sets.length; i++) {
    if (isHead(sets[i])) continue;
    legsOf.putIfAbsent(sets[i].parentSetId!, () => <int>[]).add(i);
  }

  final groups = <_SetGroupData>[];
  var counted = 0;

  for (var i = 0; i < sets.length; i++) {
    final set = sets[i];
    if (!isHead(set)) continue; // collected with its head

    final positions = <int>[i, ...?legsOf[set.id]];
    final legs = [for (final p in positions) sets[p]];

    final isDrop = set.setType == SetType.drop || legs.length > 1;
    final label = switch (set.setType) {
      SetType.warmup => 'W',
      // A drop is a set you dropped weight inside, so it takes a number of
      // its own — the reference numbers W, D, 2.
      SetType.drop => 'D',
      _ => '',
    };
    if (set.setType != SetType.warmup) counted++;

    groups.add(
      _SetGroupData(
        legs,
        positions,
        label.isEmpty ? '$counted' : label,
        isDrop,
      ),
    );
  }
  return groups;
}

class _SetGroup extends ConsumerWidget {
  const _SetGroup({
    required this.group,
    required this.entry,
    required this.dayKey,
    required this.unit,
    required this.editing,
    required this.partialShownFor,
    required this.partialClosedFor,
    required this.partialEditing,
    required this.buffer,
    required this.openSwipe,
    required this.onEdit,
    required this.onEditPartial,
    required this.rowKeyFor,
    required this.onToggleDone,
  });

  final _SetGroupData group;
  final ExerciseEntry entry;

  /// The day the session is logged on, which is the day its sets are scored on.
  final int dayKey;
  final WeightUnit unit;
  final EditTarget? editing;

  /// The set showing its partial half, and whether the digits are going into
  /// that half rather than the reps.
  final String? partialShownFor;
  final String? partialClosedFor;
  final bool partialEditing;

  final ValueListenable<String> buffer;

  /// The one row swiped open across the whole screen.
  final ValueNotifier<String?> openSwipe;
  final void Function(SetLog, SetField) onEdit;
  final void Function(SetLog) onEditPartial;
  final GlobalKey Function(String setId) rowKeyFor;
  final void Function(SetLog, bool) onToggleDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefill = ref
        .watch(workoutPrefillProvider(entry.workoutExercise.workoutId))
        .valueOrNull?[entry.exercise.id];
    // The figure the bodyweight pill above the table prints, so the done mark
    // and the pill never disagree about what the set was scored on.
    final bodyweightKg = bodyweightBasis(
      dayKey,
      ref.watch(bodyweightSeriesProvider).valueOrNull ?? const [],
    ).kg;
    final repo = ref.read(trainingRepositoryProvider);
    final last = group.sets.length - 1;

    void addLeg() => repo.addDropLeg(
      entry.workoutExercise.id,
      headSetId: group.sets.first.id,
    );

    // One index cell per row, always the same height as the row beside it.
    // The previous version stacked chip / spine / plus in a column of its own
    // and let [IntrinsicHeight] size the group, which stretched the first row
    // taller than the rest and slid every chip out of line with its row.
    //
    // No row wash. A completed set is said by its fields and its checkbox
    // (THEME → Components); a full-width band behind the row was the loudest thing in
    // the table, and the table is mostly completed rows by the end.
    return Column(
      children: [
        for (var k = 0; k < group.sets.length; k++)
          // The whole row travels — chip, capsule segment and fields together.
          // Wrapped around the fields alone this slid the numbers out from
          // under a chip that stayed put, which reads as the table coming
          // apart rather than as one row moving aside.
          SwipeToDelete(
            rowId: group.sets[k].id,
            open: openSwipe,
            onDelete: () => repo.deleteSets(_deleteIds(k)),
            child: Row(
              children: [
                _IndexCell(
                  // The spine only exists to tie a drop run together. A group of
                  // one head keeps its square foot for the `+` row below it.
                  spine: !group.isDrop
                      ? _Spine.none
                      : (k == 0
                            ? _Spine.top
                            : (k == last ? _Spine.bottom : _Spine.middle)),
                  child: switch (k) {
                    0 => SetIndexChip(
                      type: group.sets.first.setType,
                      label: group.label,
                      done: group.sets.first.isDone,
                      onTap: () => _openActions(context, ref, k),
                    ),
                    // The `+` rides in the last leg's cell, level with the row
                    // it continues. Given a row of its own it left a cell-high
                    // gap under a dot that marked nothing, which on a two-row
                    // drop set was half the height of the group.
                    //
                    // Long-press is that leg's own actions: its cell is spoken
                    // for, and every other row in this column opens a sheet.
                    _ when k == last => _addButton(
                      context,
                      tooltip: 'Add a leg',
                      onTap: addLeg,
                      onLongPress: () => _openActions(context, ref, k),
                    ),
                    // A middle leg's way into its type, note and delete.
                    _ => _LegMarker(onTap: () => _openActions(context, ref, k)),
                  },
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: KeyedSubtree(
                    key: rowKeyFor(group.sets[k].id),
                    child: SetRow(
                      set: group.sets[k],
                      loadMode: entry.exercise.loadMode,
                      measure: entry.exercise.measureMode,
                      unit: unit,
                      ghost: _ghostFor(prefill, entry.sets, group.positions[k]),
                      bodyweightKg: bodyweightKg,
                      bodyweightPct: entry.exercise.bodyweightPct,
                      editing: editing,
                      partialShownFor: partialShownFor,
                      partialClosedFor: partialClosedFor,
                      partialEditing: partialEditing,
                      buffer: buffer,
                      onEdit: onEdit,
                      onEditPartial: onEditPartial,
                      onToggleDone: onToggleDone,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // A drop set whose last leg has been deleted has no cell to put the `+`
        // in but still has to offer one, or it can never be a drop set again.
        // This is the only case that costs a row.
        if (group.isDrop && group.sets.length == 1)
          Row(
            children: [
              _IndexCell(
                spine: _Spine.bottom,
                height: _footHeight,
                child: _addButton(context, tooltip: 'Add a leg', onTap: addLeg),
              ),
            ],
          ),
      ],
    );
  }

  /// Shorter than a set row: it holds a button, not a number to read. Exactly
  /// the button's own diameter, so the capsule's foot closes on its edge.
  static const _footHeight = SetRow.indexColumn;

  /// Everything deleting row [k] removes. Deleting the head of a drop group
  /// takes the whole group: its legs are continuations of that set and mean
  /// nothing without it.
  List<String> _deleteIds(int k) =>
      k == 0 ? [for (final s in group.sets) s.id] : [group.sets[k].id];

  void _openActions(BuildContext context, WidgetRef ref, int k) {
    showSetActions(
      context,
      ref,
      group.sets[k],
      // The number the chip prints, not the raw position. Tapping the set
      // marked `1` would otherwise open a sheet headed "Set 2" whenever a
      // warm-up or a drop sat above it. The sheet names the type itself.
      label: group.label,
      leg: k == 0 ? null : k + 1,
      deleteIds: _deleteIds(k),
    );
  }
}

enum _Spine { none, top, middle, bottom }

/// The fixed-width column down the left of the table. For a drop group the
/// cells join into one capsule behind the chip, the legs and the `+`.
class _IndexCell extends StatelessWidget {
  const _IndexCell({
    required this.spine,
    required this.child,
    this.height = SetRow.rowHeight,
  });

  final _Spine spine;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The full width of the column, with the chip flat on it. A narrower
    // capsule with a filled chip proud of it read as beads on a string —
    // three bulges down the left of the table instead of one run.
    const spineWidth = SetRow.indexColumn;
    const r = Radius.circular(spineWidth / 2);

    // The cap stops on the chip's own edge, not on the row's. A row is taller
    // than the chip in it, so a capsule drawn to the full height of the top row
    // reached half a chip above the `D` and ended in a rounded shoulder with
    // nothing under it — the same at the foot, around the `+`. Inset by the
    // gap between the two and the cap circumscribes the circle exactly.
    final inset = math.max(
      0.0,
      math.min(height / 2, (height - SetRow.indexColumn) / 2),
    );

    return SizedBox(
      width: SetRow.indexColumn,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (spine != _Spine.none)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  top: spine == _Spine.top ? inset : 0,
                  bottom: spine == _Spine.bottom ? inset : 0,
                ),
                child: Container(
                  width: spineWidth,
                  decoration: BoxDecoration(
                    color: c.surfaceHighest,
                    borderRadius: BorderRadius.vertical(
                      top: spine == _Spine.top ? r : Radius.zero,
                      bottom: spine == _Spine.bottom ? r : Radius.zero,
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// A drop leg's index cell. The capsule already says the row belongs to the set
/// above it, so this is only a mark that something is here to press — and, like
/// every other chip in this column, the way into that row's type, note and
/// delete.
class _LegMarker extends StatelessWidget {
  const _LegMarker({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: SetRow.indexColumn,
        height: SetRow.rowHeight,
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: c.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Session length, as `m:ss` or `h:mm:ss`. Top-level because both the screen
/// and its top bar need it and neither owns the other.
String _formatElapsed(int startedAtMs) {
  final start = DateTime.fromMillisecondsSinceEpoch(
    startedAtMs,
    isUtc: true,
  ).toLocal();
  final d = DateTime.now().difference(start);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The ⓘ, with a dot on it when the numbers in the table were borrowed.
///
/// The provenance lives in the sheet rather than in a header caption —
/// `Last time · 12 Jul`, or `Borrowed from Push 2 · 3 Aug` in amber — which
/// would say what the sheet already says, on the screen with the least room for
/// a second line. The *warning* cannot live there alone: numbers prefilled from
/// another session are the one case where ignoring where they came from means
/// chasing somebody else's day, so the button wears a dot and the sheet spells
/// it out.
class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CircleIconButton(
      icon: Icons.info_outline_rounded,
      tooltip: 'About this exercise',
      onTap: onTap,
    );
  }
}

/// The `+` in the set table's index column: the width of the column, so a
/// capsule's foot closes on its edge, and quieter than a header's buttons
/// because it sits among the set numbers rather than above them.
Widget _addButton(
  BuildContext context, {
  required String tooltip,
  required VoidCallback onTap,
  VoidCallback? onLongPress,
}) =>
    CircleIconButton(
      icon: Icons.add_rounded,
      tooltip: tooltip,
      onTap: onTap,
      onLongPress: onLongPress,
      size: SetRow.indexColumn,
      glyphScale: 0.6,
      pressScale: 0.97,
      tint: context.c.textSecondary,
    );
