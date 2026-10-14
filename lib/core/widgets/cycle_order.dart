import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'primitives.dart';

/// One day in one cycle of a [CycleOrderCard].
class CycleOrderDay {
  const CycleOrderDay({required this.name, this.alternates = false});

  final String name;

  /// Whether this position holds a different day in another cycle. It is the
  /// only thing the card marks, because it is the only thing that changes.
  final bool alternates;
}

/// One cycle of a [CycleOrderCard]: its days in order, and what to call it.
class CycleOrderRow {
  const CycleOrderRow({required this.days, this.label});

  /// `This cycle`, `Next cycle`. Null when the card draws a single cycle,
  /// which needs no name to tell it from another.
  final String? label;
  final List<CycleOrderDay> days;
}

/// The order a cycle runs in, drawn as one row of tiles per cycle
/// (THEME → Components → Cycle order).
///
/// A regime whose days never alternate is one row. One that alternates is a
/// row per cycle until the order repeats, and the tiles line up in columns so
/// the position that changes is the one column whose tiles differ.
///
/// The first row is the cycle in flight and is drawn at full strength. The
/// rows under it are cycles that have not started, so every tile in them is
/// taken down a step, the marked one included: a tile as bright as the one
/// above it would claim the day is as current as that one.
class CycleOrderCard extends StatelessWidget {
  const CycleOrderCard({super.key, required this.rows, this.caption});

  final List<CycleOrderRow> rows;

  /// One clause under the rows naming what alternates, or null when nothing
  /// does.
  final String? caption;

  /// The most positions that share the card's width.
  ///
  /// Five tiles of a day's name fit a narrow phone at the label size. A sixth
  /// would ellipsize every one of them, so past five the tiles keep their
  /// width and the rows scroll together instead.
  static const fitLimit = 5;

  /// A tile's width once the rows scroll.
  static const _scrollTile = 76.0;

  @override
  Widget build(BuildContext context) {
    final positions = rows.isEmpty ? 0 : rows.first.days.length;
    final scrolls = positions > fitLimit;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (rows[r].label != null)
            Padding(
              padding: EdgeInsets.only(
                top: r == 0 ? 0 : Space.md,
                bottom: Space.sm,
              ),
              child: Text(rows[r].label!, style: context.t.bodySmall),
            ),
          Row(
            mainAxisSize: scrolls ? MainAxisSize.min : MainAxisSize.max,
            children: [
              for (var i = 0; i < rows[r].days.length; i++) ...[
                if (i > 0) const SizedBox(width: Space.xs),
                if (scrolls)
                  SizedBox(
                    width: _scrollTile,
                    child: _Tile(day: rows[r].days[i], current: r == 0),
                  )
                else
                  Expanded(
                    child: _Tile(day: rows[r].days[i], current: r == 0),
                  ),
              ],
            ],
          ),
        ],
      ],
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scrolls)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: body,
            )
          else
            body,
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text(caption!, style: context.t.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.day, required this.current});

  final CycleOrderDay day;

  /// Whether the tile belongs to the cycle in flight.
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The selected-chip pair for the day that alternates, and the resting
    // chip for the rest. No hue: which day a cycle trains is the order of the
    // programme, and neither progress nor a deload.
    final fill = day.alternates
        ? (current ? c.accent : c.textSecondary)
        : c.surfaceHigh;
    final ink = day.alternates
        ? c.onAccent
        : (current ? c.textPrimary : c.textTertiary);

    return Container(
      height: 40,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.cell),
      ),
      child: Text(
        day.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.t.bodySmall?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The mark that leads a day in the list of a cycle's positions
/// (THEME → Components → Cycle order).
///
/// A position's number in a circle for the day that holds it, and a small ring
/// for a day waiting its turn in the same position. The two are the ends of
/// the line [TurnLine] draws between them.
class PositionMark extends StatelessWidget {
  const PositionMark({super.key, this.number});

  /// The position, counted from one. Null for a day that is not the one due,
  /// which has no number of its own because it shares the one above it.
  final int? number;

  /// The width every mark occupies, so titles line up whichever is drawn.
  static const extent = 28.0;

  /// The diameter of the ring drawn for a day that is not due.
  static const ring = 10.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final number = this.number;
    return SizedBox(
      width: extent,
      height: extent,
      child: Center(
        child: number == null
            ? Container(
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.textTertiary, width: 2),
                ),
              )
            : Container(
                width: extent,
                height: extent,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surfaceHigh,
                ),
                child: Text(
                  '$number',
                  style: context.t.bodySmall?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
      ),
    );
  }
}

/// The line joining the days that alternate in one position, drawn behind a
/// row whose leading widget is a [PositionMark].
///
/// Each row draws its own half: [below] from its mark to its bottom edge, and
/// [above] from its top edge to its mark. Two rows stacked with no gap then
/// meet in one unbroken line whatever height either lays out at, which a line
/// measured once for the pair would not survive at a larger font.
class TurnLine extends StatelessWidget {
  const TurnLine({
    super.key,
    required this.child,
    required this.numbered,
    this.above = false,
    this.below = false,
  });

  final Widget child;

  /// Whether the row's mark is the numbered circle or the ring, which decides
  /// where the line stops short of it.
  final bool numbered;
  final bool above;
  final bool below;

  @override
  Widget build(BuildContext context) {
    if (!above && !below) return child;
    return CustomPaint(
      painter: _TurnLinePainter(
        color: context.c.surfaceHighest,
        markRadius: (numbered ? PositionMark.extent : PositionMark.ring) / 2,
        above: above,
        below: below,
      ),
      child: child,
    );
  }
}

class _TurnLinePainter extends CustomPainter {
  const _TurnLinePainter({
    required this.color,
    required this.markRadius,
    required this.above,
    required this.below,
  });

  final Color color;
  final double markRadius;
  final bool above;
  final bool below;

  /// Clear space between the line and the mark it runs to.
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // A row's padding, then half the mark: the centre every mark sits on.
    const x = Space.lg + PositionMark.extent / 2;
    final middle = size.height / 2;
    final reach = markRadius + _gap;
    if (above && middle - reach > 0) {
      canvas.drawLine(const Offset(x, 0), Offset(x, middle - reach), paint);
    }
    if (below && middle + reach < size.height) {
      canvas.drawLine(
        Offset(x, middle + reach),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TurnLinePainter old) =>
      old.color != color ||
      old.markRadius != markRadius ||
      old.above != above ||
      old.below != below;
}
