import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ids.dart';
import '../../../core/theme/tokens.dart';
import '../heatmap_data.dart';
import '../workouts_providers.dart';

/// One day's colour, shared by the compact grid on Workouts and the full-history
/// one behind it so the two can never drift apart.
Color heatCellColor(
  BuildContext context,
  HeatDay? day, {
  required bool isFuture,
}) =>
    heatColourIn(context.c, day, isFuture: isFuture);

/// [heatCellColor] for a painter, which has no `BuildContext` and resolves the
/// palette once rather than once per cell.
Color heatColourIn(
  DeltoidColors c,
  HeatDay? day, {
  required bool isFuture,
}) {
  if (isFuture) return c.heatEmpty.withValues(alpha: 0.4);
  if (day == null) return c.heatEmpty;
  // Deload is a solid amber, not an outlined cell. An outline on a 4dp square
  // is a smudge, and a light week is a *kind* of trained day rather than a
  // trained day with a note on it.
  if (day.isDeload) return c.deload;
  // One tone, whatever the day held. The ramp made a single session — a full
  // day's work — the darkest thing on the grid, and three sessions read as
  // three times the achievement when it is usually just a Saturday.
  return c.heatOn;
}

/// One cell. Square, tooltipped, and told nothing about where it sits.
class HeatCell extends StatelessWidget {
  const HeatCell({
    super.key,
    required this.date,
    required this.day,
    required this.size,
    required this.isFuture,
  });

  final DateTime date;
  final HeatDay? day;
  final double size;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    final stamp = DateFormat('EEE d MMM y').format(date);

    return Tooltip(
      message: day == null
          ? stamp
          : '$stamp · ${day.workouts} session${day.workouts == 1 ? '' : 's'}'
              '${day.isDeload ? ' · deload' : ''}',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: heatCellColor(context, day, isFuture: isFuture),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// GitHub-style consistency grid: one column per week, one cell per day.
///
/// Deliberately not a bar chart — the point is pattern recognition at a glance
/// ("I always miss Thursdays"), which a dense grid does better than any
/// aggregate.
class ConsistencyHeatmap extends StatelessWidget {
  const ConsistencyHeatmap({
    super.key,
    required this.days,
    // The window the query already fetches. The card under the grid captions
    // this number in words, and a caption that disagrees with the grid — or
    // with the rows the query returned — is worse than no caption.
    this.weeks = heatmapWeeks,
    this.showMonthLabels = true,
  });

  final Map<int, HeatDay> days;
  final int weeks;
  final bool showMonthLabels;

  @override
  Widget build(BuildContext context) {
    // Date arithmetic happens in UTC even though these are local calendar days:
    // `add(Duration(days: 1))` across a DST boundary lands on 23:00 the previous
    // day, which would duplicate one column's worth of cells twice a year.
    // `dayKeyOf` only reads y/m/d, so nothing here cares about the zone.
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final todayKey = dayKeyOf(today);

    // Columns run Monday-first, ending with the week containing today.
    final endOfWeek = today.add(Duration(days: 7 - today.weekday));
    final start = endOfWeek.subtract(Duration(days: weeks * 7 - 1));

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        const labelWidth = 22.0;
        // The month row and the air under it. Labels sitting straight on top
        // of the first cell row read as a caption stuck to the grid rather than
        // a header over it, with the weekday column beside them having
        // breathing room the months do not.
        const monthRow = 15.0;
        const monthGap = 7.0;
        final available = constraints.maxWidth - labelWidth;
        // Still capped — cells any larger read as a chart rather than a
        // texture, and every point of cell size costs seven points of height
        // off the bottom of the screen. 16 rather than 14 so the widest phones
        // do not leave a margin of empty card to the right of the grid, though
        // the column count does most of that work.
        final cell =
            ((available - gap * (weeks - 1)) / weeks).clamp(8.0, 16.0);

        final columns = <Widget>[];
        // Column a label was last drawn in. A month label is allowed to overrun
        // its own column — that is what the [OverflowBox] below is for — so two
        // labels landing two columns apart print over each other. This is how
        // the grid rendered "MaApr" the day it grew from 13 columns to 18.
        var lastLabelWeek = -99;
        // A three-letter month at 11pt needs about 24pt; one column is the cell
        // plus its gap.
        final columnsPerLabel = (24 / (cell + gap)).ceil();

        for (var w = 0; w < weeks; w++) {
          final cells = <Widget>[];
          var monthLabel = '';

          for (var d = 0; d < 7; d++) {
            final date = start.add(Duration(days: w * 7 + d));
            final key = dayKeyOf(date);

            // A month is labelled at the column holding its 1st, whatever
            // weekday that is — not at the first Monday of a new month.
            //
            // Labelling the leading column whenever the window opens mid-month
            // blocks the real label: a grid starting 30 March would print "Mar"
            // over two days of March and suppress "Apr" one column later as a
            // collision. The window's first days are the least interesting
            // thing in it; the month boundaries are the whole reason for the
            // row.
            if (date.day == 1 && w - lastLabelWeek >= columnsPerLabel) {
              lastLabelWeek = w;
              monthLabel = DateFormat('MMM').format(date);
            }

            cells.add(Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: HeatCell(
                date: date,
                day: days[key],
                size: cell,
                isFuture: key > todayKey,
              ),
            ));
          }

          columns.add(Padding(
            padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMonthLabels) ...[
                  SizedBox(
                    height: monthRow,
                    width: cell,
                    child: monthLabel.isEmpty
                        ? null
                        : OverflowBox(
                            maxWidth: 40,
                            alignment: Alignment.centerLeft,
                            child: Text(monthLabel, style: context.t.labelSmall),
                          ),
                  ),
                  const SizedBox(height: monthGap),
                ],
                ...cells,
              ],
            ),
          ));
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showMonthLabels)
                    const SizedBox(height: monthRow + monthGap),
                  // Only alternate days are labelled; seven labels would be
                  // noisier than the data.
                  for (final label in ['M', '', 'W', '', 'F', '', 'S'])
                    SizedBox(
                      height: cell + gap,
                      child: Text(label, style: context.t.labelSmall),
                    ),
                ],
              ),
            ),
            Expanded(child: Row(children: columns)),
          ],
        );
      },
    );
  }
}

/// Legend explaining the two colour families.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget swatch(Color color, {Color? border}) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: border == null ? null : Border.all(color: border),
          ),
        );

    return Row(
      children: [
        swatch(c.heatEmpty),
        const SizedBox(width: Space.xs),
        Text('Rest', style: context.t.labelSmall),
        const SizedBox(width: Space.lg),
        swatch(c.heatOn),
        const SizedBox(width: Space.xs),
        Text('Trained', style: context.t.labelSmall),
        const SizedBox(width: Space.lg),
        swatch(c.deload),
        const SizedBox(width: Space.xs),
        Text('Deload', style: context.t.labelSmall),
      ],
    );
  }
}
