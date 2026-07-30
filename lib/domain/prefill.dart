import 'dart:math' as math;

import 'enums.dart';
import 'units.dart';

/// One set from a previous performance.
class PastSet {
  const PastSet({
    required this.type,
    this.weight,
    this.reps,
    this.addedWeight,
  });

  final SetType type;
  final double? weight;
  final int? reps;
  final double? addedWeight;

  PastSet copyWith({double? weight, int? reps, double? addedWeight}) => PastSet(
        type: type,
        weight: weight ?? this.weight,
        reps: reps ?? this.reps,
        addedWeight: addedWeight ?? this.addedWeight,
      );
}

/// A past performance of one exercise, with enough context to explain where a
/// suggestion came from.
class PastPerformance {
  const PastPerformance({
    required this.workoutId,
    required this.sessionId,
    required this.sessionName,
    required this.dayKey,
    required this.isDeload,
    required this.sets,
    this.skipReason = SkipReason.none,
  });

  final String workoutId;
  final String? sessionId;
  final String sessionName;
  final int dayKey;
  final bool isDeload;
  final List<PastSet> sets;

  /// Why this performance was cut short, when it was. A skipped slot that
  /// still holds logged sets is a real performance — the sets happened — and
  /// history says so next to the reason rather than hiding them.
  final SkipReason skipReason;
}

enum PrefillSource {
  /// Last time you did this exercise *in this session*. The default and the
  /// whole point.
  sameSession,

  /// Only a deload performance exists for this session.
  sameSessionDeload,

  /// Never done here before — borrowed from another session, always labelled.
  otherSession,

  /// No history at all.
  none,
}

class PrefillResult {
  const PrefillResult({
    required this.sets,
    required this.source,
    this.reference,
    this.deloadApplied = false,
  });

  const PrefillResult.empty()
      : sets = const [],
        source = PrefillSource.none,
        reference = null,
        deloadApplied = false;

  /// Suggested sets, already deload-adjusted if applicable.
  final List<PastSet> sets;
  final PrefillSource source;

  /// The performance these numbers came from, for the "from Push 2 · 12 Jul"
  /// label.
  final PastPerformance? reference;

  final bool deloadApplied;

  bool get hasSuggestion => sets.isNotEmpty;
}

/// Picks what to show as last-time numbers when a workout opens.
///
/// The rule that matters: history is scoped to the **session**, not the
/// exercise. Incline press opens Push 1 at 22.5kg and sits second in Push 2 at
/// 20kg; each session must keep its own progression or the whole point of
/// progressive overload is lost. Anything borrowed from another session is
/// returned with [PrefillSource.otherSession] so the UI can say so out loud.
///
/// [candidates] must contain performances of one exercise, newest first.
PrefillResult resolvePrefill({
  required List<PastPerformance> candidates,
  required String? sessionId,
  bool targetIsDeload = false,
  int deloadSetDelta = -1,
  int deloadWeightPct = 80,
  WeightUnit unit = WeightUnit.kg,
}) {
  PastPerformance? pick;
  var source = PrefillSource.none;

  if (sessionId != null) {
    for (final p in candidates) {
      if (p.sessionId == sessionId && !p.isDeload && p.sets.isNotEmpty) {
        pick = p;
        source = PrefillSource.sameSession;
        break;
      }
    }
    // Fall back to a deload performance of the same session before ever
    // reaching across to a different one — a light week here still reflects
    // this slot's progression better than a different day's numbers.
    if (pick == null) {
      for (final p in candidates) {
        if (p.sessionId == sessionId && p.sets.isNotEmpty) {
          pick = p;
          source = PrefillSource.sameSessionDeload;
          break;
        }
      }
    }
  }

  if (pick == null) {
    for (final p in candidates) {
      if (p.sets.isNotEmpty) {
        pick = p;
        source = PrefillSource.otherSession;
        break;
      }
    }
  }

  if (pick == null) return const PrefillResult.empty();

  // Never scale a light week again. If the only history for this slot is
  // itself a deload, 80% of 80% is 64% — a deload is 80% of your working
  // weight, not 80% of the last time you backed off. Reachable as soon as a
  // deload can be forced two cycles running from the UI.
  final scale = targetIsDeload && !pick.isDeload;

  final sets = scale
      ? applyDeload(
          pick.sets,
          setDelta: deloadSetDelta,
          weightPct: deloadWeightPct,
          unit: unit,
        )
      : pick.sets;

  return PrefillResult(
    sets: sets,
    source: source,
    reference: pick,
    deloadApplied: scale,
  );
}

/// Deload transform: fewer working sets, lighter bar.
///
/// Warmups are left alone — they're not the fatiguing part. Drop and
/// rest-pause extensions are removed entirely, since taking a working set past
/// failure is precisely what a deload is meant to avoid.
List<PastSet> applyDeload(
  List<PastSet> sets, {
  required int setDelta,
  required int weightPct,
  /// A scaled load has to be a weight you can actually load on a bar, and
  /// which weights those are depends on whether the plates are kilos or
  /// pounds. Storage stays kg either way.
  WeightUnit unit = WeightUnit.kg,
}) {
  final warmups = sets.where((s) => s.type == SetType.warmup).toList();
  final working = sets
      .where((s) => s.type != SetType.warmup && !s.type.isContinuation)
      .toList();

  final keep = math.max(1, working.length + setDelta);
  final trimmed = working.take(keep).toList();

  double? scale(double? w) =>
      w == null ? null : roundLoadIn(w * weightPct / 100, unit);

  return [
    ...warmups,
    for (final s in trimmed)
      PastSet(
        type: s.type,
        weight: scale(s.weight),
        reps: s.reps,
        addedWeight: scale(s.addedWeight),
      ),
  ];
}
