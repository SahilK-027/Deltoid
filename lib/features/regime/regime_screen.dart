import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/reorder_sheet.dart';
import '../../data/db/database.dart';
import '../../data/repositories/regime_repository.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/enums.dart';
import '../log/widgets/exercise_sheets.dart';
import 'exercise_catalog_screen.dart';
import 'regime_settings.dart';
import 'exercise_screen.dart';

final regimeRepositoryProvider = Provider<RegimeRepository>(
  (ref) => RegimeRepository(ref.watch(databaseProvider)),
);

/// Every regime with its size and how much was logged under it. Watched rather
/// than read on demand: a `ref.read` of a provider nobody listens to always
/// comes back empty, which is exactly how the old switcher managed to make a
/// full shelf of regimes look deleted.
final regimeSummariesProvider = StreamProvider<List<RegimeSummary>>((ref) {
  return ref.watch(regimeRepositoryProvider).watchRegimeSummaries();
});

/// Session template rows joined with their exercises.
final sessionSlotsProvider = StreamProvider.family<
    List<({SessionExercise slot, Exercise exercise})>, String>((ref, sessionId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.sessionExercises).join([
    innerJoin(
        db.exercises, db.exercises.id.equalsExp(db.sessionExercises.exerciseId)),
  ])
    ..where(db.sessionExercises.sessionId.equals(sessionId) &
        db.sessionExercises.deletedAt.isNull())
    ..orderBy([OrderingTerm(expression: db.sessionExercises.orderIndex)]);

  return query.watch().map((rows) => [
        for (final r in rows)
          (
            slot: r.readTable(db.sessionExercises),
            exercise: r.readTable(db.exercises),
          ),
      ]);
});

/// One programme, opened from the Regime index.
///
/// A training day is a **tab**, not a row you push into (THEME → Composing a screen): switching
/// days is a context change, and the vertical list it replaced put a screen
/// between you and the thing you came to edit. Everything about the regime
/// itself — its name, its deload, the order of its days — is behind the one
/// sliders button in the bar, because none of it is what you open a programme
/// to do.
///
/// Scoped to [regimeId], not to the active regime: a programme you are not
/// training is still a programme you can edit, and that is the whole point of
/// keeping the old ones.
class RegimeEditorScreen extends ConsumerStatefulWidget {
  const RegimeEditorScreen({super.key, required this.regimeId});

  final String regimeId;

  @override
  ConsumerState<RegimeEditorScreen> createState() => _RegimeEditorScreenState();
}

class _RegimeEditorScreenState extends ConsumerState<RegimeEditorScreen> {
  int _day = 0;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(regimeByIdProvider(widget.regimeId));
    final regime = async.valueOrNull;
    final sessions =
        ref.watch(sessionsForRegimeProvider(widget.regimeId)).valueOrNull ??
            const [];
    final c = context.c;

