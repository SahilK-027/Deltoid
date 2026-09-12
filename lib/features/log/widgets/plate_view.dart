import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/plates.dart';
import '../../../domain/units.dart';

/// Competition plate colours.
///
/// The one place in this app where a colour is not chosen — it is the colour
/// the plate physically is, which is the whole point of drawing it: you match
/// the screen to the rack without reading a number. Rule 1 holds anyway (colour
/// is data), and this is about as literal as data gets.
///
/// Kilo plates: 25 red, 20 blue, 15 yellow, 10 green, 5 white, 2.5 grey.
Color plateColor(BuildContext context, double kg) {
  final c = context.c;
  return switch (kg) {
    >= 25 => const Color(0xFFE03A3E),
    >= 20 => const Color(0xFF2F7BFF),
    >= 15 => const Color(0xFFF2C300),
    >= 10 => const Color(0xFF3FA35C),
    >= 5 => c.textPrimary,
    // Grey, not the competition red. In the drawing a red 2.5 was never
    // confused with the 25 — one is the tallest slab and the other the
    // shortest — but the list beside it shows each plate as a swatch of one
    // size, and two red squares side by side read as the same plate. Grey is
    // also what most gyms' change plates actually are: chrome or black.
    _ => c.textSecondary,
  };
}

/// How tall a plate is drawn, as a fraction of the tallest one.
///
/// Not linear in kilograms: a 2.5 next to a 25 would be a tenth of its height
/// and read as a rounding error rather than a plate. Compressed the way the
/// real ones are — a 2.5 is a third the diameter of a 25, not a tenth.
double _plateHeightFactor(double kg) => switch (kg) {
  >= 25 => 1.0,
  >= 20 => 0.94,
  >= 15 => 0.86,
  >= 10 => 0.74,
  >= 5 => 0.58,
  _ => 0.42,
};

/// What to draw for what is currently typed, or null for "draw nothing".
///
/// Null on every doubtful case rather than a diagram that might be wrong:
/// nothing typed yet, no bar on this movement, a weight under the bar, or a
/// display unit the plates do not exist in. The bar weight exactly is not a
/// doubtful case — it draws as a bare bar, which is what
/// [solvePlateLoad] returns for it. The rack is metric — 45s and
/// 25s are a different set of plates, and inventing a pound breakdown from
/// kilogram plates would put a diagram on screen that no gym can load.
PlateLoad? plateLoadFor({
  required String buffer,
  required double? barKg,
  required WeightUnit unit,
}) {
  if (barKg == null || unit != WeightUnit.kg) return null;
  final typed = double.tryParse(buffer);
  if (typed == null) return null;
  return solvePlateLoad(totalKg: unit.toKg(typed), barKg: barKg);
}

/// The bar, the plates for one side, and the bar's own weight, side by side.
///
/// Three columns, read left to right the way a bar is loaded: the drawing, a
/// list of what goes on one end, and the bar. Each plate in the list carries a
/// swatch in its own colour, so the list and the drawing are one picture read
/// twice rather than two things to reconcile. It replaced a single sentence —
/// `25 + 5 a side + 20 kg bar = 80 kg` — which had to be parsed like a formula
/// in the middle of a set. The sentence survives as the screen reader label,
/// where a sentence is what is wanted.
///
/// Sits above the keypad while a barbell weight is being typed — the moment the
/// question "what do I actually put on" is being asked.
/// THEME → Components → The numeric keypad.
class PlateView extends StatelessWidget {
  const PlateView({super.key, required this.load, required this.unit});

  final PlateLoad load;

