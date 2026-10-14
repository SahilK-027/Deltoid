/// One position in a cycle: a day trained every cycle, or the days that
/// alternate there.
///
/// A regime that trains Leg 1 in one cycle and Leg 2 in the next has one
/// position holding both. A position holding a single day is the ordinary
/// case, and every regime without alternating days is a list of those.
class CyclePosition {
  const CyclePosition({required this.sessionIds, required this.dueSessionId});

  /// The days sharing this position, in programme order. Never empty.
  final List<String> sessionIds;

  /// The day this cycle trains here.
  ///
  /// Once one of the days has been trained in the cycle it is that day, so a
  /// position reports what was done rather than what was planned.
  final String dueSessionId;

  bool get alternates => sessionIds.length > 1;

  /// The days in the order their turns come round, starting with the one due.
  List<String> get turnOrder {
    final start = sessionIds.indexOf(dueSessionId);
    if (start <= 0) return sessionIds;
    return [...sessionIds.skip(start), ...sessionIds.take(start)];
  }
}

/// Groups [sessionIds] into the positions of one cycle.
///
/// [rotations] maps a session to the rotation it alternates in. A session
/// absent from it holds a position of its own, and so does the only member of
/// a rotation, which is what a delete leaves behind. A position stands where
/// its earliest member does, so [sessionIds] must be in programme order.
List<List<String>> cyclePositions(
  List<String> sessionIds,
  Map<String, String> rotations,
) {
  final byRotation = <String, List<String>>{};
  final positions = <List<String>>[];
  for (final id in sessionIds) {
    final rotation = rotations[id];
    final shared = rotation == null ? null : byRotation[rotation];
    if (shared != null) {
      shared.add(id);
      continue;
    }
    final members = [id];
    if (rotation != null) byRotation[rotation] = members;
    positions.add(members);
  }
  return positions;
}

/// The member of a rotation whose turn it is.
///
/// A member already trained in the open cycle is the answer, because the
/// position is spent on it. Otherwise it is the member after [lastTrained],
/// the one most recently trained in an earlier cycle, wrapping at the end.
/// A rotation nobody has trained, or whose last-trained member has since been
/// deleted, starts from its first member.
///
/// Derived from logged work rather than counted from the cycle number. A
/// cycle closed early without this position trained leaves the same member
/// due, where a counter would skip it.
String dueInRotation(
  List<String> members, {
  required Set<String> trainedThisCycle,
  String? lastTrained,
}) {
  for (final id in members) {
    if (trainedThisCycle.contains(id)) return id;
  }
  return _after(members, lastTrained);
}

String _after(List<String> members, String? id) {
  final at = id == null ? -1 : members.indexOf(id);
  return members[(at + 1) % members.length];
}

/// The positions of one cycle in programme order, each naming the day due.
///
/// The one place a position is assembled, for the status of the cycle in
/// flight and for the editor of a regime that has none.
List<CyclePosition> buildPositions(
  List<String> sessionIds, {
  Map<String, String> rotations = const {},
  Set<String> trainedThisCycle = const {},
  Map<String, String> lastTrainedInRotation = const {},
}) =>
    [
      for (final members in cyclePositions(sessionIds, rotations))
        CyclePosition(
          sessionIds: members,
          dueSessionId: dueInRotation(
            members,
            trainedThisCycle: trainedThisCycle,
            lastTrained: lastTrainedInRotation[rotations[members.first]],
          ),
        ),
    ];

/// The days each of the next [count] cycles trains, the open one first.
///
/// One list per cycle, one session id per position. A position holding one day
/// names it in every cycle, and a rotation steps through its members from the
/// one due now.
List<List<String>> cyclesAhead(List<CyclePosition> positions, int count) => [
      for (var n = 0; n < count; n++)
        [
          for (final p in positions) p.turnOrder[n % p.sessionIds.length],
        ],
    ];

/// How many cycles pass before the order repeats, capped at [most].
///
/// One for a regime with no alternating days, two for a pair, and the least
/// common multiple where rotations of different lengths meet. Capped because
/// the answer is drawn as rows, and the rows past the third say nothing the
/// first three have not.
int cyclesBeforeRepeat(List<CyclePosition> positions, {int most = 3}) {
  var period = 1;
  for (final p in positions) {
    final n = p.sessionIds.length;
    period = period * n ~/ _gcd(period, n);
    if (period >= most) return most;
  }
  return period;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// Whether every position of a cycle has had a day trained in it.
///
/// The one definition of a finished cycle, shared by the status a screen reads
/// and by the repository that closes the cycle, so the two cannot disagree
/// about a regime with alternating days.
bool everyPositionTrained(
  List<String> sessionIds,
  Map<String, String> rotations,
  Set<String> completed,
) {
  if (sessionIds.isEmpty) return false;
  return cyclePositions(sessionIds, rotations)
      .every((members) => members.any(completed.contains));
}

/// The state of one cycle: a complete pass through every position in a regime.
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
    this.rotations = const {},
    this.lastTrainedInRotation = const {},
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

  /// Session id to rotation id, for the days that alternate. Empty for a
  /// regime in which every day is trained every cycle.
  final Map<String, String> rotations;

  /// Rotation id to the member most recently trained in an earlier cycle.
  /// A rotation absent from it has never been trained.
  final Map<String, String> lastTrainedInRotation;

  /// The positions of this cycle in programme order, each naming the day it
  /// trains.
  List<CyclePosition> get positions => buildPositions(
        sessionIds,
        rotations: rotations,
        trainedThisCycle: completedSessionIds,
        lastTrainedInRotation: lastTrainedInRotation,
      );

  bool _trained(CyclePosition p) =>
      p.sessionIds.any(completedSessionIds.contains);

  /// Positions rather than days: two days that alternate are one of them.
  int get total => cyclePositions(sessionIds, rotations).length;

  int get done => positions.where(_trained).length;

  bool get isComplete =>
      everyPositionTrained(sessionIds, rotations, completedSessionIds);

  double get progress => total == 0 ? 0 : done / total;

  /// The next session to train: the day due in the first position, in
  /// programme order, that this cycle has not yet trained.
  ///
  /// Once the cycle is complete this wraps to the start of the next one, where
  /// a rotation has moved on to the member after the one just trained.
  ///
  /// The selection is based on programme order rather than on dates, so that
  /// training out of sequence, or repeating a session, never leaves the
  /// remainder of the programme unreachable.
  String? get nextSessionId {
    final all = positions;
    if (all.isEmpty) return null;
    for (final p in all) {
      if (!_trained(p)) return p.dueSessionId;
    }
    return _after(all.first.sessionIds, all.first.dueSessionId);
  }

  /// The sessions outstanding in this cycle, in programme order: the day due
  /// in each position not yet trained. A day whose turn it is not owes nothing.
  List<String> get remainingSessionIds => [
        for (final p in positions)
          if (!_trained(p)) p.dueSessionId,
      ];

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
      rotations: rotations,
      lastTrainedInRotation: lastTrainedInRotation,
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
