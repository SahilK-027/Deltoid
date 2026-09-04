/// Rest, as numbers rather than as a screen.
///
/// Three durations decide what the timer counts down from, and they are read
/// in this order:
///
/// 1. the **slot's** own `rest_seconds`, set on the exercise inside a training
///    day — a heavy compound wants three minutes and a cable fly wants sixty
///    seconds, and that is a property of the movement in that day;
/// 2. the **default**, one number in Settings, used by every exercise that has
///    not been given one;
/// 3. the **between-exercises** duration, also in Settings, used in the one
///    place the first two cannot describe: the last set of an exercise is
///    ticked and the next set belongs to a different movement.
///
/// There used to be a fourth reading between 1 and 2 — the last rest actually
/// taken on that movement, inferred from `set_logs`. It is gone. A number
/// nobody chose, arrived at by measuring how long someone took to pick their
/// phone back up, is not a target; it made the timer open on a different
/// number every week with nothing on screen to say why.
///
/// Everything here is pure and tested without a database.
library;

/// The three `app_settings` keys rest is configured through.
///
/// Here rather than beside the providers that watch them: the repository reads
/// the same two keys without going anywhere near Riverpod, and a key spelled
/// in two places is a preference that silently stops being read the day one of
/// them is edited.
const restDefaultKey = 'rest_default_seconds';
const restBetweenExercisesKey = 'rest_between_seconds';
const restSoundKey = 'rest_sound';

/// Two minutes, the number the app ships with and falls back to.
const int kDefaultRestSeconds = 120;

/// The bounds every rest duration is held to.
///
/// Tighter than the schema's `CHECK (rest_seconds BETWEEN 1 AND 3600)` on
/// purpose: the column has to accept anything a restore or a merge can carry
/// in, and this is what a person is allowed to dial. A one-second rest is a
/// mis-tap and a half-hour rest is a phone left on a bench.
const int kMinRestSeconds = 15;
const int kMaxRestSeconds = 900;

/// The notch the ± controls move by.
const int kRestStepSeconds = 15;

/// Holds [seconds] inside the dialable range.
int clampRest(int seconds) =>
    seconds < kMinRestSeconds
        ? kMinRestSeconds
        : seconds > kMaxRestSeconds
            ? kMaxRestSeconds
            : seconds;

/// Reads a stored rest setting, falling back to [fallback] for anything this
/// app did not write.
///
/// Deliberately total: `app_settings` is a text table, a restore can put any
/// string in it, and a rest timer is not the place to throw. Out-of-range
/// values are clamped rather than rejected, so a row carrying `3600` from an
/// older build still opens a usable timer.
int parseRestSeconds(String? raw, {int fallback = kDefaultRestSeconds}) {
  final value = int.tryParse(raw?.trim() ?? '');
  if (value == null) return fallback;
  return clampRest(value);
}

/// Whether the end-of-rest tone plays. On unless it has been turned off.
bool parseRestSound(String? raw) => raw?.trim() != 'off';

/// The clock face: `2:00`, `0:45`. Used wherever a rest is counted or shown
/// as a value the ± controls are changing.
String formatRestClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = safe % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
