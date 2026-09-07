import 'dart:math' as math;

import 'enums.dart';
import 'units.dart';

/// One set from a previous performance.
class PastSet {
  const PastSet({
    required this.type,
    this.weight,
    this.reps,
    this.partialReps,
    this.addedWeight,
    this.isLeg = false,
  });

  final SetType type;
  final double? weight;
  final int? reps;

  /// Partials from that set, carried so the ghost can show them.
  ///
  /// **Shown, never adopted.** Everything else in a `PastSet` is a plan for
  /// today — the same weight, one more rep — and partials are not: they are
  /// what went wrong, or what was squeezed out at the end. Filling them in
  /// ahead of the set would log halves nobody did. `_adoptGhost` deliberately
  /// leaves this alone.
  final int? partialReps;

  final double? addedWeight;

  /// Whether this set was a leg of the drop group above it rather than the head
  /// of one. The type cannot answer that: a drop set's *head* is a `drop` too,
  /// so mirroring last week's shape by type alone rebuilt a group of legs with
  /// nothing to be legs of.
  final bool isLeg;

  PastSet copyWith({double? weight, int? reps, double? addedWeight}) => PastSet(
    type: type,
    weight: weight ?? this.weight,
    reps: reps ?? this.reps,
    partialReps: partialReps,
    addedWeight: addedWeight ?? this.addedWeight,
    isLeg: isLeg,
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
    this.slotId = '',
    this.startedAt = 0,
    this.skipReason = SkipReason.none,
  });

  final String workoutId;

  /// The `workout_exercises` row this performance is of — the slot, not the
  /// day.
  ///
  /// It is the identity two queries' results are merged on, and it has to be
  /// the slot: the same movement can legitimately be run twice in one session,
  /// and a merge keyed on the workout collapsed the pair into one. The dropped
  /// half then never reached prefill, so a second pass of a lift quietly did
  /// not count as last time. Empty on a performance built without one — the
  /// merge falls back to the workout, which is what it always did.
  final String slotId;
  final String? sessionId;
  final String sessionName;
  final int dayKey;

  /// When the workout began. Ordering on [dayKey] alone is not enough: train
  /// the same session twice in a day and "last time" has to mean the later of
  /// the two, not whichever the map happened to hold first.
  final int startedAt;
  final bool isDeload;
  final List<PastSet> sets;

  /// Why this performance was cut short, when it was. A skipped slot that
  /// still holds logged sets is a real performance — the sets happened — and
  /// history says so next to the reason rather than hiding them.
  final SkipReason skipReason;
}

enum PrefillSource {
  /// The most recent performance of this exercise within this session. The
  /// default source, and the behaviour the feature exists to provide.
  sameSession,

  /// Only a deload performance exists for this session.
  sameSessionDeload,

  /// Never done here before, but done somewhere else.
  ///
  /// **Carries a [PrefillResult.reference] and no sets.** The movement has a
  /// past and this session is not it, so the ⓘ can name where and when while
  /// the plate stays blank — see [resolvePrefill].
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

  /// The performance behind this result, for the "Push 2 · 12 Jul" label.
  ///
  /// Present without [sets] when the only history is another session's: the
  /// numbers are not offered, the fact that they exist is.
  final PastPerformance? reference;

  final bool deloadApplied;

  bool get hasSuggestion => sets.isNotEmpty;
}

/// Picks what to show as last-time numbers when a workout opens.
///
/// The rule that matters: history is scoped to the **session**, not the
/// exercise. Incline press opens Push 1 at 22.5kg and sits second in Push 2 at
/// 20kg; each session must keep its own progression or the whole point of
/// progressive overload is lost.
///
/// **A session with no history of its own opens blank.** Borrowing the most
/// recent performance from anywhere is not made safe by labelling it: "Borrowed
/// from Leg 1" reads as *where this movement was last done*, and it is not — it
/// is the most recent performance anywhere, which for a movement trained in two
/// sessions is whichever came round last. Train Leg 1 for the first time on
/// Monday and Leg 2 for the first time on Friday, and every plate in Friday's
/// session would be filled from Monday's, from a day that says nothing about
/// what belongs here.
/// A first time is a first time, and the plate is blank for it.
///
/// What survives is the knowledge, not the number: the other session's
/// performance comes back as [PrefillResult.reference] with
/// [PrefillSource.otherSession] and **no sets**, so the ⓘ can say where the
/// movement was last done while nothing is filled in or adoptable.
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
    // Another session's, and it stays another session's: named, dated, and
    // never written into a cell. `hasSuggestion` is false on the way out, so
    // every reader downstream — the ghosts, the shape a workout opens with,
    // the deload scaling — treats this as the first time it is.
    for (final p in candidates) {
      if (p.sets.isNotEmpty) {
        return PrefillResult(
          sets: const [],
          source: PrefillSource.otherSession,
          reference: p,
        );
      }
    }
  }

  if (pick == null) return const PrefillResult.empty();

  // A light week is never scaled a second time. Where the only history for
  // this slot is itself a deload, 80% of 80% yields 64%: a deload is 80% of the
  // working weight rather than 80% of the previous reduction. This is reachable
  // whenever a deload is forced for two consecutive cycles.
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

  /// A scaled load must be loadable on a bar, and which weights qualify depends
  /// on whether the plates are calibrated in kilograms or pounds. Storage
  /// remains in kilograms in either case.
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
        // Carried, not scaled: there is no such thing as 70% of a partial rep,
        // and the ghost's job is to say what happened last time.
        partialReps: s.partialReps,
        addedWeight: scale(s.addedWeight),
      ),
  ];
}
