import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import 'regime_screen.dart';

/// Everything about the regime that is not one of its days.
///
/// Behind the sliders button in the bar (THEME → Composing a screen), because none of it is what
/// the editor is opened to do: you open it to look at a training day. A name, a
/// deload schedule and the order of the days are all things you change once and
/// then live with.
///
/// The catalog and the list of regimes used to be in here too. They are on the
/// Regime index now — neither is a property of this programme.
Future<void> showRegimeSettings(
  BuildContext context,
  WidgetRef ref,
  Regime regime,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    // The screen's context, kept for the rows that close this sheet and open
    // the next thing: a sheet's own context is dead the moment it pops, and
    // `Re-order days` would then open on nothing.
    builder: (sheet) => _SettingsSheet(regime: regime, host: context),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet({required this.regime, required this.host});

  final Regime regime;
  final BuildContext host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(sessionsForRegimeProvider(regime.id)).valueOrNull ?? const [];

    return AppSheet(
      title: 'Regime',
      subtitle: regime.name,
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        AppRow(
          icon: Icons.edit_outlined,
          title: 'Rename',
          onTap: () async {
            final navigator = Navigator.of(context);
            final taken = await ref
                .read(regimeRepositoryProvider)
                .liveNames(exceptId: regime.id);
            if (!context.mounted) return;
            final name = await promptForText(
              context,
              title: 'Rename regime',
              initial: regime.name,
              validate: (value) => taken.contains(value.trim().toLowerCase())
                  ? 'A regime called ${value.trim()} already exists'
                  : null,
            );
            if (name == null || name.isEmpty) return;
            await ref
                .read(regimeRepositoryProvider)
                .updateRegime(regime.id, name: Value(name));
            navigator.pop();
          },
        ),
        AppRow(
          icon: Icons.trending_down_rounded,
          title: 'Deload',
          subtitle: regime.deloadEnabled
              ? 'Every ${regime.deloadAfterCycles == 1 ? '' : '${regime.deloadAfterCycles} '}'
                  'cycle${regime.deloadAfterCycles == 1 ? '' : 's'} · '
                  '${regime.deloadWeightPct}% weight'
              : 'Off, with no scheduled light week',
          onTap: () async {
            Navigator.of(context).pop();
            await showDeloadSettings(host, regime.id);
          },
        ),
        if (sessions.length > 1)
          AppRow(
            icon: Icons.swap_vert_rounded,
            title: 'Re-order days',
            subtitle: 'The order one cycle runs in',
            onTap: () async {
              // Read *before* the pop: this sheet is about to be disposed, and
              // everything it hands on has to be able to outlive it.
              final repo = ref.read(regimeRepositoryProvider);
              Navigator.of(context).pop();
              await showDayReorder(host, repo, sessions);
            },
          ),
      ],
    );
  }
}

/// Deload is configured here and nowhere else: on, how often, and how much
/// lighter. The app suggests; it never forces.
/// No [WidgetRef] parameter: the sheet it opens is a `ConsumerWidget` with a
/// ref of its own, and the caller's was already disposed by the time this ran.
Future<void> showDeloadSettings(
  BuildContext context,
  String regimeId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => _DeloadSheet(regimeId: regimeId),
  );
}

class _DeloadSheet extends ConsumerWidget {
  const _DeloadSheet({required this.regimeId});

  final String regimeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regime = ref.watch(regimeByIdProvider(regimeId)).valueOrNull;
    if (regime == null) {
      return const AppSheet(title: 'Deload', children: []);
    }
    final repo = ref.read(regimeRepositoryProvider);

    return AppSheet(
      title: 'Deload',
      subtitle: regime.name,
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        AppRow(
          icon: Icons.event_repeat_rounded,
          title: 'Scheduled deload',
          subtitle: 'A lighter cycle after every N complete cycles',
          trailing: Switch(
            value: regime.deloadEnabled,
            onChanged: (v) =>
                repo.updateRegime(regime.id, deloadEnabled: Value(v)),
          ),
        ),
        if (regime.deloadEnabled) ...[
          StepperRow(
            label: 'Deload after',
            value: '${regime.deloadAfterCycles} '
                'cycle${regime.deloadAfterCycles == 1 ? '' : 's'}',
            onDecrement: regime.deloadAfterCycles > 1
                ? () => repo.updateRegime(regime.id,
                    deloadAfterCycles: Value(regime.deloadAfterCycles - 1))
                : null,
            onIncrement: () => repo.updateRegime(regime.id,
                deloadAfterCycles: Value(regime.deloadAfterCycles + 1)),
          ),
          StepperRow(
            label: 'Sets during deload',
            helper: 'Applied to each exercise, never below one set',
            value: regime.deloadSetDelta == 0
                ? 'Unchanged'
                : '${regime.deloadSetDelta}',
            onDecrement: regime.deloadSetDelta > -3
                ? () => repo.updateRegime(regime.id,
                    deloadSetDelta: Value(regime.deloadSetDelta - 1))
                : null,
            onIncrement: regime.deloadSetDelta < 0
                ? () => repo.updateRegime(regime.id,
                    deloadSetDelta: Value(regime.deloadSetDelta + 1))
                : null,
          ),
          StepperRow(
            label: 'Weight during deload',
            helper: 'Of the last working weight in that session',
            value: '${regime.deloadWeightPct}%',
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
    );
  }
}

/// A row whose trailing control is a pair of steps around a value. The one
/// shape in the app for "a small number, changed one notch at a time".
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
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
    return AppRow(
      title: label,
      subtitle: helper,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleIconButton(
            icon: Icons.remove_rounded,
            size: 36,
            tooltip: 'Decrease',
            tint: onDecrement == null ? c.textTertiary : null,
            onTap: onDecrement,
          ),
          SizedBox(
            width: 76,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: context.t.labelLarge,
            ),
          ),
          CircleIconButton(
            icon: Icons.add_rounded,
            size: 36,
            tooltip: 'Increase',
            tint: onIncrement == null ? c.textTertiary : null,
            onTap: onIncrement,
          ),
        ],
      ),
    );
  }
}
