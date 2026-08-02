import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import '../../domain/metrics.dart';
import '../../domain/session_diff.dart';
import '../../domain/units.dart';
import '../history/history_screen.dart' show formatWeight;
import 'log_providers.dart';

/// The last screen of a session: what it came to, and the only place a note can
/// be written while the session is still in your head.
///
/// It exists because finishing used to drop straight back to Today, which meant
/// the note — the one thing you can only write now — was reachable only by
/// going and finding the day again in History.
///
/// It sits *after* the write: the workout is already completed when this opens,
/// so there is nothing to confirm and no way to fail out of it. The finish
/// confirmation that names unfinished exercises still happens before.
class SessionSummaryScreen extends ConsumerWidget {
  const SessionSummaryScreen({super.key, required this.workoutId});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(workoutDetailProvider(workoutId)).valueOrNull;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final c = context.c;

    if (detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final workout = detail.workout;
    final done = detail.entries.expand((e) => e.sets).where((s) => s.isDone);
    final sets = done.length;
    final ended = workout.endedAt;
    final minutes = ended == null ? null : (ended - workout.startedAt) ~/ 60000;
    final bodyweight =
        ref.watch(bodyweightSeriesProvider).valueOrNull ?? const [];
    final volume = _volume(detail, bodyweight);
    final hasNote = workout.notes?.isNotEmpty == true;
    final sessionName =
        workout.sessionId == null ? null : detail.session?.name ?? 'this session';

    return PopScope(
      // Back belongs to Done: there is nothing behind this screen but the log
      // of a session that is already closed.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(context);
      },
      child: Scaffold(
        body: Column(
          children: [
            // Composed centre — a ✕ that leaves, a title naming the moment, the
            // session's name under it — where workout detail is left-flush with
            // a back arrow and an overflow. Same band, opposite posture: one is
            // a place you arrived at, this is a thing that just finished.
            HeaderBand(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Space.sm, Space.sm, Space.gutter, 0),
                    child: Row(
                      children: [
                        CircleIconButton(
                          icon: Icons.close_rounded,
                          fill: Colors.transparent,
                          tooltip: 'Done',
                          onTap: () => _leave(context),
                        ),
                        Expanded(
                          child: Text(
                            'Session complete',
                            textAlign: TextAlign.center,
                            style: context.t.titleMedium,
                          ),
                        ),
                        if (workout.isDeload)
                          Pill('Deload', color: c.deload)
                        else
                          const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Space.gutter, Space.lg, Space.gutter, Space.xl),
                    child: Text(
                      detail.session?.name ?? 'Ad-hoc session',
                      textAlign: TextAlign.center,
                      // `section`, not `pageTitle`: the masthead type is
                      // uppercase and belongs to a tab you navigated to. This is
                      // a sentence about what just happened.
                      style: context.t.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Space.gutter, Space.lg, Space.gutter, Space.lg),
                children: [
                  // The day's numbers as labelled rows rather than as three
                  // stat tiles. Tiles are for a dashboard you scan; this is a
                  // short list of facts you read once, and a row can carry a
                  // unit and a dash without the label wrapping under it.
                  const SectionHeader('The session'),
                  ListCard(
                    children: [
                      AppRow(
                        icon: Icons.fitness_center_rounded,
                        title: 'Volume',
                        trailing: _Value(
                          // A dash, not a zero: a session of chins with no
                          // bodyweight ever logged has an unknown volume, not a
                          // volume of nothing (rule 4).
                          value: volume <= 0 ? '—' : formatWeight(volume, unit),
                          unit: volume <= 0 ? null : unit.label,
                        ),
                      ),
                      AppRow(
                        icon: Icons.format_list_numbered_rounded,
                        title: 'Sets logged',
                        trailing: _Value(value: '$sets'),
                      ),
                      AppRow(
                        icon: Icons.schedule_rounded,
                        title: 'Duration',
                        trailing: _Value(
                          value: minutes == null || minutes < 0
                              ? '—'
                              : '$minutes',
                          unit: minutes == null || minutes < 0 ? null : 'min',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.section),
                  // Then what you can still do something about: the programme
                  // decision, which expires the moment you leave this screen,
                  // then the note, then the recap, which is a read.
                  if (sessionName != null)
                    _ChangesSection(
                      workoutId: workoutId,
                      sessionId: workout.sessionId!,
                      sessionName: sessionName,
                    ),
                  SectionHeader(
                    hasNote ? 'Session note' : 'How did it go?',
                    actionLabel: hasNote ? 'Edit' : null,
                    onAction: hasNote
                        ? () => _editSessionNote(context, ref, workout)
                        : null,
                  ),
                  _NoteBox(
                    note: workout.notes,
                    onTap: () => _editSessionNote(context, ref, workout),
                  ),
                  const SizedBox(height: Space.section),
                  SectionHeader(
                    '${detail.entries.length} exercise'
                    '${detail.entries.length == 1 ? '' : 's'}',
                  ),
                  // A recap, not a record: one card of rows that state what each
                  // movement came to. Detail's rows are full-bleed and expand
                  // into every set, because that is a screen for going back
                  // through a day; nothing here opens.
                  ListCard(
                    inset: 0,
                    children: [
                      for (final entry in detail.entries)
                        _EntryRow(entry: entry, unit: unit),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.lg,
              ),
              child: SafeArea(
                top: false,
                child: PrimaryButton(
                  label: 'Done',
                  onPressed: () => _leave(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Back to Today, however this screen was reached — it replaced the log, so
  /// one pop is the whole way out.
  static void _leave(BuildContext context) {
    Navigator.of(context).pop();
  }

  static Future<void> _editSessionNote(
    BuildContext context,
    WidgetRef ref,
    Workout workout,
  ) async {
    final text = await promptForNote(
      context,
      title: 'Session note',
      initial: workout.notes ?? '',
      hint: 'Slept badly, everything felt heavy',
    );
    if (text == null) return;
    await ref.read(trainingRepositoryProvider).setWorkoutNotes(workout.id, text);
  }

  /// Load × reps over every completed set, in kg. The maths is in
  /// `domain/metrics.dart` and tested without a database.
  static double _volume(
    WorkoutDetail detail,
    List<({int dayKey, double weightKg})> bodyweight,
  ) {
    return sessionVolume(
      bodyweightKg: bodyweightOn(detail.workout.dayKey, bodyweight),
      exercises: [
        for (final entry in detail.entries)
          (
            mode: entry.exercise.loadMode,
            measure: entry.exercise.measureMode,
            sets: [
              for (final set in entry.sets)
                if (set.isDone)
                  ScoredSet(
                    type: set.setType,
                    weight: set.weight,
                    reps: set.reps,
                    addedWeight: set.addedWeight,
                  ),
            ],
          ),
      ],
    );
  }
}

/// Today's improvisation, offered to the programme one line at a time.
///
/// A workout is a snapshot, so adding a movement or running the day in a
/// different order changes today and nothing else — right for a busy rack,
/// wrong for the fourth week in a row of adding the same exercise by hand. This
/// asks once, at the only moment the answer is obvious, and takes nothing
/// unless it is ticked.
///
/// Each change is separate on purpose: keeping the leg raises and throwing away
/// the shuffle is the normal answer, and a single "save today's version" button
/// cannot express it.
class _ChangesSection extends ConsumerStatefulWidget {
  const _ChangesSection({
    required this.workoutId,
    required this.sessionId,
    required this.sessionName,
  });

  final String workoutId;
  final String sessionId;
  final String sessionName;

  @override
  ConsumerState<_ChangesSection> createState() => _ChangesSectionState();
}

class _ChangesSectionState extends ConsumerState<_ChangesSection> {
  /// Ticked by index into the change list. Nothing is ticked to begin with:
  /// the programme is what you decided when you were not tired, and it does not
  /// change because a squat rack was busy.
  final _picked = <int>{};
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final changes =
        ref.watch(sessionChangesProvider(widget.workoutId)).valueOrNull ??
            const [];

    // Answered first, empty second. Applying a change makes the diff empty by
    // definition, so testing `changes.isEmpty` before `_saved` meant the
    // section could vanish mid-interaction and take its own confirmation with
    // it — the moment anything else on the screen invalidated the provider.
    if (_saved) {
      final kept = _picked.length;
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.section),
        child: Row(
          children: [
            Icon(
              kept == 0 ? Icons.remove_rounded : Icons.check_rounded,
              size: 18,
              color: kept == 0 ? c.textTertiary : c.positive,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                kept == 0
                    ? '${widget.sessionName} left as it was'
                    : '${widget.sessionName} updated — '
                        '$kept change${kept == 1 ? '' : 's'} kept',
                style: context.t.bodyMedium?.copyWith(
                  color: kept == 0 ? c.textSecondary : c.positive,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (changes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader('You changed ${widget.sessionName} today'),
          // Says what the checkboxes are for *before* showing any, and says
          // what happens if you ignore them — which is the answer most days.
          // Without this the section is a list of ticks with no stated
          // consequence, and the safe read of an unexplained tick is "don't".
          Text(
            'These changes apply to today either way. Tick anything '
            '${widget.sessionName} should do every time from now on.',
            style: context.t.bodyMedium,
          ),
          const SizedBox(height: Space.md),
          ListCard(
            inset: 0,
            children: [
              for (var i = 0; i < changes.length; i++)
                AppRow(
                  title: changes[i].label,
                  subtitle: _picked.contains(i)
                      ? _kept(changes[i].kind, widget.sessionName)
                      : 'Today only',
                  leading: Icon(
                    _picked.contains(i)
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 24,
                    color:
                        _picked.contains(i) ? c.textPrimary : c.textTertiary,
                  ),
                  onTap: () => setState(() {
                    if (!_picked.remove(i)) _picked.add(i);
                  }),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          SecondaryButton(
            label: _picked.isEmpty
                ? 'Keep ${widget.sessionName} as it is'
                : 'Update ${widget.sessionName}',
            icon: _picked.isEmpty ? null : Icons.playlist_add_check_rounded,
            // Enabled with nothing ticked, and it means "leave the programme
            // alone" — a dead button gives no way to say the thing most people
            // mean, and leaves the section sitting open as if unanswered.
            onPressed: () => _apply(changes),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(List<SessionChange> changes) async {
    await ref.read(trainingRepositoryProvider).applySessionChanges(
          sessionId: widget.sessionId,
          changes: [
            for (var i = 0; i < changes.length; i++)
              if (_picked.contains(i)) changes[i],
          ],
        );
    if (mounted) setState(() => _saved = true);
  }

  /// What a ticked row promises, named so the row reads as a sentence with its
  /// title: "Added Hanging leg raise / In Push 1 from now on".
  static String _kept(SessionChangeKind kind, String session) =>
      switch (kind) {
        SessionChangeKind.added => 'In $session from now on',
        SessionChangeKind.removed => 'Out of $session from now on',
        SessionChangeKind.reordered => '$session opens in this order',
      };
}

/// A number on the right of a row, with its unit one step down beside it —
/// rule 5, in the shape a row needs rather than a tile's.
class _Value extends StatelessWidget {
  const _Value({required this.value, this.unit});

  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: context.t.labelLarge),
        if (unit != null) ...[
          const SizedBox(width: Space.xs),
          Text(unit!, style: context.t.bodyMedium),
        ],
      ],
    );
  }
}

/// The session note, written here or nowhere.
///
/// A field, not a row: this is the one screen where writing the note is a thing
/// you came to do, so it looks like somewhere to write rather than like a
/// setting to open. Workout detail shows the same note as a quote, because
/// there it is a record.
class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.note, required this.onTap});

  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = note?.isEmpty == true ? null : note;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      // `surfaceHigh`, the app's input fill — not `surfaceSunken`, which is the
      // keypad's bed and reads as a hole cut in the page.
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Text(
          text ?? 'Slept badly, everything felt heavy, the rack was busy…',
          style: text == null
              ? context.t.bodyLarge?.copyWith(color: c.textTertiary)
              : context.t.bodyLarge,
        ),
      ),
    );
  }
}

/// One exercise as it ended up, with its note for the day editable in place.
class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry, required this.unit});

  final ExerciseEntry entry;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final done = entry.sets.where((s) => s.isDone).toList();
    final skipped = entry.workoutExercise.skipReason != SkipReason.none;
    final note = entry.workoutExercise.notes;

    final summary = done.isEmpty
        ? (skipped ? 'Not trained' : 'Nothing logged')
        : '${done.length} set${done.length == 1 ? '' : 's'} · '
            '${_top(done, entry.exercise, unit)}';

    return Pressable(
      scale: 0.99,
      onTap: () => _editNote(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
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
                  if (note != null) ...[
                    const SizedBox(height: Space.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sticky_note_2_outlined,
                            size: 14, color: c.textTertiary),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: Text(
                            note,
                            style: context.t.bodySmall,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (skipped) ...[
              const SizedBox(width: Space.sm),
              Pill(entry.workoutExercise.skipReason.label, color: c.negative),
            ] else if (note == null) ...[
              const SizedBox(width: Space.sm),
              Icon(Icons.sticky_note_2_outlined, size: 18, color: c.textTertiary),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref) async {
    final text = await promptForNote(
      context,
      title: entry.exercise.name,
      subtitle: 'Note for today',
      initial: entry.workoutExercise.notes ?? '',
      hint: 'Shoulder felt off, bench was the wide one',
    );
    if (text == null) return;
    await ref
        .read(trainingRepositoryProvider)
        .setWorkoutExerciseNotes(entry.workoutExercise.id, text);
  }

  /// The heaviest working set, warm-ups excluded — the same figure the workout
  /// detail screen prints, so the two never disagree about a day.
  static String _top(List<SetLog> done, Exercise exercise, WeightUnit unit) {
    final counted = done.where((s) => s.setType != SetType.warmup).toList();
    final pool = counted.isEmpty ? [...done] : counted;
    // A hold's best set is its longest, not its heaviest — the load on a plank
    // rarely moves and sorting by it picks an arbitrary one of five.
    final measure = exercise.measureMode;
    pool.sort(measure.isHold
        ? (a, b) => (b.reps ?? 0).compareTo(a.reps ?? 0)
        : (a, b) => ((b.weight ?? b.addedWeight) ?? 0)
            .compareTo((a.weight ?? a.addedWeight) ?? 0));
    final set = pool.first;
    final count = formatCount(set.reps, measure);

    if (exercise.loadMode == LoadMode.bodyweight) {
      return 'Bodyweight × $count';
    }
    if (exercise.loadMode == LoadMode.bodyweightPlus) {
      final added = set.addedWeight;
      return added == null || added == 0
          ? 'Bodyweight × $count'
          : 'BW + ${formatWeight(added, unit)} ${unit.label} × $count';
    }
    final weight = set.weight;
    if (weight == null) return measure.isHold ? count : '$count reps';
    final perSide = exercise.loadMode == LoadMode.perSide ? ' × 2' : '';
    return '${formatWeight(weight, unit)} ${unit.label}$perSide × $count';
  }
}
