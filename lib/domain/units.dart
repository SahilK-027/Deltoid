import 'dart:math' as math;

/// Which unit weights are shown and typed in.
///
/// Storage is always kilograms. Converting at the edges is the only safe
/// arrangement: a database holding mixed units silently breaks every
/// historical comparison the app is built on, and there is no way to tell
/// afterwards which rows meant what.
enum WeightUnit { kg, lb }

const kgPerLb = 0.45359237;

extension WeightUnitX on WeightUnit {
  String get label => switch (this) {
        WeightUnit.kg => 'kg',
        WeightUnit.lb => 'lb',
      };

  /// The plate step the keypad's ± keys move by, in display units.
  ///
  /// 2.5 kg is the smallest pair of plates on a kilo bar; 5 lb is its
  /// equivalent on a pound bar. Using 2.5 for both would be a step nobody's
  /// gym has.
  double get step => switch (this) {
        WeightUnit.kg => 2.5,
        WeightUnit.lb => 5,
      };

  /// What a displayed number is rounded to. Half a kilo is the smallest
  /// microplate in normal use; a pound is the equivalent granularity.
  double get increment => switch (this) {
        WeightUnit.kg => 0.5,
        WeightUnit.lb => 1,
      };

  double fromKg(double kg) => switch (this) {
        WeightUnit.kg => kg,
        WeightUnit.lb => kg / kgPerLb,
      };

  double toKg(double value) => switch (this) {
        WeightUnit.kg => value,
        WeightUnit.lb => value * kgPerLb,
      };

  /// A stored kg value as a display number, snapped to this unit's granularity
  /// so 100 kg reads as 220 lb rather than 220.46226218487757.
  double display(double kg) {
    final raw = fromKg(kg);
    return (raw / increment).roundToDouble() * increment;
  }

  static WeightUnit parse(String? name) => WeightUnit.values.firstWhere(
        (u) => u.name == name,
        orElse: () => WeightUnit.kg,
      );
}

/// Rounds a load to the granularity of [unit], in kg.
///
/// Deload scaling and any other computed weight goes through this, so a
/// suggestion is always a number you can actually load on a bar.
double roundLoadIn(double kg, WeightUnit unit) {
  if (unit == WeightUnit.kg) return (kg * 2).round() / 2;
  final lb = kg / kgPerLb;
  return lb.roundToDouble() * kgPerLb;
}

/// Trailing zeros are noise on a gym screen.
String formatInUnit(double kg, WeightUnit unit) {
  final v = unit.display(kg);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final rounded = (v * 100).round() / 100;
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// The move from [previousKg] to [kg], as it will actually be *shown* — or
/// null when both round to the same displayed figure.
///
/// Comparing the raw kilograms was wrong in the one direction that matters:
/// two weights 0.2 apart differ, so the row printed a signed delta, and then
/// formatting rounded it to the display increment and it came out as "+0". A
/// change too small for the app to show is not a change the app should claim.
String? formatDeltaInUnit(double kg, double previousKg, WeightUnit unit) {
  final difference = unit.display(kg) - unit.display(previousKg);
  if (difference.abs() < unit.increment / 2) return null;
  final magnitude = formatInUnit(unit.toKg(difference.abs()), unit);
  return '${difference > 0 ? '+' : '−'}$magnitude';
}

/// What a bodyweight is shown to, in display units.
///
/// Bodyweight is the one figure in the app that is not plates. Every other
/// weight rounds to [WeightUnitX.increment] because it has to be loadable on a
/// bar — half a kilo is the smallest microplate — but nobody loads
/// themselves. A scale reads a tenth, so typing 76.4 and being shown 76.5 was
/// the app telling you your own weight is wrong — twice over: once in the
/// figure, and again in the sheet, which prefilled the rounded number so
/// correcting anything else about the entry silently moved the weight.
const bodyweightIncrement = 0.1;

/// A stored bodyweight as a display number, to the tenth.
double displayBodyweight(double kg, WeightUnit unit) =>
    roundToDecimals(unit.fromKg(kg), 1);

/// As [formatInUnit], at bodyweight's precision. Trailing zeros still go: 76.0
/// reads `76`.
String formatBodyweight(double kg, WeightUnit unit) {
  final v = displayBodyweight(kg, unit);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

/// As [formatDeltaInUnit], at bodyweight's precision — and null for the same
/// reason: a difference too small to show is not a change to claim.
String? formatBodyweightDelta(double kg, double previousKg, WeightUnit unit) {
  final difference =
      displayBodyweight(kg, unit) - displayBodyweight(previousKg, unit);
  if (difference.abs() < bodyweightIncrement / 2) return null;
  final magnitude = formatBodyweight(unit.toKg(difference.abs()), unit);
  return '${difference > 0 ? '+' : '−'}$magnitude';
}

/// Smallest sensible display precision, used where a raw double would show
/// fifteen decimals of floating point noise.
double roundToDecimals(double v, int places) {
  final f = math.pow(10, places);
  return (v * f).round() / f;
}

/// Trailing zeros are noise on a gym screen: 22.5 stays 22.5, 60.0 becomes 60.
///
/// Takes a stored kilogram value and renders it in [unit]. Capped at two
/// decimals because this also formats *computed* numbers — an estimated 1RM is
/// an arbitrary double, and `55.733333333333334 kg` is not a weight anyone has
/// ever lifted.
///
/// [unit] is required on purpose. It was optional with a kilogram default for
/// exactly one commit, and in that commit two call sites forgot it and rendered
/// pounds as kilograms — next to a tooltip that had it right. An optional unit
/// makes "wrong" the thing that compiles.
String formatWeight(double kg, WeightUnit unit) {
  final v = unit.display(kg);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final rounded = (v * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
