import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
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
    required this.hue,
    this.height = 150,
    this.onSelected,
  });

  final VolumeSeries series;
  final Color hue;
  final double height;
  final ValueChanged<VolumeWeek?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final axis = _Axis.of(series.peakSets);

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
                      series: series,
                      hue: hue,
                      height: height,
                      // Bars are drawn against the axis rather than the peak,
                      // or the tallest bar touches the top of the plot and the
                      // gridline it should sit under is invisible behind it.
                      scaleTo: axis.max,
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
            key: ValueKey(series.weeks.length),
            weeks: series.weeks,
          ),
        ),
      ],
    );
  }
}

/// The gutter the y labels sit in, to the right of the plot.
const _yAxisWidth = 26.0;

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
  factory _Axis.of(int peak) {
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

/// Month names under the baseline, each spanning the weeks it covers.
///
/// Calendar-shaped ticks, as THEME asks: a label every *n* weeks would print
/// three different months at the same interval and read as noise. Each month
/// takes as many slots as it has weeks, so the labels line up with the bars
/// above them without a single measurement.
class _Months extends StatelessWidget {
  const _Months({super.key, required this.weeks});

  final List<VolumeWeek> weeks;

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) return const SizedBox.shrink();

    // Runs of consecutive weeks sharing a month, in order.
    final runs = <({String label, int weeks})>[];
    for (final week in weeks) {
      // A week belongs to the month its Monday is in — the same rule the bar
      // itself is bucketed by, so a label can never sit over a bar counted
      // into a different month.
      final label = DateFormat('MMM').format(week.start);
      if (runs.isNotEmpty && runs.last.label == label) {
        runs[runs.length - 1] =
            (label: label, weeks: runs.last.weeks + 1);
      } else {
        runs.add((label: label, weeks: 1));
      }
    }

    // A year is twelve labels across a phone — about four weeks of slot each,
    // which is narrower than the word `Sep`. Every other one is dropped rather
    // than letting them collide or ellipsize into `Se…`, and the strip stays
    // calendar-shaped because what is dropped is a whole month.
    final everyOther = runs.length > 8;

    return Padding(
      // The gutter the y labels take on the right, so the strip lines up with
      // the plot rather than with the row that contains it.
      padding: const EdgeInsets.only(right: _yAxisWidth + Space.sm),
      child: Row(
        children: [
          for (var i = 0; i < runs.length; i++)
            Expanded(
              flex: runs[i].weeks,
              child: Text(
                everyOther && i.isOdd ? '' : runs[i].label,
                style: context.t.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
              ),
            ),
        ],
      ),
    );
  }
}
