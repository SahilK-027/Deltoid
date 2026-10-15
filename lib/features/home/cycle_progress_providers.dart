import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/cycle_progress.dart';
import '../history/history_providers.dart';

/// The active regime's cycle progress, for the Workouts card.
///
/// **Kept alive, and warmed beside the screen's other reads.** The card sits
/// above the fold on the screen the app opens on, so a provider created by the
/// first build of that card draws an empty card and then pops a chart into it a
/// frame later. The read is on local disk; it should be sitting there when the
/// screen is built.
final activeRegimeProgressProvider = StreamProvider<RegimeProgress?>((ref) {
  // Gated on the seeder for the reason `homeProvider` is: a first launch
  // would otherwise score an empty database and immediately re-score it when
  // the starter rows land.
  final init = ref.watch(appInitProvider);
  if (!init.hasValue) return const Stream.empty();

  return ref.watch(trainingRepositoryProvider).watchActiveRegimeProgress();
});

/// One regime's cycle progress, for the regime screen and the All time cards.
///
/// `autoDispose`, unlike [activeRegimeProgressProvider]: this is a pushed
/// screen, and holding a whole-regime score per regime ever opened for the rest
/// of the app's life is the pattern `exerciseProgressProvider` documents as the
/// wrong one.
final regimeProgressProvider =
    StreamProvider.autoDispose.family<RegimeProgress?, String>((ref, regimeId) {
  return ref.watch(trainingRepositoryProvider).watchRegimeProgress(regimeId);
});

/// Which regime was trained in each ISO week of one year, for the All time
/// timeline.
///
/// The window is the year's own weeks rather than its calendar days, because
/// week 1 can begin in December: 2026 opens on Monday 29 December 2025, and a
/// query bounded by 1 January would drop the first three days of the strip.
final timelineYearProvider =
    StreamProvider.autoDispose.family<List<TimelineWeek>, int>((ref, year) {
  final repo = ref.watch(trainingRepositoryProvider);
  final from = isoWeekStart(year, 1);
  final to = isoWeekStart(year, isoWeeksInYear(year)).add(const Duration(days: 6));

  return repo
      .watchTrainedDaysBetween(
        fromDayKey: dayKeyOf(from),
        toDayKey: dayKeyOf(to),
      )
      .map((days) => computeTimelineWeeks(year: year, days: days));
});

/// The regimes the All time screen draws a card for, newest first.
final liveRegimesProvider =
    StreamProvider.autoDispose<List<RegimeMark>>((ref) {
  return ref.watch(trainingRepositoryProvider).watchLiveRegimes();
});

/// The ISO years the timeline's stepper can move between.
final trainedYearsProvider = StreamProvider.autoDispose<List<int>>((ref) {
  final overview = ref.watch(historyOverviewProvider).valueOrNull;
  return Stream.value(
    trainedYears(
      firstDayKey: overview?.firstDayKey,
      lastDayKey: overview?.lastDayKey,
    ),
  );
});

/// Every lift a regime's programme holds, for the first-cycle screen and for
/// the card's `8 of 15` denominator.
final regimeLiftsProvider = StreamProvider.autoDispose
    .family<List<({LiftId lift, LiftLabel label})>, String>((ref, regimeId) {
  return ref.watch(trainingRepositoryProvider).watchRegimeLifts(regimeId);
});
