import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ids.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// The one line chart in the app, and the one range control above it.
///
/// Both were written twice — once for an exercise's e1RM, once for bodyweight —
/// and the second copy came out with a different range control (`3m 6m 1y All`
/// in a segmented pill against `1W 1M 3M 1Y` in chips), no edge suppression on
/// the axes, and no calendar-aware tick spacing, so it printed `Dec 19Jul 26`
/// and `330 Jul` on top of themselves. A chart is a language, not a widget you
/// write per screen.

// ─── Range ──────────────────────────────────────────────────────────────────

/// The rolling windows, shortest first. Whole calendar years are the other
/// question, and they are the picker at the end of the row.
enum ChartRange {
  week('1W', 7),
  month('1M', 30),
  threeMonths('3M', 90),
  year('1Y', 365);

  const ChartRange(this.label, this.days);

  final String label;
  final int days;
}

/// What a chart is showing: a window ending today, or one calendar year.
class TrendWindow {
  const TrendWindow.rolling(this.range) : year = null;
  const TrendWindow.calendar(this.year) : range = null;

  /// Set when the window rolls back from today.
  final ChartRange? range;

  /// Set when the window is a whole calendar year.
  final int? year;

  bool contains(int dayKey) =>
      dayKey >= fromDayKey && dayKey <= toDayKey;

  /// The window as day-key bounds, so a query can ask for it rather than a
  /// screen filtering everything it has ever stored.
  int get fromDayKey => year != null
      ? year! * 10000
      : dayKeyOf(DateTime.now().subtract(Duration(days: range!.days)));

  int get toDayKey => year != null ? year! * 10000 + 1231 : 99999999;

  @override
  bool operator ==(Object other) =>
      other is TrendWindow && other.range == range && other.year == year;

  @override
  int get hashCode => Object.hash(range, year);
}

/// The range chips, and the year picker that takes the place `All` had.
///
/// Chips, not a segmented pill: the pill is for a control that governs the page
/// under it, and this one governs a card. It is also six choices wide once the
/// years arrive, which is a scroll rather than a track.
class TrendRangeBar extends StatelessWidget {
  const TrendRangeBar({
    super.key,
    required this.window,
    required this.years,
    required this.onChanged,
    this.ranges = ChartRange.values,
  });

  final TrendWindow window;

  /// The rolling windows offered, shortest first. All of them unless a screen
  /// has one it cannot honestly draw — weekly volume bars over `1W` is a chart
  /// of one bar, so that screen passes the three that are charts.
  ///
  /// A subset rather than a per-screen control: the chips, the year picker and
  /// the sheet stay one component, so a screen cannot quietly grow a second
  /// range control with different spacing (THEME → Charts).
  final List<ChartRange> ranges;

  /// Years there is something to look at, newest first. A picker offering 2019
  /// to a log that starts in 2024 is a list of empty charts.
  final List<int> years;

  final ValueChanged<TrendWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in ranges) ...[
            AppChip(
              label: r.label,
              selected: window.range == r,
              onTap: () => onChanged(TrendWindow.rolling(r)),
            ),
            const SizedBox(width: Space.sm),
          ],
          if (years.isNotEmpty)
            AppChip(
              label: '${window.year ?? years.first}',
              selected: window.year != null,
              caret: true,
              onTap: () => _pickYear(context),
            ),
        ],
      ),
    );
  }

  Future<void> _pickYear(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      // The sheet keeps itself inside the system's insets rather than relying
      // on the one inside it: `isScrollControlled` lets a long list grow to the
      // full height of the *window*, which on an edge-to-edge Android is taller
      // than the screen you can see.
      useSafeArea: true,
      // And it never takes the whole of it. Twenty years of training is a list
      // longer than a phone, and a sheet that fills the screen is a screen
      // wearing a sheet's clothes — the barrier above it is what says this is a
      // question you can dismiss.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (sheet) => AppSheet(
        title: 'Which year?',
        // The default padding, minus the top the header already provides. It
        // used to pass `only(bottom:)`, which drops the sheet's side gutter as
        // well — the rows then ran edge to edge while every other sheet's did
        // not.
        contentPadding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.lg,
        ),
        children: [
          for (final year in years)
            AppRow(
              title: '$year',
              onTap: () => Navigator.of(sheet).pop(year),
              trailing: AppRadio(selected: year == window.year),
            ),
        ],
      ),
    );
    if (picked == null) return;
    onChanged(TrendWindow.calendar(picked));
  }
}

// ─── The plot ───────────────────────────────────────────────────────────────

/// One line on a [TrendChart].
class TrendSeries {
  const TrendSeries({
    required this.name,
    required this.color,
    required this.spots,
  });

  final String name;
  final Color color;

  /// x is [trendX] of a day key, y is the value in display units.
  final List<FlSpot> spots;
}

/// Day key → days since the epoch, so the x axis is real time. Otherwise a
/// six-week gap in the log looks identical to a week.
double trendX(int dayKey) =>
    dateFromDayKey(dayKey).millisecondsSinceEpoch / 86400000;

