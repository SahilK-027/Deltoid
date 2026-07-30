import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/regime_repository.dart';
import '../../domain/cycle_engine.dart';
import 'exercise_catalog_screen.dart';
import 'regime_setup.dart';
import 'regimes_screen.dart';
import 'session_editor.dart';

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

/// Exercise count per session, for the summary rows.
final sessionSlotCountProvider =
    StreamProvider.family<int, String>((ref, sessionId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.sessionExercises)
    ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull());
  return query.watch().map((rows) => rows.length);
});

class RegimeScreen extends ConsumerWidget {
  const RegimeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regime = ref.watch(activeRegimeProvider).valueOrNull;
    final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];
    final status = ref.watch(cycleStatusProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Regime'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fitness_center),
            tooltip: 'Exercises',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExerciseCatalogScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Regimes',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RegimesScreen()),
            ),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: regime == null
          ? EmptyState(
              icon: Icons.tune,
              title: 'No regime yet',
              message: 'Build your own split, or start from a template and '
                  'edit it into shape.',
              action: FilledButton(
                onPressed: () => _createRegime(context, ref),
                child: const Text('Create regime'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.sm, Space.lg, Space.huge),
              children: [
                _RegimeHeader(regime: regime, status: status),
                if (status != null) ...[
                  const SizedBox(height: Space.md),
                  _CycleControls(status: status, sessions: sessions),
                ],
                const SizedBox(height: Space.xxl),
                SectionLabel(
                  'Sessions · one cycle',
                  trailing: TextButton(
                    onPressed: () => addSessionPrompt(context, ref, regime.id),
                    child: const Text('Add'),
                  ),
                ),
                _SessionList(sessions: sessions, regimeId: regime.id),
                const SizedBox(height: Space.xxl),
                const SectionLabel('Deload'),
                _DeloadCard(regime: regime),
              ],
            ),
    );
  }

  Future<void> _createRegime(BuildContext context, WidgetRef ref) =>
      createRegimeFlow(context, ref);
}

class _RegimeHeader extends ConsumerWidget {
  const _RegimeHeader({required this.regime, required this.status});

  final Regime regime;
  final CycleStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final all = ref.watch(regimeSummariesProvider).valueOrNull ?? const [];
    final position = all.indexWhere((s) => s.regime.id == regime.id) + 1;

