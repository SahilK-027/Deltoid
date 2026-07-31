import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/regime_repository.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/enums.dart';

/// Full exercise catalog, searchable. Shared by the log screen's swap/add flow
/// and the regime editor.
final exerciseCatalogProvider = StreamProvider<List<Exercise>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.exercises)
    ..where((t) => t.archived.equals(false) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.name)]);
  return query.watch();
});

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
  final videos = entry.exercise.formVideoUrls;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
            child: Text(entry.exercise.name, style: sheetContext.t.titleLarge),
          ),
          if (entry.exercise.notes != null)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
              child: Text(
                entry.exercise.notes!,
                style: sheetContext.t.bodySmall,
              ),
            ),
          for (var i = 0; i < videos.length; i++)
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(videos.length == 1 ? 'Form video' : 'Form video ${i + 1}'),
              subtitle: Text(
                videos[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sheetContext.t.labelSmall,
              ),
              onTap: () => launchUrl(
                Uri.parse(videos[i]),
                mode: LaunchMode.externalApplication,
              ),
            ),
          // Drag-to-reorder went away with the vertical list; moving an
          // exercise is now an explicit step so it can't happen by accident
          // while turning pages.
          if (total > 1)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Move earlier'),
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
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Move later'),
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
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Swap exercise'),
            subtitle: const Text('Today only — the template keeps its version'),
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
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: Text(
              entry.workoutExercise.skipReason == SkipReason.none
                  ? 'Mark as skipped'
                  : 'Un-skip',
            ),
            subtitle: const Text('Recorded with a reason, not just left blank'),
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
          ListTile(
            leading: Icon(Icons.delete_outline, color: sheetContext.c.negative),
            title: Text(
              'Remove from this workout',
              style: TextStyle(color: sheetContext.c.negative),
            ),
            onTap: () async {
              final navigator = Navigator.of(sheetContext);
              await repo.removeExerciseFromWorkout(entry.workoutExercise.id);
              navigator.pop();
            },
          ),
          const SizedBox(height: Space.sm),
        ],
      ),
    ),
  );
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
  /// What the row's chip prints — `2`, `W`, `D`. Not the raw position: the
  /// sheet used to head itself "Set 4" for the row marked `2` whenever
  /// warm-ups or drop legs sat above it, because it counted rows.
  required String label,

  /// Everything this delete removes. A drop group's head takes its legs.
  required List<String> deleteIds,
}) async {
  final repo = ref.read(trainingRepositoryProvider);

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
              child: Text('Set $label', style: sheetContext.t.titleLarge),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text('TYPE', style: sheetContext.t.labelSmall),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final type in const [
                    SetType.warmup,
                    SetType.working,
                    SetType.drop,
                  ])
                    GestureDetector(
                      onTap: () {
                        repo.updateSet(set.id, setType: Value(type));
                        Navigator.of(sheetContext).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: Space.sm,
                        ),
                        decoration: BoxDecoration(
                          color: type == set.setType
                              ? sheetContext.c.accent
                              : sheetContext.c.surfaceHigh,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          type.label,
                          style: sheetContext.t.titleSmall?.copyWith(
                            color: type == set.setType
                                ? sheetContext.c.onAccent
                                : sheetContext.c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(color: sheetContext.c.border, height: 1),
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(set.note == null ? 'Add a note' : 'Edit note'),
              subtitle: set.note == null ? null : Text(set.note!),
              onTap: () async {
                final navigator = Navigator.of(sheetContext);
                final note = await _promptNote(context, set.note);
                navigator.pop();
                if (note == null) return;
                await repo.updateSet(
                  set.id,
                  note: Value(note.isEmpty ? null : note),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: sheetContext.c.negative),
              title: Text(
                deleteIds.length > 1 ? 'Delete drop set' : 'Delete set',
                style: TextStyle(color: sheetContext.c.negative),
              ),
              subtitle: deleteIds.length > 1
                  ? Text('Removes all ${deleteIds.length} legs')
                  : null,
              onTap: () async {
                final navigator = Navigator.of(sheetContext);
                await repo.deleteSets(deleteIds);
                navigator.pop();
              },
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _promptNote(BuildContext context, String? initial) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Set note'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Felt heavy, elbow tucked, …',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<SkipReason?> _pickSkipReason(BuildContext context) {
  return showModalBottomSheet<SkipReason>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
            child: Text('Why skipped?', style: ctx.t.titleLarge),
          ),
          for (final r in SkipReason.values.where((r) => r != SkipReason.none))
            ListTile(
              title: Text(r.label),
              onTap: () => Navigator.of(ctx).pop(r),
            ),
        ],
      ),
    ),
  );
}

/// Searchable exercise picker.
Future<Exercise?> pickExercise(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
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

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exerciseCatalogProvider).valueOrNull ?? const [];
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all.where((e) => e.name.toLowerCase().contains(q)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search exercises',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: context.c.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide.none,
                  ),
                ),
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
                          return ListTile(
                            leading: Icon(Icons.add, color: context.c.accent),
                            title: Text(
                              'Create "${_query.trim()}"',
                              style: context.t.titleSmall
                                  ?.copyWith(color: context.c.accent),
                            ),
                            onTap: () => _create(context, ref, _query.trim()),
                          );
                        }
                        final e = filtered[i];
                        return ListTile(
                          title: Text(e.name),
                          subtitle: Text(
                            '${e.muscle.label} · ${e.equipment.label}',
                            style: context.t.labelSmall,
                          ),
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
  late bool _loadModeTouched = widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Equipment implies the usual load mode; only stop guessing once the user
  /// has set it themselves.
  void _setEquipment(Equipment value) {
    setState(() {
      _equipment = value;
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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'New exercise' : 'Edit exercise',
                style: context.t.titleLarge,
              ),
              const SizedBox(height: Space.lg),
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
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: _save,
                child: Text(widget.existing == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
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
