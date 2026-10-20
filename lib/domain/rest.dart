/// Rest durations and the settings that govern them.
///
/// Three durations determine what the timer counts down from. They are resolved
/// in the following order:
///
/// 1. the slot's own `rest_seconds`, configured on the exercise within a
///    training day. A heavy compound requires three minutes and a cable fly
///    sixty seconds, and that is a property of the movement within that day.
/// 2. the default, a single value in Settings, applied to every exercise that
///    has not been given one.
/// 3. the between-exercises duration, also in Settings, applied in the one case
///    the first two cannot describe: the final set of an exercise is completed
///    and the next set belongs to a different movement.
///
/// No fourth source is consulted between the first and second. Inferring the
/// last rest actually taken on a movement from `set_logs` would derive a target
/// from how long the user took to resume, which is not a chosen value: it opens
/// the timer on a different number each week with no explanation on screen.
///
/// All functions here are pure and are tested without a database.
library;

/// The `app_settings` keys through which rest is configured.
///
/// Defined here rather than beside the providers that watch them. The
/// repository reads two of these keys without involving Riverpod, and a key
/// spelled in two places is a preference that silently ceases to be read when
/// one of them is edited.
const restDefaultKey = 'rest_default_seconds';
const restBetweenExercisesKey = 'rest_between_seconds';
const restSoundKey = 'rest_sound';
const restVibrateKey = 'rest_vibrate';

/// The default rest duration, in seconds, shipped with the application and used
/// as a fallback.
const int kDefaultRestSeconds = 120;

/// The bounds applied to every rest duration.
///
/// These are deliberately tighter than the schema's
/// `CHECK (rest_seconds BETWEEN 1 AND 3600)`. The column must accept any value
/// a restore or a merge can deliver; these constants define what a user may
/// select. A one-second rest indicates a mis-tap, and a half-hour rest
/// indicates a device left unattended.
const int kMinRestSeconds = 15;
const int kMaxRestSeconds = 900;

/// The increment applied by the plus and minus controls.
const int kRestStepSeconds = 15;

/// Constrains [seconds] to the selectable range.
int clampRest(int seconds) =>
    seconds < kMinRestSeconds
        ? kMinRestSeconds
        : seconds > kMaxRestSeconds
            ? kMaxRestSeconds
            : seconds;

/// Parses a stored rest setting, returning [fallback] for any value this
/// application did not write.
///
/// Deliberately total. `app_settings` is a text table, a restore may place any
/// string in it, and a rest timer is not an appropriate place to throw.
/// Out-of-range values are clamped rather than rejected, so a row carrying
/// `3600` from an earlier build still yields a usable timer.
int parseRestSeconds(String? raw, {int fallback = kDefaultRestSeconds}) {
  final value = int.tryParse(raw?.trim() ?? '');
  if (value == null) return fallback;
  return clampRest(value);
}

/// Whether the end-of-rest tone is played. Enabled unless explicitly disabled.
bool parseRestSound(String? raw) => raw?.trim() != 'off';

/// Whether the end-of-rest alert vibrates. Enabled unless explicitly disabled.
///
/// Configured separately from the tone because the two fail in different
/// conditions: the tone carries across a gym, whereas the vibration is what a
/// device lying face down still conveys. Disabling one does not imply an intent
/// to disable the other.
bool parseRestVibrate(String? raw) => raw?.trim() != 'off';

/// Formats [seconds] as a clock face, such as `2:00` or `0:45`.
///
/// Used wherever a rest duration is counted down or displayed as the value the
/// plus and minus controls adjust.
String formatRestClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = safe % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// A rest that has started, and what it is counting towards.
///
/// Held outside the log screen, which is disposed whenever you back out of it,
/// so that a rest outlives the screen it was started on. [workoutId] keeps one
/// workout's rest from being read as another's.
class RestClock {
  const RestClock({
    required this.workoutId,
    required this.startedAt,
    required this.targetSeconds,
    required this.betweenExercises,
  });

  final String workoutId;
  final DateTime startedAt;
  final int targetSeconds;

  /// The gap between two exercises rather than between two sets of one. Its
  /// target belongs to Settings, not to the exercise on screen.
  final bool betweenExercises;

  DateTime get endsAt => startedAt.add(Duration(seconds: targetSeconds));

  /// Whole seconds left at [now]; zero or below once the rest is over.
  int remainingAt(DateTime now) =>
      targetSeconds - now.difference(startedAt).inSeconds;

  bool runningAt(DateTime now) => remainingAt(now) > 0;

  RestClock withTarget(int seconds) => RestClock(
    workoutId: workoutId,
    startedAt: startedAt,
    targetSeconds: seconds,
    betweenExercises: betweenExercises,
  );
}

/// Which pause follows a completed set: another set of the same movement, or
/// the walk to the next one.
enum RestKind { sameExercise, betweenExercises }

/// One set as rest needs to see it.
typedef RestSet = ({String id, bool done, int? completedAtMs});

/// One exercise of a workout as rest needs to see it. A skipped exercise has
/// no sets left to rest for.
typedef RestSlot = ({bool skipped, List<RestSet> sets});

/// The pause that follows [setId], or null when no open set is left anywhere
/// and there is nothing to rest for.
///
/// [setId] is excluded by id rather than by its flag: the write marking it done
/// may still be in flight, so it can still be open in the snapshot.
RestKind? restKindAfter(List<RestSlot> slots, String setId) {
  var openHere = false;
  var openElsewhere = false;
  for (final slot in slots) {
    if (slot.skipped) continue;
    final holdsIt = slot.sets.any((s) => s.id == setId);
    for (final set in slot.sets) {
      if (set.id == setId || set.done) continue;
      if (holdsIt) {
        openHere = true;
      } else {
        openElsewhere = true;
      }
    }
  }
  if (openHere) return RestKind.sameExercise;
  if (openElsewhere) return RestKind.betweenExercises;
  return null;
}

/// The rest a workout was last in, read back from its sets.
///
/// A rest starts in the same gesture that stamps a set's `completedAt`, so the
/// newest stamp is when the last rest began. This is what lets a rest survive
/// the process being killed: nothing about the clock itself is written down,
/// and nothing needs to be.
///
/// Null when no set has been completed, when the newest one has nothing open
/// after it, or when it was completed more than [kMaxRestTakenSeconds] before
/// [now] — that is a phone left on a bench, not a rest. [slot] is the index of
/// the exercise the set belongs to, whose target a same-exercise rest uses.
({String setId, int slot, DateTime startedAt, RestKind kind})? lastRestStarted(
  List<RestSlot> slots,
  DateTime now,
) {
  ({String id, int slot, int at})? newest;
  for (var i = 0; i < slots.length; i++) {
    for (final set in slots[i].sets) {
      final at = set.completedAtMs;
      if (!set.done || at == null) continue;
      if (newest == null || at > newest.at) {
        newest = (id: set.id, slot: i, at: at);
      }
    }
  }
  if (newest == null) return null;
  final startedAt = DateTime.fromMillisecondsSinceEpoch(newest.at);
  final age = now.difference(startedAt).inSeconds;
  if (age < 0 || age > kMaxRestTakenSeconds) return null;
  final kind = restKindAfter(slots, newest.id);
  if (kind == null) return null;
  return (
    setId: newest.id,
    slot: newest.slot,
    startedAt: startedAt,
    kind: kind,
  );
}

/// The longest gap recorded as a rest. A set completed forty minutes after the
/// last one is a phone left on a bench, not a rest interval, and storing it
/// would poison the default for next week.
const int kMaxRestTakenSeconds = 1800;
