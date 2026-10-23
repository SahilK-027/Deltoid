part of '../log_screen.dart';

/// Prefill set aligned to a position in the current exercise, or null when
/// today has more sets than last time.
/// Which past set one of today's rows compares against.
///
/// Index for index broke the moment today's shape differed from last time's:
/// adding a single drop leg pushed every row under it onto the wrong ghost, so
/// the second working set started suggesting the first leg's dropped weight —
/// and adopting a blank row wrote that number in. Rows are matched inside their
/// own class instead: warm-ups against warm-ups, working sets against working
/// sets, legs against legs. An extra leg now costs that leg its ghost and
/// nothing else.
PastSet? _ghostFor(PrefillResult? prefill, List<SetLog> sets, int position) {
  if (prefill == null || position < 0 || position >= sets.length) return null;

  final want = _ghostClass(sets[position].setType);
  var rank = 0;
  for (var i = 0; i < position; i++) {
    if (_ghostClass(sets[i].setType) == want) rank++;
  }

  for (final past in prefill.sets) {
    if (_ghostClass(past.type) != want) continue;
    if (rank == 0) return past;
    rank--;
  }
  return null;
}

int _ghostClass(SetType type) => switch (type) {
  SetType.warmup => 0,
  _ when type.isContinuation => 2,
  _ => 1,
};

/// A single exercise, filling the screen.
///
/// One exercise per page keeps the thing you are actually doing at a fixed
/// place on screen. One long vertical stack means scrolling past finished work
/// to reach the set in front of you.
/// Session name, elapsed clock, and how far through the work you are.
///
/// The progress track carries the same fact as a `12 of 18 sets` line, and a
/// bar answers "nearly done?" from across a gym floor in a way two numbers
/// cannot.
class _LogTopBar extends StatelessWidget {
  const _LogTopBar({
    required this.title,
    required this.isDeload,
    required this.startedAt,
    required this.done,
    required this.total,
    required this.onBack,
    required this.onFinish,
  });

  final String title;
  final bool isDeload;

  /// Epoch milliseconds, UTC — the column's own storage format.
  final int startedAt;
  final int done;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final complete = total > 0 && done == total;

