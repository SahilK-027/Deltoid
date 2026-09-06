import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync_providers.dart';
import '../../core/widgets/progress_sheet.dart';
import '../../core/widgets/toast.dart';
import '../../data/sync/adoption.dart';
import '../../data/sync/sync_auth.dart';
import '../../data/sync/sync_backend.dart';
import 'adoption_sheet.dart';

/// How a sign-in ended, for the one caller that has to record an answer.
enum SignInOutcome {
  /// Signed in, and the account and the phone have been reconciled.
  signedIn,

  /// Backed out — of Google's sheet, or of the question in
  /// [showAdoptionSheet]. Nothing was written and nothing is signed in.
  cancelled,

  /// Reached Google or the account and neither would finish. Said out loud
  /// already.
  failed,
}

/// Sign in, then settle what the account holds against what this phone holds.
///
/// **One flow, two doors.** The welcome screen and Settings ask the same
/// question, and [SYNC.md § 10](SYNC.md#10-adoption) applies identically at
/// both: a phone signing in from Settings has been trained on for a month and
/// is the *likely* way two catalogs meet. Written twice it would have been
/// right in one place.
///
/// **The survey is read before anything is written.** A phone that loses signal
/// between the sign-in and the survey is signed back out and asked again,
/// because the alternative is a signed-in phone whose shape was never
/// established — which is the state that produces two catalogs. Past the survey
/// it is the other way round: adoption writes rows, and a failure partway
/// leaves work the engine finishes on its own.
Future<SignInOutcome> signInAndAdopt(
  BuildContext context,
  WidgetRef ref,
) async {
  final auth = ref.read(syncAuthProvider);
  final adoption = ref.read(adoptionProvider);
  final messenger = ScaffoldMessenger.of(context);

  if (auth == null) {
    showToastOn(
      messenger,
      'This version of Deltoid cannot sign in. Everything you log stays on '
      'this phone.',
      destructive: true,
    );
    return SignInOutcome.failed;
  }

  try {
    await auth.signInWithGoogle();
  } on SyncAuthCancelled {
    // Backing out of Google's own sheet is an answer to Google, not to the
    // screen that opened it. Nothing is said and the question stands.
    return SignInOutcome.cancelled;
  } on SyncAuthFailure catch (e) {
    showToastOn(messenger, e.message, destructive: true);
    return SignInOutcome.failed;
  }

  if (adoption == null) return SignInOutcome.signedIn;

  final AdoptionSurvey survey;
  try {
    survey = await adoption.survey();
  } on SyncTransportFailure catch (e) {
    await auth.signOut();
    showToastOn(messenger, e.message, destructive: true);
    return SignInOutcome.failed;
  }

  AdoptionChoice? choice;
  if (survey.shape == AdoptionShape.ask) {
    if (!context.mounted) return SignInOutcome.failed;
    choice = await showAdoptionSheet(context, survey);
    if (choice == null) {
      // Dismissed without answering. Nothing has been written, so the way back
      // is the way in: sign out, and the question stands.
      await auth.signOut();
      return SignInOutcome.cancelled;
    }
  }

  // **A sheet only where a human is waiting on one.** A first pull is the same
  // volume as a restore down a slower path, and a decade of training arriving
  // in silence looks like a hang — the failure that gets an app killed halfway
  // ([SYNC.md § 16](SYNC.md#16-still-to-decide)). A phone with nothing to
  // adopt is a round trip, and a sheet that flashes for one frame is worse than
  // no sheet at all.
  final watched = survey.shape == AdoptionShape.pull
      ? survey.accountSessions > 0
      : choice != AdoptionChoice.keepPhone;

  File? backup;
  try {
    if (watched && context.mounted) {
      backup = await withProgressSheet<File?>(
        context,
        title: 'Restoring your training',
        task: (report) =>
            adoption.adopt(survey.shape, choice: choice, onProgress: report),
      );
    } else {
      backup = await adoption.adopt(survey.shape, choice: choice);
    }
  } on SyncTransportFailure catch (e) {
    showToastOn(messenger, e.message, destructive: true);
  }

  if (backup != null) {
    showToastOn(
      messenger,
      'Saved ${backup.uri.pathSegments.last} to your backups folder.',
    );
  }
  return SignInOutcome.signedIn;
}
