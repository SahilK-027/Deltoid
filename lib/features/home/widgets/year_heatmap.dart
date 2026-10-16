import 'package:flutter/material.dart';

import '../../../core/ids.dart';
import '../../../core/theme/tokens.dart';
import '../heatmap_data.dart';
import 'heatmap.dart' show heatColourIn;

/// What a year map draws: the colour of a day that has happened, and what a
/// picked day says about itself.
///
/// The map is one design for every habit the app counts. Training days and
/// weigh-in days differ only in what fills a cell and in the words under the
/// grid, so those two answers are all a kind of day supplies, and the grid,
/// the month strip, the dimmed future and the tap stay in one place.
///
/// Equal when the days behind it are the same object, which is what a
/// provider hands over until something changes. The painter repaints on a
/// different set of days, and a fresh wrapper around the same map built on
/// every frame must not count as one.
abstract class YearMapDays {
  const YearMapDays();

  /// The fill of a day up to today. A day after today is drawn dim by the map
  /// itself, whatever the kind.
  Color fill(DeltoidColors c, int dayKey);

  /// What follows the date when a day is picked, such as `rest day` or
  /// `weighed`. Empty for nothing but the date.
  String describe(int dayKey, {required bool isFuture});

  /// The object a repaint is decided on.
  Object get source;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      identical((other as YearMapDays).source, source);

  @override
  int get hashCode => identityHashCode(source);
}

/// Training days, in the colours the compact grid on Home draws:
/// [DeltoidColors.progress] for a session and [DeltoidColors.deload] for a
/// light week.
class TrainingYearDays extends YearMapDays {
  const TrainingYearDays(this.days);

  final Map<int, HeatDay> days;

  @override
  Object get source => days;

  @override
  Color fill(DeltoidColors c, int dayKey) =>
      heatColourIn(c, days[dayKey], isFuture: false);

  @override
  String describe(int dayKey, {required bool isFuture}) {
    final day = days[dayKey];
    if (day == null) return 'rest day';
    final n = day.workouts;
    return '$n session${n == 1 ? '' : 's'}${day.isDeload ? ' · deload' : ''}';
  }
}

/// Days with a weigh-in, in [DeltoidColors.weighIn]. A day either holds one or
/// it does not, because a second weigh-in on the same day replaces the first.
class WeighInYearDays extends YearMapDays {
  const WeighInYearDays(this.days);

  final Set<int> days;

  @override
  Object get source => days;

  @override
  Color fill(DeltoidColors c, int dayKey) =>
      days.contains(dayKey) ? c.weighIn : c.heatEmpty;

  /// A day that has not happened yet is named and nothing more: `no weigh-in`
  /// under a date next month reads as a weigh-in missed.
  @override
  String describe(int dayKey, {required bool isFuture}) {
    if (days.contains(dayKey)) return 'weighed';
    return isFuture ? '' : 'no weigh-in';
  }
}

/// One calendar year, drawn rather than built.
///
/// A year is one `CustomPaint`: 366 rounded rectangles on a canvas, no
/// elements, no layout, no tooltips. The whole screen is a handful of paints.
///
/// A `Widget` per day — a `Tooltip` wrapping a `Container`, 366 of them per
/// year, inside a `ListView` whose children are built eagerly — puts **eleven
/// thousand widgets** through layout and paint before the first frame on thirty
/// years of history, which is exactly what the scroll feels like.
///
/// It also fits the width instead of scrolling. A year you have to drag through
/// is not a year at a glance, which is the only reason to open this screen —
/// so the cells shrink to fit fifty-three weeks and the horizontal scroll goes.
///
/// Consistency draws training days with it and Weigh-ins draws weigh-in days;
/// [days] decides which.
class YearHeatmap extends StatefulWidget {
  const YearHeatmap({super.key, required this.year, required this.days});

  final int year;
  final YearMapDays days;