/// The chart from THEME → Components: dashed horizontal gridlines only,
/// labels on the
/// right, no border, markers while they still mark something, horizontal zoom.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.series,
    required this.formatValue,
    this.tooltip,
    this.height = 220,
  });

  final List<TrendSeries> series;

  /// A y value as it should be read — with its unit applied, without its unit
  /// printed. The axis is inches from the tooltip, and one of them rendering
  /// kilograms while the other says pounds is the worst kind of units bug.
  final String Function(double value) formatValue;

  /// The whole tooltip line, unit and all. Null disables touch entirely.
  final String Function(double value)? tooltip;

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = [for (final s in series) ...s.spots];

    final xs = [for (final s in all) s.x];
    final ys = [for (final s in all) s.y];
    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final lowest = ys.reduce(min);
    final highest = ys.reduce(max);

    // Bounds snapped to a round step, so every gridline lands on a number a
    // person would say. Left to itself the axis labelled `1126.5` at the
    // extremes, which wrapped onto two lines and collided with the gridline
    // above. The band is the data plus air — never anchored at zero, which
    // draws a year of bodyweight as a flat line an inch off the bottom.
    final step = _niceStep((highest - lowest) / 4);
    final maxY = ((highest + step * 0.5) / step).ceilToDouble() * step;
    var minY = ((lowest - step * 0.5) / step).floorToDouble() * step;
    // Nothing this app charts is negative, so the air under the lowest point
    // stops at zero rather than drawing an axis into numbers that cannot exist.
    if (lowest >= 0 && minY < 0) minY = 0;

    final spanDays = maxX - minX;
    final xInterval = _niceDayStep(spanDays / 4);
    final dense = all.length > 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            // Pinch to zoom the time axis, drag to pan. The vertical axis stays
            // fixed: scaling weight against nothing would make the same
            // progress look like whatever you last pinched.
            transformationConfig: const FlTransformationConfig(
              scaleAxis: FlScaleAxis.horizontal,
              minScale: 1,
              maxScale: 12,
            ),
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: c.border, strokeWidth: 1, dashArray: [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                // Right-hand Y labels (THEME → Components): the left gutter is where the
                // eye starts a row, and spending it on an axis pushes the plot
                // off centre on a phone.
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: step,
                    reservedSize: 52,
                    getTitlesWidget: (value, meta) => _edgeSafe(
                      value,
                      meta,
                      Text(
                        formatValue(value),
                        style: context.t.bodySmall,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) => _edgeSafe(
                      value,
                      meta,
                      Text(
                        DateFormat(_axisFormat(spanDays)).format(
                          DateTime.fromMillisecondsSinceEpoch(
                            value.round() * 86400000,
                          ),
                        ),
                        style: context.t.bodySmall,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: tooltip == null
                  ? const LineTouchData(enabled: false)
                  : LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => c.surfaceHigh,
                        getTooltipItems: (spots) => [
                          for (final s in spots)
                            LineTooltipItem(
                              tooltip!(s.y),
                              context.t.labelMedium!
                                  .copyWith(color: c.textPrimary),
                            ),
                        ],
                      ),
                    ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: s.spots,
                    isCurved: false,
                    color: s.color,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: !dense,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 3,
                        color: c.bg,
                        strokeWidth: 2,
                        strokeColor: s.color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Markers only while they mark something. Past about forty points the
        // circles touch and the shape you came to read is hidden by the points
        // it is made of — so they go, and the gesture is named instead.
        if (dense) ...[
          const SizedBox(height: Space.sm),
          Text(
            'Pinch to zoom, drag to pan',
            style: context.t.bodySmall?.copyWith(color: c.textTertiary),
          ),
        ],
        if (series.length > 1) ...[
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.sm,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: s.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(s.name, style: context.t.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// A tick at the very edge has half a line of room and ends up printed over
  /// its neighbour — `Dec 19Jul 26`, `330 Jul`. Both axes drop theirs.
  static Widget _edgeSafe(double value, TitleMeta meta, Widget child) {
    if (value <= meta.min || value >= meta.max) return const SizedBox.shrink();
    return SideTitleWidget(meta: meta, space: Space.sm, child: child);
  }

  /// Label resolution follows the span, or four ticks a day apart all render as
  /// the same month and overlap into mush.
  static String _axisFormat(double spanDays) {
    if (spanDays <= 45) return 'd MMM';
    if (spanDays <= 400) return 'MMM';
    return "MMM ''yy";
  }

  /// The nearest round number at or above [raw], from the 1 / 2.5 / 5 / 10
  /// family, so gridlines land on numbers a person would say.
  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
    for (final multiple in const [1, 2, 2.5, 5, 10]) {
      final step = magnitude * multiple;
      if (step >= raw) return step;
    }
    return magnitude * 10;
  }

  /// The same idea on the time axis, in units a calendar has: a week, a
  /// fortnight, a month, a quarter, a year. Ticks every 97 days label three
  /// different months and read as noise.
  static double _niceDayStep(double raw) {
    for (final step in const [7.0, 14.0, 30.0, 61.0, 91.0, 182.0, 365.0]) {
      if (step >= raw) return step;
    }
    return (raw / 365).ceilToDouble() * 365;
  }
}
