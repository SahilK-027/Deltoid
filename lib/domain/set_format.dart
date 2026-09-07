/// How a logged set reads as text, in the three shapes the app needs.
///
/// Defined once rather than per feature. Duplicated implementations diverge
/// without detection: one screen may select a day's top set by weight even for
/// a hold, while another selects by duration, so the same set is reported
/// differently on two screens that each claim to print the same figure.
///
/// These functions accept plain values rather than a database row. Every file
/// in `lib/domain/` takes the numbers rather than the `SetLog` carrying them,
/// which is what allows them to be tested without a database (RULES § 4).
/// Callers unpack the row.
library;

import 'enums.dart';
import 'metrics.dart';
import 'units.dart';

/// Formats a set's load in full: `82.5 kg`, `22.5 kg each` for a pair of
/// dumbbells, `Bodyweight`, `BW + 10 kg`, or a dash when no load was recorded.
///
/// The `×` symbol is deliberately not used here. Everywhere else the
/// application prints a set it denotes "for this many reps", so applying it to
/// a pair of dumbbells would produce `20 kg × 2 × 10`: a single string
/// containing two multiplication signs with two different meanings and nothing
/// to distinguish them.
///
/// The dash follows rule 4: a set with no recorded weight is an absence rather
/// than a zero.
String loadLabel({
  required LoadMode? loadMode,
  required double? weight,
  required double? addedWeight,
  required WeightUnit unit,

  /// Whether a pair of dumbbells is spelled out as `each`.
  ///
  /// Enabled by default, because a bare `20 kg` against a per-hand movement is
  /// ambiguous as to whether it denotes the weight of one dumbbell or the total
  /// moved.
  ///
  /// Disabled where the surrounding surface has already stated which applies.
  /// The exercise sheet renders "The weight you type is per hand, and two are
  /// moving" two rows beneath the sets it lists, so the suffix would restate
  /// what has just been read, using an `×` that carries a different meaning in
  /// the adjacent format.
  bool pair = true,
}) {
  if (loadMode == LoadMode.bodyweight) return 'Bodyweight';
  if (loadMode == LoadMode.bodyweightPlus) {
    return addedWeight == null || addedWeight == 0
        ? 'Bodyweight'
        : 'BW + ${formatWeight(addedWeight, unit)} ${unit.label}';
  }
  if (weight == null) return '—';
  final perSide = pair && loadMode == LoadMode.perSide ? ' each' : '';
  return '${formatWeight(weight, unit)} ${unit.label}$perSide';
}

/// The same load with what was done against it: `82.5 kg × 8`,
/// `22.5 kg each × 8`, `Bodyweight × 12`, `1:30` for a hold that carried no
/// load.
///
/// Contains a single `×`, which denotes reps. Implemented in terms of
/// [loadLabel] rather than duplicating it, so that the load is rendered
/// identically here and everywhere else the application prints one.
String loadWithCount({
  required LoadMode? loadMode,
  required MeasureMode measureMode,
  required double? weight,
  required double? addedWeight,
  required int? reps,
  int? partialReps,
  required WeightUnit unit,
}) {
  final count = formatCount(reps, measureMode, partial: partialReps);
  final load = loadLabel(
    loadMode: loadMode,
    weight: weight,
    addedWeight: addedWeight,
    unit: unit,
  );
  // Nothing was on the bar: the count is the whole story, and a dash with a
  // count hung off it says less than the count alone.
  if (load == '—') return measureMode.isHold ? count : '$count reps';
  return '$load × $count';
}

/// Compressed, for a dense row that has one line for the whole set: `82.5×8`,
/// `+10×8` for added weight, `8 W` for a warm-up.
///
/// No unit, and no spaces around the `×`. This form appears in a column where
/// the unit is stated once in the header, and where a wrapped row cannot be
/// scanned.
String setLabel({
  required LoadMode? loadMode,
  required MeasureMode measureMode,
  required SetType setType,
  required double? weight,
  required double? addedWeight,
  required int? reps,
  required WeightUnit unit,
}) {
  final count = formatCount(reps, measureMode);
  final tag = setType.shortLabel;
  final suffix = tag.isEmpty ? '' : ' $tag';

  if (loadMode == LoadMode.bodyweight) return '$count$suffix';
  if (loadMode == LoadMode.bodyweightPlus) {
    return addedWeight == null || addedWeight == 0
        ? '$count$suffix'
        : '+${formatWeight(addedWeight, unit)}×$count$suffix';
  }
  if (weight == null) return '$count$suffix';
  return '${formatWeight(weight, unit)}×$count$suffix';
}

/// A one-line description of what an entered weight represents under [mode].
///
/// The returned strings are user-facing copy and are written in the second
/// person accordingly.
String loadBlurb(LoadMode mode) => switch (mode) {
  LoadMode.total => 'The weight you type is the whole load',
  LoadMode.perSide => 'The weight you type is per hand, and two are moving',
  LoadMode.bodyweight => 'Reps only, no external load',
  LoadMode.bodyweightPlus => 'Bodyweight plus anything you add',
};

/// Returns the index into [sets] of the heaviest set performed.
///
/// For a movement measured on a clock this returns the longest set instead. A
/// hold's load rarely varies, so ranking several identical zero loads by weight
/// would select an arbitrary one. Warm-ups are excluded, a 20 kg warm-up not
/// being representative of the session, unless the set list contains nothing
/// else.
///
/// This answers a different question from `scorePerformance`, deliberately.
/// This function describes the session: it supplies the figure on a summary
/// row, and on an intentionally light day it should report what was lifted
/// rather than nothing, so back-off sets, drop legs and rest-pause legs are all
/// eligible. `scorePerformance` determines what constitutes progress, and
/// considers only working and AMRAP sets, because a chart counting back-off
/// sets would render a light week as an improvement. The two require different
/// candidate pools; merging them would invalidate one. They must, however,
/// share the ranking defined below.
///
/// Named for what it ranks rather than `topSetIndex`, which reads as a second
/// opinion on the same question.
///
/// Ranked by the load lifted rather than the value entered, using
/// [effectiveLoad] with
/// no bodyweight: a dumbbell entered as 22.5 is 45 kg, and a `total` set
/// carrying only `addedWeight` has no load at all, where `weight ?? addedWeight`
/// would read the belt figure as though it were on the bar. Bodyweight is left
/// null on purpose: under `bodyweight` everything ties either way, and under
/// `bodyweightPlus` ordering by added weight is the same ordering, so a series
/// nobody has weighed still sorts correctly.
///
/// Returns null only for an empty list. Ranking by index rather than returning
/// a set keeps this free of the row type: the caller already holds the list.
int? heaviestLogged({
  required List<
    ({SetType setType, double? weight, double? addedWeight, int? reps})
  >
  sets,
  required MeasureMode measureMode,
  required LoadMode loadMode,
}) {
  if (sets.isEmpty) return null;
  final counted = <int>[
    for (var i = 0; i < sets.length; i++)
      if (sets[i].setType != SetType.warmup) i,
  ];
  final pool = counted.isEmpty
      ? [for (var i = 0; i < sets.length; i++) i]
      : counted;
  // A set with no load at all sorts below one that has any, rather than being
  // read as zero and tying with a bar that genuinely weighs nothing.
  double rank(int i) => measureMode.isHold
      ? (sets[i].reps ?? 0).toDouble()
      : (effectiveLoad(
              mode: loadMode,
              weight: sets[i].weight,
              addedWeight: sets[i].addedWeight,
            ) ??
            -1);
  var best = pool.first;
  for (final i in pool) {
    if (rank(i) > rank(best)) best = i;
  }
  return best;
}
