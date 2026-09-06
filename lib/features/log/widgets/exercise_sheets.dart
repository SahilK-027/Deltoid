import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ids.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/prefill.dart';
import '../../../domain/set_format.dart';
import '../../../domain/units.dart';
import '../../regime/exercise_screen.dart';

/// Full exercise catalog, searchable. Shared by the log screen's swap/add flow
/// and the regime editor.
final exerciseCatalogProvider = StreamProvider<List<Exercise>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.exercises)
    ..where((t) => t.archived.equals(false) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.name)]);
  return query.watch();
});

/// What this exercise *is*, as opposed to what you can do to it.
///
/// Opened from the ⓘ beside the ⋯. It exists because the header had grown a
/// running commentary — a line under the exercise's name saying where today's
/// ghost values came from, or "First time — no previous log" when there was
/// nothing to say. That line is load-bearing when it names a session ("From
/// Push 2 · 12 Jul" is the one rule this app exists for), and pure noise when
/// it announces an absence, so the absence moved in here with the rest of the
/// facts that are true but not urgent mid-set.
Future<void> showExerciseInfo(
  BuildContext context,
  WidgetRef ref,
  ExerciseEntry entry,
  PrefillResult? prefill,
) async {
  final exercise = entry.exercise;
  final videos = exercise.formVideoUrls;
  final unit = ref.read(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
  // The bar this session is on, rather than whatever the catalog names today.
  // A day can override it and the logged row snapshots what was used, and the
  // keypad below this sheet already draws its plates off that — a catalog
  // answer here would state one fact twice on one screen, differently (rule 6).
  final bar = entry.workoutExercise.barKind ?? exercise.barKind;

  await showModalBottomSheet<void>(
    // The route holds the system bars: a sheet that sizes itself can
    // otherwise run under the status bar. See [pickExercise].
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    // `AppSheet` draws its own grab handle, tighter than the framework's.
    showDragHandle: false,
    builder: (sheetContext) => AppSheet(
      title: exercise.name,
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        if (exercise.notes != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.sm,
            ),
            child: Text(exercise.notes!, style: sheetContext.t.bodyMedium),
          ),
        // Nothing is borrowed any more, so nothing here is a warning. The
        // movement has been done, just not on this day, and that is worth
        // saying plainly: it tells you the ⓘ is not hiding a suggestion, and
        // it tells you where to look if you want the number yourself.
        if (prefill?.source == PrefillSource.otherSession)
          AppRow(
            icon: Icons.call_split_rounded,
            title: 'First time in this session',
            subtitle:
                'Last done in ${prefill!.reference!.sessionName} · '
                '${DateFormat('d MMM').format(dateFromDayKey(prefill.reference!.dayKey))}'
                '. This day starts blank',
          )
        else
          AppRow(
            icon: Icons.history_rounded,
            title: 'Last logged',
            subtitle: _prefillBlurb(prefill),
          ),
        AppRow(
          icon: Icons.fitness_center_rounded,
          title: '${exercise.muscle.label} · ${exercise.equipment.label}',
          subtitle: loadBlurb(exercise.loadMode),
        ),
        if (bar != BarKind.none)
          AppRow(
            icon: Icons.straighten_rounded,
            title: bar.label,
            subtitle: '${formatInUnit(bar.kg!, unit)} ${unit.label} empty',
          ),
        if (entry.workoutExercise.notes != null)
          AppRow(
            icon: Icons.sticky_note_2_outlined,
            title: "Today's note",
            subtitle: entry.workoutExercise.notes,
          ),
        for (var i = 0; i < videos.length; i++)
          AppRow(
            icon: Icons.play_circle_outline,
            title: videos.length == 1 ? 'Form video' : 'Form video ${i + 1}',
            subtitle: videos[i],
            onTap: () => launchUrl(
              Uri.parse(videos[i]),
              mode: LaunchMode.externalApplication,
            ),
          ),
      ],
    ),
  );
}

