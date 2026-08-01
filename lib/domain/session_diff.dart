/// What today's session did that the programme doesn't know about yet.
///
/// A workout is a *snapshot* of its session template (README invariant 2), so
/// improvising mid-session — adding a movement the rack made available, cutting
/// one, running them in a different order — changes today and nothing else. That
/// is the right default: an app that quietly rewrote the programme every time a
/// bench was busy would have no programme left by March.
///
/// It is the wrong *only* option, though. Adding hanging leg raises to Push 1
/// for the fourth week running and re-adding it by hand every week is the app
/// making you do its filing. So the end of a session offers the diff, one line
/// per change, and you pick which ones stick.
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
}

class SessionChange {
  const SessionChange({
    required this.kind,
    required this.exerciseIds,
    required this.label,
  });

  final SessionChangeKind kind;

  /// The exercises this change is about. One for an add or a remove; the whole
  /// running order, in the order trained, for a reorder.
  final List<String> exerciseIds;

  /// What *happened*, in the past tense — "Added Hanging leg raise". The
  /// consequence of keeping it is the UI's line to write, because only the UI
  /// knows what the session is called.
  final String label;

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
