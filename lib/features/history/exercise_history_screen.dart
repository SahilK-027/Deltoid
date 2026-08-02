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
import 'exercise_trend.dart';
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

    final metric = ref.watch(exerciseMetricProvider);

    // A pushed screen, so a small centred title and a back arrow — the
    // masthead's 30sp belongs to the four destinations, and spending it here
    // made an exercise look like a tab of its own.
    return Scaffold(
      appBar: AppBar(title: Text(exercise?.name ?? 'Exercise')),
      body: Column(
        children: [
          // The metric strip pins under the bar while the chart scrolls away
          // beneath it (THEME §5): the thing you change stays reachable, the
          // thing you read does not hold half the screen for ever.
          Container(
            width: double.infinity,
            color: context.c.surface,
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, 0, Space.gutter, Space.md),
            child: SegmentedPill<ExerciseMetric>(
              expand: true,
              value: metric,
              onChanged: (m) =>
                  ref.read(exerciseMetricProvider.notifier).state = m,
              segments: [
                for (final m in ExerciseMetric.values)
                  (value: m, label: m.label),
              ],
            ),
          ),
          Expanded(child: _body(history, exercise)),
        ],
      ),
    );
  }

  Widget _body(
    AsyncValue<PagedHistory<ExercisePerformance>> history,
    Exercise? exercise,
  ) {
    return history.when(
        // The chart and the list stay put while a write reloads the page.
        skipLoadingOnReload: true,
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

          // The trend rides at the head of the list rather than pinning: it is
          // a summary, not a control, and pinned it costs half a phone screen
          // while you are reading the performances under it.
          //
          // Rows are grouped by month, the same grouping the session feed uses,
          // so a year of one movement reads as a year rather than as a run of
          // dates.
          final rows = _rowsFor(page.items);

          return ListView.separated(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, Space.lg, Space.gutter, Space.huge),
            itemCount: rows.length + 2,
            separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
            itemBuilder: (context, i) {
              if (i == 0) {
                return ExerciseTrend(exerciseId: widget.exerciseId);
              }
              i -= 1;
              if (i == rows.length) {
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
              final row = rows[i];
              if (row.heading != null) {
                // 20 here plus the separator's 8 above it is the 28 between
                // sections everywhere else — this list is the one place the
                // gap is built out of two pieces.
                return Padding(
                  padding: const EdgeInsets.only(top: Space.xl),
                  child: SectionHeader(row.heading!),
                );
              }
              return _PerformanceCard(
                // Keyed by the workout it came from. Without it the expansion
                // state belongs to a *position*, and a month heading appearing
                // above a row — or a day being backdated — hands one row's open
                // set list to another.
                key: ValueKey(row.performance!.workoutId),
                performance: row.performance!,
                exercise: exercise,
              );
            },
          );
        },
      );
  }

  /// Flattens performances into month headings + rows, newest first.
  static List<({String? heading, ExercisePerformance? performance})> _rowsFor(
    List<ExercisePerformance> items,
  ) {
    final out = <({String? heading, ExercisePerformance? performance})>[];
    String? current;
    for (final p in items) {
      final month = DateFormat('MMMM yyyy').format(dateFromDayKey(p.dayKey));
      if (month != current) {
        current = month;
        out.add((heading: month, performance: null));
      }
      out.add((heading: null, performance: p));
    }
    return out;
  }
}

/// One past performance, expanding in place.
///
/// It deliberately does not open the day it came from. This screen is reached
/// *from* a day, and pushing back into one made history a loop you could walk
/// forever without ever arriving anywhere new. Everything the row could send
/// you looking for — every set, its type and its note — opens here instead.
class _PerformanceCard extends ConsumerStatefulWidget {
  const _PerformanceCard({
    super.key,
    required this.performance,
    required this.exercise,
  });

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
    final metric = ref.watch(exerciseMetricProvider);
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
          // The number leads and the day captions it. This is a *metric*
          // screen — you came to see how the movement moved — where the session
          // feed puts the date first because there the day is the subject.
          // Same row, inverted, and the inversion is the information.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _headline(performance, metric, unit),
                      style: context.t.titleMedium,
                    ),
                    const SizedBox(height: Space.xxs),
                    Text(
                      '${DateFormat('EEE, d MMM yyyy').format(date)} · '
                      '${performance.sessionName}',
                      style: context.t.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (performance.isDeload) ...[
                const SizedBox(width: Space.sm),
                Pill('Deload', color: c.deload),
              ],
              if (skipped) ...[
                const SizedBox(width: Space.sm),
                Pill(performance.skipReason.label, color: c.negative),
              ],
              if (canExpand) ...[
                const SizedBox(width: Space.sm),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: Motion.fast,
                  curve: Motion.curve,
                  child: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: c.textTertiary,
                  ),
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
            // Every set as it was logged. The metric's own figure is the
            // headline above, so repeating it here in prose would be the same
            // number twice on one row (rule 6).
            Text(
              done.map((s) => _setLabel(s, exercise, unit)).join('   '),
              style: context.t.bodyMedium,
            ),
            // The fold has a height, so it animates to it. It used to appear
            // between two frames, which reads as the card being replaced
            // rather than as it opening.
            AnimatedSize(
              duration: Motion.base,
              curve: Motion.emphasized,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                    ),
            ),
          ],
        ],
      ),
    );
  }

  /// What this performance came to, in the metric being viewed. A day with
  /// nothing scoreable in it says so rather than printing a zero (rule 4).
  static String _headline(
    ExercisePerformance p,
    ExerciseMetric metric,
    WeightUnit unit,
  ) {
    final value = switch (metric) {
      ExerciseMetric.e1rm => p.best1RM,
      ExerciseMetric.heaviest => p.topSetLoad,
    };
    if (value == null) return '—';
    final reps = metric == ExerciseMetric.heaviest && p.topSetReps != null
        ? ' × ${p.topSetReps}'
        : '';
    return '${formatWeight(value, unit)} ${unit.label}$reps';
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