    return HeaderBand(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.sm,
              Space.sm,
              Space.gutter,
              0,
            ),
            child: Row(
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: onBack,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: context.t.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDeload) ...[
                            const SizedBox(width: Space.sm),
                            Pill('Deload', color: c.deload),
                          ],
                        ],
                      ),
                      // Its own clock, so the session timer advances without
                      // the rest of the screen rebuilding behind it once a
                      // second.
                      Ticking(
                        builder: (context) => Text(
                          _formatElapsed(startedAt),
                          style: context.t.labelSmall?.copyWith(
                            color: c.textSecondary,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Once everything is ticked this is the pinned white button at
                // the bottom instead, so it doesn't appear in two places.
                // Training this phone is holding on its own, visible from
                // the one screen a session is spent on.
                const BackupMark(),
                if (!complete) ...[
                  const SizedBox(width: Space.sm),
                  LinkAction('Finish', onTap: onFinish),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          // Full-bleed: inside the bar's padding, a finished session stopped a
          // gutter short at each end and the track never looked full.
          _ProgressTrack(done: done, total: total),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fraction = total == 0 ? 0.0 : done / total;
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Container(color: c.surfaceHigh),
            AnimatedContainer(
              duration: Motion.base,
              curve: Motion.curve,
              width: box.maxWidth * fraction,
              color: c.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExercisePage extends ConsumerWidget {
  const _ExercisePage({
    super.key,
    required this.index,
    required this.total,
    required this.entry,
    required this.nextName,
    required this.prefill,
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
    required this.onNextExercise,
    required this.onReorder,
    required this.workout,
  });

  final int index;
  final int total;
  final ExerciseEntry entry;

  /// The session being trained, so the menu can open the day this exercise
  /// came from. Its `sessionId` is null for a workout that came from no
  /// template, and the menu shows one row fewer.
  final Workout workout;
  final String? nextName;
  final PrefillResult? prefill;

  /// Display unit for every weight on this page. Storage is always kg.
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
  final VoidCallback onNextExercise;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final skipped = entry.workoutExercise.skipReason != SkipReason.none;

    final groups = _groupSets(entry.sets);
    final (position, counted) = setPosition(entry.sets);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.huge,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.exercise.name,
                    style: context.t.headlineSmall?.copyWith(
                      color: skipped ? c.textTertiary : c.textPrimary,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!skipped && counted > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Set $position of $counted',
                      style: context.t.bodyMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Where today's numbers came from lives behind here, in one
            // sentence with the rest of the exercise's facts.
            //
            // It wore an amber dot while a session with no history of its own
            // was filled from another one: the ghosts in the table were
            // somebody else's day, and that is not something to leave a person
            // to notice. Nothing is borrowed now — a first time here opens
            // blank — so there is no warning left to carry.
            // First of the three controls, and as tall as the two buttons
            // after it. It draws nothing on a movement that takes a load, so
            // the gap is its own to carry.
            if (!skipped &&
                BodyweightPill.appliesTo(
                  entry.exercise.loadMode,
                  entry.exercise.measureMode,
                )) ...[
              const SizedBox(width: Space.sm),
              BodyweightPill(
                loadMode: entry.exercise.loadMode,
                measureMode: entry.exercise.measureMode,
                bodyweightPct: entry.exercise.bodyweightPct,
                dayKey: workout.dayKey,
              ),
              const SizedBox(width: Space.sm),
            ],
            _InfoButton(
              onTap: () => showExerciseInfo(
                context,
                ref,
                entry,
                prefill,
                customSession: workout.sessionId == null,
              ),
            ),
            const SizedBox(width: Space.sm),
            CircleIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Exercise actions',
              onTap: () => showExerciseMenu(
                context,
                ref,
                entry,
                index: index,
                total: total,
                onReorder: onReorder,
                workout: workout,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        if (skipped)
          AppCard(
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline, size: 18, color: c.negative),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'Skipped: ${entry.workoutExercise.skipReason.label.toLowerCase()}',
                    style: context.t.bodySmall?.copyWith(color: c.negative),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // No card. In one the table is inset by the page gutter and then
          // again by the card's own padding, so the SET column starts 32dp in
          // while the exercise name above it starts at 16 — the two things a
          // reader scans down this screen on different vertical lines. On the
          // page it is also one less surface behind a row that already has a
          // fill of its own per field.
          Column(
            children: [
              SetTableHeader(
                loadMode: entry.exercise.loadMode,
                measure: entry.exercise.measureMode,
                unit: unit,
              ),
              for (final group in groups)
                _SetGroup(
                  group: group,
                  entry: entry,
                  dayKey: workout.dayKey,
                  unit: unit,
                  editing: editing,
                  partialShownFor: partialShownFor,
                  partialClosedFor: partialClosedFor,
                  partialEditing: partialEditing,
                  buffer: buffer,
                  openSwipe: openSwipe,
                  onEdit: onEdit,
                  onEditPartial: onEditPartial,
                  rowKeyFor: rowKeyFor,
                  onToggleDone: onToggleDone,
                ),
              // The add button lives in the index column, directly under the
              // numbers it continues — no label, because a `+` under a
              // column of set numbers cannot mean anything else. The
              // `n of m done` line this replaces said what the header already
              // says.
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Row(
                  children: [
                    _addButton(
                      context,
                      tooltip: 'Add a set',
                      onTap: () => ref
                          .read(trainingRepositoryProvider)
                          .addSet(entry.workoutExercise.id),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.exercise.notes != null) ...[
            const SizedBox(height: Space.lg),
            Text(
              entry.exercise.notes!,
              style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
            ),
          ],
          // Today's note, written from the exercise menu. Kept visually
          // separate from the cue above: the cue is always true, this is only
          // true of this session.
          if (entry.workoutExercise.notes != null) ...[
            const SizedBox(height: Space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 16,
                  color: c.textTertiary,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    entry.workoutExercise.notes!,
                    style: context.t.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
        if (nextName != null) ...[
          const SizedBox(height: Space.section),
          // Turning the page works too; this is the discoverable version.
          SecondaryButton(
            label: 'Next: $nextName',
            icon: Icons.arrow_forward_rounded,
            onPressed: onNextExercise,
          ),
        ],
      ],
    );
  }
}

enum _FinishChoice { finish, discard, keepLogging }
