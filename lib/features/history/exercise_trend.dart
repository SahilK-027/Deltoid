import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/trend_chart.dart';
import '../../domain/chart_buckets.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import '../../domain/metrics.dart';
import '../../domain/units.dart';

/// Estimated 1RM over time for one movement, split by the session it was
/// trained in.
///
/// Not its own tab. "How has my bench moved" is a history question, and
/// History's per-exercise index is a better picker than a dropdown, so the
/// chart sits at the head of the exercise's own history rather than keeping a
/// fourth destination alive to ask the same thing twice.
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

/// The precision the value axis prints a measure at, so no gridline is
/// labelled with a rounding of itself: a whole second for a hold, and half a
/// kilogram for a load.
///
/// The least band the axis shows goes with it at each call: ten seconds, or 5%
/// of the load, so one session or a flat run of them sits in a band rather
/// than on a single gridline.
double metricStep(MeasureMode measure) => measure.isHold ? 1 : 0.5;

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

/// The averaging the *user* picked, or null for "let the range decide".
///
/// Deliberately stores the choice rather than the granularity auto resolved to:
/// storing the resolved one pins the chart at, say, weekly, and then switching
/// from a year to a week leaves it drawing one mark per week on a seven-day
/// chart — auto's whole job is to move when the window does.
final chartGranularityProvider = StateProvider<Granularity?>((ref) => null);

final chartRangeProvider =
    StateProvider<TrendWindow>((ref) => const TrendWindow.rolling(
          ChartRange.year,
        ));

/// **`autoDispose`, and that is the point.** Scoring a chart walks four hundred
/// performances and every set in them — 150ms or more on a long history — and
/// this watches `set_logs`, the hot table during a session. Kept alive, one
/// visit to one exercise's chart re-runs that whole computation on every set
/// ticked for the rest of the app's life, for a screen nobody is looking at,
/// once per exercise ever opened. The exercise beside it
/// (`exerciseByIdProvider`) and the page under it are `autoDispose` for the
/// same reason.
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
    final progress = ref.watch(exerciseProgressProvider(exerciseId));
    final all = progress.valueOrNull;
    final window = ref.watch(chartRangeProvider);
    final metric = ref.watch(exerciseMetricProvider);
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final chosen = ref.watch(chartGranularityProvider);

    // The first day there is anything for. Only `All` reads it, and without it
    // `All` would open on a year and call that everything.
    final earliest = all == null || all.isEmpty
        ? null
        : dateFromDayKey(all.first.dayKey);
    final (from, to) = window.xBoundsSince(earliest);
    final by = resolveGranularity(chosen, daysBetween(from, to));

    // **The same shape whatever the answer is**, and that is the whole point of
    // this method. Scoring the chart is a walk over every performance ever, so
    // it lands a beat after the list beneath it. Without a fixed shape the
    // header collapses to nothing while it is absent, so the rows draw at the
    // top of the screen and are shoved down a chart's height when it
    // arrives. Range bar,
    // plot, three figures: the layout is built before the numbers are known and
    // only its contents change.
    final points = all == null
        ? const <ProgressPoint>[]
        : [for (final p in all) if (window.contains(p.dayKey)) p];

    // Only years there is something to look at. A picker offering 2019 to a
    // log that starts in 2024 is a list of empty charts.
    final years = all == null
        ? const <int>[]
        : ({for (final p in all) p.dayKey ~/ 10000}.toList()
          ..sort((a, b) => b.compareTo(a)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrendRangeBar(
          window: window,
          years: years,
          onChanged: (w) => ref.read(chartRangeProvider.notifier).state = w,
          earliest: earliest,
          granularity: by,
          granularityIsAuto: chosen == null,
          onGranularity: (g) =>
              ref.read(chartGranularityProvider.notifier).state = g,
        ),
        const SizedBox(height: Space.lg),
        if (all == null || all.isEmpty)
          // Loading, or never trained. Both are the empty chart and neither
          // says anything: one has not read the log yet, and the other is a
          // graph with nothing on it, which is already the sentence. Both keep
          // their axes — see [scaleOf].
          EmptyTrendChart(
            window: window,
            earliest: earliest,
            scale: blankScale(measure),
            formatValue: (v) => metricFormat(v, unit, measure),
            minStep: metricStep(measure),
            minSpan: measure.isHold ? 10 : 0,
            minSpanFraction: measure.isHold ? 0 : 0.05,
          )
        else
          _Chart(
            points: points,
            scale: scaleOf(all, metric, measure),
            metric: metric,
            measure: measure,
            window: window,
            earliest: earliest,
            from: from,
            to: to,
            by: by,
          ),
        const SizedBox(height: Space.lg),
        _Summary(
          all: all ?? const [],
          windowed: points,
          metric: metric,
          measure: measure,
        ),
      ],
    );
  }
}

