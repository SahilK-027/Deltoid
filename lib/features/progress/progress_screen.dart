import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/cycle_progress.dart';
import '../../domain/muscle_volume.dart';
import '../account/backup_mark.dart';
import '../home/home_providers.dart';
import 'all_time_screen.dart';
import 'cycle_progress_providers.dart';
import 'regime_progress_screen.dart';
import 'volume_history_screen.dart';
import 'volume_providers.dart';
import 'widgets/strength_card.dart';
import 'widgets/volume_bars.dart';

/// Where the training is read rather than entered.
///
/// Cycle progress and Weekly volume, moved here from Home unchanged
/// (THEME → The destinations): the same headings, the same cards, the same
/// `All time` links and the same screens behind them. Cycle progress comes
/// first because it answers the question the page exists for.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every read is started here, in the same frame, rather than by the card
    // that draws it. A provider created by a card's first build makes that
    // section draw empty and pop its chart in a frame later.
    //
    // Home's snapshot is read for the card's `of 37 lifts` denominator. It is
    // already alive for Home, so this costs nothing.
    final today = ref.watch(homeProvider).valueOrNull;
    final volume = ref.watch(weeklyVolumeProvider).valueOrNull;
    final cycles = ref.watch(activeRegimeProgressProvider);

    return Scaffold(
      body: Column(
        children: [
          const HeaderBand(
            child: PageHeader(
              title: 'Progress',
              // The inventory of the page, as Regimes and History state theirs.
              eyebrow: 'Cycles and volume',
              topGap: Space.md,
              actions: [BackupMark()],
            ),
          ),
          Expanded(
            // Blank until every read has arrived, not a spinner: the answers
            // are on local disk, and the page arrives whole rather than in
            // layers. A score that *failed* is a different case — the page
            // renders and that section is absent, rather than the whole screen
            // being held hostage by one query.
            child: today == null || volume == null || cycles.isLoading
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.lg,
                      Space.gutter,
                      Space.huge,
                    ),
                    children: [
                      if (!cycles.hasError) ...[
                        _CycleProgressCard(
                          // No active regime scores as null, and the section
                          // still draws, in the shape it will have.
                          regime: cycles.valueOrNull ?? _noProgress,
                          plannedLifts: _plannedLifts(today.snapshot),
                        ),
                        const SizedBox(height: Space.section),
                      ],
                      // Not gated on history. Appearing only once something
                      // was logged would make the section arrive out of nowhere
                      // on the day of the first workout. The zero state carries
                      // it too, so the page is the same page before and after.
                      _VolumeCard(volume: volume),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// This week's sets per muscle (THEME → Components → Bar list).
///
/// A section on a tab rather than a screen you navigate to — a volume dashboard
/// came off the non-goals list on exactly that condition.
///
/// **Handed its numbers rather than watching for them.** A provider starts when
/// something first watches it, so reading [weeklyVolumeProvider] here would
/// start it only once the card is being built — after the score it should have
/// been racing, which is what makes a section arrive late. The screen starts
/// every read in the same frame and does not draw until it has them all, so
/// there is nothing here to be absent.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.volume});

  final WeeklyVolume volume;

  @override
  Widget build(BuildContext context) {
    void openHistory() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VolumeHistoryScreen()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `Weekly volume`, not `This week`: the window is a rolling seven days
        // ([volumeWindowDays]), and the habit tiles count a calendar week —
        // two different weeks in one app, both called this one.
        SectionHeader(
          'Weekly volume',
          // Nothing to open on a fresh install, and a link to an empty screen
          // is a control that does nothing.
          actionLabel: volume.isEmpty ? null : 'All time',
          onAction: openHistory,
        ),
        AppCard(
          // 16 at the sides, as every chart card is padded (THEME → Charts),
          // and 8 above and below, where each row carries 8 of its own, so
          // the ink stands 16 from every edge. At 12 all round the names stood
          // 4 in from the cards above and below them.
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm,
          ),
          onTap: volume.isEmpty ? null : openHistory,
          // Just the bars. A sentence under them would restate what every row
          // already prints — a total, a count of trained regions, and the
          // window named in the heading — and no other card in the app explains
          // its own chart in prose.
          child: VolumeBars(volume: volume),
        ),
      ],
    );
  }
}

/// The score a phone with no regime on it has.
///
/// The page carries the Cycle progress section in every state (THEME -> Empty
/// states): the card already draws itself with no cycles in it, so hiding it
/// made the first regime look as though it had built a card rather than filled
/// one.
const _noProgress = RegimeProgress(
  regimeId: '',
  regimeName: '',
  identityIndex: 0,
  isActive: false,
  progress: CycleProgress(cycles: [], latest: null, trend: null),
  labels: {},
);

/// What the programme is actually doing, and the way into the detail.
///
/// The question this answers — is the training working — is asked nowhere else
/// in the app.
class _CycleProgressCard extends StatelessWidget {
  const _CycleProgressCard({required this.regime, this.plannedLifts});

  final RegimeProgress regime;
  final int? plannedLifts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Cycle progress',
          // Nothing to open before anything is scored: an open cycle with no
          // sets in it still fills the list of cycles, so the link is gated on
          // there being a point to look at rather than on a row existing.
          actionLabel: regime.progress.latest == null ? null : 'All time',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AllTimeScreen()),
          ),
        ),
        StrengthCard(
          regime: regime,
          plannedLifts: plannedLifts,
          // Before a regime exists there is no name to caption the card with
          // and no regime screen to open: the section is the shape it will
          // have, with the figures printed as dashes.
          showName: regime.regimeId.isNotEmpty,
          onOpen: regime.regimeId.isEmpty
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RegimeProgressScreen(regimeId: regime.regimeId),
                  ),
                ),
        ),
      ],
    );
  }
}

/// How many lifts the active programme holds: every exercise in every session,
/// counted once per session it appears in.
///
/// Read off Home's snapshot, which already holds every session's exercise
/// names, rather than a query of its own.
///
/// Per session rather than per exercise, because that is what a lift is — Push
/// 1 bench and Push 2 bench are two progressions (CLAUDE.md rule 1), and a
/// denominator that counted them once would leave `15 of 12 lifts recorded` on
/// the card.
int? _plannedLifts(TodaySnapshot snapshot) {
  if (snapshot.exerciseNamesBySession.isEmpty) return null;
  var total = 0;
  for (final names in snapshot.exerciseNamesBySession.values) {
    total += names.length;
  }
  return total == 0 ? null : total;
}