    return AppCard(
      padding: const EdgeInsets.all(Space.xl),
      onTap: () => _rename(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('ACTIVE REGIME', style: context.t.labelSmall)),
              Icon(Icons.edit_outlined, size: 14, color: c.textTertiary),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(regime.name, style: context.t.titleLarge),
          // The other regimes are not gone, they are just not active. Saying so
          // here is the difference between "switching" and "losing" one.
          if (all.length > 1) ...[
            const SizedBox(height: Space.sm),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegimesScreen()),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$position of ${all.length} regimes',
                    style: context.t.labelMedium?.copyWith(color: c.accent),
                  ),
                  const SizedBox(width: Space.xs),
                  Icon(Icons.chevron_right, size: 14, color: c.accent),
                ],
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                Text('Cycle ${status!.cycleIndex}', style: context.t.bodyMedium),
                Text('  ·  ', style: context.t.bodyMedium),
                Text(
                  status!.deloadEnabled
                      ? (status!.isDeload
                          ? 'deload in progress'
                          : '${status!.cyclesUntilDeload} cycles to deload')
                      : 'deload off',
                  style: context.t.bodyMedium?.copyWith(
                    color: status!.isDeload ? c.deload : c.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptForText(
      context,
      title: 'Rename regime',
      initial: regime.name,
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(regimeRepositoryProvider)
        .updateRegime(regime.id, name: Value(name));
  }
}

/// The two cycle overrides, which existed in the repository long before they
/// existed on screen.
///
/// Without "Close this cycle" a session you permanently skip stalls the
/// programme: the cycle never closes, the cycle index never moves, and the
/// deload you configured never arrives. Without the deload override the
/// schedule is binding, which contradicts the one promise this app makes —
/// it suggests, it never forces. Whether you need a light week is a decision
/// made in the gym, not six cycles in advance.
class _CycleControls extends ConsumerWidget {
  const _CycleControls({required this.status, required this.sessions});

  final CycleStatus status;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final remaining = status.remainingSessionIds;
    final canClose = status.done > 0 && remaining.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CYCLE ${status.cycleIndex}',
                  style: context.t.labelSmall,
                ),
              ),
              Text(
                '${status.done} of ${status.total} done',
                style: context.t.labelMedium?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: canClose
                      ? () => _closeCycle(context, ref, remaining)
                      : null,
                  child: const Text('Close this cycle'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _toggleDeload(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: status.isDeload ? c.deload : null,
                  ),
                  child: Text(
                    status.isDeload ? 'Not a deload' : 'Make it a deload',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            canClose
                ? 'Closing skips what is left and starts the next cycle.'
                : status.done == 0
                ? 'Nothing trained yet this cycle.'
                : 'Every session is done — the next workout opens a new cycle.',
            style: context.t.labelSmall?.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }

  String _nameOf(String sessionId) {
    for (final s in sessions) {
      if (s.id == sessionId) return s.name;
    }
    return 'A session';
  }

  Future<void> _closeCycle(
    BuildContext context,
    WidgetRef ref,
    List<String> remaining,
  ) async {
    // Name what it costs. "Are you sure" tells you nothing; "Leg 2 won't be
    // trained this cycle" is the actual decision.
    final names = remaining.map(_nameOf).toList();
    final list = names.length == 1
        ? '${names.single} won\'t be trained this cycle.'
        : '${names.join(', ')} won\'t be trained this cycle.';

    final ok = await confirmAction(
      context,
      title: 'Close cycle ${status.cycleIndex}?',
      message: '$list\n\nThe next cycle starts from the top, and this one '
          'counts towards your deload.',
      confirmLabel: 'Close cycle',
      destructive: false,
    );
    if (!ok) return;

    final regime = ref.read(activeRegimeProvider).valueOrNull;
    if (regime == null) return;
    await ref.read(trainingRepositoryProvider).advanceCycle(regime.id);
  }

  Future<void> _toggleDeload(BuildContext context, WidgetRef ref) async {
    final next = !status.isDeload;
    await ref
        .read(trainingRepositoryProvider)
        .setCycleDeload(status.cycleId, next);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Cycle ${status.cycleIndex} is a deload — lighter, fewer sets.'
              : 'Cycle ${status.cycleIndex} is a normal cycle again.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _SessionList extends ConsumerWidget {
  const _SessionList({required this.sessions, required this.regimeId});

  final List<Session> sessions;
  final String regimeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No sessions yet. Add the days that make up one cycle — a cycle '
              'is one pass through all of them, not a calendar week.',
              style: context.t.bodySmall,
            ),
            const SizedBox(height: Space.md),
            OutlinedButton(
              onPressed: () => addSessionPrompt(context, ref, regimeId),
              child: const Text('Add session'),
            ),
          ],
        ),
      );
    }

    // Explicit move controls rather than a drag handle. The list is nested in
    // the tab's own ListView, and ReorderableDragStartListener is an immediate
    // vertical drag: it competed with the parent scrollable and lost, so a
    // normal-speed drag scrolled the page instead of reordering, and there was
    // no auto-scroll to carry a session past the fold at all. A reorder should
    // never depend on how fast your thumb moves.
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < sessions.length; i++)
            _SessionRow(
              session: sessions[i],
              index: i,
              total: sessions.length,
              onMove: (delta) {
                final ids = sessions.map((s) => s.id).toList();
                final target = (i + delta).clamp(0, ids.length - 1);
                if (target == i) return;
                ids.insert(target, ids.removeAt(i));
                ref.read(regimeRepositoryProvider).reorderSessions(ids);
              },
            ),
        ],
      ),
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    required this.index,
    required this.total,
    required this.onMove,
  });

  final Session session;
  final int index;
  final int total;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final count = ref.watch(sessionSlotCountProvider(session.id)).valueOrNull;

    return Column(
      children: [
        if (index > 0) Divider(color: c.border, height: 1),
        ListTile(
          leading: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MoveButton(
                icon: Icons.keyboard_arrow_up,
                onTap: index == 0 ? null : () => onMove(-1),
              ),
              _MoveButton(
                icon: Icons.keyboard_arrow_down,
                onTap: index >= total - 1 ? null : () => onMove(1),
              ),
            ],
          ),
          title: Text(session.name, style: context.t.titleSmall),
          subtitle: Text(
            count == null ? '' : '$count exercises',
            style: context.t.labelSmall,
          ),
          trailing:
              Icon(Icons.chevron_right, color: c.textTertiary, size: 18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionEditorScreen(sessionId: session.id),
            ),
          ),
        ),
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? c.border : c.textSecondary,
        ),
      ),
    );
  }
}

