import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/trend_chart.dart';
import '../../../domain/chart_buckets.dart';
import '../../../domain/date_axis.dart';
import '../../../domain/value_axis.dart';
import '../../../domain/volume_history.dart';
import 'volume_history_bars.dart';

/// The full-size weekly chart: bars, a y axis you can read a count off, and
/// months under the baseline.
///
/// The tiles draw the same weeks as a sparkline — no axis, no gridlines — which
/// is right for six of them read as a grid and wrong for the one you opened to
/// find out how much. This is where the scale is stated.
///
/// Follows THEME → Charts: dashed horizontal gridlines, in `textTertiary`
/// because they cross the `heatEmpty` tracks, no vertical gridlines and no
/// frame, y labels on the right at `label` size, x labels below the baseline,
/// and **no edge ticks** — a label at the top or bottom of the
/// plot has half a line of room and prints over the bar it is describing.
class VolumeChart extends StatelessWidget {
  const VolumeChart({
    super.key,
    required this.series,
    required this.by,
    required this.hue,
    this.onSelected,
  });

  final VolumeSeries series;

  /// How finely the weeks are folded — see [foldWeeks]. The bars are drawn in
  /// sets per week whatever it is, so this smooths the shape without moving the
  /// axis under it.
  final Granularity by;

  final Color hue;
  final ValueChanged<VolumeBar?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Coarsened against the weeks in hand — see [foldForWeeks]. A window
    // and its data disagree for a frame when the range changes, and that frame
    // must not ask for two and a half thousand bars in a phone's width.
    final safe = foldForWeeks(series.weeks.length, by);
    final bars = series.bars(safe);
    final axis = ValueAxis.bars(series.peakPerWeek(safe));
    // Measured over the labels of the axis it draws, through the one function
    // every chart's gutter comes from. It was measured against the chosen
    // fold's axis and drew the safe one's, and the two could disagree.
    final gutter = axisGutter(context, axis.labels);
    // The card chart's height is the plot and its date strip together, as a
    // line chart's is, so the two take the same room (THEME → Charts).
    final strip = xLabelStrip(context);
    final plot = chartHeightCard - strip;
    final halfLine = labelLineHeight(context) / 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: plot,
                child: WeeklyBars(
                  bars: bars,
                  hue: hue,
                  height: plot,
                  // Bars are drawn against the axis rather than the peak, or
                  // the tallest bar touches the top of the plot and the
                  // gridline it should sit under is invisible behind it.
                  scaleTo: axis.max,
                  onSelected: onSelected,
                  // Over the empty tracks and under the bars, in
                  // `textTertiary`: `border` over `heatEmpty` reads as a
                  // scratch (THEME → Charts), and behind the tracks the lines
                  // showed only in the gaps between bars, so `5 10 15` floated
                  // with nothing to read them against.
                  //
                  // Cross-faded rather than moved. The bars zoom about the
                  // right edge when the range changes, and gridlines cannot
                  // follow that — they belong to the y axis, which is not what
                  // moved. Snapping them mid-zoom reads as a glitch, so the
                  // whole axis is swapped under the motion instead.
                  grid: AnimatedSwitcher(
                    duration: Motion.base,
                    child: CustomPaint(
                      key: ValueKey(axis.max),
                      size: Size.infinite,
                      painter: _Gridlines(
                        ticks: axis.gridlines,
                        max: axis.max,
                        colour: c.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: gutter,
              height: plot,
              child: AnimatedSwitcher(
                duration: Motion.base,
                child: Stack(
                  key: ValueKey(axis.max),
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < axis.gridlines.length; i++)
                      Positioned(
                        // `Space.xs` from the plot, as a line chart's side
                        // title is, inside the same measured gutter.
                        left: Space.xs,
                        // Centred on its own rule, by the line it is drawn
                        // at, which grows with the system font.
                        top: plot - plot * (axis.gridlines[i] / axis.max) -
                            halfLine,
                        child: Text(
                          axis.labels[i],
                          style: context.t.bodySmall,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Same reasoning as the axis: `Jul` cannot travel to where `Jan` is, so
        // the strip is replaced rather than dragged.
        AnimatedSwitcher(
          duration: Motion.base,
          child: _Months(
            key: ValueKey('${bars.length}:${safe.name}'),
            bars: bars,
            by: safe,
            gutter: gutter,
            height: strip,
          ),
        ),
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

  final List<double> ticks;
  final double max;
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
      final on = gridlineDash[0].toDouble();
      final step = on + gridlineDash[1];
      for (var x = 0.0; x < size.width; x += step) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + on, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Gridlines old) =>
      old.max != max || old.colour != colour || old.ticks.length != ticks.length;
}

/// The date strip under the baseline: the same ladder of labels, in the same
/// words, that a line chart prints (THEME → Charts), from [DateAxis.bars].
///
/// The last label is today, the rest are counted back from it in whole bars,
/// and each is centred on the bar its day falls in, so every gap is the same.
/// No label is pulled in from its bar; the newest may run on under the value
/// gutter. Which labels fit is measured at the size they print, system font scale
/// included.
class _Months extends StatelessWidget {
  const _Months({
    super.key,
    required this.bars,
    required this.by,
    required this.gutter,
    required this.height,
  });

  final List<VolumeBar> bars;
  final Granularity by;

  /// The room the value labels take on the right, so the strip lines up with
  /// the plot rather than with the row that contains it.
  final double gutter;

  /// The strip's height, from [xLabelStrip]: `Space.sm` under the plot and one
  /// measured line. A fixed 16 overflowed at a 1.3 font.
  final double height;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return SizedBox(height: height);

    // The last day the bars stand for: today, in the week that holds it. A
    // calendar year in the past ends on its 31 December, though its last week
    // runs into January.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = bars.last;
    var through = last.end.isAfter(today) ? today : last.end;
    final yearEnd = DateTime(last.start.year, 12, 31);
    if (through.isAfter(yearEnd)) through = yearEnd;

    final measure = dateLabelMeasure(context);
    return Padding(
      padding: EdgeInsets.only(right: gutter),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final axis = DateAxis.bars(
              from: bars.first.start,
              to: through,
              by: by,
              count: bars.length,
              width: width,
              measure: measure,
              // Where the step does not divide the bars, the newest label is
              // centred on today's bar and may run on under the value gutter,
              // which is empty at this height, and the card's padding beyond.
              rightRoom: gutter + Space.lg - Space.xs,
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final label in axis.labels)
                  Positioned(
                    top: Space.sm,
                    left: label.at * width - measure(label.text) / 2,
                    child: Text(
                      label.text,
                      style: context.t.bodySmall,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
