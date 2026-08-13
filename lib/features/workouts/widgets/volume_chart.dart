import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/trend_chart.dart';
import '../../../domain/chart_buckets.dart';
import '../../../domain/volume_history.dart';
import 'volume_history_bars.dart';

/// The full-size weekly chart: bars, a y axis you can read a count off, and
/// months under the baseline.
///
/// The tiles draw the same weeks as a sparkline — no axis, no gridlines — which
/// is right for six of them read as a grid and wrong for the one you opened to
/// find out how much. This is where the scale is stated.
///
/// Follows THEME → Charts: dashed horizontal gridlines in `border`, no vertical
/// gridlines and no frame, y labels on the right at `label` size, x labels below
/// the baseline, and **no edge ticks** — a label at the top or bottom of the
/// plot has half a line of room and prints over the bar it is describing.
class VolumeChart extends StatelessWidget {
  const VolumeChart({
    super.key,
    required this.series,
    required this.by,
    required this.hue,
    this.height = 150,
    this.onSelected,
  });

  final VolumeSeries series;

  /// How finely the weeks are folded — see [foldWeeks]. The bars are drawn in
  /// sets per week whatever it is, so this smooths the shape without moving the
  /// axis under it.
  final Granularity by;

  final Color hue;
  final double height;
  final ValueChanged<VolumeBar?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Coarsened against the weeks in hand — see [autoGranularityFor]. A window
    // and its data disagree for a frame when the range changes, and that frame
    // must not ask for two and a half thousand bars in a phone's width.
    final safe = autoGranularityFor(series.weeks.length, by);
    final bars = series.bars(safe);
    final axis = _Axis.of(series.peakPerWeek(safe));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    // Behind the bars, never over them: a rule drawn on top of
                    // a filled bar reads as a break in the bar.
                    //
                    // Cross-faded rather than moved. The bars zoom about the
                    // right edge when the range changes, and gridlines cannot
                    // follow that — they belong to the y axis, which is not
                    // what moved. Snapping them mid-zoom reads as a glitch, so
                    // the whole axis is swapped under the motion instead.
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: Motion.base,
                        child: CustomPaint(
                          key: ValueKey(axis.max),
                          painter: _Gridlines(
                            ticks: axis.ticks,
                            max: axis.max,
                            colour: c.border,
                          ),
                        ),
                      ),
                    ),
                    WeeklyBars(
                      bars: bars,
                      hue: hue,
                      height: height,
                      // Bars are drawn against the axis rather than the peak,
                      // or the tallest bar touches the top of the plot and the
                      // gridline it should sit under is invisible behind it.
                      scaleTo: axis.max.toDouble(),
                      onSelected: onSelected,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            SizedBox(
              // Fixed, not intrinsic: the labels are counts of sets, and a
              // gutter that resizes with them would shift the plot every time
              // the axis crossed 100. Wide enough for three digits at `label`.
              width: _yAxisWidth,
              height: height,
              child: AnimatedSwitcher(
                duration: Motion.base,
                child: Stack(
                  key: ValueKey(axis.max),
                  children: [
                    for (final tick in axis.ticks)
                      Positioned(
                        right: 0,
                        // Centred on its own rule. `label` is 13/16, so half a
                        // line is 8.
                        top: height - height * (tick / axis.max) - 8,
                        child: Text('$tick', style: context.t.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        // Same reasoning as the axis: `Jul` cannot travel to where `Jan` is, so
        // the strip is replaced rather than dragged.
        AnimatedSwitcher(
          duration: Motion.base,
          child: _Months(
            key: ValueKey('${bars.length}:${safe.name}'),
            bars: bars,
            by: safe,
          ),
        ),
      ],
    );
  }
}

/// The gutter the y labels sit in, to the right of the plot.
const _yAxisWidth = 26.0;

/// How many date labels the strip prints at most — the same seven the line
/// charts keep, so both kinds of chart are read at the same rhythm.
const _axisLabels = 7;

/// A y axis: a round maximum at or above the peak, and the rules to draw inside
/// it.
class _Axis {
  const _Axis({required this.max, required this.ticks});

  final int max;

  /// Interior gridlines only — never 0, never [max]. See the class doc on
  /// [VolumeChart] for why the edges are dropped.
  final List<int> ticks;

  /// Snapped to a step that reads as a number of sets rather than as whatever
  /// the tallest week happened to be: 5s up to fifty, 10s beyond.
  ///
  /// Anchored at zero, unlike the trend chart, and for the opposite reason —
  /// zero sets *is* in the data. A week you skipped has to sit on the baseline.
  factory _Axis.of(double rawPeak) {
    // Rounded up before it is snapped: a peak of 6.4 sets a week has to fit
    // under the axis, not sit on its top gridline.
    final peak = rawPeak.ceil();
    if (peak <= 0) return const _Axis(max: 1, ticks: []);
    final step = peak <= 10
        ? 2
        : peak <= 50
            ? 5
            : 10;
    final max = ((peak + step - 1) ~/ step) * step;
    return _Axis(
      max: max,
      ticks: [
        for (var t = step; t < max; t += step) t,
      ],
    );
  }
}

class _Gridlines extends CustomPainter {
  const _Gridlines({
    required this.ticks,
    required this.max,
    required this.colour,
  });

  final List<int> ticks;
  final int max;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1;

    for (final tick in ticks) {
      final y = size.height - size.height * (tick / max);
      // Dashed, drawn by hand: `Canvas` has no dash, and a solid rule at every
      // step turns the plot into a grid you read instead of bars.
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Gridlines old) =>
      old.max != max || old.colour != colour || old.ticks.length != ticks.length;
}

/// The date strip under the baseline: the same seven labels, in the same words,
/// that a line chart prints (THEME → Charts).
///
/// It used to be built out of *runs* — one `Expanded` per calendar period,
/// flexed by how many bars it covered, with every *n*th one printed. Three
/// things were wrong with that and all three were visible. The count was
/// whatever the calendar happened to produce, so a month showed two labels and
/// six months showed seven. Each label was clipped to its own run's box, so
/// `2024` under a narrow year came out as `2`. And a run's box is not centred on
/// anything, so the words drifted away from the bars they name.
///
/// Positions are chosen the way the line chart chooses ticks — evenly across the
/// plot, at most seven — and each label is **centred on its bar** rather than
/// packed into a slot, with the outermost two pulled flush to the edges so a
/// wide word cannot hang off either end.
class _Months extends StatelessWidget {
  const _Months({super.key, required this.bars, required this.by});

  final List<VolumeBar> bars;
  final Granularity by;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();

    // Named by how much time is on screen, not by how it is folded — the same
    // rule and the same function the line charts use. A fortnight of monthly
    // bars is still a fortnight.
    final span = bars.last.end.difference(bars.first.start).inDays.toDouble();
    final format = DateFormat(axisDateFormat(span));

    // At most seven, and never more than there are bars: four bars get four
    // labels rather than seven crowded onto four positions.
    final n = bars.length;
    final count = n < _axisLabels ? n : _axisLabels;

    // The bars the labels sit on, evenly spread and including both ends.
    final indices = [
      for (var k = 0; k < count; k++)
        count == 1 ? 0 : (k * (n - 1) / (count - 1)).round(),
    ];

    List<({int index, String label})> pickedWith(DateFormat f) {
      final out = <({int index, String label})>[];
      for (final i in indices) {
        final label = f.format(bars[i].start);
        // Two picks inside one month would print `Jul Jul`. Dropping the second
        // is better than printing a word that says nothing new.
        if (out.isNotEmpty && out.last.label == label) continue;
        out.add((index: i, label: label));
      }
      return out;
    }

    var picks = pickedWith(format);

    // **A repeat at the two ends is a different problem from a repeat in the
    // middle.** A year of weekly bars reaching back from August covers thirteen
    // months, so `Aug` lands at both edges — and dropping one of them would
    // take away an end of the axis rather than a duplicate. When the labels
    // cannot tell those two apart, the fix is to say which year each is in,
    // not to print one of them fewer times.
    if (picks.map((p) => p.label).toSet().length != picks.length) {
      picks = pickedWith(DateFormat("MMM ''yy"));
    }

    return Padding(
      // The gutter the y labels take on the right, so the strip lines up with
      // the plot rather than with the row that contains it.
      padding: const EdgeInsets.only(right: _yAxisWidth + Space.sm),
      child: SizedBox(
        // One line of `label`, which is 13/16.
        height: 16,
        child: LayoutBuilder(
          builder: (context, box) {
            final slot = box.maxWidth / n;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (var k = 0; k < picks.length; k++)
                  _label(context, picks[k], k, picks.length, slot),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _label(
    BuildContext context,
    ({int index, String label}) pick,
    int k,
    int total,
    double slot,
  ) {
    final text = Text(
      pick.label,
      style: context.t.bodySmall,
      maxLines: 1,
      softWrap: false,
    );

    // The ends are anchored rather than centred: half of `2024` hanging past
    // the plot is the overflow this replaced.
    if (k == 0) return Positioned(left: 0, child: text);
    if (k == total - 1) return Positioned(right: 0, child: text);

    // Centred on its bar without measuring the word: place the box at the bar's
    // centre, then shift it left by half of whatever width it turns out to be.
    return Positioned(
      left: (pick.index + 0.5) * slot,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: text,
      ),
    );
  }
}
