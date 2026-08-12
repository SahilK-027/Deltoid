import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/trend_chart.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
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

/// What a hold is measured by, whichever metric is selected: the clock.
///
/// Neither metric applies to a plank — there is no 1RM and the load is usually
/// nothing — so rather than draw an empty chart under a pill that offers two
/// wrong answers, the whole screen switches to seconds and the pill is hidden.
double? metricValue(
  ProgressPoint p,
  ExerciseMetric metric,
  MeasureMode measure,
) =>
    measure.isHold ? p.topSetReps?.toDouble() : metric.valueOf(p);

String metricFormat(double v, WeightUnit unit, MeasureMode measure) =>
    measure.isHold ? '${v.round()}s' : formatWeight(v, unit);

/// The same measure named mid-sentence, where it never starts the line.
String metricNoun(ExerciseMetric metric, MeasureMode measure) =>
    measure.isHold
        ? 'hold time'
        : switch (metric) {
            ExerciseMetric.e1rm => 'est. 1RM',
            ExerciseMetric.heaviest => 'heaviest weight',
          };

/// The same measure, named as the best one on record.
String metricBestLabel(ExerciseMetric metric, MeasureMode measure) =>
    measure.isHold
        ? 'Longest hold'
        : switch (metric) {
            ExerciseMetric.e1rm => 'Best est. 1RM',
            ExerciseMetric.heaviest => 'Heaviest weight',
          };

final exerciseMetricProvider =
    StateProvider<ExerciseMetric>((ref) => ExerciseMetric.e1rm);

final chartRangeProvider =
    StateProvider<TrendWindow>((ref) => const TrendWindow.rolling(
          ChartRange.year,
        ));

/// **`autoDispose`, and that is the point.** Scoring a chart walks four hundred
/// performances and every set in them — 150ms or more on a long history — and
/// this watches `set_logs`, the hot table during a session. Kept alive, one
/// visit to one exercise's chart meant that whole computation re-ran on every
/// set ticked for the rest of the app's life, for a screen nobody was looking
/// at, once per exercise ever opened. The exercise beside it
/// (`exerciseByIdProvider`) and the page under it were already `autoDispose`;
/// this one was the odd one out.
final exerciseProgressProvider = StreamProvider.autoDispose
    .family<List<ProgressPoint>, String>((ref, exerciseId) {
  return ref.watch(trainingRepositoryProvider).watchExerciseProgress(exerciseId);
});

/// The chart, its range selector and the three figures under it. Scrolls with
/// the performances beneath rather than pinning: it is a summary, not a
/// control.
class ExerciseTrend extends ConsumerWidget {
  const ExerciseTrend({
    super.key,
    required this.exerciseId,
    this.measure = MeasureMode.reps,
  });

  final String exerciseId;
  final MeasureMode measure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(exerciseProgressProvider(exerciseId)).valueOrNull;
    final window = ref.watch(chartRangeProvider);
    final metric = ref.watch(exerciseMetricProvider);

    // Nothing at all is the history screen's own empty state, not a chart's.
    if (all == null || all.isEmpty) return const SizedBox.shrink();

    final points = all.where((p) => window.contains(p.dayKey)).toList();

    // Only years there is something to look at. A picker offering 2019 to a
    // log that starts in 2024 is a list of empty charts.
    final years = {for (final p in all) p.dayKey ~/ 10000}.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrendRangeBar(
          window: window,
          years: years,
          onChanged: (w) => ref.read(chartRangeProvider.notifier).state = w,
        ),
        const SizedBox(height: Space.lg),
        _Chart(points: points, metric: metric, measure: measure),
        const SizedBox(height: Space.lg),
        _Summary(
          all: all,
          windowed: points,
          metric: metric,
          measure: measure,
        ),
      ],
    );
  }
}

class _Chart extends ConsumerWidget {
  const _Chart({
    required this.points,
    required this.metric,
    required this.measure,
  });

  final List<ProgressPoint> points;
  final ExerciseMetric metric;
  final MeasureMode measure;

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
            : 'One session so far. A second one draws a trend.',
      );
    }

    // A performance the metric cannot score is not a zero. Chin-ups with no
    // bodyweight ever logged have no load and no e1RM, and plotting them at 0
    // drew a flat line along the axis and called it a year of training.
    final scored =
        points.where((p) => metricValue(p, metric, measure) != null).toList();
    if (scored.length < 2) {
      return EmptyBox(
        icon: Icons.timeline,
        message: scored.isEmpty
            ? 'No ${metricNoun(metric, measure)} recorded in this range.'
            : 'One session so far. A second one draws a trend.',
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
            : 'One full-weight session so far. A second one draws a trend.',
      );
    }

    final bySession = <String, List<ProgressPoint>>{};
    for (final p in source) {
      bySession.putIfAbsent(p.sessionName, () => []).add(p);
    }

    // One line per session slot is the point, not a detail: 22.5 in Push 1 and
    // 20 in Push 2 are two progressions, and drawing them as one is the mistake
    // this app exists to avoid.
    final palette = [c.data, c.info, c.deload, c.positive];
    final names = bySession.keys.toList();

    return TrendChart(
      series: [
        for (var i = 0; i < names.length; i++)
          TrendSeries(
            name: names[i],
            color: palette[i % palette.length],
            spots: [
              for (final p in bySession[names[i]]!)
                FlSpot(trendX(p.dayKey), metricValue(p, metric, measure)!),
            ],
          ),
      ],
      formatValue: (v) => metricFormat(v, unit, measure),
      tooltip: (v) => measure.isHold
          ? '${metricFormat(v, unit, measure)} held'
          : '${formatWeight(v, unit)} ${unit.label} '
              '${metricNoun(metric, measure)}',
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({
    required this.all,
    required this.windowed,
    required this.metric,
    required this.measure,
  });

  final List<ProgressPoint> all;
  final List<ProgressPoint> windowed;
  final ExerciseMetric metric;
  final MeasureMode measure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final real = windowed.where((p) => !p.isDeload).toList();
    final stalled = stalledSessions(
      [for (final p in real) metricValue(p, metric, measure)],
    );

    final best = all
        .where((p) => !p.isDeload)
        .map((p) => metricValue(p, metric, measure))
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null || b > a ? b : a);

    // A percentage change needs two points. With one, "+0.0%" reads as
    // "no progress" when the truth is "not enough data yet".
    final first =
        real.length >= 2 ? metricValue(real.first, metric, measure) : null;
    final last =
        real.length >= 2 ? metricValue(real.last, metric, measure) : null;
    final delta = (first != null && last != null && first > 0)
        ? (last - first) / first * 100
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StatTile(
            value: best == null ? '—' : metricFormat(best, unit, measure),
            unit: best == null || measure.isHold ? null : unit.label,
            label: metricBestLabel(metric, measure),
          ),
        ),
        Expanded(
          child: StatTile(
            // The range is already named by the selected chip above.
            value: delta == null
                ? '—'
                : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
            label: 'Change',
            emphasis:
                delta == null ? null : (delta >= 0 ? c.positive : c.negative),
          ),
        ),
        Expanded(
          child: StatTile(
            value: stalled == 0 ? 'Peak' : '$stalled',
            label: stalled == 0
                ? 'Best is the latest'
                : 'Session${stalled == 1 ? '' : 's'} since best',
            emphasis: stalled >= 3 ? c.negative : null,
          ),
        ),
      ],
    );
  }
}
