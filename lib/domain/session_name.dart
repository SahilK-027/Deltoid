/// The display name for a workout that has no session template behind it.
///
/// A workout logged outside the programme — through "log a past session", or as
/// a second session on a day that already has one — carries a null `sessionId`,
/// and every screen that renders a workout must display something in place of
/// the session name. Left to individual screens, this produced four answers to
/// one question: `Ad-hoc session` in history and workout detail, `Ad-hoc` in
/// three repository reads feeding the trend chart legend, and `Today` in the
/// log screen's reorder sheet.
///
/// It belongs in the domain layer because it converts data — the absence of a
/// session — into a string. RULES § 4 places every other formatter here for the
/// same reason: duplicated copies diverge without detection.
///
/// The wording is a full noun phrase rather than an abbreviation. It appears
/// alongside real session names such as "Push 1" and "Upper A" in legends and
/// lists, and must read consistently with them.
library;

/// The name applied to a workout logged without a session template.
const unplannedSessionName = 'Unplanned session';
