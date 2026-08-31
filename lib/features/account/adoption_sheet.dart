import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/sync/adoption.dart';

/// The third shape, asked once, with the numbers on both sides.
///
/// [SYNC.md § 10](SYNC.md#10-adoption). Two independent histories share no ids
/// — every id is UUID v7 — so a merge is a union rather than a reconciliation,
/// and a union claims the user trained twice as often as they did on every day
/// both sides recorded. That is not a thing to decide for them.
///
/// **Merge is offered and is not the default**, and its line says what it
/// leaves behind. Dismissing answers nothing: the caller signs back out and the
/// welcome screen asks again, which is the harmless half of the failure.
Future<AdoptionChoice?> showAdoptionSheet(
  BuildContext context,
  AdoptionSurvey survey,
) {
  return showModalBottomSheet<AdoptionChoice>(
    // The route holds the system bars: a sheet that sizes itself can
    // otherwise run under the status bar. See [pickExercise].
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    // Two histories and one of them is about to go. Not something to lose by
    // brushing the scrim.
    isDismissible: false,
    enableDrag: false,
    showDragHandle: false,
    builder: (_) => _AdoptionSheet(survey: survey),
  );
}

class _AdoptionSheet extends StatelessWidget {
  const _AdoptionSheet({required this.survey});

  final AdoptionSurvey survey;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return AppSheet(
      title: 'This account already has training on it',
      subtitle:
          'Whichever history you do not keep is saved to your backups '
          'folder first.',
      children: [
        _Side(
          label: 'The account',
          sessions: survey.accountSessions,
          latest: survey.accountLatest,
        ),
        const SizedBox(height: Space.md),
        _Side(
          label: 'This phone',
          sessions: survey.phoneSessions,
          latest: survey.phoneLatest,
        ),
        const SizedBox(height: Space.xl),
        PrimaryButton(
          label: "Keep the account's history",
          onPressed: () =>
              Navigator.of(context).pop(AdoptionChoice.keepAccount),
        ),
        const SizedBox(height: Space.md),
        SecondaryButton(
          label: "Keep this phone's history",
          onPressed: () => Navigator.of(context).pop(AdoptionChoice.keepPhone),
        ),
        const SizedBox(height: Space.md),
        SecondaryButton(
          label: 'Merge both',
          onPressed: () => Navigator.of(context).pop(AdoptionChoice.merge),
        ),
        const SizedBox(height: Space.md),
        Text(
          // What merge costs, in the sentence next to the button rather than in
          // a surprise afterwards: nothing is lost and the result is not clean.
          'Merging keeps everything and tidies nothing: days both sides '
          'recorded appear twice, and exercises you made yourself can end up '
          'listed twice.',
          style: context.t.bodySmall?.copyWith(
            color: c.textTertiary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// One side of the choice: how much of it there is, and how recent it is.
class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.sessions,
    required this.latest,
  });

  final String label;
  final int sessions;
  final DateTime? latest;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final when = latest;

    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.t.labelMedium?.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Space.xs),
          Text(
            sessions == 1 ? '1 session' : '$sessions sessions',
            style: context.t.titleLarge,
          ),
          if (when != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              'Most recently ${DateFormat('d MMMM y').format(when)}',
              style: context.t.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
