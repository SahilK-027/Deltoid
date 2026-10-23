import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../account/recovery_note.dart';
import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/calendar.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/ticking.dart';
import '../../data/db/database.dart';
import '../../domain/habits.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/session_name.dart';
import '../../domain/set_format.dart';
import '../history/workout_detail_screen.dart';
import '../log/log_screen.dart';
import '../log/widgets/exercise_sheets.dart';
import '../regime/regime_screen.dart';
import '../regime/regime_setup.dart';
import 'heatmap_data.dart';
import 'history_heatmap_screen.dart';
import 'home_providers.dart';
import 'weigh_ins_screen.dart';
import 'widgets/habit_tile.dart';
import 'widgets/phase_card.dart';
import '../../core/widgets/toast.dart';
import '../../core/failure.dart';
import '../account/backup_mark.dart';

part 'home_screen/session_start.dart';
part 'home_screen/sections.dart';

/// The screen reads top to bottom as one thought: where you stand, the one
/// thing to do about it, then the record.
///
/// The hero's track is the only rendering of cycle progress, and the sessions
/// live in a sheet. Drawing the cycle twice — labelled bars inside the hero
/// card and the same sessions again as a tappable list — pushes the consistency
/// grid off the bottom of the screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One value, one frame. `valueOrNull` keeps the last snapshot on screen
    // while a reload runs, so a write on another tab never blanks this one.
    final today = ref.watch(homeProvider).valueOrNull;
    // Warmed here, drawn two screens away. `Consistency` and the backfill
    // calendar both read every day ever logged, and starting that query when
    // they open means both open empty and fill in. Workouts is where you are
    // before you go to either, and this costs one aggregated query per change
    // to `workouts`.
    ref.watch(fullHeatmapProvider);
    // The Weigh-ins tile, waited for with the rest so the Habits row arrives
    // with the page rather than half of it a frame later.
    final weighIns = ref.watch(weighInDaysProvider).valueOrNull;
    // The Phase card, waited for on the same terms.
    final phase = ref.watch(phaseCardProvider).valueOrNull;
    final regime = today?.regime;
    final sessions = today?.sessions ?? const <Session>[];
    final status = today?.snapshot.status;
    final open = today?.openWorkout;

    return Scaffold(
      body: switch ((today, regime, sessions.isEmpty)) {
        // Nothing has loaded yet. Blank, not a spinner: the answers are on
        // local disk, and a spinner that shows for two frames is worse than
        // nothing. Any empty state here would be a guess — the frame before
        // the snapshot arrives looks exactly like a fresh install.
        (null, _, _) => const SizedBox.shrink(),
        _ when weighIns == null || phase == null => const SizedBox.shrink(),
        (_, null, _) => _NoRegimeState(
          last: today!.lastCompleted,
          heatmap: today.heatmap,
          weighIns: weighIns,
          phase: phase,
          hasHistory: today.hasHistory,
        ),
        (_, final r?, true) => _NoSessionsState(
          regime: r,
          last: today!.lastCompleted,
          heatmap: today.heatmap,
          weighIns: weighIns,
          phase: phase,
          hasHistory: today.hasHistory,
        ),
        // The masthead and the one action are a single band, and the record
        // scrolls under it. See [_HomeHeader] for why the hero is not a card:
        // `AppCard` and `HeaderBand` are the same grey, so a card here grouped
        // nothing — it drew a rounded seam between two identical surfaces,
        // 16pt below a band it matched exactly. The band is also the answer to
        // why this block, alone on the screen, had no section header over it:
        // it is not a section, it is the header.
        // The band is pinned and the record scrolls under it. As the first
        // item in the list it would slide off the top the moment you looked at
        // the heatmap, taking the one thing you came for with it — the session,
        // and the button that starts it.
        (_, final r?, false) => Column(
          children: [
            _HomeHeader(last: today!.lastCompleted),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: Space.huge),
                children: [
                  // The session is the page's first *section*, not part of the
                  // masthead. The band ends at the line about when you last
                  // trained; everything you can act on is content under it,
                  // with its own heading like every other block here.
                  // The band's own `surface`, full width — connected to the
                  // header by colour, separated from it by the gap. On the page
                  // background the screen's one primary action sat on the
                  // flattest surface the app has.
                  if (open != null)
                    _SurfaceBlock(
                      child: _ResumeHero(
                        workout: open,
                        owner: today.snapshot.openWorkoutOwner,
                        doneSets: today.snapshot.openWorkoutDoneSets,
                        totalSets: today.snapshot.openWorkoutTotalSets,
                        preview: today.snapshot.openWorkoutExerciseNames,
                        activeRegimeId: r.id,
                        activeRegimeName: r.name,
                        sessions: sessions,
                      ),
                    )
                  else if (status != null)
                    _SurfaceBlock(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader("Today's session"),
                          _NextUpHero(
                            regimeId: r.id,
                            regimeName: r.name,
                            status: status,
                            sessions: sessions,
                            preview: today
                                .snapshot
                                .exerciseNamesBySession[status.nextSessionId],
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.section,
                      Space.gutter,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HabitsSection(
                          heatmap: today.heatmap,
                          weighIns: weighIns,
                          play: _PlayAction(
                            regimeId: r.id,
                            open: open,
                            status: status,
                            sessions: sessions,
                            preview: today.snapshot.exerciseNamesBySession,
                          ),
                        ),
                        const SizedBox(height: Space.section),
                        PhaseSection(data: phase),
                        const SizedBox(height: Space.section),
                        _PastSessionsCard(
                          onTap: () => _logPastSession(
                            context,
                            ref,
                            regimeId: r.id,
                            sessions: sessions,
                            hasOpenWorkout: open != null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      },
    );
  }
}
