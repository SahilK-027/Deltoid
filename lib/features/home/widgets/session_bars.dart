import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/trend_chart.dart';
import '../../../domain/chart_buckets.dart';
import '../../../domain/chart_density.dart';
import '../../../domain/consistency_year.dart';
import '../../../domain/date_axis.dart';
import '../../../domain/value_axis.dart';

/// Sessions per week across one year: a bar a week, a y axis you can read a
/// count off, and months under the baseline.
///
/// Drawn in the language of the volume chart (THEME → Charts): dashed
/// gridlines, y labels on the right, the date strip from [DateAxis.bars], and
/// one painter for every bar. A bar is progress blue, or the deload orange for
/// a week that held a deload, the two colours the calendar under it uses for
/// the same days. A week without a session draws nothing, so a gap in the
/// training is a gap in the chart.
///
/// **Read by a tooltip over the bar.** Pressing or dragging across the plot
/// picks the week under the finger, steps the other bars back, and names the
/// week and its sessions in a tooltip standing over its bar. The pick stays
/// after the finger lifts, so the week can be read and found in the calendar;
/// pressing the same week again clears it.
class SessionBars extends StatefulWidget {
  const SessionBars({
    super.key,
    required this.weeks,
    required this.picked,
    required this.onPicked,
    required this.today,
  });

  /// Oldest first, as [foldConsistencyYear] gives them.
  final List<TrainingWeek> weeks;

  /// The index of the week being read, or null.
  final int? picked;
  final ValueChanged<int?> onPicked;

  final DateTime today;

  @override
  State<SessionBars> createState() => _SessionBarsState();
}

class _SessionBarsState extends State<SessionBars> {
  /// The pick a press began on, so lifting the finger after pressing the week
  /// already picked clears it, and lifting it after a drag does not.
  int? _pressedFrom;
  bool _dragged = false;

  int? _indexAt(double dx, double width) {
    final n = widget.weeks.length;
    if (n == 0 || width <= 0) return null;
    return math.max(0, math.min(n - 1, (dx / width * n).floor()));
  }

  void _pick(double dx, double width) {
    final i = _indexAt(dx, width);
    if (i != null && i != widget.picked) widget.onPicked(i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final weeks = widget.weeks;
    final axis = ValueAxis.bars(math.max(widget.weeks.fold<int>(
        0, (m, w) => w.sessions > m ? w.sessions : m), 1).toDouble());
    final gutter = axisGutter(context, axis.labels);
    final strip = xLabelStrip(context);
    final plot = chartHeightCard - strip;
    final halfLine = labelLineHeight(context) / 2;

    return Semantics(
      label: _summary(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final width = box.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // A press or a drag, never a tap per bar: a year is 52
                      // bars across a phone, a few points each.
                      onTapDown: (d) {
                        _pressedFrom = widget.picked;
                        _dragged = false;
                        _pick(d.localPosition.dx, width);
                      },
                      onTapUp: (d) {
                        final i = _indexAt(d.localPosition.dx, width);
                        if (!_dragged && i != null && i == _pressedFrom) {
                          widget.onPicked(null);
                        }
                      },
                      onHorizontalDragStart: (d) {
                        _dragged = true;
                        _pick(d.localPosition.dx, width);
                      },
                      onHorizontalDragUpdate: (d) =>
                          _pick(d.localPosition.dx, width),
                      child: SizedBox(
                        height: plot,
                        width: width,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _BarsPainter(
                                  weeks: weeks,
                                  max: axis.max,
                                  ticks: axis.gridlines,
                                  picked: widget.picked,
                                  progress: c.progress,
                                  deload: c.deload,
                                  grid: c.border,
                                ),
                              ),
                            ),
                            if (widget.picked case final i?
                                when i < weeks.length)
                              Positioned.fill(
                                child: CustomSingleChildLayout(
                                  delegate: _TipLayout(
                                    anchor: _anchor(i, width, plot, axis.max),
                                  ),
                                  child: _Tip(
                                    week: weeks[i],
                                    thisWeek: _isThisWeek(weeks[i]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: gutter,
                height: plot,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < axis.gridlines.length; i++)
                      Positioned(
                        left: Space.xs,
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
            ],
          ),
          _Months(
            weeks: weeks,
            today: widget.today,
            gutter: gutter,
            height: strip,
          ),
        ],
      ),
    );
  }

  /// The top centre of week [i]'s bar, where its tooltip points from.
  Offset _anchor(int i, double width, double height, double max) {
    final slot = barSlot(width, widget.weeks.length);
    final sessions = widget.weeks[i].sessions;
    final top = max <= 0 ? height : height - height * sessions / max;
    return Offset(slot * i + slot / 2, top);
  }

  bool _isThisWeek(TrainingWeek week) {
    final today = DateTime(
        widget.today.year, widget.today.month, widget.today.day);
    return !today.isBefore(week.start) &&
        today.isBefore(DateTime(
            week.start.year, week.start.month, week.start.day + 7));
  }

  String _summary() {
    final i = widget.picked;
    if (i == null || i >= widget.weeks.length) {
      return 'Sessions per week, one bar a week';
    }
    final w = widget.weeks[i];
    return '${weekRangeLabel(w)}, ${_sessions(w.sessions)}';
  }
}

String _sessions(int n) => '$n session${n == 1 ? '' : 's'}';

/// The week a tooltip names: its days, then its sessions, and the deload in
/// its own colour where there was one.
class _Tip extends StatelessWidget {
  const _Tip({required this.week, required this.thisWeek});

