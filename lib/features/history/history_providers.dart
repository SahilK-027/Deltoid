import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repositories/training_repository.dart';

/// Rows fetched per page. Enough to fill a phone screen twice over, small
/// enough that the first page lands instantly with years of history in the
/// database.
const historyPageSize = 20;

/// A window onto a list that is longer than what has been loaded.
class PagedHistory<T> {
  const PagedHistory({
    required this.items,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<T> items;

  /// False once a short page came back — the end of history.
  final bool hasMore;

  final bool loadingMore;

  bool get isEmpty => items.isEmpty;

  PagedHistory<T> copyWith({
    List<T>? items,
    bool? hasMore,
    bool? loadingMore,
  }) {
    return PagedHistory(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

/// Reloads the loaded window shortly after history changes *shape*.
///
/// Debounced because a write comes in bursts, and each one would otherwise
/// re-query every page the user has scrolled through — `limit: _loaded + 1`, so
/// the cost grows with how far down they are.
///
/// Deliberately [TrainingRepository.historyShapeChanges] rather than
/// [TrainingRepository.historyChanges]: `set_logs` is the hot table during a
/// session — one write per keystroke — and **not one of those writes can change
/// this list.** These views show completed workouts only, the log screen is the
/// only place a set is ever written, and the two moments a finished day's sets
/// do change (`completeWorkout` tombstoning the untouched rows, `deleteWorkout`
/// taking the tree) both write `workouts` in the same transaction. So the
/// narrow stream sees every change that matters and none of the ones that
/// don't. Watching `set_logs` meant every pause in logging re-read the whole
/// scrolled window to rebuild a list the session is not even in yet.
void _reloadOnHistoryWrites(Ref ref, TrainingRepository repo) {
  Timer? debounce;
  final sub = repo.historyShapeChanges().listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), ref.invalidateSelf);
  });
  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
  });
}

/// Which slice of history the feed is showing.
///
/// One day, or the light weeks, or both. Deliberately not a date range: the
/// feed is already ordered by date and scrolling *is* the range control —
/// a pair of date fields would ask you to type what the list already answers.
class HistoryFilter {
  const HistoryFilter({this.sessionId, this.deloadOnly = false});

  /// A training day, from [TrainingRepository.loggedSessions].
  final String? sessionId;

  final bool deloadOnly;

  bool get isEmpty => sessionId == null && !deloadOnly;

  HistoryFilter copyWith({
    String? sessionId,
    bool clearSession = false,
    bool? deloadOnly,
  }) {
    return HistoryFilter(
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      deloadOnly: deloadOnly ?? this.deloadOnly,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.sessionId == sessionId &&
      other.deloadOnly == deloadOnly;

  @override
  int get hashCode => Object.hash(sessionId, deloadOnly);
}

final historyFilterProvider =
    StateProvider<HistoryFilter>((ref) => const HistoryFilter());

/// The training days that appear in history, for the filter's picker.
final loggedSessionsProvider = StreamProvider<List<LoggedSession>>((ref) {
  return ref.watch(trainingRepositoryProvider).watchLoggedSessions();
});

/// Every completed workout, newest first, one page at a time.
final workoutFeedProvider =
    AsyncNotifierProvider<WorkoutFeedNotifier, PagedHistory<WorkoutSummary>>(
  WorkoutFeedNotifier.new,
);

class WorkoutFeedNotifier extends AsyncNotifier<PagedHistory<WorkoutSummary>> {
  /// Survives `invalidateSelf`, so a write does not scroll the user back to the
  /// top of history.
  int _loaded = historyPageSize;

  /// What [_loaded] was counted against. Changing the filter changes what the
  /// list *is*, so the window starts again — carrying 120 loaded rows over to a
  /// filter with 8 matches would fetch every one of them in a single query and
  /// call it the first page.
  HistoryFilter? _filter;

  @override
  Future<PagedHistory<WorkoutSummary>> build() async {
    final repo = ref.watch(trainingRepositoryProvider);
    final filter = ref.watch(historyFilterProvider);
    if (_filter != null && filter != _filter) _loaded = historyPageSize;
    _filter = filter;
    _reloadOnHistoryWrites(ref, repo);

    // One past the window, and the extra row is dropped. `length >= limit` is
    // not "there is more" — it is also exactly what the last page of history
    // looks like, so the feed offered a `load more` that fetched nothing and
    // then removed itself. Asking for one row it does not intend to show is
    // the difference between guessing and knowing.
    final page = await repo.workoutFeed(
      limit: _loaded + 1,
      sessionId: filter.sessionId,
      deloadOnly: filter.deloadOnly,
    );
    return PagedHistory(
      items: page.take(_loaded).toList(),
      hasMore: page.length > _loaded,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.items.isEmpty) {
      return;
    }

    final filter = ref.read(historyFilterProvider);
    state = AsyncData(current.copyWith(loadingMore: true));
    final fetched = await ref.read(trainingRepositoryProvider).workoutFeed(
          limit: historyPageSize + 1,
          olderThan: current.items.last.cursor,
          sessionId: filter.sessionId,
          deloadOnly: filter.deloadOnly,
        );
    final next = fetched.take(historyPageSize).toList();

    _loaded = current.items.length + next.length;
    state = AsyncData(PagedHistory(
      items: [...current.items, ...next],
      hasMore: fetched.length > historyPageSize,
    ));
  }
}

/// One exercise's performances, newest first, one page at a time.
final exerciseHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<ExerciseHistoryNotifier, PagedHistory<ExercisePerformance>, String>(
  ExerciseHistoryNotifier.new,
);

class ExerciseHistoryNotifier extends AutoDisposeFamilyAsyncNotifier<
    PagedHistory<ExercisePerformance>, String> {
  int _loaded = historyPageSize;

  @override
  Future<PagedHistory<ExercisePerformance>> build(String exerciseId) async {
    final repo = ref.watch(trainingRepositoryProvider);
    _reloadOnHistoryWrites(ref, repo);

    // The probe row, as in [WorkoutFeedNotifier.build].
    final page = await repo.exerciseHistoryPage(exerciseId, limit: _loaded + 1);
    return PagedHistory(
      items: page.take(_loaded).toList(),
      hasMore: page.length > _loaded,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.items.isEmpty) {
      return;
    }

    state = AsyncData(current.copyWith(loadingMore: true));
    final fetched =
        await ref.read(trainingRepositoryProvider).exerciseHistoryPage(
              arg,
              limit: historyPageSize + 1,
              olderThan: current.items.last.cursor,
            );
    final next = fetched.take(historyPageSize).toList();

    _loaded = current.items.length + next.length;
    state = AsyncData(PagedHistory(
      items: [...current.items, ...next],
      hasMore: fetched.length > historyPageSize,
    ));
  }
}

/// The totals behind History's masthead.
final historyOverviewProvider = StreamProvider<HistoryOverview>((ref) {
  return ref.watch(trainingRepositoryProvider).watchHistoryOverview();
});

/// Exercises that have actually been trained, most recent first.
final exercisesWithHistoryProvider =
    StreamProvider<List<ExerciseHistorySummary>>((ref) {
  return ref.watch(trainingRepositoryProvider).watchExercisesWithHistory();
});

final workoutDetailProvider =
    StreamProvider.autoDispose.family<WorkoutDetail?, String>((ref, workoutId) {
  return ref.watch(trainingRepositoryProvider).watchWorkoutDetail(workoutId);
});