/// The band this movement's numbers live in, over its whole history — what the
/// y axis is scaled to even in a range that has nothing in it, so an empty
/// month reads as an empty stretch of the same chart rather than as a chart
/// that lost its axis.
///
/// With nothing scoreable anywhere it falls back to [blankScale] rather than
/// dropping the labels. An axis with no numbers on it reads as a chart that
/// failed to draw, and a scale under an empty plot claims nothing: there is no
/// line on it to be read against.
(double, double) scaleOf(
  List<ProgressPoint> all,
  ExerciseMetric metric,
  MeasureMode measure,
) {
  double? lowest;
  double? highest;
  for (final p in all) {
    if (p.isDeload) continue;
    final v = metricValue(p, metric, measure);
    if (v == null) continue;
    if (lowest == null || v < lowest) lowest = v;
    if (highest == null || v > highest) highest = v;
  }
  return lowest == null ? blankScale(measure) : (lowest, highest!);
}

/// The axis a movement with no history is drawn against: a plain zero to a
/// round number, in kg or in seconds, which the chart then labels in whatever
/// unit is being displayed.
///
/// Anchored at zero, which the trend chart otherwise never is — there the rule
/// exists because zero is not in the data and anchoring flattens a real line.
/// There is no data here, and zero is where an axis starts when nothing has
/// been measured yet.
(double, double) blankScale(MeasureMode measure) =>
    measure.isHold ? (0, 60) : (0, 100);

class _Chart extends ConsumerWidget {
  const _Chart({
    required this.points,
    required this.scale,
    required this.metric,
    required this.measure,
    required this.window,
    required this.earliest,
    required this.from,
    required this.to,
    required this.by,
  });

  final List<ProgressPoint> points;

  /// All-time bounds for the y axis — see [scaleOf].
  final (double, double) scale;

  final ExerciseMetric metric;
  final MeasureMode measure;
  final TrendWindow window;
  final DateTime? earliest;

  /// The span being drawn, and how finely it is folded.
  final DateTime from;
  final DateTime to;
  final Granularity by;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // The y axis is estimated 1RM in kilograms; only the labels change.
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    // Every "there is nothing to draw" below is the chart itself, empty, on the
    // axes it would have had. A short captioned box instead changes the height
    // of the header, so moving from a full year to an untrained week pulls the
    // performances up under your thumb, and the box reads as the chart having
    // failed rather than as a range you did not train in.
    //
    // **One session is a chart, not an empty state.** A single dot is where you
    // are, and the next one is read against it; refusing to draw it until there
    // are two made the first month of a new movement look like a bug.

    // A performance the metric cannot score is not a zero. Chin-ups with no
    // bodyweight ever logged have no load and no e1RM, and plotting them at 0
    // drew a flat line along the axis and called it a year of training.
    final scored =
        points.where((p) => metricValue(p, metric, measure) != null).toList();

    // Deload weeks never appear. A light week is periodisation, not a drop in
    // strength, and an estimated 1RM taken off 80% of your working weight is a
    // number about the programme rather than about you.
    final source = scored.where((p) => !p.isDeload).toList();

    if (source.isEmpty) {
      return EmptyTrendChart(
        window: window,
        earliest: earliest,
        scale: scale,
        formatValue: (v) => metricFormat(v, unit, measure),
        minStep: metricStep(measure),
        minSpan: measure.isHold ? 10 : 0,
        minSpanFraction: measure.isHold ? 0 : 0.05,
        // Silent when the range is simply empty — an empty graph says that
        // better than a sentence does. It speaks only when the emptiness is
        // something you could not have read off the plot: days that are there
        // but unscoreable, or days that are all deloads.
        message: points.isEmpty
            ? null
            : scored.isEmpty
                ? 'No ${metricNoun(metric, measure)} recorded in this range.'
                : 'Only deload weeks in this range.',
      );
    }

    final bySession = <String, List<ProgressPoint>>{};
    for (final p in source) {
      bySession.putIfAbsent(p.sessionName, () => []).add(p);
    }

