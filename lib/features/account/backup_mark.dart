import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/table_labels.dart';
import '../settings/settings_screen.dart' show backupState;

/// The header's one word on backing up: training that has not reached the
/// account yet, because the last attempt to send it failed.
///
/// Absent the rest of the time. It is not a status light — there is no mark
/// for *backed up*, because that is what an account is for, and none for *a
/// set was ticked a second ago*, because the push waits for writes to settle
/// and a mark that blinked on every set would be a flicker, not a state
/// ([backupWaitingProvider]). What it marks is a stretch of time the phone has
/// been holding training on its own, which is worth knowing mid-session and
/// which nothing else on the log screen can say.
///
/// Grey for no connection, because a gym without signal is the design working
/// and not a fault. `warning` for a refusal, because that one does not clear by
/// walking outside. Never red: nothing has been lost.
///
/// Nothing on Settings wears it. The account row there already says the same
/// thing in words, and a fact says itself once per screen (THEME § 2, rule 6).
class BackupMark extends ConsumerWidget {
  const BackupMark({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trouble = ref.watch(backupWaitingProvider);
    if (trouble == null) return const SizedBox.shrink();
    final c = context.c;
    return CircleIconButton(
      icon: Icons.cloud_off_outlined,
      tooltip: 'Not backed up yet',
      tint: trouble == SyncTrouble.refused ? c.warning : c.textSecondary,
      onTap: () =>
          showAppSheet<void>(context, builder: (_) => const _WaitingSheet()),
    );
  }
}

/// What is waiting, and why, in the words Settings already uses.
///
/// The first sentence is the one the mark exists to say: nothing is lost. The
/// rest is the account row's own line — how much, since when, and why — then
/// the same count broken down into the things the app calls them, so *37
/// changes* becomes *1 workout, 5 logged exercises, 31 sets*.
class _WaitingSheet extends ConsumerWidget {
  const _WaitingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(syncStateProvider).valueOrNull;
    final trouble = ref.watch(syncTroubleProvider).valueOrNull;
    final owed = ref.watch(owedByTableProvider).valueOrNull ?? const [];

    return AppSheet(
      title: 'Not backed up yet',
      subtitle:
          'Everything is saved on this phone. '
          '${backupState(state, trouble)}',
      footer: SecondaryButton(
        label: 'Try again now',
        icon: Icons.refresh_rounded,
        onPressed: () {
          ref.read(syncEngineProvider)?.resumed();
          Navigator.of(context).pop();
        },
      ),
      children: [
        // Emptied as a drain lands, so an open sheet ends with nothing listed
        // rather than with counts that are no longer owed.
        if (owed.isEmpty)
          Text(
            'Nothing is waiting.',
            style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        for (final (table, count) in owed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _capitalised(
                      count == 1 ? tableLabelOne(table) : tableLabel(table),
                    ),
                    style: context.t.bodyLarge,
                  ),
                ),
                Text(
                  '$count',
                  style: context.t.labelLarge?.copyWith(fontFeatures: tabular),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _capitalised(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
