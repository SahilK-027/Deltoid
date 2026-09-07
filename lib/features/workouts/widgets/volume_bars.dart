import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/enums.dart';
import '../../../domain/muscle_volume.dart';

/// Weekly sets per muscle: the one chart in this app that is a list (THEME → Components).
///
/// One row per region, name on the left, a bar in the middle, the count on the
/// right. No axis, no gridlines, no legend — a bar list whose longest bar *is*
/// the maximum needs none of them, and they are what turn six rows into a chart
/// nobody reads.
///
/// A compound row (arms, legs) opens onto its own muscles. That fold is not a
/// nicety: `Legs 18` is a number you can read at a glance and cannot act on,
/// and `Quads 12 · Hamstrings 2` is the same week saying something you would
/// change your next session over.
class VolumeBars extends StatefulWidget {
  const VolumeBars({super.key, required this.volume});

  final WeeklyVolume volume;

  @override
  State<VolumeBars> createState() => _VolumeBarsState();
}

class _VolumeBarsState extends State<VolumeBars> {
  final _open = <MuscleRegion>{};

  @override
  Widget build(BuildContext context) {
    final rows = widget.volume.rows;
    // Every bar is drawn against the biggest row, not against a target: this
    // app has no business inventing a number of sets you are failing to hit
    // (RULES § Scope). One set in a week is therefore a full bar, which is
    // correct — it is the most you did.
    final max = widget.volume.maxSets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) ...[
          _RegionRow(
            row: row,
            max: max,
            hue: context.c.forRegion(row.region),
            open: _open.contains(row.region),
            onTap: !row.region.isCompound
                ? null
                : () => setState(() {
                    _open.contains(row.region)
                        ? _open.remove(row.region)
                        : _open.add(row.region);
                  }),
          ),
          // The muscles under a region, animated to their height rather than
          // appearing — the same fold the bodyweight months use.
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.emphasized,
            alignment: Alignment.topCenter,
            child: !_open.contains(row.region)
                ? const SizedBox(width: double.infinity)
                : _Parts(
                    row: row,
                    max: max,
                    hue: context.c.forRegion(row.region),
                  ),
          ),
        ],
      ],
    );
  }
}

/// The width the names column takes, so every bar starts at the same x.
///
/// Fixed rather than intrinsic: an intrinsic column re-measures as the longest
/// name changes, and `Shoulders` week to `Arms` week would move every bar on
/// the card sideways.
const _nameWidth = 84.0;

class _RegionRow extends StatelessWidget {
  const _RegionRow({
    required this.row,
    required this.max,
    required this.hue,
    required this.open,
    this.onTap,
  });

  final MuscleVolume row;
  final int max;
  final Color hue;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final content = Padding(
      // The right inset matches the one the opened block's own padding puts on
      // its rows ([_Parts]). Without it a region's bar ran 8pt further right
      // than its muscles' bars and its count sat 8pt outboard of theirs — two
      // columns that are read as one, misaligned by exactly that padding. The
      // fix is the parent moving in, not the child losing its inset and
      // printing its counts against the block's edge.
      padding: const EdgeInsets.fromLTRB(0, Space.sm, Space.sm, Space.sm),
      child: Row(
        children: [
          SizedBox(
            width: _nameWidth,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.region.label,
                    style: context.t.bodyMedium?.copyWith(
                      // A row you can open says so by being readable, not by a
                      // chevron: six chevrons down the left of a six-row card
                      // is a column of furniture over a column of data.
                      color: onTap == null ? null : c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: Space.xxs),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: Motion.fast,
                    curve: Motion.curve,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(child: _Bar(sets: row.sets, max: max, hue: hue)),
          const SizedBox(width: Space.sm),
          _Count(sets: row.sets),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkRow(onTap: onTap, ink: false, child: content);
  }
}

/// A region's own muscles, opened.
///
/// On `surfaceHigh` and indented, for the reason the bodyweight days are: a
/// child has to look like a child, or `Legs` and `Quads` in the same type on
/// the same ground read as two regions.
class _Parts extends StatelessWidget {
  const _Parts({required this.row, required this.max, required this.hue});

  final MuscleVolume row;
  final int max;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Space.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        children: [
          for (final part in row.parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: _nameWidth - Space.sm,
                    child: Text(
                      part.muscle.label,
                      style: context.t.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  // Against the same maximum as the rows above, not against the
                  // region's own total: a hamstring bar that fills its track
                  // because hamstrings were the biggest *part of legs* would
                  // say the opposite of what the fold was opened to find out.
                  // Its region's hue, not one of its own: the fold is the row
                  // opened, and four colours inside a green row would read as
                  // four new categories rather than as what legs is made of.
                  Expanded(
                    child: _Bar(
                      sets: part.sets,
                      max: max,
                      hue: hue,
                      height: 8,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  _Count(sets: part.sets, small: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The bar itself: the region's hue on a `surfaceHighest` track that always
/// shows its full width, so an untrained muscle is a row rather than a gap
/// (THEME rule 4).
///
/// That track and the heatmap's unworked day are the same grey: `heatEmpty` is
/// `surfaceHighest`, rather than the bars carrying a grey of their own. The two
/// graphics sit one above the other on this screen and are read as one
/// answer: a rest day and an untrained muscle are the same absence, and two
/// greys eight points apart say they are not.
///
/// Barely rounded (2), not pilled: six pill-ended bars stacked at 10pt read as
/// six lozenges of different lengths, and a full radius eats the short ones — a
/// one-set bar is about as wide as its own two end caps. 2 takes the mechanical
/// edge off without making the length hard to compare.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.sets,
    required this.max,
    required this.hue,
    this.height = 10,
  });

  final int sets;
  final int max;
  final Color hue;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fraction = max == 0 ? 0.0 : sets / max;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Stack(
        children: [
          Container(height: height, color: c.surfaceHighest),
          if (fraction > 0)
            FractionallySizedBox(
              widthFactor: fraction,
              child: AnimatedContainer(
                duration: Motion.base,
                curve: Motion.emphasized,
                height: height,
                color: hue,
              ),
            ),
        ],
      ),
    );
  }
}

/// `12` in `valueSm` with `sets` in `micro` beside it. A muscle trained zero
/// times prints `0 sets` rather than nothing at all.
class _Count extends StatelessWidget {
  const _Count({required this.sets, this.small = false});

  final int sets;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Wide enough for three digits and the word — a hundred sets a week is
      // not a real training week, but a number that overflows its box is a
      // striped bar across the card. Fixed, so every bar ends at the same x
      // whatever the counts are.
      width: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$sets',
            // Same size in both rows, parent and part — a column of counts is
            // one column, and a figure that shrinks halfway down it reads as a
            // different kind of number. The child says it is a child with
            // colour, which is what `small` is.
            style: small
                ? context.t.labelLarge?.copyWith(
                    color: context.c.textSecondary,
                  )
                : context.t.labelLarge,
          ),
          const SizedBox(width: Space.xxs),
          Text('sets', style: context.t.labelSmall),
        ],
      ),
    );
  }
}
