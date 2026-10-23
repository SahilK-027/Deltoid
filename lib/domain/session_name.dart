/// The display name for a workout that has no session template behind it.
///
/// A custom session — one started from the session sheet's
/// `Custom session` row, or logged after the fact through "log a past
/// session" — carries a null `sessionId`, as do workouts restored from older
/// data, and every screen that renders a workout must display something in
/// place of the session name. Left to individual screens, this produced four
/// answers to one question: `Ad-hoc session` in history and workout detail,
/// `Ad-hoc` in three repository reads feeding the trend chart legend, and
/// `Today` in the log screen's reorder sheet.
///
/// It belongs in the domain layer because it converts data — the absence of a
/// session — into a string. RULES § 4 places every other formatter here for the
/// same reason: duplicated copies diverge without detection.
///
/// The wording names what the session is rather than what it is not. It
/// appears alongside real session names such as "Push 1" and "Upper A" in
/// legends and lists, and must read as a name beside them. The label is
/// derived and never stored, so renaming it renames every such workout
/// already on the phone.
library;

/// The name applied to a workout logged without a session template.
const customSessionName = 'Custom session';

/// Whether [name] would collide with [customSessionName] as a day's name.
///
/// Compared the way `idx_sessions_name_live` compares day names, trimmed and
/// case-folded: a programme day called `custom session` would be
/// indistinguishable from a custom session in History, in a chart legend and in
/// the prefill disclosure.
bool isReservedSessionName(String name) =>
    name.trim().toLowerCase() == customSessionName.toLowerCase();

/// A session's name as it reads inside a sentence.
///
/// A programme day keeps its name, which is a proper noun: `Finish Push 1?`.
/// A custom session has no name of its own, and [customSessionName] mid-sentence
/// would print a capital where none belongs, so it reads as a description:
/// `Finish this custom session?`.
String sessionInSentence(String? sessionName) =>
    sessionName ?? 'this custom session';

/// What is wrong with [value] as the name of a day, or null when nothing is.
///
/// [taken] is the regime's live day names, trimmed and lowercased, as
/// `liveSessionNames` returns them. The one validator behind every prompt that
/// names a day, so adding, renaming and adding an alternate cannot disagree
/// about what a day may be called.
String? dayNameProblem(String value, Set<String> taken) {
  final name = value.trim();
  if (isReservedSessionName(name)) {
    return '$customSessionName is the name of a session outside the programme';
  }
  if (taken.contains(name.toLowerCase())) {
    return 'This regime already has a day called $name';
  }
  return null;
}
