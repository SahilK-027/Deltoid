import 'dart:math' as math;

import 'enums.dart';

/// Round a suggested weight to something you can actually load.
double roundLoad(double kg) => (kg * 2).round() / 2;

/// Effective load moved by one set, in kg.
///
/// [LoadMode] is what makes this honest: a dumbbell entered as 22.5 is 45kg of
/// total load, and a pull-up is only comparable across months if bodyweight is
/// part of the number.
double? effectiveLoad({
  required LoadMode mode,
  double? weight,
  double? addedWeight,
  double? bodyweightKg,
}) {
  switch (mode) {
    case LoadMode.total:
      return weight;
    case LoadMode.perSide:
      return weight == null ? null : weight * 2;
    case LoadMode.bodyweight:
      return bodyweightKg;
    case LoadMode.bodyweightPlus:
      if (bodyweightKg == null) return addedWeight;
      return bodyweightKg + (addedWeight ?? 0);
  }
}

/// Epley estimated 1RM.
///
/// Reps are capped at 12 because the formula drifts badly into high-rep
/// territory and would otherwise reward a 20-rep lateral raise over a heavy
/// triple.
double? estimated1RM({double? load, int? reps}) {
  if (load == null || reps == null || reps <= 0 || load <= 0) return null;
  final r = math.min(reps, 12);
  return load * (1 + r / 30);
}

/// Whether a set beats the same slot last time.
///
/// Deliberately not [estimated1RM]: that caps reps at 12 so high-rep work can't
/// masquerade as strength, which also makes 12 → 13 reps invisible — exactly
/// the improvement most worth celebrating on a hypertrophy set.
///
/// The rule is strict on purpose. More load at no cost in reps, or more reps at
/// the same load, is unambiguously better. Heavier for fewer reps is a
/// trade-off, not a win, and lighting it up green would make the highlight
/// meaningless.
bool beatsPrevious({
  double? load,
  int? reps,
  double? previousLoad,
  int? previousReps,
}) {
  if (load == null || reps == null || previousLoad == null || previousReps == null) {
    return false;
  }
  if (load > previousLoad && reps >= previousReps) return true;
  if (load == previousLoad && reps > previousReps) return true;
  return false;
}

/// One completed set, reduced to what the progress maths needs.
class ScoredSet {
  const ScoredSet({
    required this.type,
    this.weight,
    this.reps,
    this.addedWeight,
  });

  final SetType type;
  final double? weight;
  final int? reps;
  final double? addedWeight;
}

/// Summary of a single exercise performance, used by charts and history.
class PerformanceScore {
  const PerformanceScore({
    required this.topSetLoad,
    required this.topSetReps,
    required this.best1RM,
    required this.workingSets,
    required this.totalReps,
    required this.volume,
  });

  /// Heaviest working set's effective load.
  final double? topSetLoad;
  final int? topSetReps;

  /// Best estimated 1RM across working sets — the fairest single number for
  /// "did I get stronger", since it credits both weight and reps.
  ///
  /// Null for a [MeasureMode.hold]: a plank has no one-rep max, and a formula
  /// fed seconds would answer anyway.
  final double? best1RM;

  final int workingSets;

  /// Reps across working sets — or seconds, for a hold. The caller knows which
  /// from the exercise's [MeasureMode] and labels it accordingly.
  final int totalReps;

  /// Load × reps across working sets. Zero for a hold: kg × seconds is a
  /// different unit, and summing it in would inflate every total it reaches.
  final double volume;

  bool get isEmpty => workingSets == 0;
}

/// [measure] decides what the count on each set means, and therefore which of
/// these numbers exist at all. A hold has a top load and a longest hold, and
/// nothing else: Epley on seconds would report a 45-second plank as a 2.5×
/// bodyweight single, and kg × seconds is not volume in the same unit as
/// kg × reps, so adding it into a session total would quietly inflate it.
/// Both come back null / zero rather than wrong — see [PerformanceScore].
PerformanceScore scorePerformance({
  required List<ScoredSet> sets,
  required LoadMode mode,
  MeasureMode measure = MeasureMode.reps,
  double? bodyweightKg,
}) {
  double? topLoad;
  int? topReps;
  double? best;
  var count = 0;
  var reps = 0;
  var volume = 0.0;

  for (final s in sets) {
    // Warmups, drops and rest-pause extensions are excluded on purpose:
    // including them is what makes naive logs claim progress that isn't there.
    if (!s.type.countsForProgress) continue;

    final load = effectiveLoad(
      mode: mode,
      weight: s.weight,
      addedWeight: s.addedWeight,
      bodyweightKg: bodyweightKg,
    );

    count++;
    reps += s.reps ?? 0;
    if (!measure.isHold && load != null && s.reps != null) {
      volume += load * s.reps!;
    }

    // A hold's top set is the longest one, not the heaviest: a plank carries
    // the same load every week and the whole progression is in the clock.
    if (measure.isHold) {
      if (topReps == null || (s.reps ?? 0) > topReps) {
        topReps = s.reps;
        topLoad = load;
      }
    } else if (load != null && (topLoad == null || load > topLoad)) {
      topLoad = load;
      topReps = s.reps;
    }
    if (!measure.isHold) {
      final e = estimated1RM(load: load, reps: s.reps);
      if (e != null && (best == null || e > best)) best = e;
    }
  }

  return PerformanceScore(
    topSetLoad: topLoad,
    topSetReps: topReps,
    best1RM: best,
    workingSets: count,
    totalReps: reps,
    volume: volume,
  );
}

