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

/// Reloads the loaded window shortly after any write to logged history.
///
/// Debounced because a live logging session writes on every tap, and each write
/// would otherwise re-query every page the user has scrolled through.
void _reloadOnHistoryWrites(Ref ref, TrainingRepository repo) {
  Timer? debounce;
  final sub = repo.historyChanges().listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), ref.invalidateSelf);
  });
  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
  });
}

/// Every completed workout, newest first, one page at a time.
final workoutFeedProvider =
    AsyncNotifierProvider<WorkoutFeedNotifier, PagedHistory<WorkoutSummary>>(
  WorkoutFeedNotifier.new,
);

class WorkoutFeedNotifier extends AsyncNotifier<PagedHistory<WorkoutSummary>> {
  /// Survives `invalidateSelf`, so a write does not scroll the user back to the
  /// top of history.
  int _loaded = historyPageSize;

  @override
  Future<PagedHistory<WorkoutSummary>> build() async {
    final repo = ref.watch(trainingRepositoryProvider);
    _reloadOnHistoryWrites(ref, repo);

    final items = await repo.workoutFeed(limit: _loaded);
    return PagedHistory(items: items, hasMore: items.length >= _loaded);
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
    final next = await ref.read(trainingRepositoryProvider).workoutFeed(
          limit: historyPageSize,
          olderThan: current.items.last.cursor,
        );

    _loaded = current.items.length + next.length;
    state = AsyncData(PagedHistory(
      items: [...current.items, ...next],
      hasMore: next.length >= historyPageSize,
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

    final items = await repo.exerciseHistoryPage(exerciseId, limit: _loaded);
    return PagedHistory(items: items, hasMore: items.length >= _loaded);
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
    final next =
        await ref.read(trainingRepositoryProvider).exerciseHistoryPage(
              arg,
              limit: historyPageSize,
              olderThan: current.items.last.cursor,
            );

    _loaded = current.items.length + next.length;
    state = AsyncData(PagedHistory(
      items: [...current.items, ...next],
      hasMore: next.length >= historyPageSize,
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