  @override
  State<YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<YearHeatmap> {
  /// The day being inspected. One readout under the grid answers "which day is
  /// that" for the cost of one widget, where a tooltip per cell is most of what
  /// makes this screen slow.
  int? _picked;

  /// The month strip sits *under* the grid, not over it, and it is the only
  /// axis the year gets. There is no weekday column: three letters down the
  /// left cost a tenth of the width to answer a question nobody opens this
  /// screen with, and the space goes into the cells instead.
  ///
  /// Tall enough for one line of `labelSmall` and no taller — this row *is* the
  /// bottom of the block, so every spare pixel in it shows up as a card that
  /// sits lower under the grid than it does over it.
  static const _monthRow = 18.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();

    // UTC throughout: `add(Duration(days: 1))` across a DST boundary lands on
    // 23:00 the day before, which doubles a column twice a year.
    //
    // Always Jan 1 to Dec 31, the current year included. Stopping at today
    // made this year a different shape from every year under it — thirty-one
    // weeks stretched across the same width, so its cells were twice the size
    // and its month strip ran out at August. A year block is a year: the days
    // that have not happened yet are drawn dim, and the grid stays comparable.
    final jan1 = DateTime.utc(widget.year, 1, 1);
    final start = jan1.subtract(Duration(days: jan1.weekday - 1));
    final lastDay = DateTime.utc(widget.year, 12, 31);
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

        final caption = _caption(dayKeyOf(now));
        return GestureDetector(
          onTapUp: (details) => _pick(details.localPosition, start,
              cell: cell, gap: gap, weeks: weeks),
          // The caption is painted, so it is named here as well: a screen
          // reader reads nothing on a canvas.
          child: Semantics(
            label: caption.isEmpty ? '${widget.year}' : caption,
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
                // The readout replaces 366 tooltips, and it takes over the month
                // strip rather than adding a row of its own. A reserved line
                // under the strip was empty almost always, and an empty line is
                // just padding the card can't see — which is why the bottom of
                // every year sat lower than its top.
                caption: caption,
                colours: _Palette(
                  days: c,
                  label: c.textSecondary,
                  ring: c.textPrimary,
                ),
                labelStyle: context.t.labelSmall!,
              ),
            ),
          ),
        );
      },
    );
  }

  String _caption(int todayKey) {
    final key = _picked;
    if (key == null) return '';
    final stamp = _stamp(dateFromDayKey(key));
    final said = widget.days.describe(key, isFuture: key > todayKey);
    return said.isEmpty ? stamp : '$stamp · $said';
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
    required this.days,
    required this.label,
    required this.ring,
  });

  /// The palette a day's fill is read from, through [YearMapDays.fill].
  final DeltoidColors days;

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
    required this.caption,
    required this.colours,
    required this.labelStyle,
  });

  final int year;
  final YearMapDays days;
  final DateTime start;
  final int weeks;
  final double cell;
  final double gap;
  final double monthRow;
  final int todayKey;
  final int? picked;

  /// What the picked day was, or empty. Drawn in the month strip's row.
  final String caption;

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
        final rect = Rect.fromLTWH(
          w * (cell + gap),
          d * (cell + gap),
          cell,
          cell,
        );

        fill.color = _colourFor(key, isFuture: key > todayKey);
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
  /// All twelve, always. The type shrinks to fit, down to a floor, rather than
  /// dropping labels when two would touch — that is how a year ends up labelled
  /// Jan, Apr, Jul, Oct, and a missing month is worse than a small one.
  void _months(Canvas canvas, Size size, Map<int, _Span> spans) {
    if (spans.isEmpty) return;
    final top = 7 * cell + 6 * gap + gap;

    // A picked day answers the question the month strip was answering, and
    // more precisely — so it borrows the row for as long as it is picked.
    if (caption.isNotEmpty) {
      TextPainter(
        text: TextSpan(
          text: caption,
          style: labelStyle.copyWith(color: colours.ring),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )
        ..layout(maxWidth: size.width)
        ..paint(canvas, Offset(0, top));
      return;
    }

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

  /// A day after today is dim whatever the kind, so every year map shows the
  /// rest of the current year the same way.
  Color _colourFor(int key, {required bool isFuture}) => isFuture
      ? colours.days.heatEmpty.withValues(alpha: 0.4)
      : days.fill(colours.days, key);

  static String _monthName(int month) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][month - 1];

  @override
  bool shouldRepaint(_YearPainter old) =>
      old.picked != picked ||
      old.caption != caption ||
      old.days != days ||
      old.cell != cell ||
      old.weeks != weeks ||
      // A theme switch changes nothing above, and without these the grid kept
      // the colours it was first painted in.
      old.colours.days != colours.days ||
      old.colours.label != colours.label ||
      old.colours.ring != colours.ring ||
      old.labelStyle != labelStyle;
}
