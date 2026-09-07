/// Calculation of the plates required on each end of a bar for a target weight.
///
/// Pure arithmetic, with no database or widget dependencies. This is read at
/// arm's length while loading a bar, and must not produce an incorrect
/// result.
library;

/// The plates assumed to exist, heaviest first.
///
/// Deliberately a fixed set rather than a configurable inventory. A
/// plate-inventory editor would require a settings screen, a migration and
/// ongoing maintenance in order to describe a rack that does not change. Should
/// it change, this list is the only definition that requires updating.
const olympicPlatesKg = <double>[25, 20, 15, 10, 5, 2.5];

/// The smallest increment these plates can add to a bar: the lightest plate on
/// both ends. No weight between two multiples of this value is loadable.
final plateStepKg = olympicPlatesKg.last * 2;

/// A single plate size and the quantity required on each end.
typedef PlateStack = ({double kg, int count});

/// The decomposition of a target weight into a bar and its plates.
class PlateLoad {
  const PlateLoad({
    required this.barKg,
    required this.perSide,
    required this.remainderKg,
  });

  /// The empty bar.
  final double barKg;

  /// The plates for one end, heaviest first. An empty list denotes a bare
  /// bar.
  final List<PlateStack> perSide;

  /// The portion of the total load the plates cannot produce, in kilograms.
  ///
  /// Non-zero when the target is not a multiple of [plateStepKg]. A 2.5 kg
  /// keypad increment against a rack whose smallest plate is 2.5 kg produces a
  /// remainder on alternate presses.
  ///
  /// Reported rather than silently rounded. Rendering 60 kg for an entered
  /// 61 kg would make the diagram inaccurate at the moment it is relied upon.
  final double remainderKg;

  bool get isBarOnly => perSide.isEmpty;

  /// The total weight the rendered plates produce, including the bar.
  double get loadedKg =>
      barKg + perSide.fold(0.0, (sum, p) => sum + p.kg * p.count) * 2;

  /// The load on one end, which is the figure conventionally quoted
  /// ("a hundred a side").
  double get perSideKg => perSide.fold(0.0, (sum, p) => sum + p.kg * p.count);
}

/// Decomposes [totalKg] into a bar and its plates, returning null when there is
/// nothing to render.
///
/// Returns null, rather than an empty load, for a target below the bar weight.
/// An unattainable weight has no plate diagram, and rendering a bare bar for a
/// 15 kg target on a 20 kg bar would answer a question that was not asked.
///
/// A target equal to the bar weight is a valid load and is rendered as such:
/// `isBarOnly`, with no plates, as asserted by `an empty bar loads nothing`.
/// The boundary condition is `totalKg < barKg`.
///
/// The algorithm is greedy from the heaviest plate down. This is optimal for
/// this plate set, in which each plate divides or halves the next, and it
/// matches loading practice, where the heaviest plates are placed innermost.
PlateLoad? solvePlateLoad({
  required double totalKg,
  required double barKg,
  List<double> plates = olympicPlatesKg,
}) {
  if (barKg <= 0 || totalKg < barKg) return null;

  // Integer half-kilograms of total load rather than per-side load, for two
  // reasons. Floating-point arithmetic leaves 2.4999999999999996 kg of
  // apparently unloadable weight on a bar that loads exactly, and a per-side
  // figure is not always a whole number of half-kilograms: 62.5 kg on a 20 kg
  // bar is 21.25 per side, which rounds to 21.5 and introduces a kilogram that
  // is not present.
  //
  // A plate is placed on both ends, so it consumes `kg * 4` half-kilograms of
  // the total.
  var remainingHalves = ((totalKg - barKg) * 2).round();
  final perSide = <PlateStack>[];

  for (final plate in plates) {
    final halvesPerPair = (plate * 4).round();
    final count = remainingHalves ~/ halvesPerPair;
    if (count == 0) continue;
    perSide.add((kg: plate, count: count));
    remainingHalves -= count * halvesPerPair;
  }

  return PlateLoad(
    barKg: barKg,
    perSide: perSide,
    remainderKg: remainingHalves / 2,
  );
}
