import 'package:flutter/material.dart';

import '../../../core/ids.dart';
import '../../../core/theme/tokens.dart';
import '../heatmap_data.dart';

/// One calendar year, drawn rather than built.
///
/// The old version was a `Widget` per day — a `Tooltip` wrapping a `Container`,
/// 366 of them per year, inside a `ListView` whose children are built eagerly.
/// Thirty years of history was **eleven thousand widgets** laid out and painted
/// before the first frame, which is exactly what the scroll felt like.
///
/// A year is one `CustomPaint` now: 366 rounded rectangles on a canvas, no
/// elements, no layout, no tooltips. The whole screen is a handful of paints.
///
/// It also fits the width instead of scrolling. A year you have to drag through
/// is not a year at a glance, which is the only reason to open this screen —
/// so the cells shrink to fit fifty-three weeks and the horizontal scroll goes.
class YearHeatmap extends StatefulWidget {
  const YearHeatmap({
    super.key,
    required this.year,
    required this.days,
    required this.isCurrent,
  });

  final int year;
  final Map<int, HeatDay> days;

  /// The current year stops at today rather than drawing months of empty
  /// cells for a future nobody has trained yet.
  final bool isCurrent;

  @override
  State<YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<YearHeatmap> {
  /// The day being inspected. Tooltips were the old way of answering "which
  /// day is that", and a tooltip per cell is what made this screen slow — one
  /// readout under the grid says the same thing and costs one widget.
  int? _picked;

  static const _labelWidth = 18.0;
  static const _monthRow = 15.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();

    // UTC throughout: `add(Duration(days: 1))` across a DST boundary lands on
    // 23:00 the day before, which doubles a column twice a year.
    final jan1 = DateTime.utc(widget.year, 1, 1);
    final start = jan1.subtract(Duration(days: jan1.weekday - 1));
    final lastDay = widget.isCurrent
        ? DateTime.utc(now.year, now.month, now.day)
        : DateTime.utc(widget.year, 12, 31);
    final end = lastDay.add(Duration(days: 7 - lastDay.weekday));
    final weeks = (end.difference(start).inDays + 1) ~/ 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Cells are whatever fits. Fifty-three weeks in a phone's width is a
        // small square, and small is the right answer: the pattern is what you
        // read here, not any individual day.
        //
        // The gap scales with the cell rather than sitting at a fixed 2dp — at
        // a 4dp cell a 2dp gap is half the grid, and the year reads as a mesh
        // rather than as days.
        final available = constraints.maxWidth - _labelWidth;
        final unit = available / weeks;
        final gap = (unit * 0.2).clamp(1.0, 3.0);
        final cell = (unit - gap).clamp(2.0, 14.0);
        final gridWidth = weeks * cell + (weeks - 1) * gap;
        final gridHeight = 7 * cell + 6 * gap;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: gridHeight + _monthRow,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: _labelWidth,
                    height: gridHeight,
                    // Seven rows have six gaps between them, not seven. Giving
                    // every row `cell + gap` made the column one gap taller
                    // than the grid it labels, which is an overflow stripe on
                    // every year.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var row = 0; row < 7; row++)
                          SizedBox(
                            height: row == 6 ? cell : cell + gap,
                            child: const ['M', '', 'W', '', 'F', '', ''][row]
                                    .isEmpty
                                ? null
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      const ['M', '', 'W', '', 'F', '', ''][row],
                                      style: context.t.labelSmall,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTapUp: (details) => _pick(details.localPosition, start,
                        cell: cell, gap: gap, weeks: weeks),
                    child: CustomPaint(
                      size: Size(gridWidth, gridHeight + _monthRow),
                      painter: _YearPainter(
                        year: widget.year,
                        days: widget.days,
                        start: start,
                        weeks: weeks,
                        cell: cell,
                        gap: gap,
                        monthRow: _monthRow,
                        todayKey: dayKeyOf(now),
                        picked: _picked,
                        colours: _Palette(
                          empty: c.heatEmpty,
                          future: c.heatEmpty.withValues(alpha: 0.4),
                          deload: c.deloadMuted,
                          deloadEdge: c.deload,
                          scale: c.heatScale,
                          label: c.textSecondary,
                          ring: c.textPrimary,
                        ),
                        labelStyle: context.t.labelSmall!,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The readout replaces 366 tooltips. Empty until something is
            // tapped, and it keeps its height so the grid below never jumps.
            SizedBox(
              height: 20,
              child: Text(
                _caption(),
                style: context.t.bodySmall,
                maxLines: 1,
              ),
            ),
          ],
        );
      },
    );
  }

  String _caption() {
    final key = _picked;
    if (key == null) return '';
    final day = widget.days[key];
    final stamp = _stamp(dateFromDayKey(key));
    if (day == null) return '$stamp · rest day';
    final n = day.workouts;
    return '$stamp · $n session${n == 1 ? '' : 's'}'
        '${day.isDeload ? ' · deload' : ''}';
  }

  static String _stamp(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1]} ${date.day} '
        '${months[date.month - 1]}';
  }

  void _pick(
    Offset position,
    DateTime start, {
    required double cell,
    required double gap,
    required int weeks,
  }) {
    final column = (position.dx / (cell + gap)).floor();
    final row = ((position.dy - _monthRow) / (cell + gap)).floor();
    if (column < 0 || column >= weeks || row < 0 || row > 6) return;

    final date = start.add(Duration(days: column * 7 + row));
    if (date.year != widget.year) return;
    final key = dayKeyOf(date);
    setState(() => _picked = key == _picked ? null : key);
  }
}

