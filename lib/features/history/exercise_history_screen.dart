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
import '../../domain/units.dart';
import 'history_providers.dart';
import 'history_screen.dart' show formatWeight;

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

/// One past performance, expanding in place.
///
/// It deliberately does not open the day it came from. This screen is reached
/// *from* a day, and pushing back into one made history a loop you could walk
/// forever without ever arriving anywhere new. Everything the row could send
/// you looking for — every set, its type and its note — opens here instead.
class _PerformanceCard extends ConsumerStatefulWidget {
  const _PerformanceCard({required this.performance, required this.exercise});

  final ExercisePerformance performance;
  final Exercise? exercise;

  @override
  ConsumerState<_PerformanceCard> createState() => _PerformanceCardState();
}

class _PerformanceCardState extends ConsumerState<_PerformanceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final performance = widget.performance;
    final exercise = widget.exercise;
    final c = context.c;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final date = dateFromDayKey(performance.dayKey);
    final done = performance.sets.where((s) => s.isDone).toList();
    final skipped = performance.skipReason != SkipReason.none;
    // A skipped slot with sets in it is still a performance worth opening —
    // those sets happened, and they are what prefill and the chart read.
    final canExpand = done.isNotEmpty;

    return AppCard(
      padding:
          const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
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
              if (canExpand) ...[
                const SizedBox(width: Space.sm),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: c.textTertiary,
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.sm),
          if (skipped && done.isNotEmpty)
            Text(
              'Stopped after ${done.length} '
              '${done.length == 1 ? 'set' : 'sets'}',
              style: context.t.labelSmall?.copyWith(color: c.negative),
            ),
          if (done.isEmpty)
            Text(
              skipped ? 'Not trained' : 'Nothing logged',
              style: context.t.labelSmall,
            )
          else ...[
            Text(
              done.map((s) => _setLabel(s, exercise, unit)).join('   '),
              style: context.t.labelLarge,
            ),
            if (performance.best1RM != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                'Best e1RM ${formatWeight(performance.best1RM!, unit)} '
                '${unit.label}'
                '${performance.topSetLoad == null ? '' : '  ·  top set '
                    '${formatWeight(performance.topSetLoad!, unit)} '
                    '${unit.label}'
                    '${performance.topSetReps == null ? '' : ' × ${performance.topSetReps}'}'}',
                style: context.t.labelSmall,
              ),
            ],
            if (_expanded && done.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Divider(color: c.border, height: 1),
              const SizedBox(height: Space.sm),
              for (var i = 0; i < done.length; i++)
                _ExpandedSetLine(
                  set: done[i],
                  position: i,
                  exercise: exercise,
                ),
            ],
          ],
        ],
      ),
    );
  }

  /// `22.5×8`, with the set type appended when it is not a plain working set.
  static String _setLabel(SetLog set, Exercise? exercise, WeightUnit unit) {
    final reps = set.reps ?? 0;
    final tag = set.setType.shortLabel;
    final suffix = tag.isEmpty ? '' : ' $tag';

    if (exercise?.loadMode == LoadMode.bodyweight) return '$reps$suffix';
    if (exercise?.loadMode == LoadMode.bodyweightPlus) {
      final added = set.addedWeight;
      return added == null || added == 0
          ? '$reps$suffix'
          : '+${formatWeight(added, unit)}×$reps$suffix';
    }
    final weight = set.weight;
    if (weight == null) return '$reps$suffix';
    return '${formatWeight(weight, unit)}×$reps$suffix';
  }

  /// Spelled out rather than compressed, for the expanded rows: `22.5 kg × 2`
  /// on a dumbbell is the number you'd read off the rack.
  static String _loadLabel(SetLog set, Exercise? exercise, WeightUnit unit) {
    final added = set.addedWeight;
    if (exercise?.loadMode == LoadMode.bodyweight) return 'Bodyweight';
    if (exercise?.loadMode == LoadMode.bodyweightPlus) {
      return added == null || added == 0
          ? 'Bodyweight'
          : 'BW + ${formatWeight(added, unit)} ${unit.label}';
    }
    final weight = set.weight;
    if (weight == null) return '—';
    final perSide = exercise?.loadMode == LoadMode.perSide ? ' × 2' : '';
    return '${formatWeight(weight, unit)} ${unit.label}$perSide';
  }
}

/// One set inside an expanded card: what it was, what it weighed, and anything
/// written about it at the time.
class _ExpandedSetLine extends ConsumerWidget {
  const _ExpandedSetLine({
    required this.set,
    required this.position,
    required this.exercise,
  });

  final SetLog set;
  final int position;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final type = set.setType.shortLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              type.isEmpty ? '${position + 1}' : type,
              style: context.t.labelSmall?.copyWith(color: c.textTertiary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _PerformanceCardState._loadLabel(set, exercise, unit),
                  style: context.t.labelLarge,
                ),
                if (set.note != null && set.note!.isNotEmpty)
                  Text(set.note!, style: context.t.labelSmall),
              ],
            ),
          ),
          Text(
            '${set.reps ?? 0} reps',
            style: context.t.labelMedium?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
