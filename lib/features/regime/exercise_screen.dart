import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/regime_repository.dart';
import '../../domain/enums.dart';
import '../../domain/units.dart';
import '../history/exercise_history_screen.dart';
import 'regime_screen.dart';
import 'regime_settings.dart';
import '../../core/widgets/toast.dart';

/// One catalog row, watched so an edit made here redraws the screen it was
/// made on.
final exerciseByIdProvider =
    StreamProvider.family<Exercise?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.exercises)
    ..where((t) => t.id.equals(id) & t.deletedAt.isNull())
    ..limit(1);
  return query.watchSingleOrNull();
});

/// **One screen for an exercise, wherever you came from.**
///
/// There were two shapes doing this job: a read-only slot screen whose
/// `General` section listed the exercise and handed off to an `Edit` sheet, and
/// that sheet — a stack of dropdowns and text fields with its own header and
/// its own Save. So editing a movement looked nothing like looking at one, and
/// creating a movement looked like neither. Three UIs for one noun.
///
/// This is the noun's screen. It is the same page every time:
///
/// * **Overrides**, only when you arrived from a training day — the things that
///   are true of this exercise *in that day*, which is the one section that has
///   no meaning anywhere else.
/// * **General**, always — the catalog row itself, as ordinary rows you tap,
///   not a form. Every screen in this app edits by opening one question at a
///   time (THEME → Components); this one was the exception.
///
/// Existing rows **save as you go**, like every other settings surface here. A
/// new one holds a draft until `Create`, because a half-filled exercise
/// abandoned by a back-swipe should not be in the catalog.
class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({
    super.key,
    this.exerciseId,
    this.initialName = '',
    this.regimeId,
    this.sessionId,
    this.slotId,
  });

  /// Null when this screen is creating one.
  final String? exerciseId;

  /// Prefills the name of a new exercise — typed into the picker's search box
  /// before finding nothing.
  final String initialName;

  /// The day this was opened from, if any. All three arrive together.
  final String? regimeId;
  final String? sessionId;
  final String? slotId;

  bool get isNew => exerciseId == null;
  bool get fromDay => slotId != null;

  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen> {
  // The draft, used only while creating. An existing row is the source of
  // truth for itself and is written to on every change.
  late String _name = widget.initialName.trim();
  // Null until chosen. A new exercise answers every one of these before it can
  // be created — see [_complete]. They were pre-set to chest / machine / total
  // load, which is a guess wearing the clothes of an answer: tap Create without
  // reading and you have filed a cable fly under chest-machine-total, and load
  // mode is the field that decides how every set you ever log against it is
  // read.
  MuscleGroup? _muscle;
  Equipment? _equipment;
  LoadMode? _loadMode;
  BarKind? _barKind;

  /// Not in [_complete], unlike every other field on this screen. Reps is not a
  /// guess: it is what a movement is unless it is a plank, and the row states
  /// it rather than hiding behind `Choose`. Making it a fourth required answer
  /// would put a question in front of every new exercise to hear `Reps` back
  /// ninety-nine times in a hundred.
  MeasureMode _measureMode = MeasureMode.reps;

  String? _notes;
  bool _saving = false;

  RegimeRepository get _repo => RegimeRepository(ref.read(databaseProvider));

  /// Every question answered. `Create exercise` stays off until it is.
  ///
  /// The cue is the one field not in here, and deliberately: it is a note in
  /// the user's own words about a movement they may not have performed yet.
  /// Demanding one would mean inventing something to type.
  ///
  /// `Bar` counts only for a total load, because that is the only load a bar
  /// can be subtracted from — for anything else the row is not on screen, and a
  /// question that isn't asked cannot be outstanding.
  bool get _complete =>
      _name.trim().isNotEmpty &&
      _muscle != null &&
      _equipment != null &&
      _loadMode != null &&
      (_loadMode != LoadMode.total || _barKind != null);

  @override
  Widget build(BuildContext context) {
    if (widget.isNew) return _scaffold(context, null);

    final async = ref.watch(exerciseByIdProvider(widget.exerciseId!));
    final exercise = async.valueOrNull;
    if (exercise == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exercise')),
        body: async.hasValue
            ? const EmptyState(
                icon: Icons.delete_outline,
                title: 'Removed',
                message: 'This exercise is no longer in the catalog.',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    return _scaffold(context, exercise);
  }

  Widget _scaffold(BuildContext context, Exercise? exercise) {
    final c = context.c;

    // The slot, when there is one. Null while its day is still loading, and
    // null for good once the slot is removed from under the screen.
    final slots = widget.fromDay
        ? ref.watch(sessionSlotsProvider(widget.sessionId!)).valueOrNull
        : null;
    final entry = slots?.where((s) => s.slot.id == widget.slotId).firstOrNull;
    final sessions = widget.fromDay
        ? ref.watch(sessionsForRegimeProvider(widget.regimeId!)).valueOrNull ??
            const <Session>[]
        : const <Session>[];
    final session =
        sessions.where((s) => s.id == widget.sessionId).firstOrNull;
    final regime = widget.fromDay
        ? ref.watch(regimeByIdProvider(widget.regimeId!)).valueOrNull
        : null;
    final dayName = session?.name ?? 'this day';

    final name = exercise?.name ?? _name;
    final muscle = exercise?.muscle ?? _muscle;
    final equipment = exercise?.equipment ?? _equipment;
    final loadMode = exercise?.loadMode ?? _loadMode;
    final barKind = exercise?.barKind ?? _barKind;
    final measure = exercise?.measureMode ?? _measureMode;
    final notes = exercise?.notes ?? _notes;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          exercise?.name ?? (name.isEmpty ? 'New exercise' : name),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.huge),
        children: [
          // Which day this is, sharing the bar's surface so the two read as one
          // header — the centred title has room for a name, not for a name and
          // the day it sits in (THEME → Components).
          //
          // The muscle used to sit here too, and it was the same word as the
          // `Muscle` row's own value a few hundred pixels below it — a fact
          // stated twice on one screen (rule 6), and the copy that could not be
          // tapped. Opened from the catalog there is now nothing to say up here
          // at all, so the block goes rather than shrinking to one word.
          if (widget.fromDay) ...[
            Container(
              width: double.infinity,
              color: c.surface,
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.lg,
              ),
              child: Text(dayName, style: context.t.bodyMedium),
            ),
            // 16 between a header block and the first section under it, as on
            // every other screen that pins one.
            const SizedBox(height: Space.lg),
          ] else
            const SizedBox(height: Space.lg),

          // ── Overrides, only when opened from a day ───────────────────────
          if (widget.fromDay && entry != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              // No subtitle. Which day these belong to is printed in the
              // header block at the top of the page, and a heading that
              // carries a second line starts its card 20pt lower than
              // `General` starts its own.
              child: const SectionHeader('Overrides'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: ListCard(
                inset: Space.lg,
                children: [
                  AppRow(
                    title: 'Targets',
                    subtitle: 'What this day asks for',
                    trailing: _Value(targetLabel(entry.slot)),
                    onTap: () => showTargetEditor(
                        context, ref, entry.slot, entry.exercise),
                  ),
                  _DeloadSetsRow(slot: entry.slot, regime: regime),
                  _DeloadWeightRow(slot: entry.slot, regime: regime),
                  AppRow(
                    title: entry.slot.notes == null ? 'Add a note' : 'Note',
                    subtitle: entry.slot.notes ??
                        'A cue for this day. The exercise keeps its own.',
                    onTap: () async {
                      final note = await promptForNote(
                        context,
                        title: entry.exercise.name,
                        subtitle: 'Note for $dayName',
                        initial: entry.slot.notes ?? '',
                        hint: 'Third set from the pins, no belt',
                      );
                      if (note == null) return;
                      await ref
                          .read(regimeRepositoryProvider)
                          .updateSessionExercise(
                            entry.slot.id,
                            notes: Value(note.isEmpty ? null : note),
                          );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.section),
          ],

          // ── General, always ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: const SectionHeader('General'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: ListCard(
              inset: Space.lg,
              children: [
                AppRow(
                  title: 'Name',
                  // A new exercise has nothing to show yet, and a dash is for a
                  // number that should be there (rule 4) — this is a prompt.
                  subtitle: name.isEmpty ? 'Tap to name it' : name,
                  onTap: () => _editName(exercise, name),
                ),
                AppRow(
                  title: 'Muscle',
                  trailing: _Value.orChoose(muscle?.label),
                  onTap: () async {
                    final picked = await _pick<MuscleGroup>(
                      context,
                      title: 'Muscle',
                      values: MuscleGroup.values,
                      current: muscle,
                      labelOf: (v) => v.label,
                    );
                    if (picked == null || picked == muscle) return;
                    if (!await _confirmChange(
                      exercise,
                      field: 'muscle',
                      from: muscle?.label ?? 'nothing',
                      to: picked.label,
                      consequence: 'Its sets move to that muscle in the '
                          'weekly volume, and it is filed there in the '
                          'catalog.',
                    )) {
                      return;
                    }
                    _apply(exercise, muscle: picked);
                  },
                ),
                AppRow(
                  title: 'Equipment',
                  trailing: _Value.orChoose(equipment?.label),
                  onTap: () async {
                    final picked = await _pick<Equipment>(
                      context,
                      title: 'Equipment',
                      values: Equipment.values,
                      current: equipment,
                      labelOf: (v) => v.label,
                    );
                    if (picked == null || picked == equipment) return;
                    if (!await _confirmChange(
                      exercise,
                      field: 'equipment',
                      from: equipment?.label ?? 'nothing',
                      to: picked.label,
                    )) {
                      return;
                    }
                    _setEquipment(exercise, picked);
                  },
                ),
                AppRow(
                  title: 'How the weight is entered',
                  subtitle: loadMode == null
                      ? 'Decides what the number you type means'
                      : _loadBlurb(loadMode),
                  trailing: loadMode == null
                      ? _Value.orChoose(null)
                      : const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => _editLoadMode(exercise, loadMode),
                ),
                // Only for a total load: the plate view breaks a barbell total
                // into plates, and there is nothing to break down when the
                // number means one dumbbell or what is hanging off a belt.
                if (loadMode == LoadMode.total)
                  AppRow(
                    title: 'Bar',
                    trailing: _Value.orChoose(
                      barKind == null
                          ? null
                          : barKind == BarKind.none
                              ? barKind.label
                              : '${barKind.label} · '
                                  '${formatInUnit(barKind.kg!, WeightUnit.kg)}'
                                  ' kg',
                    ),
                    onTap: () async {
                      final picked = await _pick<BarKind>(
                        context,
                        title: 'Bar',
                        values: BarKind.values,
                        current: barKind,
                        labelOf: (v) => v == BarKind.none
                            ? v.label
                            : '${v.label} · '
                                '${formatInUnit(v.kg!, WeightUnit.kg)} kg',
                      );
                      if (picked == null || picked == barKind) return;
                      if (!await _confirmChange(
                        exercise,
                        field: 'bar',
                        from: barKind?.label ?? 'nothing',
                        to: picked.label,
                        consequence: picked == BarKind.none
                            ? 'The keypad stops breaking its weights into '
                                'plates.'
                            : 'Every weight you type is broken into plates '
                                'over a ${picked.label.toLowerCase()}.',
                      )) {
                        return;
                      }
                      _apply(exercise, barKind: picked);
                    },
                  ),
                AppRow(
                  title: 'Measured in',
                  subtitle: measure.isHold
                      ? 'Seconds held, with no reps and no estimated 1RM'
                      : 'Repetitions',
                  trailing: _Value(measure.label),
                  onTap: () => _editMeasure(exercise, measure),
                ),
                AppRow(
                  title: notes == null || notes.isEmpty ? 'Add a cue' : 'Cue',
                  subtitle: notes == null || notes.isEmpty
                      ? 'Applies wherever this exercise appears'
                      : notes,
                  onTap: () async {
                    final note = await promptForNote(
                      context,
                      title: name.isEmpty ? 'Cue' : name,
                      subtitle: 'Applies everywhere this exercise appears',
                      initial: notes ?? '',
                      hint: 'Elbows tucked, pause on the chest',
                    );
                    if (note == null) return;
                    _apply(exercise, notes: note.isEmpty ? null : note);
                  },
                ),
                if (exercise != null)
                  AppRow(
                    title: 'History',
                    subtitle: 'Every time you have trained it',
                    chevron: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ExerciseHistoryScreen(exerciseId: exercise.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── The destructive foot ─────────────────────────────────────────
          if (exercise != null) ...[
            const SizedBox(height: Space.section),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: ListCard(
                inset: Space.lg,
                children: [
                  if (widget.fromDay && entry != null)
                    AppRow(
                      icon: Icons.remove_circle_outline,
                      title: 'Remove from $dayName',
                      subtitle: 'Future workouts only. Past logs keep it.',
                      tint: c.negative,
                      onTap: () => _removeFromDay(entry.exercise.name),
                    ),
                  // Archive rather than delete: past workouts point at this
                  // row, and history with a hole in it is worse than a catalog
                  // with one extra entry.
                  AppRow(
                    icon: exercise.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    title: exercise.archived
                        ? 'Restore to the catalog'
                        : 'Archive this exercise',
                    subtitle: exercise.archived
                        ? 'It appears in the picker again'
                        : 'It leaves the picker; logged sets stay',
                    tint: exercise.archived ? null : c.negative,
                    onTap: () => _setArchived(exercise, !exercise.archived),
                  ),
                ],
              ),
            ),
          ],

          if (widget.isNew) ...[
            const SizedBox(height: Space.section),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: PrimaryButton(
                label: 'Create exercise',
                onPressed: _complete && !_saving ? _create : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Writes a field, or holds it in the draft when there is nothing to write
  /// to yet. Every row on this screen goes through here, which is what makes
  /// "save as you go" and "hold until Create" the same code.
  void _apply(
    Exercise? exercise, {
    String? name,
    MuscleGroup? muscle,
    Equipment? equipment,
    LoadMode? loadMode,
    BarKind? barKind,
    MeasureMode? measureMode,
    Object? notes = _unset,
  }) {
    if (exercise == null) {
      setState(() {
        if (name != null) _name = name;
        if (muscle != null) _muscle = muscle;
        if (equipment != null) _equipment = equipment;
        if (loadMode != null) _loadMode = loadMode;
        if (barKind != null) _barKind = barKind;
        if (measureMode != null) _measureMode = measureMode;
        if (notes != _unset) _notes = notes as String?;
      });
      return;
    }
    // Not awaited — this is a row tap on a save-as-you-go screen, and every
    // caller is a `void` handler. So it says out loud that it is not being
    // watched, and reports anyway: load mode in particular re-reads every set
    // ever logged against this movement, and a failure that only reverted the
    // row on the next rebuild would look like the tap missed.
    _repo
        .updateExercise(
          exercise.id,
          name: name == null ? const Value.absent() : Value(name),
          muscle: muscle == null ? const Value.absent() : Value(muscle),
          equipment:
              equipment == null ? const Value.absent() : Value(equipment),
          loadMode:
              loadMode == null ? const Value.absent() : Value(loadMode),
          barKind: barKind == null ? const Value.absent() : Value(barKind),
          measureMode:
              measureMode == null ? const Value.absent() : Value(measureMode),
          notes: notes == _unset
              ? const Value.absent()
              : Value(notes as String?),
        )
        .reportOnError('That change could not be saved.');
  }

  /// Asks before changing a saved exercise, and never while creating one.
  ///
  /// Every row here writes the moment the sheet closes, which is right for a
  /// screen you came to *edit* and wrong for one you opened to read: the
  /// catalog row, the picker and the ⓘ all land on this screen, so a mis-tap on
  /// `Muscle` followed by a mis-tap on a name silently refiled a movement that
  /// has a year of history behind it. A draft has nothing to protect — the
  /// exercise does not exist until `Create exercise` — so it is never asked.
  ///
  /// [_editLoadMode] asks its own, harder question, because that field re-reads
  /// every set ever logged rather than changing where they are counted.
  Future<bool> _confirmChange(
    Exercise? exercise, {
    required String field,
    required String from,
    required String to,
    String? consequence,
  }) async {
    if (exercise == null) return true;
    return confirmAction(
      context,
      title: 'Change ${exercise.name}?',
      // Named in full — from and to — and both lifted out of the sentence. The
      // question being answered is "did I mean to touch this at all", and the
      // value it currently holds is half that answer.
      message: [
        'Its $field changes from $from to $to, everywhere this exercise '
            'appears.',
        ?consequence,
      ].join(' '),
      highlight: [from, to],
      confirmLabel: 'Change it',
      destructive: false,
    );
  }

  /// Equipment is just equipment now.
  ///
  /// Picking one used to pre-fill the load mode and the bar — dumbbell meant
  /// per-side, barbell meant an Olympic bar. Helpful, and wrong for a screen
  /// where every field is an answer: a guess that fills a required field is
  /// indistinguishable from an answer once the sheet closes, and load mode is
  /// the field that decides how every set ever logged is read. Each question is
  /// asked once and answered once.
  void _setEquipment(Exercise? exercise, Equipment value) =>
      _apply(exercise, equipment: value);

  Future<void> _editName(Exercise? exercise, String current) async {
    final db = ref.read(databaseProvider);
    // Two rows with the same name are indistinguishable in the picker, and the
    // picker is where you choose what a set gets logged against. Archived rows
    // count: they are one tap from being restored.
    final rows = await (db.select(db.exercises)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final taken = {
      for (final e in rows)
        if (e.id != exercise?.id) e.name.trim().toLowerCase(),
    };
    if (!mounted) return;

    final name = await promptForText(
      context,
      title: exercise == null ? 'Name this exercise' : 'Rename exercise',
      hint: 'Incline dumbbell press',
      initial: current,
      validate: (value) => taken.contains(value.trim().toLowerCase())
          ? 'There is already an exercise called ${value.trim()}'
          : null,
      // A movement's name carries more than a programme's does — "Incline
      // dumbbell press (neutral grip)" is one thing people write — so the
      // catalog allows more room than a regime or a day, and this is the field
      // that gets it.
      maxLength: 80,
    );
    if (name == null || name.isEmpty) return;
    _apply(exercise, name: name);
  }

  /// Load mode is the one field that is not a label: it decides how every set
  /// ever logged for this movement is read. Flipping "total" to "per dumbbell"
  /// doubles the effective load of all of them, moving e1RM, the chart, the
  /// beat-last-time highlight and every prefill comparison. No migration — the
  /// reinterpretation is the point — but it has to be chosen knowingly, with
  /// the number in front of you.
  Future<void> _editLoadMode(Exercise? exercise, LoadMode? current) async {
    final picked = await _pick<LoadMode>(
      context,
      title: 'How the weight is entered',
      values: LoadMode.values,
      current: current,
      labelOf: _loadModeLabel,
      helperOf: _loadBlurb,
    );
    if (picked == null || picked == current) return;

    if (exercise != null) {
      final affected =
          await ref.read(trainingRepositoryProvider).loggedSetCount(exercise.id);
      if (affected > 0) {
        if (!mounted) return;
        final ok = await confirmAction(
          context,
          title: 'Change how this load is read?',
          message: '$affected logged ${affected == 1 ? 'set' : 'sets'} will be '
              're-read as ${_loadModeName(picked)}. Their estimated 1RMs, the '
              'progress chart and every "beat last time" comparison move with '
              'them.',
          confirmLabel: 'Change it',
          destructive: false,
        );
        if (!ok) return;
      }
    }
    // A load that is not a total has no bar to break into plates — the row
    // disappears, so the answer is settled rather than left outstanding.
    _apply(
      exercise,
      loadMode: picked,
      barKind: picked == LoadMode.total ? null : BarKind.none,
    );
  }

  /// The second field that is not a label: it decides what the count on every
  /// set of this movement *is*. Flipping it does not rewrite a single row —
  /// eight stays eight — it changes whether eight means eight reps or eight
  /// seconds, which moves the chart, the column heading and the e1RM the same
  /// way [_editLoadMode] moves the load. Same shape of question, for the same
  /// reason: no migration, but not a mis-tap either.
  Future<void> _editMeasure(Exercise? exercise, MeasureMode current) async {
    final picked = await _pick<MeasureMode>(
      context,
      title: 'Measured in',
      values: MeasureMode.values,
      current: current,
      labelOf: (v) => v.label,
      helperOf: (v) => v.isHold
          ? 'A plank or a hang: the set is seconds held, and there is no 1RM '
              'to estimate.'
          : 'The set is a count of reps. Almost everything.',
    );
    if (picked == null || picked == current) return;

    if (exercise != null) {
      final affected =
          await ref.read(trainingRepositoryProvider).loggedSetCount(exercise.id);
      if (affected > 0) {
        if (!mounted) return;
        final ok = await confirmAction(
          context,
          title: 'Change what its sets count?',
          message: '$affected logged ${affected == 1 ? 'set' : 'sets'} will be '
              're-read as ${picked.isHold ? 'seconds held' : 'reps'}. '
              '${picked.isHold ? 'Its estimated 1RM and its share of session '
                  'volume go away, because a hold has neither.' : 'It gets an '
                  'estimated 1RM and counts toward session volume again.'}',
          confirmLabel: 'Change it',
          destructive: false,
        );
        if (!ok) return;
      }
    }
    _apply(exercise, measureMode: picked);
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final db = ref.read(databaseProvider);
    final id = await _repo.createExercise(
      name: _name.trim(),
      muscle: _muscle!,
      equipment: _equipment!,
      loadMode: _loadMode!,
      barKind: _barKind ?? BarKind.none,
      measureMode: _measureMode,
      notes: (_notes?.trim().isEmpty ?? true) ? null : _notes!.trim(),
    );
    final row = await (db.select(db.exercises)..where((t) => t.id.equals(id)))
        .getSingle();
    navigator.pop(row);
  }

  Future<void> _setArchived(Exercise exercise, bool archived) async {
    await _repo.updateExercise(exercise.id, archived: Value(archived));
    if (!mounted) return;
    showToast(
      context,
      archived ? '${exercise.name} archived' : '${exercise.name} restored',
    );
  }

  /// Removing a slot is one tap, so it gets an undo rather than a dialog — the
  /// row is only tombstoned, and putting it back keeps its sets and rep range.
  Future<void> _removeFromDay(String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(regimeRepositoryProvider);
    await repo.removeSessionExercise(widget.slotId!);
    navigator.pop();
    messenger.hideCurrentSnackBar();
    showToastOn(
      messenger,
      '$name removed',
      actionLabel: 'Undo',
      onAction: () => repo.restoreSessionExercise(widget.slotId!),
    );
  }
}

const _unset = Object();

/// One question, one sheet of choices — the shape every other setting in this
/// app uses, in place of the dropdowns this screen replaced. A dropdown puts a
/// Material menu over the page with no room to say what an option *means*;
/// these rows carry a helper line where the choice needs one.
Future<T?> _pick<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T? current,
  required String Function(T) labelOf,
  String Function(T)? helperOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    // Capped, and this is what stops `Muscle` reading as a drawer rather than a
    // sheet. Twelve rows at 56 plus a header is taller than the phone, so an
    // uncapped sheet opened edge to edge over the status bar with the page it
    // came from nowhere in sight — and a panel that already fills the screen
    // has almost no distance left to travel, so its entrance and its exit both
    // looked like a cut. Two thirds leaves the screen behind it visible, which
    // is the thing that makes the movement legible.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.66,
    ),
    builder: (sheet) => AppSheet(
      title: title,
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        for (final v in values)
          AppRow(
            title: labelOf(v),
            subtitle: helperOf?.call(v),
            trailing: AppRadio(selected: v == current),
            onTap: () => Navigator.of(sheet).pop(v),
          ),
      ],
    ),
  );
}

String _loadModeLabel(LoadMode mode) => switch (mode) {
      LoadMode.total => 'Total load',
      LoadMode.perSide => 'Per dumbbell',
      LoadMode.bodyweight => 'Bodyweight only',
      LoadMode.bodyweightPlus => 'Bodyweight plus added weight',
    };

String _loadModeName(LoadMode mode) => switch (mode) {
      LoadMode.total => 'a total load',
      LoadMode.perSide => 'per dumbbell',
      LoadMode.bodyweight => 'bodyweight only',
      LoadMode.bodyweightPlus => 'bodyweight plus the entered load',
    };

/// What the number you type into this exercise means.
String _loadBlurb(LoadMode mode) => switch (mode) {
      LoadMode.total => 'The weight you type is the whole load',
      LoadMode.perSide => 'The weight you type is per hand, and two are moving',
      LoadMode.bodyweight => 'Reps only, no external load',
      LoadMode.bodyweightPlus => 'Bodyweight plus anything you add',
    };

/// A trailing figure on a row, in the value size with the row's own chevron
/// after it.
class _Value extends StatelessWidget {
  const _Value(this.text) : pending = false;

  /// An unanswered question, while a new exercise is being drafted: the word
  /// `Choose` in `textTertiary` where the value will go. Not a dash — a dash is
  /// for a measurement that should exist and doesn't (rule 4), and this is a
  /// question waiting on you.
  const _Value.orChoose(String? value)
      : text = value ?? 'Choose',
        pending = value == null;

  final String text;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            style: pending
                ? context.t.labelLarge?.copyWith(color: context.c.textTertiary)
                : context.t.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Space.sm),
        Icon(Icons.chevron_right_rounded,
            size: 18, color: context.c.textTertiary),
      ],
    );
  }
}

/// Per-slot deload overrides. The columns have existed since the first
/// migration and never had a screen: a movement that is already light does not
/// need the same cut as a heavy compound, and until now the only way to say so
/// was to change it for the whole regime.
///
/// A null column means "follow the regime", which is what the row prints. The
/// steps start from whatever the regime says, so overriding is a nudge rather
/// than a form to fill in, and one row clears it again.
class _DeloadSetsRow extends ConsumerWidget {
  const _DeloadSetsRow({required this.slot, required this.regime});

  final SessionExercise slot;
  final Regime? regime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = regime?.deloadSetDelta ?? -1;
    final own = slot.deloadSetDelta;
    final live = own ?? fallback;
    final repo = ref.read(regimeRepositoryProvider);

    void set(int? v) => repo.updateSessionExercise(
          slot.id,
          deloadSetDelta: Value(v),
        );

    return Column(
      children: [
        StepperRow(
          label: 'Sets during deload',
          helper: own == null ? 'Following the regime' : 'This day only',
          value: live == 0 ? 'Unchanged' : '$live',
          onDecrement: live > -3 ? () => set(live - 1) : null,
          onIncrement: live < 0 ? () => set(live + 1) : null,
        ),
        if (own != null)
          AppRow(
            title: 'Follow the regime again',
            subtitle: 'Back to ${fallback == 0 ? 'unchanged' : fallback}',
            onTap: () => set(null),
          ),
      ],
    );
  }
}

class _DeloadWeightRow extends ConsumerWidget {
  const _DeloadWeightRow({required this.slot, required this.regime});

  final SessionExercise slot;
  final Regime? regime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = regime?.deloadWeightPct ?? 80;
    final own = slot.deloadWeightPct;
    final live = own ?? fallback;
    final repo = ref.read(regimeRepositoryProvider);

    void set(int? v) => repo.updateSessionExercise(
          slot.id,
          deloadWeightPct: Value(v),
        );

    return Column(
      children: [
        StepperRow(
          label: 'Weight during deload',
          helper: own == null ? 'Following the regime' : 'This day only',
          value: '$live%',
          onDecrement: live > 40 ? () => set(live - 5) : null,
          onIncrement: live < 100 ? () => set(live + 5) : null,
        ),
        if (own != null)
          AppRow(
            title: 'Follow the regime again',
            subtitle: 'Back to $fallback%',
            onTap: () => set(null),
          ),
      ],
    );
  }
}

