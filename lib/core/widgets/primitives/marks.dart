part of '../primitives.dart';

// ─── Marks ──────────────────────────────────────────────────────────────────

/// A rounded square holding one icon, tinted to an identity colour. The mark
/// that lets a history list be scanned rather than read.
///
/// Reserved for identities (a regime, a session). A row's ordinary leading
/// glyph is bare — see [AppRow].
class IconTile extends StatelessWidget {
  const IconTile(
    this.icon, {
    super.key,
    required this.color,
    this.size = 44,
    this.solid = true,
    this.glyph,
  });

  final IconData icon;

  /// Overrides the glyph's colour, for a tile whose fill is chrome rather
  /// than a hue: the Phase card's `surfaceHigh` tile, whose glyph is
  /// `textPrimary` because a phase is not an identity (THEME → Phase card).
  final Color? glyph;

  /// Required rather than defaulted. A tile's colour is what it means, and a
  /// default would be a meaning no caller chose: every tile reached for one
  /// explicitly anyway, and the blue it fell back to is now progress.
  final Color color;
  final double size;

  /// Filled in [color] with the glyph knocked out. Off gives a tinted wash for
  /// a mark that must not outshout its row.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final tint = color;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: solid ? tint : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: glyph ?? (solid ? glyphOn(tint) : tint),
      ),
    );
  }

  /// The glyph takes the fill's own hue, darkened, rather than white or
  /// black.
  ///
  /// White breaks outright on a saturated yellow (1.9:1), and near-black fixes
  /// the ratio at the cost of the point: a tile is one colour with a shape cut
  /// out of it, and a black shape makes it two. Same hue, same saturation, less
  /// light — the mark stays "the green one" at arm's length, which is the only
  /// job it has.
  ///
  /// Solved rather than multiplied. A fixed `× 0.4` lands between 2.9:1 and
  /// 3.7:1 depending on where a hue sits, which is the uneven-set problem again
  /// one level down. This walks the lightness down until the glyph clears
  /// [_glyphContrast] against its own fill, so every tile in both themes reads
  /// at the same strength.
  static Color glyphOn(Color fill) {
    final hsl = HSLColor.fromColor(fill);
    for (var l = hsl.lightness; l >= 0.04; l -= 0.01) {
      final candidate = hsl.withLightness(l).toColor();
      if (_contrast(candidate, fill) >= _glyphContrast) return candidate;
    }
    // An almost-black fill has no room left below it: go up instead, which is
    // the same rule read the other way.
    for (var l = hsl.lightness; l <= 0.96; l += 0.01) {
      final candidate = hsl.withLightness(l).toColor();
      if (_contrast(candidate, fill) >= _glyphContrast) return candidate;
    }
    return hsl.withLightness(0.04).toColor();
  }

  /// Enough to name the shape at 22pt, not so much that the tile reads as two
  /// colours. 3:1 is the floor for a graphic; this sits just above it.
  static const _glyphContrast = 3.2;

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// The radio from THEME → Components: selected is a filled disc with a dark
/// dot punched out of it,
/// unselected a 2px ring in `textTertiary`. No accent hue, and no Material
/// `Radio`, whose ripple and 48pt slop belong to a different design language.
///
/// It is the trailing control of an [AppRow] — a list of rows that are one
/// choice each, where a [SegmentedPill] would put three words in a track and
/// lose the room to say what each one means.
/// A trailing figure on a row, in the value size with the row's own chevron
/// after it.
///
/// Shared because three screens want the same trailing slot — an exercise's
/// fields, and Settings' unit and rest rows — and a hand-rolled `Row` that
/// looks like one drifts off the others within a week, which is the argument
/// THEME makes for section headers and holds here for the same reason.
class RowValue extends StatelessWidget {
  const RowValue(this.text, {super.key}) : pending = false;

