import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/calendar.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import '../../domain/set_format.dart';
import '../../domain/units.dart';
import 'exercise_history_screen.dart';
import 'history_providers.dart';
import '../../core/widgets/toast.dart';
import '../../domain/session_name.dart';

/// One day, exactly as it was logged.
///
/// Reads from the workout's own snapshot rows, so a session that has since been
/// reordered, renamed or gutted still shows what actually happened.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workoutDetailProvider(workoutId));
    final detail = async.valueOrNull;
    final c = context.c;

    if (detail == null) {
      // Loaded-and-null means the day was deleted, which is reachable: the feed
      // behind this screen can outlive it. Saying so beats a spinner forever.
      return Scaffold(
        appBar: AppBar(
          backgroundColor: c.surface,
          title: const Text('Session'),
        ),
        body: async.hasValue
            ? const EmptyState(
                icon: Icons.delete_outline,
                title: 'Session deleted',
                message: 'This day is no longer in your history.',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final workout = detail.workout;
    final date = dateFromDayKey(workout.dayKey);
    final hasNote = workout.notes?.isNotEmpty == true;

    // A pushed screen: small centred title, back arrow, actions on the right.
    // The 30sp masthead belongs to the four destinations — a logged day wearing
    // one looks like somewhere you navigate to rather than into.
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.session?.name ?? unplannedSessionName),
        actions: [
          if (workout.isDeload) ...[
            Pill('Deload', color: c.deload),
            const SizedBox(width: Space.sm),
          ],
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'Session actions',
            onPressed: () => _showActions(context, ref, detail),
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: Column(
        children: [
          // The day and what it came to, under the bar rather than in it — a
          // centred title has room for a name, not for a name and a date and a
          // set count.
          Container(
            width: double.infinity,
            color: c.surface,
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE d MMMM yyyy').format(date),
                  style: context.t.titleMedium,
                ),
                const SizedBox(height: Space.xxs),
                Text(_facts(detail).join(' · '), style: context.t.bodyMedium),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Space.huge),
              children: [
                const SizedBox(height: Space.lg),
                // The day's own note, as prose rather than as a settings row —
                // it is somebody's sentence about the session, and the same
                // block the exercises use for theirs, so the page has one way
                // of showing a note rather than two.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        'Session note',
                        actionLabel: hasNote ? 'Edit' : null,
                        onAction: hasNote
                            ? () => _editNotes(context, ref, detail)
                            : null,
                      ),
                      _NoteBlock(
                        note: workout.notes?.isEmpty == true
                            ? null
                            : workout.notes,
                        placeholder: 'How it felt, what got in the way',
                        onTap: () => _editNotes(context, ref, detail),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.section),
                if (detail.entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: EmptyBox(
                      icon: Icons.inbox_outlined,
                      message:
                          'This workout was finished without anything '
                          'logged in it.',
                    ),
                  )
                else ...[
                  // Count as heading (THEME → Composing a screen): "6 exercises" says more than the
                  // word does on its own.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.gutter,
                    ),
                    child: SectionHeader(
                      '${detail.entries.length} exercise'
                      '${detail.entries.length == 1 ? '' : 's'}',
                    ),
                  ),
                  for (var i = 0; i < detail.entries.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.border),
                    _ExerciseBlock(entry: detail.entries[i]),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The three things you can do to a logged day, in a sheet rather than a
  /// popup menu — a menu anchored to a glyph is the one surface in this app
  /// that never got a design.
  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    WorkoutDetail detail,
  ) async {
    final hasNote = detail.workout.notes?.isNotEmpty == true;
    final action = await showModalBottomSheet<String>(
      // The route holds the system bars: a sheet that sizes itself can
      // otherwise run under the status bar. See [pickExercise].
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      // `AppSheet` draws its own grab handle, tighter than the framework's.
      showDragHandle: false,
      builder: (sheet) => AppSheet(
        title: detail.session?.name ?? unplannedSessionName,
        subtitle: DateFormat(
          'd MMMM yyyy',
        ).format(dateFromDayKey(detail.workout.dayKey)),
        // Full-bleed rows, no card. A card inside a sheet is a panel in a
        // panel, and the sheet's gutter then insets the rows a second time on
        // top of the padding `AppRow` already carries, standing the left edge
        // of every action in from the title above it.
        contentPadding: const EdgeInsets.only(bottom: Space.md),
        children: [
          AppRow(
            icon: Icons.edit_calendar_outlined,
            title: 'Change the date',
            subtitle: 'Logged on the wrong day',
            onTap: () => Navigator.of(sheet).pop('date'),
          ),
          AppRow(
            icon: Icons.sticky_note_2_outlined,
            title: hasNote ? 'Edit the note' : 'Add a note',
            subtitle: hasNote
                ? detail.workout.notes
                : 'How it felt, what got in the way',
            onTap: () => Navigator.of(sheet).pop('notes'),
          ),
          AppRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete this session',
            subtitle: 'Removes it from history and the heatmap',
            tint: sheet.c.negative,
            onTap: () => Navigator.of(sheet).pop('delete'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'date':
        await _editDate(context, ref, detail);
      case 'notes':
        await _editNotes(context, ref, detail);
      case 'delete':
        await _delete(context, ref, detail);
    }
  }

  Future<void> _editDate(
    BuildContext context,
    WidgetRef ref,
    WorkoutDetail detail,
  ) async {
    final current = dateFromDayKey(detail.workout.dayKey);
    // Training in the future is not a thing; a stray tap on next month is —
    // so `last` stays today and the rest of the month is visible but dead.
    final picked = await pickDay(
      context,
      initial: current,
      title: 'When was this trained?',
    );
    if (picked == null || !context.mounted) return;
    if (dayKeyOf(picked) == detail.workout.dayKey) return;

    await ref
        .read(trainingRepositoryProvider)
        .setWorkoutDate(detail.workout.id, picked);
  }

  Future<void> _editNotes(
    BuildContext context,
    WidgetRef ref,
    WorkoutDetail detail,
  ) async {
    final text = await promptForNote(
      context,
      title: 'Session note',
      initial: detail.workout.notes ?? '',
      hint: 'Slept badly, everything felt heavy',
    );
    if (text == null) return;
    await ref
        .read(trainingRepositoryProvider)
        .setWorkoutNotes(detail.workout.id, text);
  }

  /// Logging the wrong session, or logging one twice, has to be undoable —
  /// otherwise the heatmap, the cycle count and every "last time" number carry
  /// a day that never happened.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    WorkoutDetail detail,
  ) async {
    final sets = detail.entries
        .expand((e) => e.sets)
        .where((s) => s.isDone)
        .length;
    final date = DateFormat(
      'd MMMM yyyy',
    ).format(dateFromDayKey(detail.workout.dayKey));

    final ok = await confirmAction(
      context,
      title: 'Delete this session?',
      message:
          '${detail.session?.name ?? unplannedSessionName} · $date\n\n'
          '$sets logged set${sets == 1 ? '' : 's'} will be removed from '
          'history, the heatmap and every last-time suggestion. If it closed a '
          'cycle, the cycle reopens.\n\nThis cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(trainingRepositoryProvider).deleteWorkout(detail.workout.id);
    navigator.pop();
    showToastOn(messenger, 'Session deleted');
  }

  static List<String> _facts(WorkoutDetail detail) {
    final sets = detail.entries
        .expand((e) => e.sets)
        .where((s) => s.isDone)
        .length;
    final ended = detail.workout.endedAt;
    final minutes = ended == null
        ? null
        : (ended - detail.workout.startedAt) ~/ 60000;

    return [
      '${detail.entries.length} exercise'
          '${detail.entries.length == 1 ? '' : 's'}',
      '$sets set${sets == 1 ? '' : 's'}',
      if (minutes != null && minutes >= 0) '$minutes min',
    ];
  }
}

/// One exercise, collapsed to what it came to. Tapping it opens the sets.
///
/// Full-bleed, no card: the block is separated from its neighbours by a
/// hairline, which is what makes a day of six exercises read as one list rather
/// than six panels (THEME → Components).
class _ExerciseBlock extends ConsumerStatefulWidget {
  const _ExerciseBlock({required this.entry});

  final ExerciseEntry entry;

  @override
  ConsumerState<_ExerciseBlock> createState() => _ExerciseBlockState();
}

class _ExerciseBlockState extends ConsumerState<_ExerciseBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entry = widget.entry;
    final done = entry.sets.where((s) => s.isDone).toList();
    final skipped = entry.workoutExercise.skipReason != SkipReason.none;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    // Sets logged before the skip are kept. Hiding them made history disagree
    // with itself: they survived, they fed prefill and the progress chart, and
    // only these views pretended otherwise.
    final note = entry.workoutExercise.notes;
    final summary = done.isEmpty
        ? (skipped ? 'Not trained' : 'Nothing logged')
        : [
            '${done.length} set${done.length == 1 ? '' : 's'}',
            _topLoad(done, entry.exercise, unit),
            if (skipped) 'Then stopped',
          ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          scale: 0.99,
          // With sets under it the row opens; with none there is nothing to
          // open, so the tap goes to the only thing the block still holds.
          onTap: done.isEmpty
              ? _editNote
              : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.gutter,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.exercise.name,
                        style: context.t.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(
                        summary,
                        style: context.t.bodyMedium?.copyWith(
                          color: skipped && done.isEmpty ? c.negative : null,
                        ),
                      ),
                      // Only when the block has no expansion to hold it. With
                      // sets under it the note is inside, in full, and printing
                      // an ellipsized copy up here is the same sentence twice
                      // — once cut short, once whole.
                      if (note != null && done.isEmpty) ...[
                        const SizedBox(height: Space.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.sticky_note_2_outlined,
                              size: 14,
                              color: c.textTertiary,
                            ),
                            const SizedBox(width: Space.xs),
                            Expanded(
                              child: Text(note, style: context.t.bodySmall),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (skipped) ...[
                  const SizedBox(width: Space.sm),
                  Pill(
                    entry.workoutExercise.skipReason.label,
                    color: c.negative,
                  ),
                ],
                if (done.isNotEmpty) ...[
                  const SizedBox(width: Space.sm),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: Motion.base,
                    curve: Motion.curve,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < done.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 60),
                      child: Divider(height: 1, color: c.border),
                    ),
                  _SetLine(
                    set: done[i],
                    exercise: entry.exercise,
                    index: _workingIndex(done, i),
                    unit: unit,
                  ),
                ],
                // Three different kinds of thing, told apart: what happened is
                // a table, what was said about it is a card of prose, and only
                // where to go next looks like a link.
                const SizedBox(height: Space.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: _NoteBlock(
                    note: note,
                    placeholder: 'Add a note for this day',
                    onTap: _editNote,
                  ),
                ),
                const SizedBox(height: Space.md),
                Padding(
                  padding: const EdgeInsets.only(left: Space.gutter),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: LinkAction(
                      'All ${entry.exercise.name} history',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ExerciseHistoryScreen(
                            exerciseId: entry.exercise.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// This exercise on this day — not the catalog's cue, which every session
  /// shares, and not a set's note. Editing it writes the workout's own snapshot
  /// row, so the movement and the template are untouched.
  Future<void> _editNote() async {
    final entry = widget.entry;
    final text = await promptForNote(
      context,
      title: entry.exercise.name,
      subtitle: 'Note for this day',
      initial: entry.workoutExercise.notes ?? '',
      hint: 'Shoulder felt off, so I kept it light',
    );
    if (text == null) return;
    await ref
        .read(trainingRepositoryProvider)
        .setWorkoutExerciseNotes(entry.workoutExercise.id, text);
  }

  /// What the exercise came to in one figure: the heaviest set logged. Warm-ups
  /// are excluded — a 20 kg warm-up is not what the day was about.
  static String _topLoad(
    List<SetLog> done,
    Exercise exercise,
    WeightUnit unit,
  ) {
    final i = heaviestLogged(
      sets: [
        for (final s in done)
          (
            setType: s.setType,
            weight: s.weight,
            addedWeight: s.addedWeight,
            reps: s.reps,
          ),
      ],
      measureMode: exercise.measureMode,
      loadMode: exercise.loadMode,
    );
    if (i == null) return '—';
    final set = done[i];
    return loadLabel(
      loadMode: exercise.loadMode,
      weight: set.weight,
      addedWeight: set.addedWeight,
      unit: unit,
    );
  }

  /// The number on the chip. Warm-ups and continuations carry a letter instead,
  /// so they do not consume a working-set number — the same count the log
  /// screen shows while you are in the session.
  static int _workingIndex(List<SetLog> done, int i) {
    var n = 0;
    for (var j = 0; j <= i; j++) {
      final t = done[j].setType;
      if (t != SetType.warmup && !t.isContinuation) n++;
    }
    return n;
  }
}

/// What was said about a day, or about one exercise on it.
///
/// A card of prose, built the same way every other block on this page is: the
/// note is the *content* of its section, not a quote pinned to the side of one.
/// A sunken panel with a rule down its left would put the one piece of writing
/// on the screen in the darkest box on it, at the smallest contrast.
class _NoteBlock extends StatelessWidget {
  const _NoteBlock({
    required this.note,
    required this.onTap,
    this.placeholder = 'Add a note for this day',
  });

  final String? note;
  final VoidCallback onTap;

  /// What the empty state offers. Says which note is being asked for — the
  /// day's, or this exercise on it.
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = note;

    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                text ?? placeholder,
                // `body` at 15 on `surface`, in the primary colour once there
                // is something to read: a written note is the only prose on
                // this page, and the captions' grey would file it as a
                // caption.
                style: text == null
                    ? context.t.bodyLarge?.copyWith(color: c.textTertiary)
                    : context.t.bodyLarge?.copyWith(color: c.textPrimary),
              ),
            ),
            const SizedBox(width: Space.md),
            Icon(
              text == null ? Icons.add_rounded : Icons.edit_outlined,
              size: 18,
              color: c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// One logged set: index chip, then the load and reps as one phrase.
class _SetLine extends StatelessWidget {
  const _SetLine({
    required this.set,
    required this.exercise,
    required this.index,
    required this.unit,
  });

  final SetLog set;
  final Exercise exercise;
  final int index;

  /// Handed down, not watched. See `_ExpandedSetLine` in
  /// `exercise_history_screen.dart`: one listener per set is one listener per
  /// set to wake when the unit changes.
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final short = set.setType.shortLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Text(
              short.isEmpty ? '$index' : short,
              style: context.t.bodySmall?.copyWith(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // `loadWithCount`, not a load and a count joined here: that
                  // would be the same function written a second time, and two
                  // spellings are exactly how one screen ends up disagreeing
                  // with another about the same set.
                  loadWithCount(
                    loadMode: exercise.loadMode,
                    measureMode: exercise.measureMode,
                    weight: set.weight,
                    addedWeight: set.addedWeight,
                    reps: set.reps,
                    partialReps: set.partialReps,
                    unit: unit,
                  ),
                  style: context.t.labelLarge,
                ),
                if (set.note != null && set.note!.isNotEmpty)
                  Text(set.note!, style: context.t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