/// Where today's suggested numbers came from, spelled out.
///
/// The header prints the short version when there *is* one; this says the same
/// thing in a sentence, and is the only place the "nothing to go on" case is
/// stated at all.
String _prefillBlurb(PrefillResult? prefill) {
  final p = prefill;
  if (p == null || !p.hasSuggestion) {
    return 'First time here, with nothing to suggest from';
  }
  final reference = p.reference!;
  final date = DateFormat(
    'd MMM yyyy',
  ).format(dateFromDayKey(reference.dayKey));
  final scaled = p.deloadApplied ? ', scaled for the deload' : '';
  return switch (p.source) {
    PrefillSource.sameSession => '${reference.sessionName} · $date$scaled',
    PrefillSource.sameSessionDeload =>
      '${reference.sessionName} · $date · deload week$scaled',
    // Unreachable: an other-session result carries no sets, so `hasSuggestion`
    // is false and this returns above — and it has its own row anyway.
    PrefillSource.otherSession => '${reference.sessionName} · $date$scaled',
    PrefillSource.none => 'First time here, with nothing to suggest from',
  };
}

/// Actions available on an exercise mid-workout.
///
/// Everything here writes to the workout only — the session template is never
/// touched, so today's improvisation can't rewrite the programme or past logs.
Future<void> showExerciseMenu(
  BuildContext context,
  WidgetRef ref,
  ExerciseEntry entry, {
  required int index,
  required int total,
  required VoidCallback onReorder,
  required Workout workout,
}) async {
  final repo = ref.read(trainingRepositoryProvider);

  // **The way into this exercise's settings without leaving the session.**
  //
  // The template is safe to edit mid-workout — `WorkoutExercise` and `SetLog`
  // are snapshots rather than pointers (RULES § Data), which is exactly what
  // `live_workout_vs_editing_test.dart` proves — so nothing here was ever
  // blocked. There was simply no door: the exercise's own screen, and with it
  // the day's rest, bar, targets and deload, could only be reached from the
  // Regime tab, which means walking out of the session you are standing in.
  //
  // Resolved before the sheet is built, because the row's presence depends on
  // it: an exercise added mid-session is not in the template and has no slot,
  // and a row that opened onto an empty Overrides section would be a promise
  // the screen cannot keep.
  final slotId = await repo.slotIdFor(
    sessionId: workout.sessionId,
    exerciseId: entry.exercise.id,
  );
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    // The route holds the system bars: a sheet that sizes itself can
    // otherwise run under the status bar. See [pickExercise].
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    // `AppSheet` draws its own grab handle, tighter than the framework's.
    showDragHandle: false,
    builder: (sheetContext) => AppSheet(
      title: entry.exercise.name,
      // Actions only. The cue, the videos and where today's numbers came from
      // are facts about the exercise, and they live behind the ⓘ — a menu that
      // opens with two paragraphs before its first button is a page.
      //
      // Same construction as the session drawer in workout detail: full-bleed
      // `AppRow`s, no card, no rules between them. The two sheets are the same
      // object in two places and used to be built two different ways, so their
      // rows sat on different insets and their titles in different sizes.
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        // Today's note on today's exercise. Distinct from the cue above it,
        // which is the catalog's and permanent, and from a set's note, which
        // is one row: this one is how the movement felt in this session.
        AppRow(
          icon: Icons.sticky_note_2_outlined,
          title: entry.workoutExercise.notes == null
              ? 'Add a note for today'
              : "Edit today's note",
          subtitle:
              entry.workoutExercise.notes ??
              'This session only. The exercise keeps its cue.',
          onTap: () async {
            final navigator = Navigator.of(sheetContext);
            final note = await promptForNote(
              context,
              title: entry.exercise.name,
              subtitle: 'Note for today',
              initial: entry.workoutExercise.notes ?? '',
              hint: 'Shoulder felt off, bench was the wide one',
            );
            navigator.pop();
            if (note == null) return;
            await repo.setWorkoutExerciseNotes(entry.workoutExercise.id, note);
          },
        ),
        if (slotId != null)
          AppRow(
            icon: Icons.tune_rounded,
            title: 'Exercise settings',
            subtitle: 'Rest, bar, targets — for this day, from next time on',
            onTap: () {
              Navigator.of(sheetContext).pop();
              openExercise(
                context,
                exerciseId: entry.exercise.id,
                regimeId: workout.regimeId,
                sessionId: workout.sessionId,
                slotId: slotId,
              );
            },
          ),
        AppRow(
          icon: Icons.swap_horiz,
          title: 'Swap exercise',
          subtitle: 'Today only. The template keeps its version.',
          onTap: () async {
            final navigator = Navigator.of(sheetContext);
            final replacement = await pickExercise(context, ref);
            navigator.pop();
            if (replacement == null) return;
            // In place: same position, same target sets, set shape from the
            // replacement's own history. Remove-then-add used to drop it at
            // the end of the workout.
            await repo.replaceExerciseInWorkout(
              entry.workoutExercise.id,
              replacement.id,
            );
          },
        ),
        AppRow(
          icon: Icons.remove_circle_outline,
          title: entry.workoutExercise.skipReason == SkipReason.none
              ? 'Mark as skipped'
              : 'Un-skip',
          subtitle: 'Recorded with a reason, not just left blank',
          onTap: () async {
            final navigator = Navigator.of(sheetContext);
            if (entry.workoutExercise.skipReason != SkipReason.none) {
              await repo.setSkipReason(
                entry.workoutExercise.id,
                SkipReason.none,
              );
              navigator.pop();
              return;
            }
            final reason = await _pickSkipReason(context);
            navigator.pop();
            if (reason == null) return;
            await repo.setSkipReason(entry.workoutExercise.id, reason);
          },
        ),
        // One row that opens the whole order, rather than a pair of buttons
        // that nudge this one exercise a place at a time. Two directions is a
        // fine control for moving something *once*; it is a bad one for
        // arranging six movements, which is what you are actually doing when
        // you open this — and the rail's own long-press drag already exists for
        // the single nudge.
        if (total > 1)
          AppRow(
            icon: Icons.swap_vert_rounded,
            title: 'Re-order exercises',
            subtitle: 'Drag them into the order you are training them',
            onTap: () {
              Navigator.of(sheetContext).pop();
              onReorder();
            },
          ),
        AppRow(
          icon: Icons.delete_outline_rounded,
          title: 'Remove from this workout',
          subtitle: 'Takes any sets logged under it',
          tint: sheetContext.c.negative,
          onTap: () async {
            final navigator = Navigator.of(sheetContext);
            final logged = entry.sets.where((s) => s.isDone).length;
            // Only when there is something to lose. Removing an exercise you
            // have not started is a correction and asking about it is noise;
            // removing one you have logged four sets into deletes those four
            // sets, and it was one tap from a sheet with no way back.
            if (logged > 0) {
              final sure = await confirmAction(
                context,
                title: 'Remove ${entry.exercise.name}?',
                message:
                    '$logged logged set${logged == 1 ? '' : 's'} '
                    '${logged == 1 ? 'is' : 'are'} deleted with it. '
                    'This cannot be undone.',
                confirmLabel: 'Remove',
                cancelLabel: 'Keep it',
                destructive: true,
              );
              if (!sure) return;
            }
            await repo.removeExerciseFromWorkout(entry.workoutExercise.id);
            navigator.pop();
          },
        ),
      ],
    ),
  );
}

