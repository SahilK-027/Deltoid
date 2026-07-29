import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ids.dart';
import '../../../core/theme/tokens.dart';
import '../heatmap_providers.dart';

/// GitHub-style consistency grid: one column per week, one cell per day.
///
/// Deliberately not a bar chart — the point is pattern recognition at a glance
/// ("I always miss Thursdays"), which a dense grid does better than any
/// aggregate.
class ConsistencyHeatmap extends StatelessWidget {
  const ConsistencyHeatmap({
    super.key,
    required this.days,
    this.weeks = 13,
    this.showMonthLabels = true,
  });

  final Map<int, HeatDay> days;
  final int weeks;
  final bool showMonthLabels;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = DateTime.now();

    // Columns run Monday-first, ending with the week containing today.
    final endOfWeek = today.add(Duration(days: 7 - today.weekday));
    final start = endOfWeek.subtract(Duration(days: weeks * 7 - 1));

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        const labelWidth = 22.0;
        final available = constraints.maxWidth - labelWidth;
        final cell =
            ((available - gap * (weeks - 1)) / weeks).clamp(8.0, 18.0);

        final columns = <Widget>[];
        var lastMonth = -1;

        for (var w = 0; w < weeks; w++) {
          final cells = <Widget>[];
          var monthLabel = '';

          for (var d = 0; d < 7; d++) {
            final date = start.add(Duration(days: w * 7 + d));
            final key = dayKeyOf(date);
            final day = days[key];
            final isFuture = date.isAfter(today);

            if (d == 0 && date.month != lastMonth) {
              lastMonth = date.month;
              monthLabel = DateFormat('MMM').format(date);
            }

            cells.add(Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: Tooltip(
                message: day == null
                    ? DateFormat('EEE d MMM').format(date)
                    : '${DateFormat('EEE d MMM').format(date)} · '
                        '${day.workouts} session${day.workouts == 1 ? '' : 's'}'
                        '${day.isDeload ? ' · deload' : ''}',
                waitDuration: const Duration(milliseconds: 400),
                child: Container(
                  width: cell,
                  height: cell,
                  decoration: BoxDecoration(
                    color: _cellColor(context, day, isFuture),
                    borderRadius: BorderRadius.circular(3),
                    border: day != null && day.isDeload
                        ? Border.all(color: c.deload, width: 1)
                        : null,
                  ),
                ),
              ),
            ));
          }

          columns.add(Padding(
            padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMonthLabels)
                  SizedBox(
                    height: 14,
                    width: cell,
                    child: monthLabel.isEmpty
                        ? null
                        : OverflowBox(
                            maxWidth: 40,
                            alignment: Alignment.centerLeft,
                            child: Text(monthLabel, style: context.t.labelSmall),
                          ),
                  ),
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
                  if (showMonthLabels) const SizedBox(height: 14),
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

  Color _cellColor(BuildContext context, HeatDay? day, bool isFuture) {
    final c = context.c;
    if (isFuture) return c.heatEmpty.withValues(alpha: 0.4);
    if (day == null) return c.heatEmpty;
    if (day.isDeload) return c.deloadMuted;

    final scale = c.heatScale;
    final index = (day.workouts - 1).clamp(0, scale.length - 1);
    // A single session is already a full day's work — start at a mid step so
    // normal days read as "done", not "barely".
    return scale[(index + 2).clamp(0, scale.length - 1)];
  }
}

/// Legend explaining the two colour families, shown under the full heatmap.
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
        swatch(c.heatScale[2]),
        const SizedBox(width: Space.xs),
        Text('Trained', style: context.t.labelSmall),
        const SizedBox(width: Space.lg),
        swatch(c.deloadMuted, border: c.deload),
        const SizedBox(width: Space.xs),
        Text('Deload', style: context.t.labelSmall),
      ],
    );
  }
}
