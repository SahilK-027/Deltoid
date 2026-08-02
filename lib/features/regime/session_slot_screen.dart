import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/enums.dart';
import '../history/exercise_history_screen.dart';
import '../log/widgets/exercise_sheets.dart';
import 'regime_screen.dart';
import 'regime_settings.dart';

/// One exercise inside one training day, split the way the data is split.
///
/// **Overrides** are this day's: how many sets, what rep range, whether this
/// movement deloads like the rest of the programme. **General** is the catalog
/// row, which every session and every past log points at — editing it changes
/// the exercise everywhere, and the split exists so that is never a surprise.
class SessionSlotScreen extends ConsumerWidget {
  const SessionSlotScreen({
    super.key,
    required this.regimeId,
    required this.sessionId,
    required this.slotId,
  });

  /// The programme this day belongs to — carried down from the editor rather
  /// than read off the active regime, since the one being edited need not be
  /// the one being trained.
  final String regimeId;
  final String sessionId;
  final String slotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sessionSlotsProvider(sessionId));
    final slots = async.valueOrNull;
    final entry = slots?.where((s) => s.slot.id == slotId).firstOrNull;
    final sessions =
        ref.watch(sessionsForRegimeProvider(regimeId)).valueOrNull ?? const [];
    final session = sessions.where((s) => s.id == sessionId).firstOrNull;
    final regime = ref.watch(regimeByIdProvider(regimeId)).valueOrNull;
    final c = context.c;

    if (entry == null) {
      // Loaded-and-missing is reachable: the day behind this screen can drop
      // the slot while it is open. Saying so beats a spinner forever.
      return Scaffold(
        appBar: AppBar(title: const Text('Exercise')),
        body: async.hasValue
            ? const EmptyState(
                icon: Icons.delete_outline,
                title: 'Removed',
                message: 'This exercise is no longer part of the day.',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final slot = entry.slot;
    final exercise = entry.exercise;
    final dayName = session?.name ?? 'this day';

    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.huge),
        children: [
          // Which day this is, sharing the bar's surface so the two read as one
          // header — the centred title has room for a name, not for a name and
          // the day it sits in (§5).
          Container(
            width: double.infinity,
            color: c.surface,
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, 0, Space.gutter, Space.lg),
            child: Text(
              '$dayName · ${exercise.muscle.label}',
              style: context.t.bodyMedium,
            ),
          ),
          const SizedBox(height: Space.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: SectionHeader('Overrides', subtitle: '$dayName only'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: ListCard(
              inset: Space.lg,
              children: [
                AppRow(
                  title: 'Targets',
                  subtitle: 'What this day asks for',
                  trailing: _Value(targetLabel(slot)),
                  onTap: () => showTargetEditor(context, ref, slot, exercise),
                ),
                _DeloadSetsRow(slot: slot, regime: regime),
                _DeloadWeightRow(slot: slot, regime: regime),
                AppRow(
                  title: slot.notes == null ? 'Add a note' : 'Note',
                  subtitle: slot.notes ??
                      'A cue for this day — the exercise keeps its own',
                  onTap: () async {
                    final note = await promptForNote(
                      context,
                      title: exercise.name,
                      subtitle: 'Note for $dayName',
                      initial: slot.notes ?? '',
                      hint: 'Third set from the pins, no belt',
                    );
                    if (note == null) return;
                    await ref.read(regimeRepositoryProvider).updateSessionExercise(
                          slot.id,
                          notes: Value(note.isEmpty ? null : note),
                        );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.section),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: SectionHeader(
              'General',
              subtitle: 'The exercise itself, everywhere it appears',
              actionLabel: 'Edit',
              onAction: () => showExerciseEditor(context, existing: exercise),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: ListCard(
              inset: Space.lg,
              children: [
                AppRow(
                  title: exercise.equipment.label,
                  subtitle: _loadBlurb(exercise.loadMode),
                ),
                if (exercise.barKind != BarKind.none)
                  AppRow(
                    title: exercise.barKind.label,
                    subtitle: '${exercise.barKind.kg} kg empty',
                  ),
                if (exercise.notes != null)
                  AppRow(title: 'Cue', subtitle: exercise.notes),
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
          const SizedBox(height: Space.section),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: ListCard(
              inset: Space.lg,
              children: [
                AppRow(
                  icon: Icons.remove_circle_outline,
                  title: 'Remove from $dayName',
                  subtitle: 'Future workouts only — past logs keep it',
                  tint: c.negative,
                  onTap: () => _remove(context, ref, exercise.name),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Removing a slot is one tap, so it gets an undo rather than a dialog — the
  /// row is only tombstoned, and putting it back keeps its sets and rep range.
  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(regimeRepositoryProvider);
    await repo.removeSessionExercise(slotId);
    navigator.pop();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$name removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.restoreSessionExercise(slotId),
        ),
      ),
    );
  }
}

/// What the number you type into this exercise means.
String _loadBlurb(LoadMode mode) => switch (mode) {
      LoadMode.total => 'The weight you type is the whole load',
      LoadMode.perSide => 'The weight you type is per hand — two are moving',
      LoadMode.bodyweight => 'Reps only, no external load',
      LoadMode.bodyweightPlus => 'Bodyweight plus anything you add',
    };

/// A trailing figure on a row, in the value size with the row's own chevron
/// after it.
class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: context.t.labelLarge),
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
          value: live == 0 ? 'unchanged' : '$live',
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

/// The target editor (THEME §7): a sheet, never a screen.
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
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: _TargetSheet(slot: slot, exercise: exercise),
    ),
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
  late final _low = TextEditingController(
      text: widget.slot.targetRepLow?.toString() ?? '');
  late final _high = TextEditingController(
      text: widget.slot.targetRepHigh?.toString() ?? '');

  @override
  void dispose() {
    _low.dispose();
    _high.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final low = int.tryParse(_low.text.trim());
    var high = int.tryParse(_high.text.trim());
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
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.sm, Space.lg, Space.sm),
          child: Row(
            children: [
              Expanded(
                child: _RepField(label: 'Reps min', controller: _low),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _RepField(label: 'Reps max', controller: _high),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One rep bound. The placeholder is the literal word `Optional` (§7): a rep
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
          textAlign: TextAlign.center,
          style: context.t.labelLarge,
          cursorColor: c.textPrimary,
          decoration: InputDecoration(
            hintText: 'Optional',
            hintStyle: context.t.bodyMedium?.copyWith(color: c.textTertiary),
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
            contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
          ),
        ),
      ],
    );
  }
}