/// What each set type does, in the one line a row has room for. Only the three
/// offered in the set sheet: backoff, rest-pause and AMRAP exist in the data
/// and arrive from a template, but nothing types them by hand mid-session.
String _typeBlurb(SetType type) => switch (type) {
  SetType.working => 'Counts toward the top set and e1RM',
  // Half of what this used to say was untrue. A warm-up is out of the
  // progression maths — no top set, no e1RM, no volume — and it is *not*
  // out of last-time: the ramp is mirrored into next week's rows and
  // ghosted like any other set, which is the whole reason it is worth
  // typing one in.
  SetType.warmup => 'Out of progression, filled from last time',
  SetType.drop => 'Continues the set above it, lighter',
  _ => '',
};

/// What the set sheet calls itself.
///
/// A working set is numbered, because that number is what the table shows and
/// what "beat last time" is measured against. Every other type is *named*: its
/// chip is a letter, and "Set W" reads as a set called W.
String _setTitle(SetType type, String label, int? leg) {
  final head = type == SetType.working ? 'Set $label' : '${type.label} set';
  return leg == null ? head : '$head · leg $leg';
}

/// Everything you can do to one set.
///
/// Opened from the set's type chip. Swipe-to-delete is not an option any more:
/// the log pages sideways, and a horizontal drag on a row would be ambiguous
/// with turning the page.
Future<void> showSetActions(
  BuildContext context,
  WidgetRef ref,
  SetLog set, {

  /// The working-set number the row's chip prints. Not the raw position: the
  /// sheet used to head itself "Set 4" for the row marked `2` whenever
  /// warm-ups or drop legs sat above it, because it counted rows.
  ///
  /// Only used for a working set. A warm-up's chip prints `W` and a drop leg's
  /// prints `D`, which are marks on a table, not names — heading a sheet
  /// "Set W" said nothing.
  required String label,

  /// Which leg of a drop group, counting the head as 1. Null for a set that is
  /// not part of one.
  int? leg,

  /// Everything this delete removes. A drop group's head takes its legs.
  required List<String> deleteIds,
}) async {
  final repo = ref.read(trainingRepositoryProvider);

  await showModalBottomSheet<void>(
    // The route holds the system bars: a sheet that sizes itself can
    // otherwise run under the status bar. See [pickExercise].
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    // `AppSheet` draws its own grab handle, tighter than the framework's.
    showDragHandle: false,
    builder: (sheetContext) => AppSheet(
      title: _setTitle(set.setType, label, leg),
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        // A picker, built the way every other picker in the app is: rows with
        // the live one ticked. It was a strip of chips, which made this the
        // only sheet where choosing something meant hitting a pill instead of
        // a row, and the chips carried no room to say what a type does.
        // Working first, because it is what almost every row already is and
        // what a mis-typed row is being put back to.
        for (final type in const [
          SetType.working,
          SetType.warmup,
          SetType.drop,
        ]) ...[
          AppRow(
            icon: type == set.setType
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            title: type.label,
            subtitle: _typeBlurb(type),
            onTap: () async {
              final navigator = Navigator.of(sheetContext);
              // The group side of the change — the first leg of a new drop
              // set, the release of the legs of one that stops being a drop —
              // belongs with the write, not here.
              await repo.setSetType(set.id, type);
              navigator.pop();
            },
          ),
        ],
        AppRow(
          icon: Icons.sticky_note_2_outlined,
          title: set.note == null ? 'Add a note' : 'Edit note',
          subtitle: set.note ?? 'Felt heavy, elbow tucked, …',
          onTap: () async {
            final navigator = Navigator.of(sheetContext);
            final note = await promptForNote(
              context,
              title: 'Set note',
              initial: set.note ?? '',
              hint: 'Felt heavy, elbow tucked, …',
              // Shorter than a session's: this one is rendered under a set row
              // in the log and under a set line in history, where anything
              // longer than a phrase pushes the table apart.
              maxLength: 200,
            );
            navigator.pop();
            if (note == null) return;
            await repo.updateSet(
              set.id,
              note: Value(note.isEmpty ? null : note),
            );
          },
        ),
        AppRow(
          icon: Icons.delete_outline_rounded,
          title: deleteIds.length > 1 ? 'Delete drop set' : 'Delete set',
          subtitle: deleteIds.length > 1
              ? 'Removes all ${deleteIds.length} legs'
              : 'Removes this row',
          tint: sheetContext.c.negative,
          onTap: () async {
            final navigator = Navigator.of(sheetContext);
            await repo.deleteSets(deleteIds);
            navigator.pop();
          },
        ),
      ],
    ),
  );
}

