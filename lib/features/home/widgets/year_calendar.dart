import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ids.dart';
import '../../../core/theme/tokens.dart';
import '../heatmap_data.dart';
import 'heatmap.dart' show heatColourIn;

/// One year as twelve small month calendars, three to a row.
///
/// Every month starts its week on Monday, so a week reads as one row of a
/// month, and the week picked on the chart above is ringed day by day. Today
/// is ringed as well. There are no weekday letters: with three months side by
/// side they would print three times across the card.
///
/// Each month is one `CustomPaint`, for the reason the year map is one: a
/// widget per day is a few hundred widgets to draw what is a set of squares.
class YearCalendar extends StatelessWidget {
  const YearCalendar({
    super.key,
    required this.year,
    required this.days,
    required this.today,
    this.week,
  });

  final int year;
  final Map<int, HeatDay> days;
  final DateTime today;

  /// The Monday of the week to ring, or null.
  final DateTime? week;

  static const _columns = 3;
  static const _columnGap = Space.lg;
  static const _rowGap = Space.lg + Space.xxs;
  static const _cellGap = 2.0;
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, box) {
        final column =
            (box.maxWidth - _columnGap * (_columns - 1)) / _columns;
        final cell = math.max(0.0, (column - _cellGap * 6) / 7);
        final todayKey = dayKeyOf(today);

        final rows = <Widget>[];
        for (var r = 0; r < 12 ~/ _columns; r++) {
          if (r > 0) rows.add(const SizedBox(height: _rowGap));
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k < _columns; k++) ...[
                if (k > 0) const SizedBox(width: _columnGap),
                SizedBox(
                  width: column,
                  child: _Month(
                    label: _months[r * _columns + k],
                    painter: _MonthPainter(
                      first: DateTime(year, r * _columns + k + 1, 1),
                      days: days,
                      todayKey: todayKey,
                      week: week,
                      cell: cell,
                      gap: _cellGap,
                      colours: c,
                    ),
                  ),
                ),
              ],
            ],
          ));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({required this.label, required this.painter});

  final String label;
  final _MonthPainter painter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.t.bodySmall, maxLines: 1),
        const SizedBox(height: Space.xs + 2),
        CustomPaint(size: painter.size, painter: painter),
      ],
    );
  }
}

class _MonthPainter extends CustomPainter {
  _MonthPainter({
    required this.first,
    required this.days,
    required this.todayKey,
    required this.week,
    required this.cell,
    required this.gap,
    required this.colours,
  });

  final DateTime first;
  final Map<int, HeatDay> days;
  final int todayKey;
  final DateTime? week;
  final double cell;
  final double gap;
  final DeltoidColors colours;

  /// Blank cells before the 1st, Monday first.
  int get _lead => first.weekday - 1;
  int get _length => DateTime(first.year, first.month + 1, 0).day;
  int get _rows => ((_lead + _length) / 7).ceil();

  Size get size => Size(7 * cell + 6 * gap, _rows * cell + (_rows - 1) * gap);

  @override
  void paint(Canvas canvas, Size size) {
    if (cell <= 0) return;
    // The year map's corner at this size: 4 on a cell too small to carry it is
    // a circle.
    final radius = Radius.circular(math.min(Radii.heatCell, cell / 4));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final weekStart = week;
    final weekEnd = weekStart == null
        ? null
        : DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

    for (var d = 0; d < _length; d++) {
      final date = DateTime(first.year, first.month, d + 1);
      final key = dayKeyOf(date);
      final at = _lead + d;
      final rect = Rect.fromLTWH(
        (at % 7) * (cell + gap),
        (at ~/ 7) * (cell + gap),
        cell,
        cell,
      );
      final day = days[key];
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()
          ..color = heatColourIn(colours, day, isFuture: key > todayKey),
      );

      final inWeek = weekStart != null &&
          !date.isBefore(weekStart) &&
          date.isBefore(weekEnd!);
      if (key == todayKey || inWeek) {
        // On a filled day the ring is the primary text colour; on an empty
        // one the secondary, which still reads against the grey and does not
        // shout over the trained days beside it.
        ring.color = key == todayKey || day != null
            ? colours.textPrimary
            : colours.textSecondary;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(1.25), radius),
          ring,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MonthPainter old) =>
      !identical(old.days, days) ||
      old.first != first ||
      old.todayKey != todayKey ||
      old.week != week ||
      old.cell != cell ||
      old.colours != colours;
}
