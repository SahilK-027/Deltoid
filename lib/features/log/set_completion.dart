import '../../domain/enums.dart';
import 'widgets/keypad.dart' show SetField;

/// What a set is still missing before it can honestly be marked done, or null
/// when it is complete.
///
/// **A ticked set with nothing in it is worse than no set at all.** It used to
/// be allowed, and it wrote a completed row with a null load and null reps:
/// invisible to the progress chart, useless as next week's prefill, and
/// indistinguishable later from a set that genuinely happened.
///
/// Pulled out of `_LogScreenState` and made a function over plain values for
/// one reason: it was a private method, and the *second* way of ticking a set
/// — typing reps and pressing Next — never called it. One rule that two paths
/// have to remember to apply is a rule that holds on one of them. Now both
/// paths ask this, and it can be tested without pumping a screen.
///
/// [ghostWeight] and friends are last time's numbers for this slot. A blank
/// cell with a ghost behind it is **not** missing: the tick adopts the ghost
/// first, so the value is about to be there.
///
/// The load asked for depends on the mode, and for [LoadMode.bodyweight] there
/// is no load to ask for at all.
///
/// **[LoadMode.bodyweightPlus] does require a number, and zero is a real
/// answer.** An unweighted set of a movement you sometimes load is not the
/// same fact as a set whose belt you forgot to record, and only one of them
/// should score as bodyweight alone. Typing `0` costs one key, and only on the
/// first unweighted set of that movement — after it, the ghost carries the
/// zero forward and this returns null on its own.
SetField? missingBeforeDone({
  required LoadMode loadMode,
  required double? weight,
  required double? addedWeight,
  required int? reps,
  double? ghostWeight,
  double? ghostAddedWeight,
  int? ghostReps,
}) {
  switch (loadMode) {
    case LoadMode.bodyweightPlus:
      if (addedWeight == null && ghostAddedWeight == null) {
        return SetField.added;
      }
    case LoadMode.total:
    case LoadMode.perSide:
      if (weight == null && ghostWeight == null) return SetField.weight;
    case LoadMode.bodyweight:
      break;
  }
  // Seconds for a hold live in `reps`, so this covers both measures.
  if (reps == null && ghostReps == null) return SetField.reps;
  return null;
}
