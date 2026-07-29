import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/metrics.dart';
import '../history/history_providers.dart';
import '../log/widgets/exercise_sheets.dart';

enum ChartRange { threeMonths, year, all }

extension on ChartRange {
  String get label => switch (this) {
    ChartRange.threeMonths => '3M',
    ChartRange.year => '1Y',
    ChartRange.all => 'All',
  };

  int? get days => switch (this) {
    ChartRange.threeMonths => 90,
    ChartRange.year => 365,
    ChartRange.all => null,
  };
}

final selectedExerciseProvider = StateProvider<String?>((ref) => null);
final chartRangeProvider = StateProvider<ChartRange>((ref) => ChartRange.year);

final exerciseProgressProvider =
    StreamProvider.family<List<ProgressPoint>, String>((ref, exerciseId) {
      return ref
          .watch(trainingRepositoryProvider)
          .watchExerciseProgress(exerciseId);
    });

/// Answers one question: am I actually getting stronger, and how fast?
///
/// Deliberately not a dashboard. One exercise, one chart, split by the session
/// it was trained in — because 22.5kg in Push 1 and 20kg in Push 2 are two
/// separate progressions, not noise in one.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(exerciseCatalogProvider).valueOrNull ?? const [];
    // Opening on the alphabetically first exercise showed "no data" to most
    // people most of the time. Default to the movement trained most recently —
    // the one whose trend you actually came to look at.
    final trained = ref.watch(exercisesWithHistoryProvider).valueOrNull;
    final fallback = trained != null && trained.isNotEmpty
        ? trained.first.exercise.id
        : (catalog.isEmpty ? null : catalog.first.id);
    final selectedId = ref.watch(selectedExerciseProvider) ?? fallback;
    final selected = catalog.where((e) => e.id == selectedId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: catalog.isEmpty
          ? const EmptyState(
              icon: Icons.show_chart,
              title: 'No exercises yet',
              message: 'Add exercises to your regime to track them here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.huge,
              ),
              children: [
                _ExerciseSelector(selected: selected),
                const SizedBox(height: Space.lg),
                if (selectedId != null) _ProgressBody(exerciseId: selectedId),
              ],
            ),
    );
  }
}

class _ExerciseSelector extends ConsumerWidget {
  const _ExerciseSelector({required this.selected});

  final Exercise? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return AppCard(
      onTap: () async {
        final picked = await pickExercise(context, ref);
        if (picked == null) return;
        ref.read(selectedExerciseProvider.notifier).state = picked.id;
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EXERCISE', style: context.t.labelSmall),
                const SizedBox(height: Space.xs),
                Text(
                  selected?.name ?? 'Pick one',
                  style: context.t.titleMedium,
                ),
              ],
            ),
          ),
          Icon(Icons.unfold_more, size: 20, color: c.textTertiary),
        ],
      ),
    );
  }
}

class _ProgressBody extends ConsumerWidget {
  const _ProgressBody({required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(exerciseProgressProvider(exerciseId)).valueOrNull;
    final range = ref.watch(chartRangeProvider);

    if (all == null) {
      return const Padding(
        padding: EdgeInsets.all(Space.huge),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.timeline,
        title: 'No data for this exercise',
        message: 'Log it once and the trend starts here.',
      );
    }

    final cutoff = range.days == null
        ? null
        : dayKeyOf(DateTime.now().subtract(Duration(days: range.days!)));
    final points = cutoff == null
        ? all
        : all.where((p) => p.dayKey >= cutoff).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final r in ChartRange.values) ...[
              _RangeChip(range: r, selected: r == range),
              const SizedBox(width: Space.sm),
            ],
          ],
        ),
        const SizedBox(height: Space.lg),
        _Chart(points: points),
        const SizedBox(height: Space.xxl),
        _Summary(all: all, windowed: points),
        const SizedBox(height: Space.xxl),
        const SectionLabel('Every session'),
        _PerformanceList(points: points.reversed.toList()),
      ],
    );
  }
}

class _RangeChip extends ConsumerWidget {
  const _RangeChip({required this.range, required this.selected});