    // One line per session slot is the point, not a detail: 22.5 in Push 1 and
    // 20 in Push 2 are two progressions, and drawing them as one is the mistake
    // this app exists to avoid.
    //
    // **And each of them is folded on its own.** Averaging the two together
    // into one monthly mark would do exactly what drawing them as one line
    // does, one layer further down where it cannot be seen.
    //
    // Newest first, so the session you trained last is the blue line, and no
    // more lines than there are colours: a repeated colour makes two
    // progressions read as one. What was left out is said under the chart.
    final palette = c.chartLines;
    final picked = mostRecentKeys(
      [for (final p in source) (key: p.sessionName, dayKey: p.dayKey)],
      max: palette.length,
    );
    final names = picked.shown;

    final chart = TrendChart(
      window: window,
      earliest: earliest,
      series: [
        for (var i = 0; i < names.length; i++)
          TrendSeries(
            name: names[i],
            color: palette[i],
            spots: [
              // Months you did not train this movement break the line. A zero
              // would draw a crash to the axis and back, and a straight line
              // across them would claim sessions that never happened. One
              // empty week, or less than a week of empty days, is the rhythm
              // of the training and is crossed.
              for (final b in lineBuckets(bucketize(
                rows: [
                  for (final p in bySession[names[i]]!)
                    (
                      dayKey: p.dayKey,
                      value: metricValue(p, metric, measure)!,
                    ),
                ],
                by: by,
                from: from,
                to: to,
              ), crossable: crossableEmpty(by)))
                b == null ? FlSpot.nullSpot : FlSpot(bucketX(b), b.value!),
            ],
          ),
      ],
      formatValue: (v) => metricFormat(v, unit, measure),
      minStep: metricStep(measure),
      minSpan: measure.isHold ? 10 : 0,
      minSpanFraction: measure.isHold ? 0 : 0.05,
      tooltip: (v) => measure.isHold
          ? '${metricFormat(v, unit, measure)} held'
          : '${formatWeight(v, unit)} ${unit.label} '
              '${metricNoun(metric, measure)}',
      // Under the plot with the zoom hint and before the legend, where every
      // chart says what it leaves out.
      caption: picked.total <= names.length
          ? null
          : 'Showing ${names.length} of ${picked.total} sessions.',
    );
    return chart;
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

    // The change along one session's own line, the session trained last:
    // Push 1 and Push 2 are two progressions (RULES § 1), and the first
    // performance in the range against the last compared one with the other.
    // A percentage needs two points, so one is a dash rather than `0%`.
    final change = latestSessionChange([
      for (final p in real)
        (session: p.sessionName, value: metricValue(p, metric, measure)),
    ]);
    final sessions = {for (final p in real) p.sessionName};
    final changed = change == null ? null : formatChangePercent(change.percent);

    return StatRow(
      children: [
        StatTile(
          value: best == null ? '—' : metricFormat(best, unit, measure),
          unit: best == null || measure.isHold ? null : unit.label,
          label: metricBestLabel(metric, measure),
        ),
        StatTile(
          // The range is already named by the selected chip above.
          value: changed ?? '—',
          // Named when the chart draws more than one session, so the figure
          // says whose line it is read off.
          label: change == null || sessions.length < 2
              ? 'Change'
              : 'Change in ${change.session}',
          // Green for gaining only, the colour the app uses for beating last
          // time. A drop is `text`: going backwards is information rather
          // than a fault, and red is the colour of deleting something
          // (THEME → Lift row).
          emphasis:
              changed != null && changed.startsWith('+') ? c.positive : null,
        ),
        // "Peak" is a claim about a best that exists. With nothing scored —
        // still loading, or never trained — the honest answer is the dash the
        // other two tiles are already showing, not a word that reads as good
        // news.
        StatTile(
          value: best == null
              ? '—'
              : stalled == 0
                  ? 'Peak'
                  : '$stalled',
          label: best == null
              ? 'Sessions since best'
              : stalled == 0
                  ? 'Best is the latest'
                  : 'Session${stalled == 1 ? '' : 's'} since best',
          // Grey, never the delete red. A run of sessions off your best is a
          // fact about the log, not a fault: you deloaded, you were ill, you
          // were working a different rep range. Red made an ordinary count
          // read as an alarm.
          emphasis: stalled >= 3 ? c.textSecondary : null,
        ),
      ],
    );
  }
}
