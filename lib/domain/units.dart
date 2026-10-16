import 'dart:math' as math;

/// The unit in which weights are displayed and entered.
///
/// Storage is always in kilograms, with conversion performed at the
/// presentation boundary. A database holding mixed units would silently
/// invalidate every historical comparison the application performs, with no way
/// to determine afterwards which unit a given row used.
enum WeightUnit { kg, lb }

const kgPerLb = 0.45359237;

extension WeightUnitX on WeightUnit {
  String get label => switch (this) {
        WeightUnit.kg => 'kg',
        WeightUnit.lb => 'lb',
      };

  /// The increment applied by the keypad's plus and minus keys, in display
  /// units.
  ///
  /// 2.5 kg is the smallest pair of plates on a kilogram bar, and 5 lb is the
  /// equivalent on a pound bar. Applying 2.5 to both would produce an increment
  /// that matches no standard plate set.
  double get step => switch (this) {
        WeightUnit.kg => 2.5,
        WeightUnit.lb => 5,
      };

  /// The granularity to which a displayed number is rounded.
  ///
  /// Half a kilogram is the smallest microplate in common use, and one pound is
  /// the equivalent granularity.
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

  /// Converts a stored kilogram value to a display number, rounded to this
  /// unit's granularity so that 100 kg is rendered as 220 lb rather than
  /// 220.46226218487757.
  double display(double kg) {
    final raw = fromKg(kg);
    return (raw / increment).roundToDouble() * increment;
  }

  static WeightUnit parse(String? name) => WeightUnit.values.firstWhere(
        (u) => u.name == name,
        orElse: () => WeightUnit.kg,
      );
}

/// Rounds a load to the granularity of [unit], in kilograms.
///
/// Deload scaling and every other computed weight is passed through this
/// function, so that a suggested weight is always one that can be loaded on a
/// bar.
double roundLoadIn(double kg, WeightUnit unit) {
  if (unit == WeightUnit.kg) return (kg * 2).round() / 2;
  final lb = kg / kgPerLb;
  return lb.roundToDouble() * kgPerLb;
}

/// Formats a stored kilogram value in [unit], omitting trailing zeros.
String formatInUnit(double kg, WeightUnit unit) {
  final v = unit.display(kg);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final rounded = (v * 100).round() / 100;
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Formats the change from [previousKg] to [kg] as it will be displayed, or
/// null when both values round to the same displayed figure.
///
/// The comparison is performed on displayed values rather than raw kilograms.
/// Two weights 0.2 kg apart differ numerically, so a raw comparison would emit
/// a signed delta which formatting then rounds to the display increment,
/// producing "+0". A change too small to display is not a change the
/// application should report.
String? formatDeltaInUnit(double kg, double previousKg, WeightUnit unit) {
  final difference = unit.display(kg) - unit.display(previousKg);
  if (difference.abs() < unit.increment / 2) return null;
  final magnitude = formatInUnit(unit.toKg(difference.abs()), unit);
  return '${difference > 0 ? '+' : '−'}$magnitude';
}

/// The display granularity for bodyweight, in display units.
///
/// Bodyweight is the one figure in the application that does not describe
/// plates. Every other weight is rounded to [WeightUnitX.increment] because it
/// must be loadable on a bar, half a kilogram being the smallest microplate.
/// Scales read to a tenth, so an entered 76.4 displayed as 76.5 would
/// contradict the entered value twice: once in the figure itself, and again in
/// the entry sheet, which prefills the rounded value, so that correcting any
/// other field would silently alter the weight.
const bodyweightIncrement = 0.1;

/// Converts a stored bodyweight to a display number, to one decimal place.
double displayBodyweight(double kg, WeightUnit unit) =>
    roundToDecimals(unit.fromKg(kg), 1);

/// As [formatInUnit], at bodyweight precision. Trailing zeros are omitted, so
/// 76.0 is rendered as `76`.
String formatBodyweight(double kg, WeightUnit unit) {
  final v = displayBodyweight(kg, unit);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

/// As [formatDeltaInUnit], at bodyweight precision. Returns null for the same
/// reason: a difference too small to display is not a change to report.
String? formatBodyweightDelta(double kg, double previousKg, WeightUnit unit) {
  final difference =
      displayBodyweight(kg, unit) - displayBodyweight(previousKg, unit);
  if (difference.abs() < bodyweightIncrement / 2) return null;
  final magnitude = formatBodyweight(unit.toKg(difference.abs()), unit);
  return '${difference > 0 ? '+' : '−'}$magnitude';
}

/// A change in bodyweight of [kg], signed, at bodyweight precision.
///
/// For a figure that is itself a change rather than the gap between two
/// readings: the Phase card's `Since start` and `Each week`. The minus is a
/// true minus, as in [formatBodyweightDelta]. A change that rounds to nothing
/// prints `0`, because unlike a delta beside a reading, this figure stands on
/// its own and must say something.
String formatBodyweightChange(double kg, WeightUnit unit) {
  final v = roundToDecimals(unit.fromKg(kg), 1);
  if (v.abs() < bodyweightIncrement / 2) return '0';
  final magnitude = v.abs() == v.abs().roundToDouble()
      ? v.abs().toStringAsFixed(0)
      : v.abs().toStringAsFixed(1);
  return '${v > 0 ? '+' : '−'}$magnitude';
}

/// Rounds [v] to [places] decimal places.
///
/// Used where a raw double would otherwise render fifteen decimal places of
/// floating-point error.
double roundToDecimals(double v, int places) {
  final f = math.pow(10, places);
  return (v * f).round() / f;
}

/// Renders a stored kilogram value in [unit], omitting trailing zeros, so that
/// 22.5 remains 22.5 and 60.0 becomes 60.
///
/// Capped at two decimal places because this also formats computed values. An
/// estimated one-rep maximum is an arbitrary double, and `55.733333333333334
/// kg` is not a meaningful weight.
///
/// [unit] is required rather than defaulting to kilograms. A default is
/// straightforward to omit accidentally, which renders pounds as kilograms; a
/// required parameter makes the incorrect call fail to compile.
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
