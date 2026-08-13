import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/chart_buckets.dart';
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
    required this.by,
    this.onTap,
    this.chartHeight = 44,
  });

  final VolumeSeries series;

  /// How finely the weeks are folded, so six tiles read at one granularity
  /// rather than each at its own.
  final Granularity by;
  final Color hue;
  final VoidCallback? onTap;
  final double chartHeight;

  @override
  State<VolumeTile> createState() => _VolumeTileState();
}

class _VolumeTileState extends State<VolumeTile> {
  VolumeBar? _week;

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
            week == null
                ? weekSpanLabel(series)
                : weekReadout(week, widget.by),
            style: context.t.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.lg),
          WeeklyBars(
            bars: series.bars(
              // Against the weeks in hand, not the window's opinion of them.
              autoGranularityFor(series.weeks.length, widget.by),
            ),
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
                        // figure on Workouts, which floors. That one counts whole
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

/// One bar, named by what it covers and what it came to.
///
/// `15–21 Jun · 11 sets` for a week, `June 2026 · 14.2 sets a week` for a month.
/// A folded bar states its **rate**, because that is its height, and never its
/// total, which would be a number the bar is not drawn to.
String weekReadout(VolumeBar bar, Granularity by) {
  if (by == Granularity.weekly || by == Granularity.daily) {
    // The month is printed once when the week does not cross one. A week that
    // does reads `29 Jun–5 Jul`.
    final sameMonth = bar.start.month == bar.end.month;
    final from = DateFormat(sameMonth ? 'd' : 'd MMM').format(bar.start);
    final to = DateFormat('d MMM').format(bar.end);
    final sets = bar.totalSets == 1 ? '1 set' : '${bar.totalSets} sets';
    return '$from–$to · $sets';
  }

  final period = DateFormat(by == Granularity.yearly ? 'yyyy' : 'MMMM yyyy')
      .format(bar.start);
  final rate = bar.setsPerWeek == bar.setsPerWeek.roundToDouble()
      ? bar.setsPerWeek.toStringAsFixed(0)
      : bar.setsPerWeek.toStringAsFixed(1);
  return '$period · $rate sets a week';
}
