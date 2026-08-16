import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ids.dart';
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
    final gutter = _yAxisWidth(context, _Axis.of(series.peakPerWeek(by)).max);
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
            const SizedBox(width: Space.xs),
            SizedBox(
              width: gutter,
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
            gutter: gutter + Space.xs,
          ),
        ),
      ],
    );
  }
}

/// The gutter the y labels sit in, to the right of the plot — **measured, not
/// guessed.**
///
/// It was a flat 26 plus an 8pt gap: 34 points spent on `12`, which is nine
/// points of ink. The room comes off the plot and therefore off the date labels
/// under it, which are the ones that were running out of space.
///
/// Still fixed rather than intrinsic, in the sense the old comment meant: it is
/// derived from the axis *maximum*, so it changes when the chart rescales and
/// not as bars move under it.
double _yAxisWidth(BuildContext context, int max) {
  final painter = TextPainter(
    text: TextSpan(text: '$max', style: context.t.bodySmall),
    textDirection: Directionality.of(context),
  )..layout();
  return painter.width + 2;
}

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
  const _Months({
    super.key,
    required this.bars,
    required this.by,
    required this.gutter,
  });

  final List<VolumeBar> bars;
  final Granularity by;

  /// The room the value labels take on the right, so the strip lines up with
  /// the plot rather than with the row that contains it.
  final double gutter;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();

    // Named by how much time is on screen, not by how it is folded — the same
    // rule and the same function the line charts use. A fortnight of monthly
    // bars is still a fortnight.
    final span = daysBetween(bars.first.start, bars.last.end).toDouble();
    final format = DateFormat(axisDateFormat(span));

    // At most seven, and never more than there are bars: four bars get four
    // labels rather than seven crowded onto four positions.
    final n = bars.length;
    final count = n < _axisLabels ? n : _axisLabels;

    // **The line chart's geometry, exactly.** Its axis pads half a step either
    // side and then ticks every step, which puts label *k* at `(k + ½) / count`
    // of the width — evenly spaced, all of them interior, no end treated
    // differently from the middle.
    //
    // The strip used to spread indices from the first bar to the last and
    // anchor the outer two flush to the edges. Both of those bend the spacing:
    // rounding to whole bars makes the gaps differ by a slot, and anchoring the
    // ends makes the two outer gaps unlike the five inner ones. The result read
    // as *nearly* even, which is worse than either even or obviously not.
    final indices = [
      for (var k = 0; k < count; k++)
        math.max(0, math.min(n - 1, (((k + 0.5) * n / count) - 0.5).round())),
    ];

    List<({int index, double at, String label})> pickedWith(DateFormat f) {
      final out = <({int index, double at, String label})>[];
      for (var k = 0; k < indices.length; k++) {
        final label = f.format(bars[indices[k]].start);
        out.add((
          index: indices[k],
          // The fraction of the plot this label sits at — see [indices].
          at: (k + 0.5) / count,
          label: label,
        ));
      }
      return out;
    }

    // **A collision is a format that is too coarse, not a label too many.**
    //
    // Dropping the repeat was the obvious fix and the wrong one: the positions
    // are fixed at `(k + ½) / count`, so removing one leaves a double-width gap
    // where it was. Thirteen weeks over three months collided four times and
    // came out as three labels spaced 42, 126 — which is exactly the uneven
    // strip this was supposed to cure.
    //
    // So the words get more specific instead. Which way depends on what the
    // picks disagree about: inside one year `Mar` becomes `9 Mar`, and across a
    // boundary — a year of weekly bars reaching back from August covers
    // *thirteen* months, so `Aug` lands at both ends — it becomes `Aug '25`.
    var picks = pickedWith(format);
    if (_collides(picks)) {
      final spansYears =
          bars.first.start.year != bars.last.start.year;
      picks = pickedWith(DateFormat(spansYears ? "MMM ''yy" : 'd MMM'));
      if (_collides(picks)) picks = pickedWith(DateFormat("d MMM ''yy"));
    }

    return Padding(
      padding: EdgeInsets.only(right: gutter),
      child: SizedBox(
        // One line of `label`, which is 13/16.
        height: 16,
        child: LayoutBuilder(
          builder: (context, box) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (var k = 0; k < picks.length; k++)
                  _label(context, picks[k], box.maxWidth),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _collides(List<({int index, double at, String label})> picks) =>
      picks.map((p) => p.label).toSet().length != picks.length;

  Widget _label(
    BuildContext context,
    ({int index, double at, String label}) pick,
    double width,
  ) {
    // Centred on its position without measuring the word: place the box at the
    // point, then shift it left by half of whatever width it turns out to be.
    return Positioned(
      left: pick.at * width,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: Text(
          pick.label,
          style: context.t.bodySmall,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}
