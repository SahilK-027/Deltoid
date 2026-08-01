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
    final c = context.c;

    return Scaffold(
      appBar: AppBar(title: const Text('Regimes')),
      body: summaries == null
          ? const Center(child: CircularProgressIndicator())
          : summaries.isEmpty
              ? EmptyState(
                  icon: Icons.tune,
                  title: 'No regimes yet',
                  message: 'Build your own split, or start from a template and '
                      'edit it into shape.',
                  action: PrimaryButton(
                    label: 'Create regime',
                    onPressed: () => createRegimeFlow(context, ref),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Space.gutter, Space.sm, Space.gutter, Space.lg),
                      child: Text(
                        'One is active at a time. Switching keeps every past '
                        'workout intact and still attached to the programme it '
                        'was run under.',
                        style: context.t.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: Space.lg),
                        itemCount: summaries.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: c.border),
                        itemBuilder: (context, i) => _RegimeRow(
                          summary: summaries[i],
                          total: summaries.length,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Space.gutter, Space.sm, Space.gutter, Space.md),
                      child: SafeArea(
                        top: false,
                        child: PrimaryButton(
                          label: 'New regime',
                          icon: Icons.add_rounded,
                          onPressed: () => _create(context, ref),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Builds a regime without switching to it, and says so in the one place a
  /// consequence like that belongs: an offer to switch, rather than a switch
  /// you have to undo.
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = await createRegimeFlow(context, ref, activate: false);
    if (id == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Added — you are still training the old one'),
        action: SnackBarAction(
          label: 'Train it',
          onPressed: () =>
              ref.read(regimeRepositoryProvider).setActiveRegime(id),
        ),
      ),
    );
  }
}

class _RegimeRow extends ConsumerWidget {
  const _RegimeRow({required this.summary, required this.total});

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
      '${summary.sessionCount} day${summary.sessionCount == 1 ? '' : 's'}',
      '${summary.workoutCount} logged',
      if (regime.deloadEnabled)
        'deload every ${regime.deloadAfterCycles}'
      else
        'no deload',
    ];

    return AppRow(
      // The identity mark History already scans by, on the row that owns it.
      leading: IconTile(
        active ? Icons.bolt_rounded : Icons.layers_outlined,
        color: c.identityFor(regime.id),
        solid: active,
      ),
      title: regime.name,
      subtitle: facts.join('  ·  '),
      onTap: active ? null : () => _activate(context, ref),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active) ...[
            const Pill('Active'),
            const SizedBox(width: Space.sm),
          ],
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            fill: Colors.transparent,
            onTap: () => _showActions(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) {
    final active = summary.regime.isActive;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheet) => AppSheet(
        title: summary.regime.name,
        contentPadding: const EdgeInsets.only(bottom: Space.md),
        children: [
          if (!active)
            AppRow(
              icon: Icons.play_circle_outline,
              title: 'Train this one',
              subtitle: 'Today and Regime switch to it',
              onTap: () {
                Navigator.of(sheet).pop();
                _activate(context, ref);
              },
            ),
          AppRow(
            icon: Icons.edit_outlined,
            title: 'Rename',
            onTap: () async {
              final navigator = Navigator.of(sheet);
              final name = await promptForText(
                context,
                title: 'Rename regime',
                initial: summary.regime.name,
              );
              if (name == null || name.isEmpty) return;
              await ref
                  .read(regimeRepositoryProvider)
                  .updateRegime(summary.regime.id, name: Value(name));
              navigator.pop();
            },
          ),
          AppRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete regime',
            subtitle: total > 1
                ? 'Its days and slots go with it'
                : 'Not the only one — there would be nothing to train',
            tint: total > 1 ? sheet.c.negative : sheet.c.textTertiary,
            onTap: total > 1
                ? () async {
                    final navigator = Navigator.of(sheet);
                    final done = await _delete(context, ref);
                    if (done) navigator.pop();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(regimeRepositoryProvider).setActiveRegime(summary.regime.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Training ${summary.regime.name}')),
    );
  }

  Future<bool> _delete(BuildContext context, WidgetRef ref) async {
    final logged = summary.workoutCount;
    final ok = await confirmAction(
      context,
      title: 'Delete ${summary.regime.name}?',
      message: logged == 0
          ? 'Its days and exercise slots go with it. Nothing has been logged '
              'under this regime.'
          : 'Its days and exercise slots go with it.\n\n'
              'The $logged workout${logged == 1 ? '' : 's'} logged under it '
              'stay in History — each one holds its own record of what you '
              'actually did.',
      confirmLabel: 'Delete',
    );
    if (!ok) return false;
    await ref.read(regimeRepositoryProvider).deleteRegime(summary.regime.id);
    return true;
  }
}