  /// An unanswered question, while a new exercise is being drafted: the word
  /// `Choose` in `textTertiary` where the value will go. Not a dash — a dash is
  /// for a measurement that should exist and doesn't (rule 4), and this is a
  /// question awaiting an answer.
  const RowValue.orChoose(String? value, {super.key})
      : text = value ?? 'Choose',
        pending = value == null;

  /// A value the row states and does not let you change: the figure in
  /// `textTertiary`, the ink of something that is not an answer of yours. The
  /// chevron stays, because the row still opens a sheet that says why.
  const RowValue.fixed(this.text, {super.key}) : pending = true;

  final String text;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            style: pending
                ? context.t.labelLarge?.copyWith(color: context.c.textTertiary)
                : context.t.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Space.sm),
        Icon(Icons.chevron_right_rounded,
            size: 18, color: context.c.textTertiary),
      ],
    );
  }
}

class AppRadio extends StatelessWidget {
  const AppRadio({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.curve,
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.accent : Colors.transparent,
        border: Border.all(
          color: selected ? c.accent : c.textTertiary,
          width: 2,
        ),
      ),
      child: selected
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.onAccent,
              ),
            )
          : null,
    );
  }
}

/// One number and what it means. Built for a row of siblings, so captions line
/// up across tiles even when one wraps.
/// Rule 5 expressed as a widget: a value with its unit beside it, one step
/// down and
/// in grey, sharing a baseline.
///
/// Hand-built, it is built seven ways — the summary's rows, the bodyweight
/// header, Today's elapsed clock, two volume widgets — each deciding for itself
/// whether the unit is `bodyMedium` or `bodySmall` and whether the pair shares
/// a baseline or a centre line. The rule is THEME → Value and unit; this is the
/// one place that implements it.
///
/// [dense] is the row form: `labelLarge` against a trailing edge, where the
/// page form is `displaySmall` and is the number a card is about.
class ValueUnit extends StatelessWidget {
  const ValueUnit({
    super.key,
    required this.value,
    this.unit,
    this.dense = false,
    this.emphasis,
    this.shrinkToFit = false,
  });

  final String value;

  /// Null where the value has no unit — a count of sets, a session name.
  final String? unit;

  /// The row form, for a value trailing an `AppRow` rather than heading a card.
  final bool dense;

  /// Paints the value. Only for a semantic reading — a record, a deload.
  final Color? emphasis;

  /// Sets the pair smaller, value and unit together, when it does not fit its
  /// width, rather than ellipsizing the value. For a figure in a row of
  /// siblings, where a third of a phone at a 1.3 font cut `+181.7%` to
  /// `+181.…`: a number missing its end is a different number.
  final bool shrinkToFit;

  @override
  Widget build(BuildContext context) {
    final valueStyle = dense ? context.t.labelLarge : context.t.displaySmall;
    if (shrinkToFit) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: valueStyle?.copyWith(color: emphasis)),
            if (unit != null) ...[
              const SizedBox(width: Space.xs),
              Text(unit!, style: context.t.bodyMedium),
            ],
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            value,
            style: valueStyle?.copyWith(color: emphasis),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: Space.xs),
          Text(unit!, style: context.t.bodyMedium),
        ],
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.emphasis,
    this.unit,
  });

  final String value;
  final String label;

  /// Trails the value at body size — `kg` is never set in the value size.
  final String? unit;

  /// Paints the value. Only for a semantic reading (a record, a deload).
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueUnit(
          value: value,
          unit: unit,
          emphasis: emphasis,
          shrinkToFit: true,
        ),
        const SizedBox(height: Space.xxs),
        Text(label, style: context.t.bodySmall, maxLines: 2),
      ],
    );
  }
}

