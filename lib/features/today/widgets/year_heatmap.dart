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

  /// The month strip sits *under* the grid, not over it, and it is the only
  /// axis the year gets. The weekday column went with the old layout: three
  /// letters down the left cost a tenth of the width to answer a question
  /// nobody opens this screen with, and losing it makes every cell bigger.
  static const _monthRow = 16.0;

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
        final available = constraints.maxWidth;
        final unit = available / weeks;
        final gap = (unit * 0.2).clamp(1.0, 3.0);
        final cell = (unit - gap).clamp(2.0, 14.0);
        final gridWidth = weeks * cell + (weeks - 1) * gap;
        final gridHeight = 7 * cell + 6 * gap;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    on: c.heatOn,
                    deload: c.deload,
                    label: c.textSecondary,
                    ring: c.textPrimary,
                  ),
                  labelStyle: context.t.labelSmall!,
                ),
              ),
            ),
            // The readout replaces 366 tooltips. It keeps its height whether
            // or not a day is picked, so nothing below it jumps — and it is a
            // row of this block rather than an overhang, which is what left
            // the card with more space under the grid than over it.
            const SizedBox(height: Space.sm),
            SizedBox(
              height: 18,
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
    final row = (position.dy / (cell + gap)).floor();
    if (column < 0 || column >= weeks || row < 0 || row > 6) return;

    final date = start.add(Duration(days: column * 7 + row));
    if (date.year != widget.year) return;
    final key = dayKeyOf(date);
    setState(() => _picked = key == _picked ? null : key);
  }
}

/// Where one month sits along the width of the year.
class _Span {
  const _Span({required this.left, required this.right});

  final double left;
  final double right;

  double get width => right - left;
}

/// Colours resolved once, on the widget side. A painter has no `BuildContext`,
/// and looking them up per cell was 366 theme lookups a year.
class _Palette {
  const _Palette({
    required this.empty,
    required this.future,
    required this.on,
    required this.deload,
    required this.label,
    required this.ring,
  });

  final Color empty;
  final Color future;

  /// One tone for any day that was trained. See `DeltoidColors.heatOn`.
  final Color on;

  /// Solid, not an outline: at 4dp a stroke is a smudge, and a light week is a
  /// kind of trained day rather than a trained day with a note on it.
  final Color deload;

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
    // Where each month begins and ends along the width, so the strip below is
    // laid out from the same geometry the cells were.
    final spans = <int, _Span>{};

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
          d * (cell + gap),
          cell,
          cell,
        );

        fill.color = _colourFor(day, isFuture: key > todayKey);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);

        if (key == picked) {
          edge.color = colours.ring;
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.inflate(1), radius),
            edge,
          );
        }

        final x = w * (cell + gap);
        if (date.month != lastMonth) {
          lastMonth = date.month;
          spans[date.month] = _Span(left: x, right: x + cell);
        } else {
          final span = spans[date.month];
          if (span != null && x + cell > span.right) {
            spans[date.month] = _Span(left: span.left, right: x + cell);
          }
        }
      }
    }

    _months(canvas, size, spans);
  }

  /// Twelve labels under the grid, one centred on each month's own columns.
  ///
  /// Centred rather than left-aligned on the week a month starts: a month is
  /// four or five columns wide, so anchoring to its first week pushes every
  /// label left of the block it names and makes December fall off the end.
  ///
  /// All twelve, always. They used to be dropped when two would have touched,
  /// which is how a year ended up labelled Jan, Apr, Jul, Oct — the type
  /// shrinks to fit instead, down to a floor, because a missing month is worse
  /// than a small one.
  void _months(Canvas canvas, Size size, Map<int, _Span> spans) {
    if (spans.isEmpty) return;
    final top = 7 * cell + 6 * gap + gap * 2;

    // The narrowest month decides the size for all of them, so the strip stays
    // one typeface at one size rather than a ragged mix.
    final slot = spans.values
        .map((s) => s.width)
        .reduce((a, b) => a < b ? a : b);

    var style = labelStyle.copyWith(color: colours.label);
    var painters = _measure(style);
    final widest =
        painters.values.map((p) => p.width).reduce((a, b) => a > b ? a : b);
    if (widest > slot - 2) {
      final scale = ((slot - 2) / widest).clamp(0.62, 1.0);
      style = style.copyWith(fontSize: (style.fontSize ?? 11) * scale);
      painters = _measure(style);
    }

    for (final entry in spans.entries) {
      final painter = painters[entry.key];
      if (painter == null) continue;
      final centre = entry.value.left + entry.value.width / 2;
      painter.paint(canvas, Offset(centre - painter.width / 2, top));
    }
  }

  Map<int, TextPainter> _measure(TextStyle style) => {
        for (var month = 1; month <= 12; month++)
          month: TextPainter(
            text: TextSpan(text: _monthName(month), style: style),
            textDirection: TextDirection.ltr,
          )..layout(),
      };

  Color _colourFor(HeatDay? day, {required bool isFuture}) {
    if (isFuture) return colours.future;
    if (day == null) return colours.empty;
    if (day.isDeload) return colours.deload;
    return colours.on;
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