/// The target editor (THEME → Composing a screen): a sheet, never a screen.
///
/// Their version is a table with one row per planned set, because their sets
/// are individually programmed. Ours are not — a slot has a set count and one
/// rep range, and what actually happens is decided at the bar by session-scoped
/// prefill. Rendering four identical rows would draw per-set targets this app
/// cannot store, so the count is a stepper and the range is the two fields the
/// reference puts on every row, once.
Future<void> showTargetEditor(
  BuildContext context,
  WidgetRef ref,
  SessionExercise slot,
  Exercise exercise,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) => _TargetSheet(slot: slot, exercise: exercise),
  );
}

class _TargetSheet extends ConsumerStatefulWidget {
  const _TargetSheet({required this.slot, required this.exercise});

  final SessionExercise slot;
  final Exercise exercise;

  @override
  ConsumerState<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends ConsumerState<_TargetSheet> {
  late int _sets = widget.slot.targetSets;
  late final _low =
      TextEditingController(text: widget.slot.targetRepLow?.toString() ?? '');
  late final _high =
      TextEditingController(text: widget.slot.targetRepHigh?.toString() ?? '');

  @override
  void dispose() {
    _low.dispose();
    _high.dispose();
    super.dispose();
  }

  /// A rep bound as the slot can hold it, or null for "no target".
  ///
  /// The field is a number pad, which is not the same as a number: it will
  /// accept `0`, and it will accept as many digits as you keep pressing.
  /// Neither is a rep range — a target of zero reps is the absence of a target,
  /// and the slot refuses both outright, so a value that got this far unbounded
  /// would come back as a failed write rather than as a saved target.
  static int? _bound(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed > 999 ? 999 : parsed;
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final low = _bound(_low.text);
    var high = _bound(_high.text);
    // A range that runs backwards is a typo, not an instruction. One number is
    // a legitimate answer — `5 × 5` — and reads as a range of one.
    if (low != null && high != null && high < low) high = low;
    await ref.read(regimeRepositoryProvider).updateSessionExercise(
          widget.slot.id,
          targetSets: Value(_sets),
          targetRepLow: Value(low),
          targetRepHigh: Value(low == null ? null : high ?? low),
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Targets',
      subtitle: widget.exercise.name,
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      footer: PrimaryButton(label: 'Save', onPressed: _save),
      children: [
        StepperRow(
          label: 'Sets',
          value: '$_sets',
          onDecrement: _sets > 1 ? () => setState(() => _sets--) : null,
          onIncrement: _sets < 12 ? () => setState(() => _sets++) : null,
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.sm),
          child: Row(
            children: [
              Expanded(child: _RepField(label: 'Reps min', controller: _low)),
              const SizedBox(width: Space.md),
              Expanded(child: _RepField(label: 'Reps max', controller: _high)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One rep bound. The placeholder is the literal word `Optional` (THEME → Composing a screen): a rep
/// range is a target, and a slot is allowed not to have one.
class _RepField extends StatelessWidget {
  const _RepField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.t.bodySmall),
        const SizedBox(height: Space.sm),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          // Three digits and nothing but digits. `TextInputType.number` is a
          // request for a keyboard, not a constraint on what arrives — a
          // hardware keyboard, a paste or a suggestion strip all bypass it.
          // Formatters rather than `maxLength`, which would hang a character
          // counter under a field two characters wide.
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          textAlign: TextAlign.center,
          style: context.t.labelLarge,
          cursorColor: c.textPrimary,
          decoration: const InputDecoration(
            hintText: 'Optional',
            // The one field that overrides the theme's insets: it is a narrow
            // centred cell in a table, and 16 of horizontal padding either side
            // leaves no room for three digits.
            contentPadding: EdgeInsets.symmetric(vertical: Space.md),
          ),
        ),
      ],
    );
  }
}

/// Opens the exercise's own screen — the catalog row, and the day's overrides
/// when there is a day.
void openExercise(
  BuildContext context, {
  required String exerciseId,
  String? regimeId,
  String? sessionId,
  String? slotId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ExerciseScreen(
        exerciseId: exerciseId,
        regimeId: regimeId,
        sessionId: sessionId,
        slotId: slotId,
      ),
    ),
  );
}

/// Creates one, on the same screen. Returns the new row, or null if the screen
/// was left without creating anything.
Future<Exercise?> createExerciseFlow(
  BuildContext context, {
  String initialName = '',
}) {
  return Navigator.of(context).push<Exercise>(
    MaterialPageRoute(
      builder: (_) => ExerciseScreen(initialName: initialName),
    ),
  );
}
