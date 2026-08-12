import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/plates.dart';
import '../../../domain/units.dart';

/// Competition plate colours.
///
/// The one place in this app where a colour is not chosen — it is the colour
/// the plate physically is, which is the whole point of drawing it: you match
/// the screen to the rack without reading a number. Rule 1 holds anyway (colour
/// is data), and this is about as literal as data gets.
///
/// Kilo plates: 25 red, 20 blue, 15 yellow, 10 green, 5 white, 2.5 red.
Color plateColor(BuildContext context, double kg) {
  final c = context.c;
  return switch (kg) {
    >= 25 => const Color(0xFFE03A3E),
    >= 20 => const Color(0xFF2F7BFF),
    >= 15 => const Color(0xFFF2C300),
    >= 10 => const Color(0xFF3FA35C),
    >= 5 => c.textPrimary,
    // The 2.5 is red like the 25 in IWF, and at this size the pair are never
    // confusable: one is the tallest slab on the bar and the other the
    // shortest.
    _ => const Color(0xFFE03A3E),
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
/// nothing typed yet, no bar on this movement, a weight at or under the bar,
/// or a display unit the plates do not exist in. The rack is metric — 45s and
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

/// The bar, what is on it, and one sentence saying so.
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _BarDiagram(load: load),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sentence(load, unit),
                    style: context.t.bodySmall?.copyWith(color: c.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (load.remainderKg > 0) ...[
                    const SizedBox(height: Space.xxs),
                    // Never silently rounded: the diagram would otherwise show a
                    // bar that is not the weight in the field.
                    Text(
                      '${_fmt(load.remainderKg, unit)} '
                      '${unit.label} short, with no plate for it',
                      style: context.t.labelSmall?.copyWith(color: c.deload),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The plain sentence the keypad spec asks for, in the order you load a bar:
  /// what goes on each side, then the bar, then the total.
  static String _sentence(PlateLoad load, WeightUnit unit) {
    final u = unit.label;
    if (load.isBarOnly) {
      return 'Empty bar, ${_fmt(load.barKg, unit)} $u';
    }
    final each = load.perSide
        .map(
          (p) => p.count == 1
              ? _fmt(p.kg, unit)
              : '${p.count}×${_fmt(p.kg, unit)}',
        )
        .join(' + ');
    return '$each a side  +  ${_fmt(load.barKg, unit)} $u bar  '
        '=  ${_fmt(load.loadedKg, unit)} $u';
  }

  static String _fmt(double kg, WeightUnit unit) => formatInUnit(kg, unit);
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