Future<SkipReason?> _pickSkipReason(BuildContext context) {
  final reasons = SkipReason.values.where((r) => r != SkipReason.none).toList();
  return showModalBottomSheet<SkipReason>(
    // The route holds the system bars: a sheet that sizes itself can
    // otherwise run under the status bar. See [pickExercise].
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    // `AppSheet` draws its own grab handle, tighter than the framework's.
    showDragHandle: false,
    builder: (ctx) => AppSheet(
      title: 'Why skipped?',
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        for (var i = 0; i < reasons.length; i++) ...[
          if (i > 0) Divider(color: ctx.c.border, height: 1, indent: Space.lg),
          AppRow(
            title: reasons[i].label,
            onTap: () => Navigator.of(ctx).pop(reasons[i]),
          ),
        ],
      ],
    ),
  );
}

/// The catalog picker: search, muscle chips, one row per movement.
///
/// The same sheet mid-session and in the programme editor, because it answers
/// the same question in both — which of my movements is this. It keeps its own
/// header rather than using `AppSheet`, since the list under the chips has to
/// scroll inside a bounded height while the search and the chips stay put.
/// [alreadyIn] marks the movements the caller is already carrying — the
/// exercises in the running workout, or the slots in the session being edited.
///
/// Marked rather than removed or refused. Running the same movement twice in a
/// day is a real thing to do, and the picker cannot tell a second pass from a
/// mis-tap — but it can stop the mis-tap being invisible, which is what it was:
/// the rail grew a second identical tab and nothing said why.
Future<Exercise?> pickExercise(
  BuildContext context,
  WidgetRef ref, {
  Set<String> alreadyIn = const {},
}) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    // **The route holds the system bars, not the sheet.** `useSafeArea`
    // defaults to false, and with `isScrollControlled` that lets the sheet take
    // the whole screen — the status bar included, which is where `Exercises`
    // ended up drawn across the clock and the battery.
    //
    // It could not be fixed inside the sheet, and that was three attempts
    // finding out. A modal route reports **both** `padding` and `viewPadding`
    // as zero to its own child — measured on a phone, not assumed:
    // `padding=(t0.0,b0.0) viewPadding=(t0.0,b0.0)` with the keyboard up. So
    // every arithmetic version of this was reading `max(0, 0)` and reserving
    // nothing. The inset is the route's to know.
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => _ExercisePicker(alreadyIn: alreadyIn),
  );
}

