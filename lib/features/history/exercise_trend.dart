import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/metrics.dart';
import '../../domain/units.dart';
import 'history_screen.dart' show formatWeight;

/// Estimated 1RM over time for one movement, split by the session it was
/// trained in.
///
/// This was its own tab. "How has my bench moved" is a history question, and
/// History's per-exercise index is a better picker than the dropdown the
/// Progress tab opened with, so the chart moved to the head of the exercise's
/// own history rather than keeping a fourth destination alive to ask the same
/// thing twice.
///
/// One line per session slot is the point, not a detail: 22.5kg in Push 1 and
/// 20kg in Push 2 are two progressions, and drawing them as one is the mistake
/// this whole app exists to avoid.
enum ChartRange { threeMonths, year, all }

extension ChartRangeX on ChartRange {
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

final chartRangeProvider = StateProvider<ChartRange>((ref) => ChartRange.year);

final exerciseProgressProvider =
    StreamProvider.family<List<ProgressPoint>, String>((ref, exerciseId) {
  return ref.watch(trainingRepositoryProvider).watchExerciseProgress(exerciseId);
});

/// The chart, its range selector and the three figures under it. Scrolls with
/// the performances beneath rather than pinning: it is a summary, not a
/// control.
class ExerciseTrend extends ConsumerWidget {
  const ExerciseTrend({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(exerciseProgressProvider(exerciseId)).valueOrNull;
    final range = ref.watch(chartRangeProvider);

    // Nothing at all is the history screen's own empty state, not a chart's.
    if (all == null || all.isEmpty) return const SizedBox.shrink();

    final cutoff = range.days == null
        ? null
        : dayKeyOf(DateTime.now().subtract(Duration(days: range.days!)));
    final points =
        cutoff == null ? all : all.where((p) => p.dayKey >= cutoff).toList();

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
        const SizedBox(height: Space.lg),
        _Summary(all: all, windowed: points),
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
    return AppChip(
      label: range.label,
      selected: selected,
      onTap: () => ref.read(chartRangeProvider.notifier).state = range,
    );
  }
}

class _Chart extends ConsumerWidget {
  const _Chart({required this.points});

  final List<ProgressPoint> points;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // The y axis is estimated 1RM in kilograms; only the labels change.
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    if (points.length < 2) {
      // Sized to the message rather than reserving chart height for a chart
      // that isn't there — an empty 200px box reads as a rendering failure.
      return EmptyBox(
        icon: Icons.timeline,
        message: points.isEmpty
            ? 'Nothing logged in this range.'
            : 'One session so far — a second one gives this a trend.',
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

    final palette = [c.data, c.info, c.deload, c.positive];
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
        SizedBox(
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
                    FlLine(color: c.border, strokeWidth: 1, dashArray: [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                // Right-hand Y labels (THEME §5): the left gutter is where the
                // eye starts a row, and spending it on an axis pushes the plot
                // off centre on a phone.
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    // The axis sits inches from the tooltip. One of them
                    // rendering kilograms while the other says pounds is the
                    // worst possible version of a units bug: both numbers on
                    // screen at once, neither labelled.
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(left: Space.sm),
                      child: Text(
                        formatWeight(value, unit),
                        style: context.t.bodySmall,
                      ),
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
                        style: context.t.bodySmall,
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
                        '${formatWeight(s.y, unit)} ${unit.label} e1RM',
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
                        color: c.bg,
                        strokeWidth: 2,
                        strokeColor: palette[i % palette.length],
                      ),
                    ),
                  ),
              ],
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
                    Text(names[i], style: context.t.bodySmall),
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

class _Summary extends ConsumerWidget {
  const _Summary({required this.all, required this.windowed});

  final List<ProgressPoint> all;
  final List<ProgressPoint> windowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StatTile(
            value: best == null ? '—' : formatWeight(best, unit),
            unit: best == null ? null : unit.label,
            label: 'best e1RM',
          ),
        ),
        Expanded(
          child: StatTile(
            // The range is already named by the selected chip above.
            value: delta == null
                ? '—'
                : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
            label: 'change',
            emphasis:
                delta == null ? null : (delta >= 0 ? c.positive : c.negative),
          ),
        ),
        Expanded(
          child: StatTile(
            value: stalled == 0 ? 'Peak' : '$stalled',
            label: stalled == 0
                ? 'best is the latest'
                : 'session${stalled == 1 ? '' : 's'} since best',
            emphasis: stalled >= 3 ? c.negative : null,
          ),
        ),
      ],
    );
  }
}