/// [StatTile]s side by side, sharing the width equally, `Space.md` apart.
///
/// A row of figures under a chart is one component, not a `Row` written per
/// card. Written per card, the tiles met edge to edge, and at a 1.3 font in a
/// card their labels ran into each other: `Best est. 1RMChange`.
///
/// Start-aligned and nothing else, for the reason THEME gives the stat tile:
/// every tile is the same shape, so the row needs no measuring. [trailing],
/// a chevron where the row opens something, sits after the last tile.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.children, this.trailing});

  final List<Widget> children;
  final Widget? trailing;

  /// The gap between two figures in a row (THEME → Charts).
  static const gap = Space.md;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: gap),
          Expanded(child: child),
        ],
        // Beside the figures rather than their labels, which is the line the
        // row is read by.
        if (trailing case final t?)
          Padding(padding: const EdgeInsets.only(top: Space.xs), child: t),
      ],
    );
  }
}

/// Small status pill. Tinted, never filled, unless it is the one live state on
/// the screen.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon, this.solid = false});

  final String text;
  final Color? color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = color ?? c.textSecondary;
    final fg = solid ? c.onAccent : tint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? tint : tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: Space.xs),
          ],
          Text(text, style: context.t.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// A [Pill] that shows only its icon until tapped, then names itself.
///
/// For a list where the same status repeats down many rows: History's deload
/// rows, where the word beside every light day is the same word and the tile's
/// orange already marks the row. A tap opens [text] beside the icon, holds it
/// for [hold], and folds it back; a second tap restarts the hold.
///
/// The label grows with an [AnimatedSize] at [Motion.base], and appears
/// without it when the platform asks for reduced motion. The timer
/// is cancelled on dispose, so a row scrolled away mid-hold leaves nothing
/// running. A screen reader hears [text] whether or not it is showing.
///
/// The tap target is 40 wide and as tall as the line it sits on: taller would
/// make a row holding one taller than its neighbours. It claims the tap, so a
/// tap on the icon does not also open the row under it.
class RevealPill extends StatefulWidget {
  const RevealPill(
    this.text, {
    super.key,
    required this.icon,
    required this.color,
    this.hold = const Duration(seconds: 2),
  });

  final String text;
  final IconData icon;
  final Color color;
  final Duration hold;

  @override
  State<RevealPill> createState() => _RevealPillState();
}

class _RevealPillState extends State<RevealPill> {
  bool _open = false;
  Timer? _close;

  void _reveal() {
    _close?.cancel();
    setState(() => _open = true);
    _close = Timer(widget.hold, () {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, size: 14, color: widget.color),
        if (_open) ...[
          const SizedBox(width: Space.xs),
          Text(
            widget.text,
            style: context.t.labelSmall?.copyWith(color: widget.color),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
    return Semantics(
      label: widget.text,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _reveal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 40),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              // No `AnimatedSize` at all under reduced motion, rather than one
              // with a zero duration, which asserts as it relays itself out.
              child: still
                  ? content
                  : AnimatedSize(
                      duration: Motion.base,
                      curve: Motion.curve,
                      alignment: Alignment.centerLeft,
                      child: content,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A day drawn as a calendar page: the weekday on a strip of [hue], the day of
/// the month large below it.
///
/// History's leading tile. The bolt it replaced was the same glyph on every
/// row, so it said nothing; a date is what the list is scanned for. [hue] is
/// `progress` for a trained day and `deload` for a light one, the two colours
/// every other trained-day mark in the app uses, and the weekday is drawn in
/// the hue taken down ([IconTile.glyphOn]) so it reads in both themes, where
/// the hues are fills and never text.
///
/// A fixed size, so a column of them lines up whatever each row holds. The
/// caller formats [day] and [weekday]: turning a date into words is domain
/// work, not a widget's.
class DateTile extends StatelessWidget {
  const DateTile({
    super.key,
    required this.day,
    required this.weekday,
    required this.hue,
  });

  final String day;
  final String weekday;
  final Color hue;

  static const width = 50.0;
  static const pageHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // No binder tabs above the page. Grey pins on a coloured strip read as
    // clutter at this size, and the strip and the date say "calendar page"
    // on their own.
    return SizedBox(
      width: width,
      height: pageHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.control - 2),
        child: ColoredBox(
          color: c.surfaceHigh,
          child: Column(
            children: [
              Container(
                height: 20,
                width: double.infinity,
                color: hue,
                alignment: Alignment.center,
                child: Text(
                  weekday,
                  maxLines: 1,
                  style: context.t.labelSmall?.copyWith(
                    color: IconTile.glyphOn(hue),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: context.t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The compact pill (THEME → Buttons): 36 tall, radius 999, `surfaceHigh`,
/// `label` text.
///
/// Without [onTap] it is a fact in a pill's shape, the Phase card's
/// `Week 7 of 12`, and opens nothing.
class CompactPill extends StatelessWidget {
  const CompactPill(this.text, {super.key, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        text,
        style: context.t.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (onTap == null) return pill;
    return Pressable(onTap: onTap, scale: 0.96, child: pill);
  }
}

/// A figure and the figure derived from it, inside a ring that is filled to a
/// share.
///
/// The log's bodyweight pill: `73.2 kg` over `+69.5 kg (95%)`, in a capsule
/// whose outline is drawn in [hue] for [fraction] of the way round and left as
/// track for the rest. The gap sits at the top centre, so 95 per cent reads as
/// a ring with a small piece missing rather than as a line that stops
/// somewhere. A ring rather than a fill, because the two lines inside it are
/// numbers to be read and a tinted ground behind them would cost the smaller
/// one its contrast.
class FigurePill extends StatelessWidget {
  const FigurePill({
    super.key,
    required this.figure,
    required this.detail,
    required this.hue,
    this.fraction = 1,
    this.onTap,
    this.semanticLabel,
  });

  final String figure;
  final String detail;
  final Color hue;

  /// How much of the ring is drawn in [hue], from 0 to 1.
  final double fraction;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// The ring's stroke: the weight of the app's other outlines, a focused
  /// field and a selected card, so a pill 40 tall is not carrying a heavier
  /// line than a field 48 tall.
  static const ringWidth = 2.0;

  /// As tall as the [CircleIconButton]s it sits beside in a header, so the
  /// three read as one row of controls.
  static const height = 40.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: CustomPaint(
          painter: _RingPainter(
            hue: hue,
            track: c.surfaceHigh,
            fraction: fraction,
          ),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // `label` over `micro`: the two rungs whose line heights, 16
                // and 14, fit inside the ring at the height of a button.
                Text(
                  figure,
                  maxLines: 1,
                  style: context.t.bodySmall?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  style: context.t.labelSmall?.copyWith(
                    color: c.textSecondary,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The capsule outline of a [FigurePill]: a full track, and over it the part
/// of the way round that [fraction] covers.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.hue,
    required this.track,
    required this.fraction,
  });

  final Color hue;
  final Color track;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const w = FigurePill.ringWidth;
    final rect = (Offset.zero & size).deflate(w / 2);
    if (rect.width <= 0 || rect.height <= 0) return;
    final r = rect.height / 2;

    // Drawn by hand from the top centre, clockwise, so that the start of the
    // path is where the gap belongs. `addRRect` starts wherever the engine
    // starts it, which is not a thing to measure a gap from.
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(
        Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
      ..close();

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;

    canvas.drawPath(path, stroke..color = track);

    final share = fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction);
    if (share == 0) return;
    if (share == 1) {
      canvas.drawPath(path, stroke..color = hue);
      return;
    }
    for (final metric in path.computeMetrics()) {
      // The missing piece is centred on the top, half of it either side of
      // where the path begins.
      final gap = metric.length * (1 - share);
      canvas.drawPath(
        metric.extractPath(gap / 2, metric.length - gap / 2),
        stroke..color = hue,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.hue != hue || old.track != track || old.fraction != fraction;
}
