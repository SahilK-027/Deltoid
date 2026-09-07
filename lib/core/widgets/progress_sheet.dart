import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../progress.dart';
import '../theme/tokens.dart';

/// Runs a long job behind a sheet that says what it is doing.
///
/// A decade of training is a hundred thousand rows. Without something on
/// screen the app looks hung, and a hung restore gets killed halfway — which
/// is the one failure mode that costs data. Both jobs report through
/// [JobStep], so this is the same sheet either way.
///
/// The sheet cannot be dismissed and the barrier does not close it: the
/// database is mid-transaction, and the way out is for the job to finish.
/// Errors are rethrown to the caller, which owns the wording.
Future<T?> withProgressSheet<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(ProgressReport report) task,
}) async {
  final step = ValueNotifier<JobStep?>(null);
  final navigator = Navigator.of(context);

  unawaited(
    showModalBottomSheet<void>(
      // The route holds the system bars: a sheet that sizes itself can
      // otherwise run under the status bar. See [pickExercise].
      useSafeArea: true,
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _ProgressSheet(title: title, step: step),
      ),
    ),
  );

  try {
    // The notifier is written from a callback that fires between database
    // batches, so the bar moves on the frames the work leaves free.
    return await task((s) => step.value = s);
  } finally {
    navigator.pop();
    step.dispose();
  }
}

class _ProgressSheet extends StatelessWidget {
  const _ProgressSheet({required this.title, required this.step});

  final String title;
  final ValueListenable<JobStep?> step;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.xl,
          Space.xl,
          Space.xxl,
        ),
        child: ValueListenableBuilder<JobStep?>(
          valueListenable: step,
          builder: (context, current, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: context.t.headlineSmall),
                const SizedBox(height: Space.xs),
                Text(
                  switch (current?.phase) {
                    null => 'Starting',
                    JobPhase.reading => 'Reading ${current!.detail}',
                    // Named rather than left as a stalled bar: this is the
                    // phase that takes the longest and reports nothing, and
                    // silence here is what makes the whole thing look hung.
                    JobPhase.encoding =>
                      'Writing ${current!.detail} to the backup file',
                    JobPhase.decoding =>
                      'Reading the file · ${current!.detail}',
                    JobPhase.clearing =>
                      'Clearing existing data on this device',
                    // The one phase that waits on a network. Named as rows
                    // rather than as a table on its own, because what makes a
                    // first pull long is the count and not which table it is
                    // on.
                    JobPhase.pulling =>
                      '${current!.rows} rows from your account',
                    JobPhase.writing =>
                      '${current!.rows} rows · ${current.detail}',
                  },
                  style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: Space.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    // Null while a phase genuinely cannot say how far it is,
                    // where the bar runs indeterminate rather than inventing a
                    // number and then jumping.
                    value: current?.fraction,
                    minHeight: 6,
                    backgroundColor: c.surfaceHigh,
                    color: c.accent,
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  'Keep the app open until this finishes.',
                  style: context.t.labelSmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The latest weight, and one tap to log today's.
///
/// One row rather than a card carrying a 30sp figure. This value is read in
/// passing on the way to recording the next one, and at display size it
/// occupies the same vertical space as the entire Data section beneath it.
///
/// Tapping opens the log sheet on today — prefilled when today already has an
/// entry, so a second weighing corrects rather than duplicates (the table is
/// keyed by day, so it would have overwritten either way; this says so).
