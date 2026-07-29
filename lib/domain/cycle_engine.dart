/// A cycle is one full pass through every session in the regime — not a
/// calendar week.
///
/// This matters because life is not a calendar. Miss Thursday and the cycle
/// simply hasn't finished yet; it advances when the work is done. Deloads are
/// counted in cycles for the same reason.
class CycleStatus {
  const CycleStatus({
    required this.cycleIndex,
    required this.isDeload,
    required this.sessionIds,
    required this.completedSessionIds,
    required this.cyclesSinceDeload,
    required this.deloadEnabled,
    required this.deloadAfterCycles,
  });

  final int cycleIndex;
  final bool isDeload;

  /// Every session in the regime, in programme order.
  final List<String> sessionIds;

  /// Sessions with at least one completed workout in this cycle.
  final Set<String> completedSessionIds;

  /// Completed cycles since the last deload cycle (deloads themselves excluded).
  final int cyclesSinceDeload;

  final bool deloadEnabled;
  final int deloadAfterCycles;

  int get total => sessionIds.length;

  int get done => sessionIds.where(completedSessionIds.contains).length;

  bool get isComplete => total > 0 && done == total;

  double get progress => total == 0 ? 0 : done / total;

  /// The next session to train: the first one in programme order that hasn't
  /// been done this cycle. Once the cycle is complete, it wraps to the start of
  /// the next one.
  ///
  /// Deliberately order-based rather than date-based, so training out of order
  /// or doing a session twice never strands the rest of the programme.
  String? get nextSessionId {
    if (sessionIds.isEmpty) return null;
    for (final id in sessionIds) {
      if (!completedSessionIds.contains(id)) return id;
    }
    return sessionIds.first;
  }

  /// Sessions still owed in this cycle, in order.
  List<String> get remainingSessionIds =>
      sessionIds.where((id) => !completedSessionIds.contains(id)).toList();

  /// Whether the cycle that follows this one should be a deload.
  ///
  /// A deload cycle never triggers another one — the counter resets when it
  /// starts.
  bool get nextCycleIsDeload {
    if (!deloadEnabled || deloadAfterCycles <= 0) return false;
    if (isDeload) return false;
    return cyclesSinceDeload + 1 >= deloadAfterCycles;
  }

  /// True when this is the last cycle before a deload, so Today can warn ahead
  /// of time rather than surprising you on the day.
  bool get deloadAfterThisCycle => nextCycleIsDeload;

  /// How many normal cycles remain before the next deload.
  int get cyclesUntilDeload {
    if (!deloadEnabled || deloadAfterCycles <= 0) return -1;
    if (isDeload) return deloadAfterCycles;
    return (deloadAfterCycles - cyclesSinceDeload - 1).clamp(0, 1 << 30);
  }

  CycleStatus copyWith({
    int? cycleIndex,
    bool? isDeload,
    List<String>? sessionIds,
    Set<String>? completedSessionIds,
    int? cyclesSinceDeload,
    bool? deloadEnabled,
    int? deloadAfterCycles,
  }) {
    return CycleStatus(
      cycleIndex: cycleIndex ?? this.cycleIndex,
      isDeload: isDeload ?? this.isDeload,
      sessionIds: sessionIds ?? this.sessionIds,
      completedSessionIds: completedSessionIds ?? this.completedSessionIds,
      cyclesSinceDeload: cyclesSinceDeload ?? this.cyclesSinceDeload,
      deloadEnabled: deloadEnabled ?? this.deloadEnabled,
      deloadAfterCycles: deloadAfterCycles ?? this.deloadAfterCycles,
    );
  }
}

/// What the next cycle should look like once the current one closes.
class NextCycle {
  const NextCycle({
    required this.cycleIndex,
    required this.isDeload,
    required this.cyclesSinceDeload,
  });

  final int cycleIndex;
  final bool isDeload;

  /// Carried into the new cycle: resets to zero when a deload begins.
  final int cyclesSinceDeload;
}

NextCycle planNextCycle(CycleStatus current) {
  final deload = current.nextCycleIsDeload;
  return NextCycle(
    cycleIndex: current.cycleIndex + 1,
    isDeload: deload,
    cyclesSinceDeload:
        deload ? 0 : (current.isDeload ? 0 : current.cyclesSinceDeload + 1),
  );
}
