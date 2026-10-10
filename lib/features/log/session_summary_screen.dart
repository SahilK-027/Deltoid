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
import '../../domain/set_format.dart';
import '../../domain/units.dart';
import 'log_providers.dart';
import '../../domain/session_name.dart';

/// Changes ticked in the summary's programme section but not yet written.
///
/// Held above [_ChangesSectionState] so that leaving the screen honours them.
/// Kept inside that section, only its own button would write them, and `Done` —
/// the white button at the bottom of the screen, and the obvious way off it —
/// would pop back to Today and throw the selection away without a word. That is
/// the worst possible answer: the user has said what the programme should do
/// from now on, and been told nothing about it not happening.
final _pendingChangesProvider =
    StateProvider<({String sessionId, List<SessionChange> changes})?>(
  (ref) => null,
);

/// The last screen of a session: what it came to, and the only place a note can
/// be written while the session is still in your head.
///
/// It exists because dropping straight back to Today on finish leaves the
/// note — the one thing you can only write now — reachable only by going and
/// finding the day again in History.
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
        if (!didPop) _leave(context, ref);
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
                          onTap: () => _leave(context, ref),
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
                      detail.session?.name ?? unplannedSessionName,
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
                        trailing: ValueUnit(
                          dense: true,
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
                        trailing: ValueUnit(value: '$sets', dense: true),
                      ),
                      AppRow(
                        icon: Icons.schedule_rounded,
                        title: 'Duration',
                        trailing: ValueUnit(
                          dense: true,
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
                    'Session note',
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
                        _ExerciseEntryRow(entry: entry, unit: unit),
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
                  onPressed: () => _leave(context, ref),
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
  ///
  /// Anything ticked and not yet written goes in on the way past. The
  /// repository and the navigator are both taken before the await, because the
  /// widget that owns this `ref` is the one being popped.
  static Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final repo = ref.read(trainingRepositoryProvider);
    final pending = ref.read(_pendingChangesProvider);
    if (pending != null && pending.changes.isNotEmpty) {
      ref.read(_pendingChangesProvider.notifier).state = null;
      await repo.applySessionChanges(
        sessionId: pending.sessionId,
        changes: pending.changes,
      );
    }
    navigator.pop();
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
            bodyweightPct: entry.exercise.bodyweightPct,
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
  void initState() {
    super.initState();
    // Nothing is carried in from a previous session's summary.
    ref.read(_pendingChangesProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final changes =
        ref.watch(sessionChangesProvider(widget.workoutId)).valueOrNull ??
            const [];
    // The changes come from this workout, so every exercise they name is on it.
    final names = {
      for (final e in ref
              .watch(workoutDetailProvider(widget.workoutId))
              .valueOrNull
              ?.entries ??
          const <ExerciseEntry>[])
        e.exercise.id: e.exercise.name,
    };

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
                    : '${widget.sessionName} updated with '
                        '$kept change${kept == 1 ? '' : 's'}',
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
                      ? _kept(changes[i], widget.sessionName, names)
                      : 'Today only',
                  leading: Icon(
                    _picked.contains(i)
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 24,
                    color:
                        _picked.contains(i) ? c.textPrimary : c.textTertiary,
                  ),
                  onTap: () {
                    setState(() {
                      if (!_picked.remove(i)) _picked.add(i);
                    });
                    _remember(changes);
                  },
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

  /// Hands the current selection to the screen, so leaving by `Done`, by the ✕
  /// or by the back gesture writes it rather than dropping it.
  void _remember(List<SessionChange> changes) {
    ref.read(_pendingChangesProvider.notifier).state = (
      sessionId: widget.sessionId,
      changes: _pickedFrom(changes),
    );
  }

  List<SessionChange> _pickedFrom(List<SessionChange> changes) => [
        for (var i = 0; i < changes.length; i++)
          if (_picked.contains(i)) changes[i],
      ];

  Future<void> _apply(List<SessionChange> changes) async {
    // Cleared first: this write is the selection, and leaving afterwards must
    // not apply the same changes a second time.
    ref.read(_pendingChangesProvider.notifier).state = null;
    await ref.read(trainingRepositoryProvider).applySessionChanges(
          sessionId: widget.sessionId,
          changes: _pickedFrom(changes),
        );
    if (mounted) setState(() => _saved = true);
  }

  /// What a ticked row promises, named so the row reads as a sentence with its
  /// title: "Added Hanging leg raise / In Push 1 from now on".
  ///
  /// A set count names its exercise, because its title's subject is the count:
  /// "1 working set in Push 1" read as the whole day being one set.
  static String _kept(
    SessionChange change,
    String session,
    Map<String, String> names,
  ) =>
      switch (change.kind) {
        SessionChangeKind.added => 'In $session from now on',
        SessionChangeKind.removed => 'Out of $session from now on',
        SessionChangeKind.reordered => '$session opens in this order',
        SessionChangeKind.setCount =>
          '${change.setCount} working set${change.setCount == 1 ? '' : 's'} '
              'of ${names[change.exerciseIds.single]} in $session from now '
              'on',
      };
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
      child: InsetPanel(
        width: double.infinity,
        minHeight: 76,
        padding: const EdgeInsets.all(Space.lg),
        child: Text(
          text ?? 'Slept badly, everything felt heavy',
          style: text == null
              ? context.t.bodyLarge?.copyWith(color: c.textTertiary)
              : context.t.bodyLarge,
        ),
      ),
    );
  }
}

/// One exercise as it ended up, with its note for the day editable in place.
class _ExerciseEntryRow extends ConsumerWidget {
  const _ExerciseEntryRow({required this.entry, required this.unit});

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
      hint: 'Shoulder felt off, so I kept it light',
    );
    if (text == null) return;
    await ref
        .read(trainingRepositoryProvider)
        .setWorkoutExerciseNotes(entry.workoutExercise.id, text);
  }

  /// The heaviest set logged, or the longest for a hold — the same figure the
  /// workout detail screen prints, because both call [heaviestLogged].
  ///
  /// **Not the chart's number.** This row describes the session, so a
  /// deliberately light day says what you lifted; `exerciseProgress` scores
  /// working and AMRAP only, so the same day draws no point. Two questions —
  /// see [heaviestLogged].
  static String _top(List<SetLog> done, Exercise exercise, WeightUnit unit) {
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
    return loadWithCount(
      loadMode: exercise.loadMode,
      measureMode: exercise.measureMode,
      weight: set.weight,
      addedWeight: set.addedWeight,
      reps: set.reps,
      partialReps: set.partialReps,
      unit: unit,
    );
  }

}
