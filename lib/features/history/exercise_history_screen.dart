import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import 'history_providers.dart';
import 'history_screen.dart' show formatWeight;
import 'workout_detail_screen.dart';

final _exerciseProvider =
    StreamProvider.autoDispose.family<Exercise?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.exercises)..where((t) => t.id.equals(id));
  return query.watchSingleOrNull();
});

/// One movement, every time it has been trained, newest first and paged.
///
/// Grouped by nothing and sorted by date on purpose: the session each
/// performance belongs to is on the row, because the same exercise runs a
/// separate progression in each one.
class ExerciseHistoryScreen extends ConsumerStatefulWidget {
  const ExerciseHistoryScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  ConsumerState<ExerciseHistoryScreen> createState() =>
      _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends ConsumerState<ExerciseHistoryScreen> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter > 600) return;
    ref.read(exerciseHistoryProvider(widget.exerciseId).notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = ref.watch(_exerciseProvider(widget.exerciseId)).valueOrNull;
    final history = ref.watch(exerciseHistoryProvider(widget.exerciseId));

    return Scaffold(
      appBar: AppBar(title: Text(exercise?.name ?? 'Exercise')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xxxl),
            child: Text('Could not load history.\n\n$e',
                textAlign: TextAlign.center, style: context.t.bodyMedium),
          ),
        ),
        data: (page) {
          if (page.isEmpty) {
            return const EmptyState(
              icon: Icons.history_toggle_off,
              title: 'Never logged',
              message: 'Do this one in a session and every set lands here.',
            );
          }

          return ListView.separated(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.md, Space.lg, Space.huge),
            itemCount: page.items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
            itemBuilder: (context, i) {
              if (i == page.items.length) {
                return page.hasMore
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: Space.xl),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.xl),
                        child: Center(
                          child: Text(
                            '${page.items.length} performance'
                            '${page.items.length == 1 ? '' : 's'} '
                            '· that is everything',
                            style: context.t.labelSmall,
                          ),
                        ),
                      );
              }
              return _PerformanceCard(
                performance: page.items[i],
                exercise: exercise,
              );
            },
          );
        },
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.performance, required this.exercise});

  final ExercisePerformance performance;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final date = dateFromDayKey(performance.dayKey);
    final done = performance.sets.where((s) => s.isDone).toList();
    final skipped = performance.skipReason != SkipReason.none;

    return AppCard(
      padding:
          const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              WorkoutDetailScreen(workoutId: performance.workoutId),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat('d MMM yyyy').format(date),
                style: context.t.titleSmall,
              ),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text(
                  performance.sessionName,
                  style: context.t.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              if (performance.isDeload) Pill('Deload', color: c.deload),
              if (skipped) Pill(performance.skipReason.label, color: c.negative),
            ],
          ),
          if (!skipped) ...[
            const SizedBox(height: Space.sm),
            if (done.isEmpty)
              Text('Nothing logged', style: context.t.labelSmall)
            else
              Text(
                done.map((s) => _setLabel(s, exercise)).join('   '),
                style: context.t.labelLarge,
              ),
            if (performance.best1RM != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                'Best e1RM ${formatWeight(performance.best1RM!)} kg'
                '${performance.topSetLoad == null ? '' : '  ·  top set '
                    '${formatWeight(performance.topSetLoad!)} kg'
                    '${performance.topSetReps == null ? '' : ' × ${performance.topSetReps}'}'}',
                style: context.t.labelSmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// `22.5×8`, with the set type appended when it is not a plain working set.
  static String _setLabel(SetLog set, Exercise? exercise) {
    final reps = set.reps ?? 0;
    final tag = set.setType.shortLabel;
    final suffix = tag.isEmpty ? '' : ' $tag';

    if (exercise?.loadMode == LoadMode.bodyweight) return '$reps$suffix';
    if (exercise?.loadMode == LoadMode.bodyweightPlus) {
      final added = set.addedWeight;
      return added == null || added == 0
          ? '$reps$suffix'
          : '+${formatWeight(added)}×$reps$suffix';
    }
    final weight = set.weight;
    if (weight == null) return '$reps$suffix';
    return '${formatWeight(weight)}×$reps$suffix';
  }
}
