import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'sign_in_flow.dart';

/// The one moment that needs a message rather than a state.
///
/// [SYNC.md § 2](SYNC.md#2-the-three-states): **a new phone taken to the gym
/// before it has ever had signal.** `Local`, nothing logged, and the history
/// sitting on an account this phone cannot reach. Nothing can fix that until
/// there is a network — but the app must not look like an install that lost
/// everything.
///
/// So it says where the training probably is. That is the difference between a
/// user who waits and a user who reinstalls in a panic, and it is the only
/// thing this screen can do about a problem it cannot solve.
///
/// **Three conditions, and all of them are needed.** This build can reach an
/// account at all; nothing is signed in; and nothing has ever been logged here.
/// The last one is what keeps it off the screen of somebody who simply chose to
/// stay local and has been training happily for a year — for them the sentence
/// would be wrong, and Settings already offers the same connection without
/// implying anything is missing.
class AccountRecoveryNote extends ConsumerWidget {
  const AccountRecoveryNote({super.key, required this.hasHistory});

  /// Whether anything has ever been logged on this phone.
  final bool hasHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hasHistory) return const SizedBox.shrink();
    if (ref.watch(syncAuthProvider) == null) return const SizedBox.shrink();
    if (ref.watch(accountProvider).valueOrNull != null) {
      return const SizedBox.shrink();
    }

    // The gap belongs to the card rather than to the caller: three of the four
    // reasons this widget draws nothing are invisible from the outside, and a
    // caller that reserved the space would leave a hole above the heatmap on
    // every phone that is signed in.
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trained on Deltoid before?', style: context.t.titleMedium),
            const SizedBox(height: Space.sm),
            Text(
              // Neither promising nor alarming: it says where to look, and it
              // says the phone is fine in the meantime.
              'If you were signed in on another phone, your training is on your '
              'Google account rather than gone. Sign in when you have a '
              'connection and it comes back. Nothing you log here in the '
              'meantime is lost.',
              style: context.t.bodyMedium?.copyWith(
                color: context.c.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Space.lg),
            SecondaryButton(
              label: 'Sign in',
              icon: Icons.cloud_sync_outlined,
              onPressed: () => signInAndAdopt(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
