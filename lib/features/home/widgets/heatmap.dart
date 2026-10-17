import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chart_legend.dart';
import '../heatmap_data.dart';

/// One day's colour on a year map, resolved from a palette rather than a
/// `BuildContext` so a painter can call it once per cell.
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
  return c.progress;
}

/// Legend explaining the colours a year map draws in: rest, trained and
/// deload on Consistency, or no weigh-in and weighed on Weigh-ins.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key}) : _weighIns = false;

  /// The Weigh-ins screen's legend, for maps drawn with `WeighInYearDays`.
  const HeatmapLegend.weighIns({super.key}) : _weighIns = true;

  final bool _weighIns;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ChartLegend(
      entries: _weighIns
          ? [
              LegendEntry('No weigh-in', c.heatEmpty),
              LegendEntry('Weighed', c.weighIn),
            ]
          : [
              LegendEntry('Rest', c.heatEmpty),
              LegendEntry('Trained', c.progress),
              LegendEntry('Deload', c.deload),
            ],
    );
  }
}
