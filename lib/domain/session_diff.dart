/// What today's session did that the programme doesn't know about yet.
///
/// A workout is a *snapshot* of its session template (RULES § Data), so
/// improvising mid-session — adding a movement the rack made available, cutting
/// one, running them in a different order — changes today and nothing else. That
/// is the right default: an app that quietly rewrote the programme every time a
/// bench was busy would have no programme left by March.
///
/// It is, however, the wrong sole option. Adding the same movement to a session
/// for the fourth consecutive week, and re-entering it manually each time,
/// requires the user to perform the application's bookkeeping. The end of a
/// session therefore presents the diff, one line per change, and the user
/// selects which are applied to the programme.
///
/// Pure: no database, no drift types. Tested in `test/domain`.
library;

enum SessionChangeKind {
  /// Trained today, not in the template.
  added,

  /// In the template, not trained today — removed from the workout, not merely
  /// skipped. A skip is a decision about one day and never appears here.
  removed,

  /// Same movements, different order.
  reordered,

  /// Fewer working sets ticked than the day programmes for a movement.
  ///
  /// Offered because the workout that follows cannot tell a plan changed from
  /// a session cut short. It opens on last time's shape with the template's
  /// count as a floor, so a deadlift done as three warm-ups and one top set
  /// comes back with two empty working sets padded on the end. The floor is
  /// right for the day that ran out of time, and only the person who trained
  /// knows which day this was.
  setCount,
}

class SessionChange {
  const SessionChange({
    required this.kind,
    required this.exerciseIds,
    required this.label,
    this.setCount,
  });

  final SessionChangeKind kind;

  /// The exercises this change is about. One for an add or a remove; the whole
  /// running order, in the order trained, for a reorder.
  final List<String> exerciseIds;

  /// What *happened*, in the past tense — "Added Hanging leg raise". The
  /// consequence of keeping it is the UI's line to write, because only the UI
  /// knows what the session is called.
  final String label;

  /// The working-set count a [SessionChangeKind.setCount] change would write
  /// to the day. Null for every other kind.
  final int? setCount;

  @override
  String toString() => '$kind: $label';
}

/// One entry in either list. Name is carried so the diff can label itself
/// without a second lookup.
typedef ExerciseRef = ({String exerciseId, String name});

/// Compares what was trained against what the session says, newest state first.
///
/// [logged] must exclude nothing — a skipped exercise is still part of the
/// session and its presence here is what stops a skip reading as a deletion.
///
/// Returns an empty list when the day followed the programme, which is the
/// common case and the one that has to cost nothing: no changes, no section, no
/// question asked at the end of a workout.
List<SessionChange> diffSession({
  required List<ExerciseRef> template,
  required List<ExerciseRef> logged,
}) {
  final templateIds = [for (final e in template) e.exerciseId];
  final loggedIds = [for (final e in logged) e.exerciseId];

  final changes = <SessionChange>[];

  // Deduped: the same movement can legitimately appear twice in one workout
  // (bench at the start, a back-off set of it at the end), and offering "Add
  // bench" twice would ask one question two ways — and, if both were ticked,
  // write two slots for one movement.
  final offered = <String>{};
  for (final e in logged) {
    if (templateIds.contains(e.exerciseId)) continue;
    if (!offered.add(e.exerciseId)) continue;
    changes.add(SessionChange(
      kind: SessionChangeKind.added,
      exerciseIds: [e.exerciseId],
      label: 'Added ${e.name}',
    ));
  }

  for (final e in template) {
    if (!loggedIds.contains(e.exerciseId)) {
      changes.add(SessionChange(
        kind: SessionChangeKind.removed,
        exerciseIds: [e.exerciseId],
        label: 'Dropped ${e.name}',
      ));
    }
  }

  // Only when the *shared* movements changed places. Without this filter every
  // add at the end of a workout would also report a reorder, since adding to a
  // list does change the list — and the user would be asked twice about one
  // decision.
  final sharedTemplate =
      [for (final id in templateIds) if (loggedIds.contains(id)) id];
  final sharedLogged =
      [for (final id in loggedIds) if (templateIds.contains(id)) id];
  if (!_sameOrder(sharedTemplate, sharedLogged)) {
    changes.add(SessionChange(
      kind: SessionChangeKind.reordered,
      exerciseIds: loggedIds,
      label: 'Ran in a different order',
    ));
  }

  return changes;
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One movement as the day programmes it: how many working sets it asks for.
typedef SetTarget = ({String exerciseId, String name, int targetSets});

/// One movement as it was trained: how many working sets were ticked, and
/// whether it was skipped.
typedef SetTally = ({String exerciseId, int workingDone, bool skipped});

/// The movements where fewer working sets were ticked than the day asks for.
///
/// Only ever fewer. More sets already carry forward, because the next workout
/// mirrors last time's shape and the template's count is only a floor.
///
/// Silent in the cases where writing the count back would be wrong or
/// ambiguous:
///
/// - **A deload**, which asks for fewer sets on purpose. The count trained is
///   the deload's answer, not the programme's.
/// - **A skip**, which is a decision about one day. So is a movement with no
///   working set ticked at all: that is a dropped movement or an unfinished
///   one, and a day cannot programme zero sets.
/// - **A movement the day runs twice**, in the template or in the workout.
///   Nothing says which occurrence a count belongs to.
///
/// Working sets are counted the way the next workout counts them when it pads
/// to the floor: `working` rows that are not drop legs.
List<SessionChange> diffSetCounts({
  required List<SetTarget> template,
  required List<SetTally> logged,
  required bool isDeload,
}) {
  if (isDeload) return const [];

  int occurrences(Iterable<String> ids, String id) =>
      ids.where((e) => e == id).length;
  final templateIds = [for (final t in template) t.exerciseId];
  final loggedIds = [for (final l in logged) l.exerciseId];

  return [
    for (final t in template)
      if (occurrences(templateIds, t.exerciseId) == 1 &&
          occurrences(loggedIds, t.exerciseId) == 1)
        for (final l in logged)
          if (l.exerciseId == t.exerciseId &&
              !l.skipped &&
              l.workingDone > 0 &&
              l.workingDone < t.targetSets)
            SessionChange(
              kind: SessionChangeKind.setCount,
              exerciseIds: [t.exerciseId],
              label: 'Did ${l.workingDone} of ${t.targetSets} working sets '
                  'of ${t.name}',
              setCount: l.workingDone,
            ),
  ];
}
