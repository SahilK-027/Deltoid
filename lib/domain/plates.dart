/// What to hang on each end of the bar to make a number.
///
/// Pure arithmetic, no database and no widgets: the gym is the one place this
/// app is read at arm's length with a bar in your hands, and "which plates" is
/// the question it has to answer without being wrong once.
library;

/// The plates assumed to exist, heaviest first.
///
/// Deliberately a fixed set rather than a per-gym inventory. This is one
/// person's log in one gym; a plate-inventory editor is a settings screen, a
/// migration and a maintenance burden to describe a rack that does not change.
/// If it ever does, this list is the only thing that moves.
const olympicPlatesKg = <double>[25, 20, 15, 10, 5, 2.5];

/// The smallest change these plates can make to a bar: the lightest plate, on
/// both ends. Nothing between two multiples of this is loadable.
final plateStepKg = olympicPlatesKg.last * 2;

/// One plate size and how many of it go on each end.
typedef PlateStack = ({double kg, int count});

/// How a target weight breaks down over a bar.
class PlateLoad {
  const PlateLoad({
    required this.barKg,
    required this.perSide,
    required this.remainderKg,
  });

  /// The empty bar.
  final double barKg;

  /// Plates for **one** end, heaviest first. Empty means an empty bar.
  final List<PlateStack> perSide;

  /// What the plates could not make, in kg of total load. Non-zero when the
  /// target is not a multiple of [plateStepKg] — a 2.5kg keypad step on a
  /// rack whose smallest plate is 2.5kg lands here every other press.
  ///
  /// Reported rather than rounded away: silently drawing 60kg when 61kg was
  /// typed would make the diagram a liar at the exact moment it is trusted.
  final double remainderKg;

  bool get isBarOnly => perSide.isEmpty;

  /// Total the drawn plates actually add up to, bar included.
  double get loadedKg =>
      barKg + perSide.fold(0.0, (sum, p) => sum + p.kg * p.count) * 2;

  /// One end's load, which is the number lifters say out loud
  /// ("a hundred a side").
  double get perSideKg => perSide.fold(0.0, (sum, p) => sum + p.kg * p.count);
}

/// Breaks [totalKg] down into bar plus plates, or null when there is nothing
/// to draw.
///
/// Null — not an empty load — for a target **under** the bar: an impossible
/// weight has no plate diagram, and drawing a bare bar for "I typed 15 on a
/// 20kg bar" would answer a question nobody asked.
///
/// The bar weight exactly is a load, and a drawn one: `isBarOnly`, no plates,
/// asserted by `an empty bar loads nothing`. This said "at or under" and meant
/// it about neither the code nor the test beneath it — the boundary is
/// `totalKg < barKg`.
///
/// Greedy from the heaviest plate down, which is both optimal for this set
/// (every plate divides the next one up, or is half of it) and what you
/// actually do at the rack: big ones first, and they go on inside.
PlateLoad? solvePlateLoad({
  required double totalKg,
  required double barKg,
  List<double> plates = olympicPlatesKg,
}) {
  if (barKg <= 0 || totalKg < barKg) return null;

  // Integer half-kilos of *total* load, not per side. Two reasons, and the
  // second one cost a red test: doubles leave 2.4999999999999996kg of
  // "unloadable" weight on a bar that loads exactly, and a per-side figure is
  // not always a whole number of half-kilos — 62.5kg on a 20kg bar is 21.25 a
  // side, which rounds to 21.5 and invents a kilo that is not on the bar.
  //
  // One plate goes on at both ends, so it spends `kg * 4` halves of total.
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