class _ExercisePicker extends ConsumerStatefulWidget {
  const _ExercisePicker({this.alreadyIn = const {}});

  final Set<String> alreadyIn;

  @override
  ConsumerState<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<_ExercisePicker> {
  String _query = '';

  /// Null is `All`. Chips filter, the field searches, and they compose: `Chest`
  /// plus "press" is a shorter list than either on its own.
  MuscleGroup? _muscle;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exerciseCatalogProvider).valueOrNull ?? const [];
    final q = _query.trim().toLowerCase();
    final filtered = all
        .where(
          (e) =>
              (_muscle == null || e.muscle == _muscle) &&
              (q.isEmpty || e.name.toLowerCase().contains(q)),
        )
        .toList();

    // Only the muscles something is filed under, in `MuscleGroup` order so a
    // chip holds its place as the catalog grows.
    final present = [
      for (final m in MuscleGroup.values)
        if (all.any((e) => e.muscle == m)) m,
    ];

    // Eight tenths of the screen, or whatever is left above the keyboard —
    // whichever is less. The two were added together before: the sheet reserved
    // the keyboard *and* then asked for 80% of the whole phone, so with the pad
    // up it wanted 115% of the screen. This is the one sheet that opens with a
    // field focused, so it was the one where that always happened.
    //
    // **Reserved in one number, the way `AppSheet` does it**, because this
    // sheet builds its own column and has to answer the same question itself.
    //
    // It used to reserve the keyboard in the padding and leave the gesture bar
    // to an inner `SafeArea`. Split like that, neither half is reliable: the
    // height was computed against `viewInsets` alone, so the box asked for more
    // room than there was above the bar, and the `SafeArea` could only inset
    // content *within* a box already too tall — on a phone reporting no
    // `viewPadding` to the sheet's own `MediaQuery` it inset nothing, and the
    // list ran under the navigation bar.
    //
    // `viewInsets.bottom + padding.bottom` is the right sum for the reason
    // `AppSheet` gives: the two never overlap, because `padding` is what the
    // system chrome covers that the keyboard does not, so with the keyboard up
    // the gesture bar is already excluded from it.
    final media = MediaQuery.of(context);
    final reserved = media.viewInsets.bottom + media.padding.bottom;

