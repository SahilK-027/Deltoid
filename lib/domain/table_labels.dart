/// User-facing names for database tables.
///
/// Table names are a wire format rather than English, and removing the
/// underscore does not change that. Without translation, a restore that falls
/// short would report finding "412 set logs and only 380", a failed pull would
/// report that "one set logs entry could not be saved", and the progress sheet
/// would enumerate "workout exercises" and "bodyweight logs". These are table
/// names presented to a reader who has never seen the schema.
///
/// Each table is therefore given a noun the application already uses for it
/// elsewhere: a `session` is a training day in the Regimes tab, a `workout` is
/// a logged session, and a `set_log` is a set. Both singular and plural forms
/// are provided, because the surrounding sentences require each — "one set
/// could not be saved" and "412 sets".
///
/// This belongs in the domain layer because it converts data into a string,
/// which is where RULES § 4 places every formatter, and because a label needed
/// in two places is a label that will be duplicated. The underscore-stripping
/// implementation this replaces existed in both `core/progress.dart` and
/// privately within `data/sync/pull.dart`, with neither aware of the other.
library;

/// Returns the plural noun for a table, such as `sets` for `set_logs`.
///
/// An unrecognised name falls back to the table name with underscores replaced
/// by spaces rather than throwing. A table added without a label here reads
/// less well, but does not cause a restore to fail.
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

/// Returns the singular noun for a table, such as `set` for `set_logs`.
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