/// Total load moved in one session, in kg.
///
/// Every completed set counts, warm-ups and drop legs included — this is a
/// "what did the day come to" figure, not a progression score, and the work of
/// a warm-up is still work you did. [scorePerformance] is the strict one.
///
/// Goes through [effectiveLoad], which is the whole point: a dumbbell entered
/// as 22.5 is 45kg moving and a chin-up is bodyweight × reps. Reading `weight`
/// off the row instead reported `0 kg` for a session of chins and dips, where
/// `weight` is null on every set.
///
/// Bodyweight sets contribute nothing when [bodyweightKg] is null, because it
/// is unknown rather than zero. A caller that gets 0 back should say so with a
/// dash, not print a total that quietly dropped half the session.
///
/// Holds contribute nothing either, for a different reason: kg × seconds is
/// not the unit this figure is in. Three minutes of plank is real work and
/// this number is not the place it gets counted — the weekly set count is.
double sessionVolume({
  required List<({LoadMode mode, MeasureMode measure, List<ScoredSet> sets})>
      exercises,
  double? bodyweightKg,
}) {
  var total = 0.0;
  for (final e in exercises) {
    if (e.measure.isHold) continue;
    for (final s in e.sets) {
      final load = effectiveLoad(
        mode: e.mode,
        weight: s.weight,
        addedWeight: s.addedWeight,
        bodyweightKg: bodyweightKg,
      );
      total += (load ?? 0) * (s.reps ?? 0);
    }
  }
  return total;
}

/// Bodyweight on a given day, linearly interpolated between the surrounding
/// entries. Without this, weighing yourself twice a month would leave most
/// pull-up sets unscoreable.
/// Called once per performance, so it copies and sorts nothing it does not
/// have to. `bodyweightSeries` already comes back ordered by day, which is
/// every caller in the app; an unsorted list is still accepted and sorted, but
/// it is the exception rather than the price of every call. Thirty years of one
/// movement is a thousand-odd calls over a thousand-odd entries, and doing the
/// copy, the sort and a linear scan on each of them cost most of a second
/// before the chart could be drawn.
double? bodyweightOn(int dayKey, List<({int dayKey, double weightKg})> log) {
  if (log.isEmpty) return null;

  var ordered = log;
  for (var i = 1; i < log.length; i++) {
    if (log[i - 1].dayKey > log[i].dayKey) {
      ordered = [...log]..sort((a, b) => a.dayKey.compareTo(b.dayKey));
      break;
    }
  }

  if (dayKey <= ordered.first.dayKey) return ordered.first.weightKg;
  if (dayKey >= ordered.last.dayKey) return ordered.last.weightKg;

  // The last entry on or before [dayKey]. The bounds above mean it is never
  // the final element, so `lo + 1` is always a real entry to interpolate to.
  var lo = 0;
  var hi = ordered.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (ordered[mid].dayKey <= dayKey) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }

  final a = ordered[lo];
  final b = ordered[lo + 1];
  if (b.dayKey == a.dayKey) return b.weightKg;
  final t = (dayKey - a.dayKey) / (b.dayKey - a.dayKey);
  return a.weightKg + (b.weightKg - a.weightKg) * t;
}

/// How many consecutive recent performances failed to beat the best e1RM that
/// came before them.
///
/// This is the actual answer to "am I progressing" — cheap to compute, and
/// surfaced as a quiet badge rather than a dashboard.
int stalledSessions(List<double?> chronological1RMs) {
  final values = chronological1RMs.whereType<double>().toList();
  if (values.length < 2) return 0;

  var best = values.first;
  var bestIndex = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > best) {
      best = values[i];
      bestIndex = i;
    }
  }
  return values.length - 1 - bestIndex;
}