  final TrainingWeek week;
  final bool thisWeek;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final count = _sessions(week.sessions);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md - 2, vertical: Space.xs + 2),
        decoration: BoxDecoration(
          color: c.surfaceHighest,
          borderRadius: BorderRadius.circular(Radii.cell),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              thisWeek ? 'This week' : weekRangeLabel(week),
              style: context.t.bodySmall?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              softWrap: false,
            ),
            Text.rich(
              TextSpan(
                text: thisWeek ? '$count so far' : count,
                children: [
                  if (week.deload)
                    TextSpan(
                      text: ' · Deload',
                      style: TextStyle(color: c.deload),
                    ),
                ],
              ),
              style: context.t.bodySmall,
              maxLines: 1,
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands the tooltip over its bar, kept inside the plot's width so it never
/// runs off the card at either end of the year.
class _TipLayout extends SingleChildLayoutDelegate {
  const _TipLayout({required this.anchor});

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final maxLeft = math.max(0.0, size.width - child.width);
    final left =
        math.min(maxLeft, math.max(0.0, anchor.dx - child.width / 2));
    return Offset(left, anchor.dy - child.height - Space.sm);
  }

  @override
  bool shouldRelayout(_TipLayout old) => old.anchor != anchor;
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({
    required this.weeks,
    required this.max,
    required this.ticks,
    required this.picked,
    required this.progress,
    required this.deload,
    required this.grid,
  });

  final List<TrainingWeek> weeks;
  final double max;
  final List<double> ticks;
  final int? picked;
  final Color progress;
  final Color deload;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || max <= 0) return;

    // Dashed by hand, `Canvas` having no dash, behind the bars.
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final on = gridlineDash[0].toDouble();
    final step = on + gridlineDash[1];
    for (final tick in ticks) {
      final y = size.height - size.height * (tick / max);
      for (var x = 0.0; x < size.width; x += step) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + on, size.width), y), line);
      }
    }

    final slot = barSlot(size.width, weeks.length);
    final ink = barWidth(slot);
    final inset = (slot - ink) / 2;
    // A 2pt radius on a 2pt bar is a lozenge, not a bar (THEME → Bar list).
    final radius = ink >= 5 ? const Radius.circular(Radii.bar) : Radius.zero;

    for (var i = 0; i < weeks.length; i++) {
      final w = weeks[i];
      if (w.sessions <= 0) continue;
      final h = math.min(size.height, size.height * w.sessions / max);
      final hue = w.deload ? deload : progress;
      final colour = picked == null || picked == i
          ? hue
          // The rest step back rather than the picked one lighting up, as the
          // volume chart's do.
          : hue.withValues(alpha: 0.35);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(slot * i + inset, size.height - h, ink, h),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      !identical(old.weeks, weeks) ||
      old.max != max ||
      old.picked != picked ||
      old.progress != progress ||
      old.deload != deload ||
      old.grid != grid;
}

/// The months under the baseline, from the same ladder every bar chart uses.
class _Months extends StatelessWidget {
  const _Months({
    required this.weeks,
    required this.today,
    required this.gutter,
    required this.height,
  });

  final List<TrainingWeek> weeks;
  final DateTime today;
  final double gutter;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) return SizedBox(height: height);
    final day = DateTime(today.year, today.month, today.day);
    final through = weeks.last.last.isAfter(day) ? day : weeks.last.last;

    final measure = dateLabelMeasure(context);
    return Padding(
      padding: EdgeInsets.only(right: gutter),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final axis = DateAxis.bars(
              from: weeks.first.first,
              to: through,
              by: Granularity.weekly,
              count: weeks.length,
              width: width,
              measure: measure,
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