  /// Only ever [WeightUnit.kg] today — see [plateLoadFor].
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // No panel behind it. A `surfaceSunken` slab on the keypad's `surface` read
    // as a black hole cut into the pad — a second container competing with the
    // keys for the eye, to hold what is really just a caption for them. It
    // shares the keypad's surface and is separated by air alone.
    //
    // It fades and rises the first time it is built, which is the frame the
    // weight becomes loadable. The builder runs on mount only: the widget is
    // created when there is a bar to draw and destroyed when there is not, so
    // typing another digit updates the numbers without replaying the entrance.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.base,
      curve: Motion.curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: child,
        ),
      ),
      child: Semantics(
        label: _sentence(load, unit),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top-aligned, as the reference does it: the bar's weight sits on
              // the line of the first plate rather than floating between two,
              // and a list of one plate starts where a list of two would. An
              // empty bar has no first plate to line up with, so its weight
              // centres on the drawing instead of riding above the sleeve.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: load.isBarOnly
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    _BarDiagram(load: load),
                    const SizedBox(width: Space.lg),
                    // No label over the list. The drawing is one end of the bar,
                    // which already says "each side", and a caption made the
                    // list taller than the drawing it sits beside.
                    //
                    // An empty bar has no list to show, so there is none: the
                    // bar's weight moves up beside the drawing rather than
                    // sitting behind a column that says there is nothing.
                    if (!load.isBarOnly) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Two rows to a column. A third kind of plate starts a
                          // second column beside the first rather than a third
                          // row: three stacked lines made the view taller than
                          // the drawing and pushed the keypad down for one row.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < load.perSide.length; i += 2) ...[
                                if (i > 0) const SizedBox(width: Space.lg),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final stack
                                        in load.perSide.skip(i).take(2))
                                      _PlateLine(stack: stack, unit: unit),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: Space.lg),
                      Container(width: 1, color: c.border),
                      const SizedBox(width: Space.lg),
                    ],
                    // One line, read as one phrase — `20 kg bar` — rather
                    // than a figure over a caption, which made the bar as tall
                    // as the plate list for a single fact.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        ValueUnit(
                          value: formatInUnit(load.barKg, unit),
                          unit: unit.label,
                          dense: true,
                        ),
                        const SizedBox(width: Space.xs),
                        Text('bar', style: context.t.bodyMedium),
                      ],
                    ),
                  ],
                ),
              ),
              if (load.remainderKg > 0) ...[
                const SizedBox(height: Space.md),
                const Divider(),
                const SizedBox(height: Space.sm),
                // Never silently rounded: the diagram would otherwise show a
                // bar that is not the weight in the field.
                //
                // Grey, not red. It is not an error — the rack simply has no
                // plate that small — and it is said per side, because a side is
                // what you load and the number you would go looking for.
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        '${_fmt(load.remainderKg / 2, unit)} ${unit.label} '
                        'each side has no plate',
                        style: context.t.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The whole load as one sentence, in the order you load a bar: what goes on
  /// each side, then the bar, then the total. Read aloud rather than shown.
  static String _sentence(PlateLoad load, WeightUnit unit) {
    final u = unit.label;
    final short = load.remainderKg > 0
        ? '. ${_fmt(load.remainderKg / 2, unit)} $u each side has no plate'
        : '';
    if (load.isBarOnly) {
      return 'Empty bar, ${_fmt(load.barKg, unit)} $u$short';
    }
    final each = load.perSide
        .map(
          (p) => p.count == 1
              ? _fmt(p.kg, unit)
              : '${p.count} times ${_fmt(p.kg, unit)}',
        )
        .join(' and ');
    return '$each each side, on a ${_fmt(load.barKg, unit)} $u bar, '
        '${_fmt(load.loadedKg, unit)} $u in all$short';
  }

  static String _fmt(double kg, WeightUnit unit) => formatInUnit(kg, unit);
}

/// One row of the plate list: a swatch in the plate's colour, then how many.
class _PlateLine extends StatelessWidget {
  const _PlateLine({required this.stack, required this.unit});

  final PlateStack stack;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // As tall as the digits beside it, and square-cornered like a bar in a
        // chart: at 12pt with a softer corner it read as a dot rather than as
        // the plate it stands for.
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: plateColor(context, stack.kg),
            borderRadius: BorderRadius.circular(Radii.bar),
            // The same hairline the drawn plate carries, for the same reason:
            // the 5 kg swatch would otherwise vanish on a light surface.
            border: Border.all(color: c.border, width: 0.5),
          ),
        ),
        const SizedBox(width: Space.sm),
        Text(
          '${stack.count} × ${formatInUnit(stack.kg, unit)}',
          style: context.t.labelLarge,
        ),
      ],
    );
  }
}

/// The bar itself: sleeve, plates outward from the collar, one end only.
///
/// One end, not both. A symmetrical diagram spends double the width to say
/// nothing new — you load both ends the same, and the sentence beside it
/// already says "a side".
class _BarDiagram extends StatelessWidget {
  const _BarDiagram({required this.load});

  final PlateLoad load;

  static const _height = 44.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The sleeve, running off to the left where the other half of the
          // bar would be.
          Container(
            width: 10,
            height: 4,
            decoration: BoxDecoration(
              color: c.textTertiary,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
          // The collar.
          Container(width: 3, height: 14, color: c.textSecondary),
          for (final stack in load.perSide)
            for (var i = 0; i < stack.count; i++)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: _Plate(kg: stack.kg),
              ),
        ],
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({required this.kg});

  final double kg;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = plateColor(context, kg);

    return Container(
      width: 7,
      height: _BarDiagram._height * _plateHeightFactor(kg),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        // The 5kg plate is white, and white on a light theme's surface is an
        // invisible plate. A hairline in the text colour keeps every slab a
        // slab in both themes.
        border: Border.all(color: c.border, width: 0.5),
      ),
    );
  }
}
