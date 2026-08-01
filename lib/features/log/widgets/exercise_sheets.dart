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
import '../../../data/repositories/regime_repository.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/prefill.dart';
import '../../../domain/units.dart';

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
  final bar = exercise.barKind;

  await showModalBottomSheet<void>(
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
                Space.lg, Space.md, Space.lg, Space.sm),
            child: Text(exercise.notes!, style: sheetContext.t.bodyMedium),
          ),
        // Borrowed is a warning, not a fact, and it is the reason the ⓘ wears
        // a dot — so this row wears the same dot in the same amber. The colour
        // carries meaning here (rule 1: hue is data), and the meaning is "these
        // numbers are not this session's".
        if (prefill?.source == PrefillSource.otherSession)
          // One row, one sentence. The explanation was a second paragraph
          // hanging under it on its own insets, in its own size, saying in
          // three lines what the row can say in one.
          AppRow(
            icon: Icons.call_split_rounded,
            title: 'Borrowed from ${prefill!.reference!.sessionName}',
            subtitle: 'First time here — '
                '${DateFormat('d MMM').format(dateFromDayKey(prefill.reference!.dayKey))}'
                "'s numbers, until you log your own",
            tint: sheetContext.c.deload,
            trailing: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: sheetContext.c.deload,
                shape: BoxShape.circle,
              ),
            ),
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
          subtitle: _loadBlurb(exercise.loadMode),
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

/// What the number you type into this exercise means.
String _loadBlurb(LoadMode mode) => switch (mode) {
      LoadMode.total => 'The weight you type is the whole load',
      LoadMode.perSide => 'The weight you type is per hand — two are moving',
      LoadMode.bodyweight => 'Reps only, no external load',
      LoadMode.bodyweightPlus => 'Bodyweight plus anything you add',
    };

/// Where today's suggested numbers came from, spelled out.
///
/// The header prints the short version when there *is* one; this says the same
/// thing in a sentence, and is the only place the "nothing to go on" case is
/// stated at all.
String _prefillBlurb(PrefillResult? prefill) {
  final p = prefill;
  if (p == null || !p.hasSuggestion) {
    return 'First time — nothing to suggest from';
  }
  final reference = p.reference!;
  final date = DateFormat('d MMM yyyy')
      .format(dateFromDayKey(reference.dayKey));
  final scaled = p.deloadApplied ? ', scaled for the deload' : '';
  return switch (p.source) {
    PrefillSource.sameSession => '${reference.sessionName} · $date$scaled',
    PrefillSource.sameSessionDeload =>
      '${reference.sessionName} · $date · deload week$scaled',
    // The borrowed case has its own row, in amber, above.
    PrefillSource.otherSession =>
      '${reference.sessionName} · $date$scaled',
    PrefillSource.none => 'First time — nothing to suggest from',
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
  required ValueChanged<int> onMove,
}) async {
  final repo = ref.read(trainingRepositoryProvider);

  await showModalBottomSheet<void>(
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
          subtitle: entry.workoutExercise.notes ??
              'This session only — the exercise keeps its cue',
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
        AppRow(
          icon: Icons.swap_horiz,
          title: 'Swap exercise',
          subtitle: 'Today only — the template keeps its version',
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
                  entry.workoutExercise.id, SkipReason.none);
              navigator.pop();
              return;
            }
            final reason = await _pickSkipReason(context);
            navigator.pop();
            if (reason == null) return;
            await repo.setSkipReason(entry.workoutExercise.id, reason);
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
        // Drag-to-reorder went away with the vertical list; moving an exercise
        // is an explicit step so it can't happen by accident while turning
        // pages. Buttons, not rows: it is a pair of directions, not an action.
        if (total > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.lg, Space.lg, Space.xs),
            child: Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Move earlier',
                    icon: Icons.arrow_back_rounded,
                    onPressed: index == 0
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            onMove(-1);
                          },
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: SecondaryButton(
                    label: 'Move later',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: index >= total - 1
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            onMove(1);
                          },
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// What each set type does, in the one line a row has room for. Only the three
/// offered in the set sheet: backoff, rest-pause and AMRAP exist in the data
/// and arrive from a template, but nothing types them by hand mid-session.
String _typeBlurb(SetType type) => switch (type) {
      SetType.warmup => 'Ignored by progression and by last-time',
      SetType.working => 'Counts toward the top set and e1RM',
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
        for (final type in const [
          SetType.warmup,
          SetType.working,
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
  final reasons =
      SkipReason.values.where((r) => r != SkipReason.none).toList();
  return showModalBottomSheet<SkipReason>(
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
Future<Exercise?> pickExercise(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => const _ExercisePicker(),
  );
}

class _ExercisePicker extends ConsumerStatefulWidget {
  const _ExercisePicker();

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
    final c = context.c;
    final all = ref.watch(exerciseCatalogProvider).valueOrNull ?? const [];
    final q = _query.trim().toLowerCase();
    final filtered = all
        .where((e) =>
            (_muscle == null || e.muscle == _muscle) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
        .toList();

    // Only the muscles something is filed under, in `MuscleGroup` order so a
    // chip holds its place as the catalog grows.
    final present = [
      for (final m in MuscleGroup.values)
        if (all.any((e) => e.muscle == m)) m,
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const SheetHeader(title: 'Exercises'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.gutter, Space.md, Space.gutter, Space.md),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: context.t.bodyLarge?.copyWith(color: c.textPrimary),
                cursorColor: c.textPrimary,
                decoration: InputDecoration(
                  hintText: 'Search exercises',
                  hintStyle:
                      context.t.bodyLarge?.copyWith(color: c.textTertiary),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: c.textTertiary),
                  filled: true,
                  fillColor: c.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide(color: c.textPrimary, width: 2),
                  ),
                ),
              ),
            ),
            if (present.length > 1)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                      Space.gutter, 0, Space.gutter, Space.md),
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
                          subtitle:
                              '${e.muscle.label} · ${e.equipment.label}',
                          onTap: () => Navigator.of(context).pop(e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref, String name) async {
    if (name.isEmpty) return;
    final navigator = Navigator.of(context);
    final created = await showExerciseEditor(context, initialName: name);
    if (created != null) navigator.pop(created);
  }
}

