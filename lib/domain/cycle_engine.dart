/// The state of one cycle: a complete pass through every session in a regime.
///
/// A cycle is not a calendar week. If a session is missed, the cycle has simply
/// not yet finished; it advances when the work is completed rather than when a
/// period elapses. Deloads are scheduled in cycles for the same reason.
class CycleStatus {
  const CycleStatus({
    required this.cycleId,
    required this.cycleIndex,
    required this.isDeload,
    required this.sessionIds,
    required this.completedSessionIds,
    required this.cyclesSinceDeload,
    required this.deloadEnabled,
    required this.deloadAfterCycles,
  });

  /// The open cycle's row id, so that a screen displaying a cycle can also
  /// operate on it, closing it early or overriding its deload status.
  final String cycleId;

  final int cycleIndex;
  final bool isDeload;

  /// Every session in the regime, in programme order.
  final List<String> sessionIds;

  /// The sessions with at least one completed workout in this cycle.
  final Set<String> completedSessionIds;

  /// The number of completed cycles since the last deload, excluding deload
  /// cycles themselves.
  final int cyclesSinceDeload;

  final bool deloadEnabled;
  final int deloadAfterCycles;

  int get total => sessionIds.length;

  int get done => sessionIds.where(completedSessionIds.contains).length;

  bool get isComplete => total > 0 && done == total;

  double get progress => total == 0 ? 0 : done / total;

  /// The next session to train: the first in programme order not yet completed
  /// in this cycle.
  ///
  /// Once the cycle is complete this wraps to the start of the next one.
  ///
  /// The selection is based on programme order rather than on dates, so that
  /// training out of sequence, or repeating a session, never leaves the
  /// remainder of the programme unreachable.
  String? get nextSessionId {
    if (sessionIds.isEmpty) return null;
    for (final id in sessionIds) {
      if (!completedSessionIds.contains(id)) return id;
    }
    return sessionIds.first;
  }

  /// The sessions outstanding in this cycle, in programme order.
  List<String> get remainingSessionIds =>
      sessionIds.where((id) => !completedSessionIds.contains(id)).toList();

  /// Whether the cycle following this one should be a deload.
  ///
  /// A deload cycle never schedules another: the counter resets when one
  /// begins.
  bool get nextCycleIsDeload {
    if (!deloadEnabled || deloadAfterCycles <= 0) return false;
    if (isDeload) return false;
    return cyclesSinceDeload + 1 >= deloadAfterCycles;
  }

  /// Whether this is the final cycle before a deload, allowing the Workouts
  /// screen to indicate it in advance rather than on the day.
  bool get deloadAfterThisCycle => nextCycleIsDeload;

  /// The number of ordinary cycles remaining before the next deload.
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
      cycleId: cycleId,
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

/// The parameters of the cycle to be opened once the current one closes.
class NextCycle {
  const NextCycle({
    required this.cycleIndex,
    required this.isDeload,
    required this.cyclesSinceDeload,
  });

  final int cycleIndex;
  final bool isDeload;

  /// Carried into the new cycle. Resets to zero when a deload begins.
  final int cyclesSinceDeload;
}

/// Determines the parameters of the cycle following [current].
NextCycle planNextCycle(CycleStatus current) {
  final deload = current.nextCycleIsDeload;
  return NextCycle(
    cycleIndex: current.cycleIndex + 1,
    isDeload: deload,
    cyclesSinceDeload:
        deload ? 0 : (current.isDeload ? 0 : current.cyclesSinceDeload + 1),
  );
}