  final ChartRange range;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return GestureDetector(
      onTap: () => ref.read(chartRangeProvider.notifier).state = range,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: selected ? c.accent : c.border),
        ),
        child: Text(
          range.label,
          style: context.t.labelMedium?.copyWith(
            color: selected ? c.onAccent : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Estimated 1RM over time, one line per session slot.
class _Chart extends StatelessWidget {
  const _Chart({required this.points});

  final List<ProgressPoint> points;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (points.length < 2) {
      // Sized to the message rather than reserving chart height for a chart
      // that isn't there — an empty 200px box reads as a rendering failure.
      return AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.xl,
        ),
        child: Row(
          children: [
            Icon(Icons.timeline, size: 18, color: c.textTertiary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                points.isEmpty
                    ? 'Nothing logged in this range.'
                    : 'One session so far — a second one gives this a trend.',
                style: context.t.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    // Deload weeks are excluded: a deliberately light week is not a regression,
    // and plotting it as one makes the chart lie.
    final real = points.where((p) => !p.isDeload).toList();
    final source = real.length >= 2 ? real : points;

    final bySession = <String, List<ProgressPoint>>{};
    for (final p in source) {
      bySession.putIfAbsent(p.sessionName, () => []).add(p);
    }

    final palette = [c.accent, c.deload, c.positive, c.negative];
    final names = bySession.keys.toList();

    final xs = source.map((p) => _x(p.dayKey)).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final ys = source.map((p) => p.best1RM ?? 0).toList();
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.15).clamp(2.0, 30.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(
            Space.sm,
            Space.xl,
            Space.lg,
            Space.md,
          ),
          child: SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: (minY - pad).clamp(0, double.infinity),
                maxY: maxY + pad,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: c.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: context.t.labelSmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: ((maxX - minX) / 3).clamp(1, double.infinity),
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: Text(
                          DateFormat(_axisFormat(maxX - minX)).format(
                            DateTime.fromMillisecondsSinceEpoch(
                              value.round() * 86400000,
                            ),
                          ),
                          style: context.t.labelSmall,
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => c.surfaceHigh,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${s.y.toStringAsFixed(1)} kg e1RM',
                          context.t.labelMedium!.copyWith(color: c.textPrimary),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  for (var i = 0; i < names.length; i++)
                    LineChartBarData(
                      spots: [
                        for (final p in bySession[names[i]]!)
                          FlSpot(_x(p.dayKey), p.best1RM ?? 0),
                      ],
                      isCurved: false,
                      color: palette[i % palette.length],
                      barWidth: 2,
                      dotData: FlDotData(
                        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                          radius: 3,
                          color: palette[i % palette.length],
                          strokeWidth: 0,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (names.length > 1) ...[
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.sm,
            children: [
              for (var i = 0; i < names.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette[i % palette.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(names[i], style: context.t.labelSmall),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Day key → days since epoch, so the x-axis is real time rather than an
  /// index. Otherwise a six-week gap looks identical to a week.
  static double _x(int dayKey) =>
      dateFromDayKey(dayKey).millisecondsSinceEpoch / 86400000;

  /// Label resolution has to follow the span, or four ticks a day apart all
  /// render as the same month and overlap into mush.
  static String _axisFormat(double spanDays) {
    if (spanDays <= 45) return 'd MMM';
    if (spanDays <= 400) return 'MMM';
    return "MMM ''yy";
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.all, required this.windowed});

  final List<ProgressPoint> all;
  final List<ProgressPoint> windowed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final real = windowed.where((p) => !p.isDeload).toList();
    final stalled = stalledSessions(real.map((p) => p.best1RM).toList());

    final best = all
        .where((p) => !p.isDeload)
        .map((p) => p.best1RM)
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null || b > a ? b : a);

    // A percentage change needs two points. With one, "+0.0%" reads as
    // "no progress" when the truth is "not enough data yet".
    final first = real.length >= 2 ? real.first.best1RM : null;
    final last = real.length >= 2 ? real.last.best1RM : null;
    final delta = (first != null && last != null && first > 0)
        ? (last - first) / first * 100
        : null;

    // IntrinsicHeight, not CrossAxisAlignment.stretch: inside a ListView the
    // Row's cross axis is unbounded, and stretch there is a layout error that
    // takes the whole surrounding Column down with it.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Stat(
              label: 'Best e1RM',
              value: best == null ? '—' : '${best.toStringAsFixed(1)} kg',
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: _Stat(
              // The range is already named by the selected chip above.
              label: 'Change',
              value: delta == null
                  ? '—'
                  : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
              color: delta == null
                  ? null
                  : (delta >= 0 ? c.positive : c.negative),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: _Stat(
              label: 'Since best',
              value: stalled == 0
                  ? 'At peak'
                  : '$stalled session${stalled == 1 ? '' : 's'}',
              color: stalled >= 3 ? c.negative : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.t.labelSmall),
          const SizedBox(height: Space.xs),
          Text(
            value,
            style: context.t.titleMedium?.copyWith(
              color: color,
              fontFeatures: tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceList extends StatelessWidget {
  const _PerformanceList({required this.points});

  final List<ProgressPoint> points;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < points.length; i++) ...[
            if (i > 0) Divider(color: c.border, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      DateFormat(
                        'd MMM',
                      ).format(dateFromDayKey(points[i].dayKey)),
                      style: context.t.labelMedium,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      points[i].sessionName,
                      style: context.t.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (points[i].isDeload) ...[
                    Pill('Deload', color: c.deload),
                    const SizedBox(width: Space.sm),
                  ],
                  Text(
                    '${_fmt(points[i].topSetLoad)} × ${points[i].topSetReps ?? '—'}',
                    style: context.t.labelLarge,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(double? v) {
    if (v == null) return '—';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }
}
