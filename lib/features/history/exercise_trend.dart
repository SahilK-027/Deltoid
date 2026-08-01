import 'dart:math';

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
/// What the chart and the rows under it are measuring.
///
/// Two, not four. A 3-RM and a 10-RM are the same Epley curve with a different
/// constant, so a third tab would draw the same shape twice and ask you to
/// notice it did. These two disagree with each other — an estimate that credits
/// reps, and the number that was actually on the bar — which is the only reason
/// a second metric is worth a tab.
enum ExerciseMetric { e1rm, heaviest }

extension ExerciseMetricX on ExerciseMetric {
  String get label => switch (this) {
        ExerciseMetric.e1rm => 'Est. 1RM',
        ExerciseMetric.heaviest => 'Heaviest',
      };

  /// The figure this metric reads off one performance, in kg.
  double? valueOf(ProgressPoint p) => switch (this) {
        ExerciseMetric.e1rm => p.best1RM,
        ExerciseMetric.heaviest => p.topSetLoad,
      };
}

final exerciseMetricProvider =
    StateProvider<ExerciseMetric>((ref) => ExerciseMetric.e1rm);

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
    final metric = ref.watch(exerciseMetricProvider);

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
        _Chart(points: points, metric: metric),
        const SizedBox(height: Space.lg),
        _Summary(all: all, windowed: points, metric: metric),
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
  const _Chart({required this.points, required this.metric});

  final List<ProgressPoint> points;
  final ExerciseMetric metric;

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

    // A performance the metric cannot score is not a zero. Chin-ups with no
    // bodyweight ever logged have no load and no e1RM, and plotting them at 0
    // drew a flat line along the axis and called it a year of training.
    final scored =
        points.where((p) => metric.valueOf(p) != null).toList();
    if (scored.length < 2) {
      return EmptyBox(
        icon: Icons.timeline,
        message: scored.isEmpty
            ? 'Nothing here to measure as ${metric.label.toLowerCase()}.'
            : 'One session so far — a second one gives this a trend.',
      );
    }

    // Deload weeks never appear. A light week is periodisation, not a drop in
    // strength, and an estimated 1RM taken off 80% of your working weight is a
    // number about the programme rather than about you. It used to fall back to
    // including them when there were fewer than two ordinary sessions, which
    // put the one misleading kind of point on the emptiest kind of chart.
    final source = scored.where((p) => !p.isDeload).toList();
    if (source.length < 2) {
      return EmptyBox(
        icon: Icons.timeline,
        message: source.isEmpty
            ? 'Only deload weeks in this range.'
            : 'One ordinary session so far — a second one gives this a trend.',
      );
    }

    final bySession = <String, List<ProgressPoint>>{};
    for (final p in source) {
      bySession.putIfAbsent(p.sessionName, () => []).add(p);
    }

    final palette = [c.data, c.info, c.deload, c.positive];
    final names = bySession.keys.toList();

    final xs = source.map((p) => _x(p.dayKey)).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final ys = source.map((p) => metric.valueOf(p)!).toList();
    final lowest = ys.reduce((a, b) => a < b ? a : b);
    final highest = ys.reduce((a, b) => a > b ? a : b);

    // Bounds snapped to a round step, so every gridline lands on a number a
    // person would say. Left to itself the axis labelled `1126.5` and `1197.5`
    // at the extremes, which wrapped onto two lines and collided with the
    // gridline above.
    final step = _niceStep((highest - lowest) / 4);
    final minY = ((lowest - step * 0.5) / step).floorToDouble() * step;
    final maxY = ((highest + step * 0.5) / step).ceilToDouble() * step;

    // Ticks across the width, in days, on a boundary that means something.
    final spanDays = maxX - minX;
    final xInterval = _niceDayStep(spanDays / 4);

    // Whether there are more points than the width can give each one a marker.
    final dense = source.length > 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: LineChart(
            // Pinch to zoom the time axis, drag to pan. `All` on a long history
            // is hundreds of sessions in a phone's width, where the only honest
            // options are to draw it unreadably or to let you get closer. The
            // vertical axis stays fixed: scaling weight against nothing would
            // make the same progress look like whatever you last pinched.
            transformationConfig: const FlTransformationConfig(
              scaleAxis: FlScaleAxis.horizontal,
              minScale: 1,
              maxScale: 12,
            ),
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY.clamp(0, double.infinity),
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
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
                    interval: step,
                    reservedSize: 52,
                    // The axis sits inches from the tooltip. One of them
                    // rendering kilograms while the other says pounds is the
                    // worst possible version of a units bug: both numbers on
                    // screen at once, neither labelled.
                    getTitlesWidget: (value, meta) {
                      // The label at the very top or bottom has half a line of
                      // room and wraps into the one next to it.
                      if (value <= meta.min || value >= meta.max) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: Space.sm,
                        child: Text(
                          formatWeight(value, unit),
                          style: context.t.bodySmall,
                          maxLines: 1,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      // Same reason as the Y axis: an edge tick has no room and
                      // ends up printed over its neighbour. `Jul Jun Jun Jul`
                      // was two months rendering four times between them.
                      if (value <= meta.min || value >= meta.max) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: Space.sm,
                        child: Text(
                          DateFormat(_axisFormat(spanDays)).format(
                            DateTime.fromMillisecondsSinceEpoch(
                              value.round() * 86400000,
                            ),
                          ),
                          style: context.t.bodySmall,
                          maxLines: 1,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.surfaceHigh,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${formatWeight(s.y, unit)} ${unit.label} '
                        '${metric.label.toLowerCase()}',
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
                        FlSpot(_x(p.dayKey), metric.valueOf(p)!),
                    ],
                    isCurved: false,
                    color: palette[i % palette.length],
                    barWidth: 2,
                    // Markers only while they still mark something. Past about
                    // forty sessions the circles touch, and a year of training
                    // renders as a thick dotted band with the line lost inside
                    // it — the shape you came to read, hidden by the points it
                    // is made of.
                    dotData: FlDotData(
                      show: dense ? false : true,
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
        if (dense) ...[
          const SizedBox(height: Space.sm),
          Text(
            'Pinch to zoom, drag to pan',
            style: context.t.bodySmall?.copyWith(color: c.textTertiary),
          ),
        ],
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

  /// The nearest round number at or above [raw], from the 1 / 2.5 / 5 / 10
  /// family. Gridlines then land on numbers a person would say — 1160, 1180 —
  /// instead of wherever the data happened to start.
  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
    for (final multiple in const [1, 2, 2.5, 5, 10]) {
      final step = magnitude * multiple;
      if (step >= raw) return step;
    }
    return magnitude * 10;
  }

  /// The same idea on the time axis, but in units a calendar has: a week, a
  /// fortnight, a month, a quarter, a year. Ticks every 97 days label three
  /// different months and read as noise.
  static double _niceDayStep(double raw) {
    for (final step in const [7.0, 14.0, 30.0, 61.0, 91.0, 182.0, 365.0]) {
      if (step >= raw) return step;
    }
    return (raw / 365).ceilToDouble() * 365;
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({
    required this.all,
    required this.windowed,
    required this.metric,
  });

  final List<ProgressPoint> all;
  final List<ProgressPoint> windowed;
  final ExerciseMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final real = windowed.where((p) => !p.isDeload).toList();
    final stalled = stalledSessions([for (final p in real) metric.valueOf(p)]);

    final best = all
        .where((p) => !p.isDeload)
        .map(metric.valueOf)
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null || b > a ? b : a);

    // A percentage change needs two points. With one, "+0.0%" reads as
    // "no progress" when the truth is "not enough data yet".
    final first = real.length >= 2 ? metric.valueOf(real.first) : null;
    final last = real.length >= 2 ? metric.valueOf(real.last) : null;
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
            label: 'best ${metric.label.toLowerCase()}',
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
