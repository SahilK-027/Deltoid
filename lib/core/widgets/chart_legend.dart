import 'package:flutter/material.dart';

import '../../domain/chart_legend.dart';
import '../theme/tokens.dart';

/// How an entry's swatch is drawn: by the kind of mark it keys.
enum LegendMark {
  /// A line on the plot, keyed by a 14 by 2 rule.
  line,

  /// A dashed line, keyed by the same rule dashed, so a solid key never names
  /// a mark the chart only draws dashed.
  dashedLine,

  /// An area — a band, a tint, a heat cell — keyed by a 10 square at radius 2.
  area,
}

/// One entry of a [ChartLegend]: a swatch and its name.
class LegendEntry {
  const LegendEntry(this.label, this.color, {this.mark = LegendMark.area});

  final String label;
  final Color color;
  final LegendMark mark;
}

/// The one legend under every chart that needs a key (THEME → Charts).
///
/// It keys the trend chart's series, the Strength card's marks, the All time
/// groups, the year maps and the Phase card's tints. It was five widgets, in
/// circles at 8 and squares at 10, `bodySmall` and `labelSmall`, 12 and 16
/// apart, and each screen's key looked like a different app's.
///
/// An entry is a swatch, 4, and the name in `labelSmall` `textSecondary`,
/// never in the swatch's hue: cyan on a white card is 1.7:1. Entries start at
/// the left, 12 apart, and wrap 4 apart. **It never grows past two rows**: the
/// last entry that fits reads `and 3 more`, so the header over the list does
/// not change height when a range brings a ninth session into view.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.entries, this.title});

  final List<LegendEntry> entries;

  /// A word naming what the swatches are of, leading the first row in the same
  /// style: the Strength card's `Cycle`, the timeline's `Regimes` and `Weeks`.
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final style = context.t.labelSmall?.copyWith(color: context.c.textSecondary);
    final wrap = LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double textWidth(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final shown = legendFit(
          [
            for (final e in entries)
              _swatchWidth(e.mark) + Space.xs + textWidth(e.label),
          ],
          box.maxWidth,
          moreWidth: (hidden) => textWidth(legendMore(hidden)),
        );
        return Wrap(
          spacing: legendSpacing,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final e in entries.take(shown)) _Entry(entry: e, style: style),
            if (shown < entries.length)
              Text(
                legendMore(entries.length - shown),
                style: style,
                maxLines: 1,
              ),
          ],
        );
      },
    );

    final heading = title;
    if (heading == null) return wrap;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: style),
        const SizedBox(width: legendSpacing),
        Expanded(child: wrap),
      ],
    );
  }
}

double _swatchWidth(LegendMark mark) => mark == LegendMark.area ? 10 : 14;

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, required this.style});

  final LegendEntry entry;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final swatch = switch (entry.mark) {
      LegendMark.area => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: entry.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      LegendMark.line => Container(width: 14, height: 2, color: entry.color),
      LegendMark.dashedLine => SizedBox(
          width: 14,
          height: 2,
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(child: ColoredBox(color: entry.color)),
              ],
            ],
          ),
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: Space.xs),
        // Cut short only when one name is wider than the whole legend, which
        // then has a row of its own to be cut on.
        Flexible(
          child: Text(
            entry.label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