/// Colours resolved once, on the widget side. A painter has no `BuildContext`,
/// and looking them up per cell was 366 theme lookups a year.
class _Palette {
  const _Palette({
    required this.empty,
    required this.future,
    required this.deload,
    required this.deloadEdge,
    required this.scale,
    required this.label,
    required this.ring,
  });

  final Color empty;
  final Color future;
  final Color deload;
  final Color deloadEdge;
  final List<Color> scale;
  final Color label;
  final Color ring;
}

class _YearPainter extends CustomPainter {
  const _YearPainter({
    required this.year,
    required this.days,
    required this.start,
    required this.weeks,
    required this.cell,
    required this.gap,
    required this.monthRow,
    required this.todayKey,
    required this.picked,
    required this.colours,
    required this.labelStyle,
  });

  final int year;
  final Map<int, HeatDay> days;
  final DateTime start;
  final int weeks;
  final double cell;
  final double gap;
  final double monthRow;
  final int todayKey;
  final int? picked;
  final _Palette colours;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(cell < 6 ? 1.2 : 3);
    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell < 6 ? 0.8 : 1;

    var lastMonth = -1;

    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final date = start.add(Duration(days: w * 7 + d));
        // Days either side of the boundary belong to a neighbouring year's
        // block, so this one leaves a hole rather than drawing them twice.
        if (date.year != year) continue;

        final key = dayKeyOf(date);
        final day = days[key];
        final rect = Rect.fromLTWH(
          w * (cell + gap),
          monthRow + d * (cell + gap),
          cell,
          cell,
        );

        fill.color = _colourFor(day, isFuture: key > todayKey);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);

        if (day != null && day.isDeload) {
          edge.color = colours.deloadEdge;
          canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), edge);
        }
        if (key == picked) {
          edge.color = colours.ring;
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.inflate(1), radius),
            edge,
          );
        }

        // A month label on the week that starts it. Only where there is room:
        // at 4dp a column, twelve labels overlap into a grey smear, so a tight
        // year gets quarters instead.
        final labelEvery = cell < 7 ? 3 : 1;
        if (d == 0 &&
            date.month != lastMonth &&
            (date.month - 1) % labelEvery == 0) {
          lastMonth = date.month;
          _label(canvas, _monthName(date.month), w * (cell + gap));
        }
      }
    }
  }

  Color _colourFor(HeatDay? day, {required bool isFuture}) {
    if (isFuture) return colours.future;
    if (day == null) return colours.empty;
    if (day.isDeload) return colours.deload;
    final index = (day.workouts - 1).clamp(0, colours.scale.length - 1);
    // A single session is already a full day's work — start at a mid step so
    // normal days read as "done", not "barely".
    return colours.scale[(index + 2).clamp(0, colours.scale.length - 1)];
  }

  void _label(Canvas canvas, String text, double x) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle.copyWith(
        color: colours.label,
        fontSize: (labelStyle.fontSize ?? 11) * (cell < 6 ? 0.9 : 1),
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(x, 0));
  }

  static String _monthName(int month) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][month - 1];

  @override
  bool shouldRepaint(_YearPainter old) =>
      old.picked != picked ||
      old.days != days ||
      old.cell != cell ||
      old.weeks != weeks;
}