/// Create or edit one catalog entry. Returns the saved row, or null if
/// dismissed.
Future<Exercise?> showExerciseEditor(
  BuildContext context, {
  String initialName = '',
  Exercise? existing,
}) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExerciseFormSheet(name: initialName, existing: existing),
  );
}

/// Minimal exercise form.
///
/// Only asks for what changes the maths: muscle and equipment are labels, but
/// load mode decides whether "22.5" means 22.5kg or 45kg, so it gets a plain
/// explanation rather than a bare enum name.
class _ExerciseFormSheet extends ConsumerStatefulWidget {
  const _ExerciseFormSheet({required this.name, this.existing});

  final String name;
  final Exercise? existing;

  @override
  ConsumerState<_ExerciseFormSheet> createState() => _ExerciseFormSheetState();
}

class _ExerciseFormSheetState extends ConsumerState<_ExerciseFormSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? widget.name);
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late MuscleGroup _muscle = widget.existing?.muscle ?? MuscleGroup.chest;
  late Equipment _equipment = widget.existing?.equipment ?? Equipment.machine;
  late LoadMode _loadMode = widget.existing?.loadMode ?? LoadMode.total;
  late BarKind _barKind = widget.existing?.barKind ?? BarKind.none;
  late bool _loadModeTouched = widget.existing != null;
  late bool _barTouched = widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Equipment implies the usual load mode and bar; only stop guessing once the
  /// user has set them themselves.
  void _setEquipment(Equipment value) {
    setState(() {
      _equipment = value;
      if (!_barTouched) {
        // The common bar, not the only one — an EZ-bar curl is two taps from
        // here, and everything that is not a barbell has no bar at all.
        _barKind =
            value == Equipment.barbell ? BarKind.olympic : BarKind.none;
      }
      if (_loadModeTouched) return;
      _loadMode = switch (value) {
        Equipment.dumbbell => LoadMode.perSide,
        Equipment.bodyweight => LoadMode.bodyweightPlus,
        _ => LoadMode.total,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final existing = widget.existing;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      // The one sheet in the app that wore its own header — a bare title, its
      // own insets, and a Material button at the bottom — while every other
      // one used `AppSheet`. Same form, in the app's sheet.
      child: AppSheet(
        title: existing == null ? 'New exercise' : 'Edit exercise',
        // Identifies, or it is not there (§5): on a new one there is nothing
        // to name yet, and the title already says which question is being
        // asked.
        subtitle: existing?.name,
        footer: PrimaryButton(
          label: existing == null ? 'Create' : 'Save',
          onPressed: _save,
        ),
        children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  filled: true,
                  fillColor: c.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              _Dropdown<MuscleGroup>(
                label: 'Muscle',
                value: _muscle,
                values: MuscleGroup.values,
                nameOf: (v) => v.label,
                onChanged: (v) => setState(() => _muscle = v),
              ),
              const SizedBox(height: Space.md),
              _Dropdown<Equipment>(
                label: 'Equipment',
                value: _equipment,
                values: Equipment.values,
                nameOf: (v) => v.label,
                onChanged: _setEquipment,
              ),
              const SizedBox(height: Space.md),
              _Dropdown<LoadMode>(
                label: 'How the weight is entered',
                value: _loadMode,
                values: LoadMode.values,
                nameOf: (v) => switch (v) {
                  LoadMode.total => 'Total load (machine, barbell, cable)',
                  LoadMode.perSide => 'Per dumbbell (two are moved)',
                  LoadMode.bodyweight => 'Bodyweight only',
                  LoadMode.bodyweightPlus => 'Bodyweight plus added weight',
                },
                onChanged: (v) => setState(() {
                  _loadMode = v;
                  _loadModeTouched = true;
                }),
              ),
              // Only for a total load: the plate view breaks a barbell total
              // into plates, and there is nothing to break down when the
              // number means one dumbbell or what is hanging off a belt.
              if (_loadMode == LoadMode.total) ...[
                const SizedBox(height: Space.md),
                _Dropdown<BarKind>(
                  label: 'Bar',
                  value: _barKind,
                  values: BarKind.values,
                  nameOf: (v) => v == BarKind.none
                      ? v.label
                      : '${v.label} · ${formatInUnit(v.kg!, WeightUnit.kg)} kg',
                  onChanged: (v) => setState(() {
                    _barKind = v;
                    _barTouched = true;
                  }),
                ),
              ],
              const SizedBox(height: Space.md),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Cues (optional)',
                  filled: true,
                  fillColor: c.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
          // Archive rather than delete: past workouts point at this row, and
          // history with a hole in it is worse than a catalog with one extra
          // entry. It lives here rather than on the catalog row because it is
          // a thing you do to an exercise, and this sheet is the exercise —
          // and because a per-row archive button put a control on eighty rows
          // to be used twice a year.
          if (existing != null) ...[
            const SizedBox(height: Space.lg),
            SecondaryButton(
              label: existing.archived
                  ? 'Restore to the catalog'
                  : 'Archive this exercise',
              icon: existing.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              onPressed: () => _setArchived(existing, !existing.archived),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setArchived(Exercise exercise, bool archived) async {
    final navigator = Navigator.of(context);
    await RegimeRepository(
      ref.read(databaseProvider),
    ).updateExercise(exercise.id, archived: Value(archived));
    navigator.pop();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final navigator = Navigator.of(context);
    final db = ref.read(databaseProvider);
    final repo = RegimeRepository(db);
    final notes = _notes.text.trim();

    // Two rows with the same name are indistinguishable in the picker, and the
    // picker is where you choose what a set gets logged against. Archived rows
    // count: they are one tap from being restored, and restoring one into a
    // collision is the state this check exists to prevent.
    final clash = await (db.select(db.exercises)
          ..where((t) => t.name.equals(name) & t.deletedAt.isNull()))
        .get();
    final duplicates =
        clash.where((e) => e.id != widget.existing?.id).toList();
    if (duplicates.isNotEmpty) {
      if (!mounted) return;
      final archived = duplicates.every((e) => e.archived);
      final ok = await confirmAction(
        context,
        title: 'There is already a "$name"',
        message: archived
            ? 'An archived exercise has this name. Restoring it later would '
                'leave two you cannot tell apart in the picker — restore that '
                'one instead?'
            : 'Two exercises with the same name are impossible to tell apart '
                'when picking one mid-session. Keep both?',
        confirmLabel: 'Keep both',
        destructive: false,
      );
      if (!ok) return;
    }

    final id = widget.existing?.id;
    if (id == null) {
      final created = await repo.createExercise(
        name: name,
        muscle: _muscle,
        equipment: _equipment,
        loadMode: _loadMode,
        barKind: _barKind,
        notes: notes.isEmpty ? null : notes,
      );
      navigator.pop(await _row(db, created));
      return;
    }

    // Load mode is the one field that is not a label: it decides how every set
    // ever logged for this movement is read. Flipping "total" to "per
    // dumbbell" doubles the effective load of all of them, moving e1RM, the
    // chart, the beat-last-time highlight and every prefill comparison. No
    // migration — the reinterpretation is the point — but it has to be chosen
    // knowingly, with the number in front of you.
    if (_loadMode != widget.existing!.loadMode) {
      final affected = await ref
          .read(trainingRepositoryProvider)
          .loggedSetCount(id);
      if (affected > 0) {
        if (!mounted) return;
        final ok = await confirmAction(
          context,
          title: 'Change how this load is read?',
          message: '$affected logged '
              '${affected == 1 ? 'set' : 'sets'} will be re-read as '
              '${_loadModeName(_loadMode)}. Their estimated 1RMs, the progress '
              'chart and every "beat last time" comparison move with them.',
          confirmLabel: 'Change it',
          destructive: false,
        );
        if (!ok) return;
      }
    }

    // Editing the catalog row is otherwise safe: past logs point at the
    // exercise, but the numbers they hold are their own snapshot.
    await repo.updateExercise(
      id,
      name: Value(name),
      muscle: Value(_muscle),
      equipment: Value(_equipment),
      loadMode: Value(_loadMode),
      barKind: Value(_barKind),
      notes: Value(notes.isEmpty ? null : notes),
    );
    navigator.pop(await _row(db, id));
  }

  static String _loadModeName(LoadMode mode) => switch (mode) {
        LoadMode.total => 'a total load',
        LoadMode.perSide => 'per dumbbell',
        LoadMode.bodyweight => 'bodyweight only',
        LoadMode.bodyweightPlus => 'bodyweight plus the entered load',
      };

  Future<Exercise> _row(AppDatabase db, String id) =>
      (db.select(db.exercises)..where((t) => t.id.equals(id))).getSingle();
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.nameOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) nameOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: c.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.md),
          items: [
            for (final v in values)
              DropdownMenuItem(
                value: v,
                child: Text(nameOf(v), style: context.t.bodyMedium),
              ),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}