    // Deleted out from under the screen — reachable, since the index behind it
    // can delete a regime while this is open.
    if (regime == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Regime')),
        body: async.hasValue
            ? const EmptyState(
                icon: Icons.delete_outline,
                title: 'Deleted',
                message: 'This regime is no longer there.',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    // The cycle belongs to the programme being trained. A regime you are not
    // training has no cycle in flight, and a line about one would be about
    // somebody else's.
    final status =
        regime.isActive ? ref.watch(cycleStatusProvider).valueOrNull : null;

    // A day deleted out from under the strip must not leave the body pointing
    // past the end of it.
    final day = sessions.isEmpty ? 0 : _day.clamp(0, sessions.length - 1);

    return Scaffold(
      // Pushed, so it wears the bar rather than a masthead (THEME → Components). The
      // cycle line and the day strip go in a `surface` block directly under it,
      // sharing its colour so the two read as one header.
      appBar: AppBar(
        title: Text(regime.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Regime settings',
            onPressed: () => showRegimeSettings(context, ref, regime),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: c.surface,
            child: Column(
              children: [
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Space.gutter, 0, Space.gutter, Space.lg),
                    child: _CycleLine(status: status, sessions: sessions),
                  ),
                // No strip at all until there is a day in it: an `Add day +`
                // tab alone under the bar is a tab bar with no tabs, and the
                // empty state below already asks for the same thing.
                if (sessions.isNotEmpty)
                  UnderlineTabs(
                    labels: [for (final s in sessions) s.name],
                    index: day,
                    onSelect: (i) => setState(() => _day = i),
                    trailingLabel: 'Add day  +',
                    onTrailing: () => _addDay(regime.id, sessions.length),
                  ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? EmptyState(
                    icon: Icons.calendar_today_outlined,
                    title: 'No days yet',
                    message: 'Add the days that make up one cycle. A cycle is '
                        'one pass through all of them, not a calendar week.',
                    action: PrimaryButton(
                      label: 'Add day',
                      onPressed: () => _addDay(regime.id, 0),
                    ),
                  )
                : _DayBody(
                    key: ValueKey(sessions[day].id),
                    regimeId: regime.id,
                    session: sessions[day],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addDay(String regimeId, int position) async {
    await addSessionPrompt(context, ref, regimeId);
    if (!mounted) return;
    // Land on what was just made, rather than leaving it as a tab off the
    // right-hand edge that nothing points at.
    setState(() => _day = position);
  }
}

/// Where the cycle is, and the way into the two overrides that move it.
///
/// One quiet line in the band (THEME → Components): the cycle is the state of things, not
/// something the page is about. Everything you can *do* to it — close it early,
/// call it a deload — is a tap away rather than a pair of buttons taking the top
/// third of the screen, which is what it used to be.
class _CycleLine extends ConsumerWidget {
  const _CycleLine({required this.status, required this.sessions});

  final CycleStatus status;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tail = status.deloadEnabled
        ? (status.isDeload
            ? 'Deload in progress'
            : '${status.cyclesUntilDeload} to deload')
        : 'Deload off';

    return Pressable(
      scale: 0.99,
      onTap: () => _showCycleSheet(context, ref, status, sessions),
      child: Row(
        children: [
          // Flexible, both of them: `Cycle 12 · 3 of 6 · deload in progress` is
          // wider than a narrow phone's band, and a status line is not worth an
          // overflow stripe.
          Flexible(
            child: Text(
              'Cycle ${status.cycleIndex} · ${status.done} of ${status.total} · ',
              style: context.t.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Flexible(
            child: Text(
              tail,
              style: context.t.bodyMedium?.copyWith(
                color: status.isDeload ? c.deload : c.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
        ],
      ),
    );
  }
}

/// The two cycle overrides, which existed in the repository long before they
/// existed on screen.
///
/// Without "Close this cycle" a session you permanently skip stalls the
/// programme: the cycle never closes, the cycle index never moves, and the
/// deload you configured never arrives. Without the deload override the
/// schedule is binding, which contradicts the one promise this app makes — it
/// suggests, it never forces. Whether you need a light week is a decision made
/// in the gym, not six cycles in advance.
Future<void> _showCycleSheet(
  BuildContext context,
  WidgetRef ref,
  CycleStatus status,
  List<Session> sessions,
) {
  final remaining = status.remainingSessionIds;
  final canClose = status.done > 0 && remaining.isNotEmpty;

  String nameOf(String id) {
    for (final s in sessions) {
      if (s.id == id) return s.name;
    }
    return 'A session';
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) => AppSheet(
      title: 'Cycle ${status.cycleIndex}',
      subtitle: '${status.done} of ${status.total} days trained',
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        AppRow(
          icon: Icons.skip_next_rounded,
          title: 'Close this cycle',
          subtitle: canClose
              ? '${remaining.map(nameOf).join(', ')} would be skipped'
              : status.done == 0
                  ? 'Nothing trained yet this cycle'
                  : 'Every day is done. The next workout opens a new one.',
          onTap: !canClose
              ? null
              : () async {
                  final navigator = Navigator.of(sheet);
                  final ok = await confirmAction(
                    context,
                    title: 'Close cycle ${status.cycleIndex}?',
                    // Name what it costs. "Are you sure" tells you nothing;
                    // "Leg 2 won't be trained this cycle" is the decision.
                    message:
                        '${remaining.map(nameOf).join(', ')} won\'t be trained '
                        'this cycle.\n\nThe next cycle starts from the top, and '
                        'this one counts towards your deload.',
                    confirmLabel: 'Close cycle',
                    destructive: false,
                  );
                  if (!ok) return;
                  final regime = ref.read(activeRegimeProvider).valueOrNull;
                  if (regime == null) return;
                  await ref
                      .read(trainingRepositoryProvider)
                      .advanceCycle(regime.id);
                  navigator.pop();
                },
        ),
        AppRow(
          icon: Icons.trending_down_rounded,
          title: status.isDeload ? 'Not a deload after all' : 'Make it a deload',
          subtitle: status.isDeload
              ? 'Back to full weight and full sets'
              : 'Lighter weights, fewer sets, for this cycle only',
          tint: status.isDeload ? null : sheet.c.deload,
          onTap: () async {
            final navigator = Navigator.of(sheet);
            await ref
                .read(trainingRepositoryProvider)
                .setCycleDeload(status.cycleId, !status.isDeload);
            navigator.pop();
          },
        ),
      ],
    ),
  );
}

/// One training day: what is in it, and the three things you do to the day
/// itself.
class _DayBody extends ConsumerWidget {
  const _DayBody({super.key, required this.regimeId, required this.session});

  final String regimeId;
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(sessionSlotsProvider(session.id)).valueOrNull;
    final c = context.c;

    if (slots == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      // The app draws edge to edge and this screen has no nav bar of its own
      // to hold the bottom, so the gesture bar sat over the last row — which
      // on this page is `Delete <session>`, the one row worth being able to
      // see before it is tapped. `Space.huge` alone is not the inset; the
      // inset is whatever the system is using plus that.
      padding: EdgeInsets.only(
        bottom: Space.huge + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        // Two chips, not three. `Delete day` was the loudest thing on a page
        // about what you train, and it sits at the foot now with the other
        // destructive rows in this cluster.
        SizedBox(
          // 16 under the header block, like the first thing on every other
          // screen, and no slack under the chips: the heading below brings its
          // own 16.
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, Space.lg, Space.gutter, 0),
            children: [
              AppChip(
                label: 'Rename',
                icon: Icons.edit_outlined,
                onTap: () => _rename(context, ref),
              ),
              const SizedBox(width: Space.sm),
              AppChip(
                label: 'Re-order',
                icon: Icons.swap_vert_rounded,
                onTap: slots.length < 2
                    ? null
                    : () => _reorder(context, ref, slots),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.lg, Space.gutter, 0),
          // Count as heading (THEME → Composing a screen): the number is the useful part of the word.
          child: SectionHeader(
            slots.isEmpty
                ? 'No exercises'
                : '${slots.length} exercise${slots.length == 1 ? '' : 's'}',
            actionLabel: 'Add',
            onAction: () => _add(context, ref, slots),
          ),
        ),
        if (slots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.gutter),
            child: EmptyBox(
              icon: Icons.self_improvement_rounded,
              message: 'A rest day, until something is in it. Add an exercise '
                  'and this becomes a day the cycle expects you to train.',
            ),
          )
        else
          for (var i = 0; i < slots.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.border),
            _SlotRow(
              regimeId: regimeId,
              sessionId: session.id,
              slot: slots[i].slot,
              exercise: slots[i].exercise,
            ),
          ],
        const SizedBox(height: Space.section),
        // Where every destructive action in this cluster lives: at the foot of
        // the thing it destroys, quiet, after everything you actually came for.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: ListCard(
            inset: Space.lg,
            children: [
              AppRow(
                icon: Icons.delete_outline_rounded,
                title: 'Delete ${session.name}',
                subtitle: 'Logged workouts stay in History',
                tint: c.negative,
                onTap: () => _delete(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(regimeRepositoryProvider);
    final taken = await repo.liveSessionNames(
      session.regimeId,
      exceptId: session.id,
    );
    if (!context.mounted) return;

    final name = await promptForText(
      context,
      title: 'Rename day',
      initial: session.name,
      // Keeping its own name is a no-op, not a collision — `exceptId` above.
      validate: (value) => taken.contains(value.trim().toLowerCase())
          ? 'This regime already has a day called ${value.trim()}'
          : null,
    );
    if (name == null || name.isEmpty) return;
    await repo.renameSession(session.id, name);
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<({SessionExercise slot, Exercise exercise})> slots,
  ) async {
    // The slots already in this day are marked in the picker rather than
    // hidden: a session may legitimately run one movement twice, and the
    // second slot should be a decision instead of a surprise.
    final exercise = await pickExercise(
      context,
      ref,
      alreadyIn: {for (final s in slots) s.exercise.id},
    );
    if (exercise == null) return;
    await ref
        .read(regimeRepositoryProvider)
        .addExerciseToSession(session.id, exercise.id);
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<({SessionExercise slot, Exercise exercise})> slots,
  ) {
    // Looked up now, while this widget is certainly alive, and used later from
    // a sheet that outlives the frame it was opened on.
    final repo = ref.read(regimeRepositoryProvider);
    return showReorderSheet(
      context,
      title: 'Re-order exercises',
      subtitle: session.name,
      items: [
        for (final s in slots) (id: s.slot.id, label: s.exercise.name),
      ],
      onCommit: repo.reorderSessionExercises,
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Delete ${session.name}?',
      message: 'It leaves the cycle, and its exercise slots go with it.\n\n'
          'Workouts already logged under this day stay in History. They hold '
          'their own record of what you did.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    final repo = ref.read(regimeRepositoryProvider);
    await repo.deleteSession(session.id);
    // Deleting the last day a cycle was still waiting on satisfies that cycle.
    // Without this it sat complete-but-open, and Today read "UP NEXT" over a
    // full row of filled dots.
    await ref
        .read(trainingRepositoryProvider)
        .closeCycleIfSatisfied(session.regimeId);
  }
}

/// One exercise in a day: one row, name over what it is, target on the right.
///
/// It was a block — name, a muscle pill, and a card under it holding the target
/// — which is three stacked things per exercise and about 130pt of height. Six
/// of those is not a training day you can read, it is a wall, and the card's
/// only job was to be a second tap target for the target sheet. The sheet is
/// one row down on the slot screen, which is where the rest of this slot's
/// settings already live; the figure stays visible here, which is what THEME asks for
/// for.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.regimeId,
    required this.sessionId,
    required this.slot,
    required this.exercise,
  });

  final String regimeId;
  final String sessionId;
  final SessionExercise slot;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final overridden =
        slot.deloadSetDelta != null || slot.deloadWeightPct != null;

    return AppRow(
      title: exercise.name,
      // Text, not a pill: a chip per row down a list is a column of chips, and
      // the muscle is a fact about the row rather than a state of it.
      subtitle: overridden
          ? '${exercise.muscle.label} · Own deload'
          : exercise.muscle.label,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(targetLabel(slot), style: context.t.labelLarge),
          const SizedBox(width: Space.sm),
          Icon(Icons.chevron_right_rounded,
              size: 20, color: context.c.textTertiary),
        ],
      ),
      onTap: () => openExercise(
        context,
        exerciseId: exercise.id,
        regimeId: regimeId,
        sessionId: sessionId,
        slotId: slot.id,
      ),
    );
  }
}

/// `4 × 8–10`, or `4 sets` when no range is set.
///
/// Never `4 × ——`: a slot without a rep range is not missing a measurement, it
/// is a slot you decided not to give one. Dashes are for a number that should
/// be there and isn't (rule 4).
String targetLabel(SessionExercise slot) {
  final low = slot.targetRepLow;
  final high = slot.targetRepHigh;
  if (low == null) {
    return '${slot.targetSets} set${slot.targetSets == 1 ? '' : 's'}';
  }
  final range = high == null || high == low ? '$low' : '$low–$high';
  return '${slot.targetSets} × $range';
}

/// Re-orders the days of a regime. Opened from the regime settings sheet, since
/// the tab strip is where you *read* the order and not where you change it.
///
/// Takes the **repository**, not a [WidgetRef]. The settings sheet closes
/// itself before opening this one, so by the time `Save order` is tapped the
/// widget that owned that ref has been disposed and reading through it throws
/// `Cannot use "ref" after the widget was disposed` — from a gesture handler,
/// where the only symptom is that the button does nothing. A repository is a
/// plain object: it outlives the widget that looked it up.
Future<void> showDayReorder(
  BuildContext context,
  RegimeRepository repo,
  List<Session> sessions,
) {
  return showReorderSheet(
    context,
    title: 'Re-order days',
    subtitle: 'The order one cycle runs in',
    items: [for (final s in sessions) (id: s.id, label: s.name)],
    onCommit: repo.reorderSessions,
  );
}

/// Adds a training day to a regime. Shared by the `Add day +` tab and the empty
/// state, which are the two places it is ever asked for.
Future<void> addSessionPrompt(
  BuildContext context,
  WidgetRef ref,
  String regimeId,
) async {
  // The names already in this regime, read once for the field's validator —
  // the same shape the regime prompt uses. A day is identified on screen by its
  // name alone: the prefill disclosure says which day it borrowed from, and
  // History filters by it. Two called `Push 1` makes both ambiguous, so the
  // field says so while it is being typed rather than the save failing after
  // the sheet has closed.
  final repo = ref.read(regimeRepositoryProvider);
  final taken = await repo.liveSessionNames(regimeId);
  if (!context.mounted) return;

  final name = await promptForText(
    context,
    title: 'New day',
    hint: 'Push 1, Upper A, Legs …',
    validate: (value) => taken.contains(value.trim().toLowerCase())
        ? 'This regime already has a day called ${value.trim()}'
        : null,
  );
  if (name == null || name.isEmpty) return;
  await repo.addSession(regimeId, name);
}

/// Small single-field prompt used for names throughout the regime editor.
///
/// A sheet, not a dialog: it rides above the keyboard, where a centred alert
/// lands in the middle of the screen and then fights the keyboard for the same
/// space (THEME → Components). The confirm sits directly under the field and stays
/// `surfaceHigh` with a `textTertiary` label until there is something to save,
/// so a stray tap can't create a day called "".
///
/// Returns the trimmed text, or null when dismissed.
/// [validate] returns the reason the current text can't be saved, or null when
/// it can. Shown under the field and the confirm stays off — a name that is
/// already taken is said while you are still typing it, not after the sheet
/// closes and a snackbar tells you the work was thrown away.
///
/// [maxLength] stops the typing rather than counting it. A name is one line on
/// a row and the row ellipsizes, so the honest ceiling is "what fits", and the
/// tables refuse anything past it outright — a limit reached silently at the
/// keyboard beats a save that fails after the sheet has closed. No counter:
/// `12 / 60` under a field nobody was going to fill is noise, which is not the
/// case for a note, where the limit is the point.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  String? Function(String value)? validate,
  int maxLength = 60,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) => _NamePromptSheet(
      title: title,
      hint: hint,
      initial: initial,
      validate: validate,
      maxLength: maxLength,
    ),
  );
}

class _NamePromptSheet extends StatefulWidget {
  const _NamePromptSheet({
    required this.title,
    required this.hint,
    required this.initial,
    required this.maxLength,
    this.validate,
  });

  final String title;
  final String? hint;
  final String initial;
  final int maxLength;
  final String? Function(String value)? validate;

  @override
  State<_NamePromptSheet> createState() => _NamePromptSheetState();
}

class _NamePromptSheetState extends State<_NamePromptSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty || _error != null) return;
    Navigator.of(context).pop(value);
  }

  String? get _error {
    final value = _controller.text.trim();
    if (value.isEmpty) return null;
    return widget.validate?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final error = _error;
    return AppSheet(
      title: widget.title,
      footer: PrimaryButton(
        label: 'Save',
        onPressed:
            _controller.text.trim().isEmpty || error != null ? null : _submit,
      ),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(widget.maxLength)],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          style: context.t.bodyLarge?.copyWith(color: c.textPrimary),
          cursorColor: c.textPrimary,
          decoration: InputDecoration(hintText: widget.hint),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              error,
              style: context.t.bodySmall?.copyWith(color: c.negative),
            ),
          ),
      ],
    );
  }
}

/// The catalog, which the Regime index points at.
void openExerciseCatalog(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExerciseCatalogScreen()),
    );

/// One programme, pushed off the Regime index.
void openRegimeEditor(BuildContext context, String regimeId) =>
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegimeEditorScreen(regimeId: regimeId)),
    );
