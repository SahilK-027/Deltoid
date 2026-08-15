/// How a logged set reads as text, in the three shapes the app needs.
///
/// These were six copies in five feature files. Two of them — the expanded row
/// in exercise history and the set line in workout detail — were byte-identical
/// and had to be edited twice every time the wording moved. The other four
/// disagreed with each other in ways nobody had noticed: workout detail picked
/// a day's top set by weight even for a plank, while the session summary picked
/// it by duration, so the same hold read as two different sets on two screens
/// that both claimed to print "the same figure".
///
/// **Plain values, never a database row.** Every other file in `lib/domain/`
/// takes the numbers rather than the `SetLog` carrying them, which is what lets
/// this be tested without a database (RULES § 4). Call sites unpack the row.
library;

import 'enums.dart';
import 'metrics.dart';
import 'units.dart';

/// One set's load, spelled out: `82.5 kg`, `82.5 kg × 2` for a pair of
/// dumbbells, `Bodyweight`, `BW + 10 kg`, or a dash when nothing was recorded.
///
/// The dash is rule 4: a set with no weight against it is a gap, not a zero.
String loadLabel({
  required LoadMode? loadMode,
  required double? weight,
  required double? addedWeight,
  required WeightUnit unit,
}) {
  if (loadMode == LoadMode.bodyweight) return 'Bodyweight';
  if (loadMode == LoadMode.bodyweightPlus) {
    return addedWeight == null || addedWeight == 0
        ? 'Bodyweight'
        : 'BW + ${formatWeight(addedWeight, unit)} ${unit.label}';
  }
  if (weight == null) return '—';
  final perSide = loadMode == LoadMode.perSide ? ' × 2' : '';
  return '${formatWeight(weight, unit)} ${unit.label}$perSide';
}

/// The same load with what was done against it: `82.5 kg × 8`, `Bodyweight × 12`,
/// `1:30` for a hold that carried no load.
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
  if (loadMode == LoadMode.bodyweight) return 'Bodyweight × $count';
  if (loadMode == LoadMode.bodyweightPlus) {
    return addedWeight == null || addedWeight == 0
        ? 'Bodyweight × $count'
        : 'BW + ${formatWeight(addedWeight, unit)} ${unit.label} × $count';
  }
  if (weight == null) return measureMode.isHold ? count : '$count reps';
  final perSide = loadMode == LoadMode.perSide ? ' × 2' : '';
  return '${formatWeight(weight, unit)} ${unit.label}$perSide × $count';
}

/// Compressed, for a dense row that has one line for the whole set: `82.5×8`,
/// `+10×8` for added weight, `8 W` for a warm-up.
///
/// No unit and no spaces around the `×`. This form appears in a column where
/// the unit is already stated once at the top, and where a row that wraps is a
/// row you cannot scan.
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

/// What the number you type into an exercise means, in the one line a row has.
String loadBlurb(LoadMode mode) => switch (mode) {
      LoadMode.total => 'The weight you type is the whole load',
      LoadMode.perSide => 'The weight you type is per hand, and two are moving',
      LoadMode.bodyweight => 'Reps only, no external load',
      LoadMode.bodyweightPlus => 'Bodyweight plus anything you add',
    };

/// The heaviest thing you actually did, as an index into [sets].
///
/// The **longest** when the movement is measured on a clock: a plank's load
/// rarely moves, so sorting five identical zeros by weight picks an arbitrary
/// one of them. Warm-ups are excluded — a 20 kg warm-up is not what the day was
/// about — unless warm-ups are all there is.
///
/// **Not the same question as `scorePerformance`, and deliberately so.** This
/// one describes the session: it is the number on a summary row, and on a
/// deliberately light day it should say what you lifted rather than nothing at
/// all, so back-offs, drops and rest-pause legs are all eligible.
/// `scorePerformance` asks what counts as *progress*, and answers over working
/// and AMRAP only, because a chart that counted back-offs would let a light
/// week look like a gain. Two questions, two pools, and merging them would
/// break one of the two. What they must share is the *ranking*, below.
///
/// It was called `topSetIndex`, which read as a second opinion on the same
/// question and got filed as a bug twice. The name is the fix.
///
/// **Ranked by what was lifted, not by what was typed.** [effectiveLoad] with
/// no bodyweight: a dumbbell entered as 22.5 is 45 kg, and — the case that was
/// wrong — a `total` set carrying only `addedWeight` has no load at all, where
/// the old `weight ?? addedWeight` read the belt figure as though it were on
/// the bar. Bodyweight is left null on purpose: under `bodyweight` everything
/// ties either way, and under `bodyweightPlus` ordering by added weight is the
/// same ordering, so a series nobody has weighed still sorts correctly.
///
/// Returns null only for an empty list. Ranking by index rather than returning
/// a set keeps this free of the row type: the caller already holds the list.
int? heaviestLogged({
  required List<({SetType setType, double? weight, double? addedWeight, int? reps})>
      sets,
  required MeasureMode measureMode,
  required LoadMode loadMode,
}) {
  if (sets.isEmpty) return null;
  final counted = <int>[
    for (var i = 0; i < sets.length; i++)
      if (sets[i].setType != SetType.warmup) i,
  ];
  final pool = counted.isEmpty ? [for (var i = 0; i < sets.length; i++) i] : counted;
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
