import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/regime_repository.dart';
import 'regime_screen.dart';
import 'regime_setup.dart';

/// Every programme, not just the one being trained.
///
/// Regimes were always additive — creating one only moves the active flag — but
/// with the list hidden behind a sheet the old ones looked deleted. They are
/// first-class rows here: switch between them, rename, delete, and see how much
/// was trained under each.
class RegimesScreen extends ConsumerWidget {
  const RegimesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(regimeSummariesProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Regimes')),
      floatingActionButton: summaries == null || summaries.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: context.c.accent,
              foregroundColor: context.c.onAccent,
              onPressed: () => createRegimeFlow(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New regime'),
            ),
      body: summaries == null
          ? const Center(child: CircularProgressIndicator())
          : summaries.isEmpty
              ? EmptyState(
                  icon: Icons.tune,
                  title: 'No regimes yet',
                  message: 'Build your own split, or start from a template and '
                      'edit it into shape.',
                  action: FilledButton(
                    onPressed: () => createRegimeFlow(context, ref),
                    child: const Text('Create regime'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      Space.lg, Space.sm, Space.lg, Space.huge),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: Text(
                        'One regime is active at a time. Switching keeps every '
                        'past workout intact and still attached to the '
                        'programme it was run under.',
                        style: context.t.bodySmall,
                      ),
                    ),
                    for (final s in summaries) ...[
                      _RegimeCard(summary: s, total: summaries.length),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                ),
    );
  }
}

class _RegimeCard extends ConsumerWidget {
  const _RegimeCard({required this.summary, required this.total});

  final RegimeSummary summary;

  /// The last regime standing can't be deleted — deleting it would drop the app
  /// back to its first-launch state with a full history behind it.
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final regime = summary.regime;
    final active = regime.isActive;

    final facts = [
      '${summary.sessionCount} session'
          '${summary.sessionCount == 1 ? '' : 's'}',
      '${summary.workoutCount} logged',
      if (regime.deloadEnabled)
        'deload every ${regime.deloadAfterCycles}'
      else
        'no deload',
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      highlightColor: active ? c.accent : null,
      onTap: active ? null : () => _activate(context, ref),
      child: Row(
        children: [
          Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: active ? c.accent : c.textTertiary,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        regime.name,
                        style: context.t.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: Space.sm),
                      Pill('Active', color: c.accent),
                    ],
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(facts.join('  ·  '), style: context.t.labelSmall),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, size: 20, color: c.textTertiary),
            onSelected: (value) => switch (value) {
              'activate' => _activate(context, ref),
              'rename' => _rename(context, ref),
              'delete' => _delete(context, ref),
              _ => null,
            },
            itemBuilder: (_) => [
              if (!active)
                const PopupMenuItem(
                  value: 'activate',
                  child: Text('Make active'),
                ),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                value: 'delete',
                enabled: total > 1,
                child: Text(
                  total > 1 ? 'Delete regime' : 'Delete (only regime)',
                  style: TextStyle(
                    color: total > 1 ? c.negative : c.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(regimeRepositoryProvider)
        .setActiveRegime(summary.regime.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Training ${summary.regime.name}')),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptForText(
      context,
      title: 'Rename regime',
      initial: summary.regime.name,
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(regimeRepositoryProvider)
        .updateRegime(summary.regime.id, name: Value(name));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final logged = summary.workoutCount;
    final ok = await confirmAction(
      context,
      title: 'Delete ${summary.regime.name}?',
      message: logged == 0
          ? 'Its sessions and exercise slots go with it. Nothing has been '
              'logged under this regime.'
          : 'Its sessions and exercise slots go with it.\n\n'
              'The $logged workout${logged == 1 ? '' : 's'} logged under it '
              'stay in History — each one holds its own record of what you '
              'actually did.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await ref.read(regimeRepositoryProvider).deleteRegime(summary.regime.id);
  }
}