/// Deload is configured here and nowhere else: on, how often, and how much
/// lighter. The app suggests; it never forces.
class _DeloadCard extends ConsumerWidget {
  const _DeloadCard({required this.regime});

  final Regime regime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(regimeRepositoryProvider);
    final c = context.c;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(
        children: [
          SwitchListTile(
            value: regime.deloadEnabled,
            activeThumbColor: c.deload,
            title: Text('Scheduled deload', style: context.t.titleSmall),
            subtitle: Text(
              'A lighter cycle after every N complete cycles',
              style: context.t.labelSmall,
            ),
            onChanged: (v) =>
                repo.updateRegime(regime.id, deloadEnabled: Value(v)),
          ),
          if (regime.deloadEnabled) ...[
            Divider(color: c.border, height: 1),
            _StepperTile(
              label: 'Deload after',
              value: '${regime.deloadAfterCycles} cycles',
              onDecrement: regime.deloadAfterCycles > 1
                  ? () => repo.updateRegime(regime.id,
                      deloadAfterCycles: Value(regime.deloadAfterCycles - 1))
                  : null,
              onIncrement: () => repo.updateRegime(regime.id,
                  deloadAfterCycles: Value(regime.deloadAfterCycles + 1)),
            ),
            Divider(color: c.border, height: 1),
            _StepperTile(
              label: 'Sets during deload',
              value: regime.deloadSetDelta == 0
                  ? 'unchanged'
                  : '${regime.deloadSetDelta}',
              helper: 'Applied to each exercise, never below one set',
              onDecrement: regime.deloadSetDelta > -3
                  ? () => repo.updateRegime(regime.id,
                      deloadSetDelta: Value(regime.deloadSetDelta - 1))
                  : null,
              onIncrement: regime.deloadSetDelta < 0
                  ? () => repo.updateRegime(regime.id,
                      deloadSetDelta: Value(regime.deloadSetDelta + 1))
                  : null,
            ),
            Divider(color: c.border, height: 1),
            _StepperTile(
              label: 'Weight during deload',
              value: '${regime.deloadWeightPct}%',
              helper: 'Of the last working weight in that session',
              onDecrement: regime.deloadWeightPct > 40
                  ? () => repo.updateRegime(regime.id,
                      deloadWeightPct: Value(regime.deloadWeightPct - 5))
                  : null,
              onIncrement: regime.deloadWeightPct < 100
                  ? () => repo.updateRegime(regime.id,
                      deloadWeightPct: Value(regime.deloadWeightPct + 5))
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    this.helper,
  });

  final String label;
  final String value;
  final String? helper;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.t.titleSmall),
                if (helper != null)
                  Text(helper!, style: context.t.labelSmall),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: onDecrement,
          ),
          SizedBox(
            width: 72,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: context.t.labelLarge?.copyWith(color: c.textPrimary),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: onIncrement,
          ),
        ],
      ),
    );
  }
}

/// Adds a training day to a regime. Shared by the section header and the empty
/// state, which are the two places it is ever asked for.
Future<void> addSessionPrompt(
  BuildContext context,
  WidgetRef ref,
  String regimeId,
) async {
  final name = await promptForText(
    context,
    title: 'New session',
    hint: 'Push 1, Upper A, Legs …',
  );
  if (name == null || name.isEmpty) return;
  await ref.read(regimeRepositoryProvider).addSession(regimeId, name);
}

/// Small single-field prompt used for names throughout the regime editor.
///
/// Returns the trimmed text, or null when dismissed. Never returns an empty
/// string: Save stays disabled until there is something to save, so a stray tap
/// can't create a session called "".
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  int maxLines = 1,
  /// Notes are the one text this app takes that you must also be able to
  /// clear, so emptiness has to be a savable answer rather than a disabled
  /// button.
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      hint: hint,
      initial: initial,
      maxLines: maxLines,
      allowEmpty: allowEmpty,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.maxLines,
    required this.allowEmpty,
  });

  final String title;
  final String? hint;
  final String initial;
  final int maxLines;
  final bool allowEmpty;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty && !widget.allowEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        textCapitalization: TextCapitalization.sentences,
        textInputAction:
            widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hint),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty && !widget.allowEmpty
              ? null
              : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Session template rows joined with their exercises.
final sessionSlotsProvider = StreamProvider.family<
    List<({SessionExercise slot, Exercise exercise})>, String>((ref, sessionId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.sessionExercises).join([
    innerJoin(db.exercises, db.exercises.id.equalsExp(db.sessionExercises.exerciseId)),
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