    // No top term. Both `padding.top` and `viewPadding.top` read zero inside a
    // modal route, so there is nothing here to subtract — `useSafeArea` on the
    // route is what keeps this sheet off the status bar, and it is the only
    // thing that can.
    final available = media.size.height - reserved;
    return Padding(
      padding: EdgeInsets.only(bottom: reserved),
      child: SizedBox(
        height: math.min(media.size.height * 0.8, available),
        child: SafeArea(
          // Sides only: the top is held by the height above and the bottom by
          // `reserved`. Letting `SafeArea` add either again double-pads it.
          top: false,
          // Sides only. The bottom is reserved above, and letting `SafeArea`
          // add it again double-pads the sheet.
          bottom: false,
          child: Column(
            children: [
              const SheetHeader(title: 'Exercises'),
              Padding(
                padding: searchFieldPadding,
                child: SearchField(
                  hint: 'Search exercises',
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (present.length > 1)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      0,
                      Space.gutter,
                      Space.md,
                    ),
                    children: [
                      AppChip(
                        label: 'All',
                        selected: _muscle == null,
                        onTap: () => setState(() => _muscle = null),
                      ),
                      for (final m in present) ...[
                        const SizedBox(width: Space.sm),
                        AppChip(
                          label: m.label,
                          hue: context.c.forMuscle(m),
                          selected: _muscle == m,
                          onTap: () =>
                              setState(() => _muscle = _muscle == m ? null : m),
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: filtered.isEmpty && q.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off,
                        title: 'No exercises yet',
                        message: 'Search for a name to create your first one.',
                      )
                    : ListView.builder(
                        // A trailing "create" row whenever there is a search
                        // term: hitting a gym with a machine the app has never
                        // heard of should not be a dead end mid-session.
                        itemCount: filtered.length + (q.isEmpty ? 0 : 1),
                        itemBuilder: (context, i) {
                          if (i == filtered.length) {
                            return AppRow(
                              icon: Icons.add_rounded,
                              title: 'Create "${_query.trim()}"',
                              onTap: () => _create(context, ref, _query.trim()),
                            );
                          }
                          final e = filtered[i];
                          return AppRow(
                            title: e.name,
                            // Tappable here for the same reason as in the catalog
                            // (THEME → Components): the muscle you can see is the filter.
                            subtitleLeading: AppChip(
                              label: e.muscle.label,
                              dense: true,
                              hue: context.c.forMuscle(e.muscle),
                              selected: _muscle == e.muscle,
                              onTap: () => setState(
                                () => _muscle = _muscle == e.muscle
                                    ? null
                                    : e.muscle,
                              ),
                            ),
                            subtitle: e.equipment.label,
                            trailing: widget.alreadyIn.contains(e.id)
                                ? const Pill('Already in')
                                : null,
                            onTap: () => Navigator.of(context).pop(e),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref, String name) async {
    if (name.isEmpty) return;
    final navigator = Navigator.of(context);
    // The exercise's own screen, not a form sheet on top of a picker sheet:
    // creating a movement and editing one are the same page (see
    // `ExerciseScreen`).
    final created = await createExerciseFlow(context, initialName: name);
    if (created != null) navigator.pop(created);
  }
}
