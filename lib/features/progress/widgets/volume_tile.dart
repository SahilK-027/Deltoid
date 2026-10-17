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
  /// rather than each at its own. The finest a tile draws: one too narrow for
  /// its bars folds them coarser (see [foldForWidth]), and tiles of one width
  /// still agree.
  final Granularity by;
  final Color hue;
  final VoidCallback? onTap;
  final double chartHeight;

  @override
  State<VolumeTile> createState() => _VolumeTileState();
}

class _VolumeTileState extends State<VolumeTile> {
  /// The bar under the finger, and the fold it was drawn at, which names it.
  ({VolumeBar bar, Granularity by})? _week;

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
                : weekReadout(week.bar, week.by),
            style: context.t.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.lg),
          // A fixed height around the `LayoutBuilder`, so a parent asking for
          // the tile's intrinsic height is answered without asking it.
          SizedBox(
            height: widget.chartHeight,
            child: LayoutBuilder(
              builder: (context, box) {
                // Against the weeks in hand, not the window's opinion of them,
                // and against the tile's width: a year of weeks in half a
                // phone is a texture, so the tile draws months instead.
                final by = foldForWidth(series.weeks, widget.by, box.maxWidth);
                return WeeklyBars(
                  bars: series.bars(by),
                  hue: widget.hue,
                  height: widget.chartHeight,
                  onSelected: (w) => setState(
                    () => _week = w == null ? null : (bar: w, by: by),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: Space.lg),
          const Divider(),
          const SizedBox(height: Space.md),
          Row(
            children: [
              // The figure and its unit share a baseline while both fit, and
              // the unit wraps under the figure when they do not. Two of these
              // sit side by side in half a phone's width, and at a 1.3 font
              // `sets/wk` was cut to `sets/...`: a unit with its end missing
              // is a figure with no unit (THEME rule 5).
              Expanded(
                child: _Figure(
                  // One decimal, deliberately unlike the sessions-per-week
                  // figure on Workouts, which floors. That one counts whole
                  // sessions you either did or did not do; this is a rate
                  // over a span, where `11` and `11.4` are different
                  // training.
                  value: series.averagePerWeek.toStringAsFixed(1),
                  unit: 'sets/wk',
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

/// The tile's figure and its unit: on one baseline while the pair fits the
/// width, and the unit on its own line under the figure when it does not.
///
/// `valueSm`, not `value`: six of these are read as a grid rather than one at
/// a time, and at 22 the figure outshouted the muscle it belongs to. THEME
/// keeps `value` for the number a card is *about* — here the card is about
/// the muscle and the chart across it.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final figure = Text(value, style: context.t.labelLarge, maxLines: 1);
    final label = Text(unit, style: context.t.bodyMedium, maxLines: 1);
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        double width(String text, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = painter.width;
          painter.dispose();
          return w;
        }

        final needed = width(value, context.t.labelLarge) +
            Space.xs +
            width(unit, context.t.bodyMedium);
        if (!box.hasBoundedWidth || needed <= box.maxWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [figure, const SizedBox(width: Space.xs), label],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [figure, label],
        );
      },
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
String weekSpanLabel(VolumeSeries series) =>
    'Last ${spanOfWeeks(series.weeks.length)}';

/// One bar, named by what it covers and what it came to.
///
/// `15–21 Jun · 11 sets` for a week, `June 2026 · 14.2 sets a week` for a month.
/// A count or a rate of exactly one takes the singular: `1 set`, `1 set a week`.
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
  return '$period · $rate ${rate == '1' ? 'set' : 'sets'} a week';
}
