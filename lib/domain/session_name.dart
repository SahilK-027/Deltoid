/// What a workout is called when no session template stands behind it.
///
/// A workout logged outside the programme — "log a past session", or a second
/// session on a day that already had one — has a null `sessionId`, and every
/// screen that shows a workout has to put *something* where the day's name
/// goes. Left to each screen, that something drifted into four answers to one
/// question: `Ad-hoc session` on history and workout detail, `Ad-hoc` in three
/// repository reads that feed the trend chart's legend, and `Today` in the log
/// screen's reorder sheet.
///
/// It is domain because it turns data — the absence of a session — into a
/// string, which is where RULES § 4 puts every other formatter for the same
/// reason: the copies drift and nothing notices.
///
/// The wording is a full noun phrase rather than the Latin abbreviation. It
/// appears beside real session names ("Push 1", "Upper A") in a legend and a
/// list, so it has to read as one of them.
library;

/// The name of a workout logged without a session template behind it.
const unplannedSessionName = 'Unplanned session';
