/// What a table is called on screen.
///
/// Table names are the wire format. `tableLabel` used to strip the underscore
/// and stop there, and its own comment said the names "are the wire format,
/// not English" — which was true before the replace and still true after it. A
/// restore that fell short told the user it had found "412 set logs and only
/// 380", a failed pull said "one set logs entry could not be saved", and the
/// progress sheet counted through "workout exercises" and "bodyweight logs".
/// Those are the names of tables, offered to somebody who has never seen one.
///
/// So each table gets a noun the app already uses for it elsewhere: a
/// `session` is a training day in the Regimes tab, a `workout` is what you
/// logged, and a `set_log` is a set. Two forms, because the sentences need
/// both — "one set could not be saved" and "412 sets".
///
/// It is domain because it turns data into a string, which is where RULES § 4
/// puts every formatter, and for the reason this file exists: there were two
/// copies of the underscore-stripper, one in `core/progress.dart` and one
/// private to `data/sync/pull.dart`, and neither knew about the other.
library;

/// The plural noun for a table: `set_logs` → `sets`.
///
/// An unknown name falls back to the old behaviour rather than throwing. A
/// table added without a label here reads a little worse; it does not take a
/// restore down with it.
String tableLabel(String table) => switch (table) {
  'exercises' => 'exercises',
  'regimes' => 'regimes',
  'sessions' => 'training days',
  'session_exercises' => 'planned exercises',
  'cycles' => 'cycles',
  'workouts' => 'workouts',
  'workout_exercises' => 'logged exercises',
  'set_logs' => 'sets',
  'bodyweight_logs' => 'bodyweight entries',
  'app_settings' => 'settings',
  _ => table.replaceAll('_', ' '),
};

/// The singular noun for a table: `set_logs` → `set`.
String tableLabelOne(String table) => switch (table) {
  'exercises' => 'exercise',
  'regimes' => 'regime',
  'sessions' => 'training day',
  'session_exercises' => 'planned exercise',
  'cycles' => 'cycle',
  'workouts' => 'workout',
  'workout_exercises' => 'logged exercise',
  'set_logs' => 'set',
  'bodyweight_logs' => 'bodyweight entry',
  'app_settings' => 'setting',
  _ => table.replaceAll('_', ' '),
};
