import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/volume_history.dart';
import 'volume_history_bars.dart';

/// A muscle's weeks as a stat tile (THEME → Components → Stat tile): title,
/// caption, chart, hairline, then the figure the tile is about.
///
/// The caption is where the readout lands. Scrub the bars and this line names
/// the week under your finger instead of the span — a tooltip on a card this
/// narrow covers the chart it is describing, and the caption is already the
/// line that says what the chart is of.
class VolumeTile extends StatefulWidget {
  const VolumeTile({
    super.key,
    required this.series,
    required this.hue,
    this.onTap,
    this.chartHeight = 44,
  });

  final VolumeSeries series;
  final Color hue;
  final VoidCallback? onTap;
  final double chartHeight;

  @override
  State<VolumeTile> createState() => _VolumeTileState();
}

class _VolumeTileState extends State<VolumeTile> {
  VolumeWeek? _week;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final series = widget.series;
    final week = _week;

    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            series.label,
            style: context.t.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            week == null ? weekSpanLabel(series) : weekReadout(week),
            style: context.t.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.lg),
          WeeklyBars(
            series: series,
            hue: widget.hue,
            height: widget.chartHeight,
            onSelected: (w) => setState(() => _week = w),
          ),
          const SizedBox(height: Space.lg),
          Divider(color: c.border, height: 1),
          const SizedBox(height: Space.md),
          Row(
            children: [
              // The figure and its unit take what they need and give way
              // together; the chevron keeps the card's right edge. Two of these
              // sit side by side in half a phone's width, so both texts are
              // `Flexible` — the same reason `StatTile` is — and the row still
              // holds when the system font is turned up.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        // One decimal, deliberately unlike the sessions-per-week
                        // figure on Today, which floors. That one counts whole
                        // sessions you either did or did not do; this is a rate
                        // over a span, where `11` and `11.4` are different
                        // training.
                        //
                        // `valueSm`, not `value`: six of these are read as a
                        // grid rather than one at a time, and at 22 the figure
                        // outshouted the muscle it belongs to. THEME keeps
                        // `value` for the number a card is *about* — here the
                        // card is about the muscle and the chart across it.
                        series.averagePerWeek.toStringAsFixed(1),
                        style: context.t.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(
                        'sets/wk',
                        style: context.t.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onTap != null)
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: c.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the tile says when nothing is under the finger: what the bars cover.
///
/// It read `peak 3 · 14 weeks`, which packed the scale and the span into one
/// line and explained neither — `peak 3` is only meaningful once you know each
/// tile is scaled to its own maximum, which is a fact about the drawing rather
/// than about your training. The scale is stated where it can be read properly,
/// on the axis of the full-size chart a tile opens onto.
String weekSpanLabel(VolumeSeries series) {
  final weeks = series.weeks.length;
  return 'Last $weeks ${weeks == 1 ? 'week' : 'weeks'}';
}

/// One week, named by the days it covers.
///
/// `15–21 Jun · 11 sets`, and the month is printed once when the week does not
/// cross one. A week that does reads `29 Jun–5 Jul`.
String weekReadout(VolumeWeek week) {
  final sameMonth = week.start.month == week.end.month;
  final from = DateFormat(sameMonth ? 'd' : 'd MMM').format(week.start);
  final to = DateFormat('d MMM').format(week.end);
  final sets = week.sets == 1 ? '1 set' : '${week.sets} sets';
  return '$from–$to · $sets';
}
