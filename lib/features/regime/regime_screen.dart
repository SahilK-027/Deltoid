import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/regime_repository.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/enums.dart';
import '../log/widgets/exercise_sheets.dart';
import 'exercise_catalog_screen.dart';
import 'regime_setup.dart';
import 'regime_settings.dart';
import 'regimes_screen.dart';
import 'session_slot_screen.dart';

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

/// The programme editor, and the only screen it takes.
///
/// A training day is a **tab**, not a row you push into (THEME §7): switching
/// days is a context change, and the vertical list it replaced put a screen
/// between you and the thing you came to edit. Everything about the regime
/// itself — its name, deload, the order of its days, the catalog, the other
/// regimes — is behind the one sliders button in the band, because none of it
/// is what you open this tab to do.
class RegimeScreen extends ConsumerStatefulWidget {
  const RegimeScreen({super.key});

  @override
  ConsumerState<RegimeScreen> createState() => _RegimeScreenState();
}

class _RegimeScreenState extends ConsumerState<RegimeScreen> {
  int _day = 0;

  @override
  Widget build(BuildContext context) {
    final regime = ref.watch(activeRegimeProvider).valueOrNull;
    final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];
    final status = ref.watch(cycleStatusProvider).valueOrNull;

    // The masthead is the screen, not a decoration on top of its content: a
    // first launch used to open on a bare empty state with nothing saying which
    // tab you were standing in — the one screen in the app whose header
    // appeared only once it had data.
    if (regime == null) {
      return Scaffold(
        body: Column(
          children: [
            const HeaderBand(
              child: PageHeader(title: 'Regime', topGap: Space.xxl),
            ),
            Expanded(
              child: EmptyState(
                icon: Icons.tune,
                title: 'No regime yet',
                message: 'Build your own split, or start from a template and '
                    'edit it into shape.',
                action: PrimaryButton(
                  label: 'Create regime',
                  onPressed: () => createRegimeFlow(context, ref),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // A day deleted out from under the strip must not leave the body pointing
    // past the end of it.
    final day = sessions.isEmpty ? 0 : _day.clamp(0, sessions.length - 1);

    return Scaffold(
      body: Column(
        children: [
          HeaderBand(
            child: Column(
              children: [
                PageHeader(
                  // The screen names itself; the regime's own name is the
                  // eyebrow above it, the slot a date takes on Today.
                  title: 'Regime',
                  eyebrow: regime.name,
                  belowGap: Space.sm,
                  actions: [
                    CircleIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Regime settings',
                      onTap: () => showRegimeSettings(context, ref, regime),
                    ),
                  ],
                  below: status == null
                      ? null
                      : _CycleLine(status: status, sessions: sessions),
                ),
                // No strip at all until there is a day in it: an `Add day +`
                // tab alone under the masthead is a tab bar with no tabs, and
                // the empty state below already asks for the same thing.
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
/// One quiet line in the band (THEME §5): the cycle is the state of things, not
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
            ? 'deload in progress'
            : '${status.cyclesUntilDeload} to deload')
        : 'deload off';

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
                  : 'Every day is done — the next workout opens a new one',
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
  const _DayBody({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(sessionSlotsProvider(session.id)).valueOrNull;
    final c = context.c;

    if (slots == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.huge),
      children: [
        // Two chips, not three. `Delete day` was the loudest thing on a page
        // about what you train, and it sits at the foot now with the other
        // destructive rows in this cluster.
        SizedBox(
          height: 60,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, Space.md, Space.gutter, Space.xs),
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
          // Count as heading (§7): the number is the useful part of the word.
          child: SectionHeader(
            slots.isEmpty
                ? 'No exercises'
                : '${slots.length} exercise${slots.length == 1 ? '' : 's'}',
            actionLabel: 'Add',
            onAction: () => _add(context, ref),
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
    final name = await promptForText(
      context,
      title: 'Rename day',
      initial: session.name,
    );
    if (name == null || name.isEmpty) return;
    await ref.read(regimeRepositoryProvider).renameSession(session.id, name);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final exercise = await pickExercise(context, ref);
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => _ReorderSheet(
        title: 'Re-order exercises',
        subtitle: session.name,
        labels: [for (final s in slots) s.exercise.name],
        ids: [for (final s in slots) s.slot.id],
        onCommit: (ids) =>
            ref.read(regimeRepositoryProvider).reorderSessionExercises(ids),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Delete ${session.name}?',
      message: 'It leaves the cycle, and its exercise slots go with it.\n\n'
          'Workouts already logged under this day stay in History — they hold '
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
/// settings already live; the figure stays visible here, which is all §9 asked
/// for.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.sessionId,
    required this.slot,
    required this.exercise,
  });

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
          ? '${exercise.muscle.label} · own deload'
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SessionSlotScreen(sessionId: sessionId, slotId: slot.id),
        ),
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

/// Explicit move controls rather than a drag handle, and in a sheet rather than
/// in the list.
///
/// `ReorderableDragStartListener` is an immediate vertical drag: nested in a
/// scrollable it competed with the page and lost, so a normal-speed drag
/// scrolled instead of reordering and there was no auto-scroll to carry a row
/// past the fold. A reorder should never depend on how fast your thumb moves.
class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({
    required this.title,
    required this.subtitle,
    required this.labels,
    required this.ids,
    required this.onCommit,
  });

  final String title;
  final String subtitle;
  final List<String> labels;
  final List<String> ids;
  final ValueChanged<List<String>> onCommit;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final _order = [
    for (var i = 0; i < widget.ids.length; i++)
      (id: widget.ids[i], label: widget.labels[i]),
  ];

  void _move(int from, int delta) {
    final to = (from + delta).clamp(0, _order.length - 1);
    if (to == from) return;
    setState(() => _order.insert(to, _order.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      footer: PrimaryButton(
        label: 'Save order',
        onPressed: () {
          widget.onCommit([for (final e in _order) e.id]);
          Navigator.of(context).pop();
        },
      ),
      children: [
        for (var i = 0; i < _order.length; i++)
          AppRow(
            title: _order[i].label,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleIconButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  size: 36,
                  tint: i == 0 ? c.textTertiary : null,
                  onTap: i == 0 ? null : () => _move(i, -1),
                ),
                const SizedBox(width: Space.sm),
                CircleIconButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  size: 36,
                  tint: i == _order.length - 1 ? c.textTertiary : null,
                  onTap:
                      i == _order.length - 1 ? null : () => _move(i, 1),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Re-orders the days of a regime. Opened from the regime settings sheet, since
/// the tab strip is where you *read* the order and not where you change it.
Future<void> showDayReorder(
  BuildContext context,
  WidgetRef ref,
  List<Session> sessions,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => _ReorderSheet(
      title: 'Re-order days',
      subtitle: 'The order one cycle runs in',
      labels: [for (final s in sessions) s.name],
      ids: [for (final s in sessions) s.id],
      onCommit: (ids) => ref.read(regimeRepositoryProvider).reorderSessions(ids),
    ),
  );
}

/// Adds a training day to a regime. Shared by the `Add day +` tab and the empty
/// state, which are the two places it is ever asked for.
Future<void> addSessionPrompt(
  BuildContext context,
  WidgetRef ref,
  String regimeId,
) async {
  final name = await promptForText(
    context,
    title: 'New day',
    hint: 'Push 1, Upper A, Legs …',
  );
  if (name == null || name.isEmpty) return;
  await ref.read(regimeRepositoryProvider).addSession(regimeId, name);
}

/// Small single-field prompt used for names throughout the regime editor.
///
/// A sheet, not a dialog: it rides above the keyboard, where a centred alert
/// lands in the middle of the screen and then fights the keyboard for the same
/// space (§5, §7). The confirm sits directly under the field and stays
/// `surfaceHigh` with a `textTertiary` label until there is something to save,
/// so a stray tap can't create a day called "".
///
/// Returns the trimmed text, or null when dismissed.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: _NamePromptSheet(title: title, hint: hint, initial: initial),
    ),
  );
}

class _NamePromptSheet extends StatefulWidget {
  const _NamePromptSheet({
    required this.title,
    required this.hint,
    required this.initial,
  });

  final String title;
  final String? hint;
  final String initial;

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
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppSheet(
      title: widget.title,
      footer: PrimaryButton(
        label: 'Save',
        onPressed: _controller.text.trim().isEmpty ? null : _submit,
      ),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          style: context.t.bodyLarge?.copyWith(color: c.textPrimary),
          cursorColor: c.textPrimary,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: context.t.bodyLarge?.copyWith(color: c.textTertiary),
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
            contentPadding: const EdgeInsets.all(Space.lg),
          ),
        ),
      ],
    );
  }
}

/// The catalog and the regime switcher, which the settings sheet points at.
void openExerciseCatalog(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExerciseCatalogScreen()),
    );

void openRegimes(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegimesScreen()),
    );
