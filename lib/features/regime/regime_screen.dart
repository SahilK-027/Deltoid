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
import 'session_editor.dart';

final regimeRepositoryProvider = Provider<RegimeRepository>(
  (ref) => RegimeRepository(ref.watch(databaseProvider)),
);

final allRegimesProvider = StreamProvider<List<Regime>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.regimes)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
  return query.watch();
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
            tooltip: 'Switch regime',
            onPressed: () => _showRegimeSwitcher(context, ref),
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

  Future<void> _showRegimeSwitcher(BuildContext context, WidgetRef ref) async {
    final regimes = ref.read(allRegimesProvider).valueOrNull ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text('Regimes', style: ctx.t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
              child: Text(
                'Switching keeps every past workout intact and still '
                'attached to the programme it was run under.',
                style: ctx.t.bodySmall,
              ),
            ),
            for (final r in regimes)
              ListTile(
                leading: Icon(
                  r.isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: r.isActive ? ctx.c.accent : ctx.c.textTertiary,
                ),
                title: Text(r.name),
                onTap: () async {
                  final navigator = Navigator.of(ctx);
                  await ref.read(regimeRepositoryProvider).setActiveRegime(r.id);
                  navigator.pop();
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New regime'),
              subtitle: const Text('Blank, or from a template'),
              onTap: () async {
                final navigator = Navigator.of(ctx);
                navigator.pop();
                await _createRegime(context, ref);
              },
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }
}

class _RegimeHeader extends ConsumerWidget {
  const _RegimeHeader({required this.regime, required this.status});

  final Regime regime;
  final CycleStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
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

class _SessionList extends ConsumerWidget {
  const _SessionList({required this.sessions, required this.regimeId});

  final List<Session> sessions;
  final String regimeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
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

    return AppCard(
      padding: EdgeInsets.zero,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: sessions.length,
        onReorder: (oldIndex, newIndex) {
          var target = newIndex;
          if (target > oldIndex) target -= 1;
          final ids = sessions.map((s) => s.id).toList();
          ids.insert(target, ids.removeAt(oldIndex));
          ref.read(regimeRepositoryProvider).reorderSessions(ids);
        },
        itemBuilder: (context, i) {
          final s = sessions[i];
          final count = ref.watch(sessionSlotCountProvider(s.id)).valueOrNull;
          return Column(
            key: ValueKey(s.id),
            children: [
              if (i > 0) Divider(color: c.border, height: 1),
              ListTile(
                leading: ReorderableDragStartListener(
                  index: i,
                  child: Icon(Icons.drag_indicator, color: c.textTertiary, size: 20),
                ),
                title: Text(s.name, style: context.t.titleSmall),
                subtitle: Text(
                  count == null ? '' : '$count exercises',
                  style: context.t.labelSmall,
                ),
                trailing: Icon(Icons.chevron_right, color: c.textTertiary, size: 18),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SessionEditorScreen(sessionId: s.id),
                  ),
                ),
              ),
            ],
          );
        },
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
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
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
