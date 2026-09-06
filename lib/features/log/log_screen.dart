import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/failure.dart';
import '../../core/providers.dart';
import '../../core/rest_alert.dart';
import '../../core/workout_notifications.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/reorder_sheet.dart';
import '../../core/widgets/ticking.dart';
import '../../data/backup/backup_service.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import '../../domain/prefill.dart';
import '../../domain/rest.dart';
import '../../domain/units.dart';
import 'log_providers.dart';
import 'session_summary_screen.dart';
import 'set_completion.dart';
import 'widgets/exercise_rail.dart';
import 'widgets/exercise_sheets.dart';
import 'widgets/hold_pad.dart';
import 'widgets/rest_timer.dart';
import 'widgets/set_row.dart';
import '../../core/widgets/toast.dart';

/// Which value the keypad is currently editing.
class EditTarget {
  const EditTarget(this.setId, this.field);

  final String setId;
  final SetField field;

  @override
  bool operator ==(Object other) =>
      other is EditTarget && other.setId == setId && other.field == field;

  @override
  int get hashCode => Object.hash(setId, field);
}

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key, required this.workoutId});

  final String workoutId;

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen>
    with WidgetsBindingObserver {
  EditTarget? _editing;

  /// Set when the hold pad has been sent away in favour of the digits, for a
  /// hold that was timed on the gym clock or is being corrected hours later.
  /// Cleared on every focus change: the stopwatch is the answer for the next
  /// set even when it was not for this one.
  bool _typeHold = false;

  /// The focused cell counts seconds rather than reps, so its buffer is a
  /// clock's digits (`225` → `2:25`) and everything reading that buffer has to
  /// convert rather than parse. Set in [_focus] and true for exactly one field
  /// type: the count column of a movement measured in time.
  bool _timeField = false;

  /// The digits are landing in the set's partial count rather than its full
  /// reps. Follows whichever half of a split count cell was last tapped, and
  /// the pad's `F` / `P`.
  bool _partialField = false;

  /// The set whose count cell is showing its partial half.
  ///
  /// Deliberately not the same thing as [_partialField], which only says where
  /// the digits are going. **Only the pad's `F` closes the half**: tapping the
  /// reps side to fix the reps moves the cursor, and taking the partial box
  /// away underneath that tap would lose the number it was opened for. Moving
  /// to another cell entirely closes it too — the row reads this against
  /// [EditTarget.setId].
  String? _partialShownFor;

  /// The set whose partials were just cleared by `F`.
  ///
  /// `F` means "this set is all full reps", so it erases the count as well as
  /// closing the box. Both the row's own number and the ghost's would otherwise
  /// re-open the split — the row's because the clearing write has not come back
  /// through the stream yet, the ghost's because it never changes — and the
  /// key would look like it had done nothing.
  String? _partialClosedFor;

  /// What was in the buffer the last time the F/P key was pressed, one for
  /// each side. Both cleared on every focus change.
  String? _fullStash;
  String? _partialStash;

  /// The keypad's in-progress text, held in a notifier rather than in state.
  ///
  /// It used to be a plain field passed down as a widget parameter, so every
  /// digit rebuilt the exercise page and every SetRow on it — the largest
  /// rebuild in the app, on its most frequent interaction. Only the cell being
  /// typed into and the keypad's own readout listen now.
  final _buffer = ValueNotifier<String>('');

  /// The set row currently swiped open, if any. Shared by every row on the
  /// screen so that opening one closes the last — two rows sitting open at once
  /// makes the next tap a guess.
  final _openSwipe = ValueNotifier<String?>(null);
  Timer? _clock;
  DateTime? _restStartedAt;
  int _restTargetSeconds = kDefaultRestSeconds;

  /// **Who owns the end of this rest.**
  ///
  /// True while the OS holds an exact alarm for it and this screen has not
  /// taken the job back. The alarm is armed the moment the rest starts rather
  /// than when the app is backgrounded, which is the fix for a rest that never
  /// made a sound: backgrounding is not the only way this process stops
  /// running, and every other way left nothing scheduled at all — so the tone
  /// arrived when the phone was picked back up, or not at all.
  ///
  /// A beat before it is due, [_takeBackRestAlert] cancels the alarm and hands
  /// the moment to [_fireAt], so a phone you are looking at buzzes without
  /// throwing a notification across the screen. If this process is asleep, the
  /// hand-back never runs and the alarm rings on time.
  bool _alarmArmed = false;

  /// Cancels the OS alarm just before it would fire. [_fireAt] then does it
  /// in-app, on the second.
  Timer? _preFire;
  Timer? _fireAt;

  /// How early the alert is taken back from the OS. Long enough for the cancel
  /// to reach the alarm manager, short enough that losing the window costs a
  /// rest alert only if the process is suspended inside it.
  static const _handover = Duration(milliseconds: 400);

  /// A hair past the end of the rest rather than exactly on it.
  ///
  /// [_checkRestElapsed] reads whole seconds off `DateTime.difference`, which
  /// truncates: a timer that lands a millisecond early sees one second still
  /// on the clock, declines to fire, and leaves the tone to the one-second
  /// clock — which is the imprecision the timer exists to avoid.
  static const _fireMargin = Duration(milliseconds: 50);

  /// Where this process is, as of the last callback.
  ///
  /// The alert is only ever taken back from the OS while this is `resumed`.
  /// Backgrounded, the timers may keep running for a while yet — Android does
  /// not suspend a process the instant it stops being visible — and taking the
  /// alert back there would cancel a working alarm in favour of playing audio
  /// from a process that is on its way to being frozen. That is the bug this
  /// whole file exists to stop, arrived at from the other direction.
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Whether the rest now running is the gap between two exercises rather than
  /// between two sets of one. The ± writes itself down against the exercise on
  /// screen, and that number is not the exercise's — see [_adjustRest].
  bool _restIsBetweenExercises = false;

  /// The target belonging to the exercise now on screen, held back while a
  /// rest started under the previous exercise is still running. Turning the
  /// page mid-rest used to swap the target under the running clock, so a rest
  /// with forty seconds left jumped back up to two minutes.
  int? _pendingRestTarget;

  /// Set once the current rest has reached zero, so the buzz fires on the
  /// crossing and not on every tick after it. Cleared whenever the rest is
  /// restarted or extended past zero.
  bool _restAlerted = false;

  /// Whether the rest bar is on screen. Separate from [_restStartedAt] on
  /// purpose: the bar goes away shortly after the buzz — counting overtime is
  /// a number nobody acts on — but the start time has to survive, because the
  /// rest a set actually got is measured from it.
  bool _showRestBar = false;
  Timer? _restBarHide;

  /// The display unit for this build. Stored values are always kg.
  WeightUnit _unit = WeightUnit.kg;

  /// Whether the opening exercise's rest target has been fetched yet.
  bool _restTargetLoaded = false;

  /// What the ongoing notification was last posted with, so a keystroke does
  /// not re-post a line that has not changed.
  String? _notifiedSignature;

  /// The keystroke waiting to be written, and its debounce.
  ({EditTarget target, String value})? _pending;
  Timer? _pendingWrite;

  // Latest build's data, so callbacks can resolve a set's ghost values without
  // threading them through every widget.
  Map<String, PrefillResult> _prefill = const {};
  WorkoutDetail? _detail;

  /// One exercise per page. Scrolling a long vertical stack mid-set was the
  /// thing this replaces: you only ever care about the movement in front of
  /// you, and the rail above keeps the rest of the session in view.
  final _pages = PageController();
  int _page = 0;

  /// A page to land on as soon as the workout comes back holding it.
  ///
  /// [_goToPage] can only reach a page that exists in the build it runs in, and
  /// an exercise added a moment ago is not in one yet — the write has been made,
  /// the watched query has not returned. Adding an exercise therefore landed on
  /// the last of the *old* pages, which is the one it was already on.
  int? _wantedPage;

  @override
  void initState() {
    super.initState();
    // The screen going off is what breaks the rest clock — see
    // [didChangeAppLifecycleState].
    WidgetsBinding.instance.addObserver(this);
    // The tick no longer rebuilds the screen. It used to call setState on the
    // whole log — PageView included — once a second whether or not anything on
    // it showed a clock; the two widgets that need one now tick themselves.
    // This is left running only to catch the moment rest reaches zero, which
    // has to fire even with the keypad covering the bar.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _checkRestElapsed();
      // The bar on the lock screen is drained a second at a time from here.
      // Only while a rest is on the clock: between sets that line says a set
      // count, and a set count does not change once a second.
      if (_restStartedAt != null && _showRestBar && !_restAlerted) {
        _postSessionNotification();
      }
    });
    // The whole point of this screen is to be put down between sets, so the
    // screen must not lock while a workout is open.
    WakelockPlus.enable().ignore();
    // Load the tone now; the first rest of the session shouldn't be the one
    // that pays for decoding it.
    RestAlert.instance.warmUp().ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // A workout you have left holds no row on the lock screen, and no alarm.
    WorkoutNotifications.instance.clear().ignore();
    _clock?.cancel();
    _preFire?.cancel();
    _fireAt?.cancel();
    _restBarHide?.cancel();
    _buffer.dispose();
    _openSwipe.dispose();
    // Anything typed in the last 300ms still belongs to the log.
    _flushWrite();
    WakelockPlus.disable().ignore();
    RestAlert.instance.release().ignore();
    _pages.dispose();
    super.dispose();
  }

  /// Re-arms the rest alert around a process that may be about to stop, or has
  /// just started, running.
  ///
  /// Everything on this screen that counts — the bar, the buzz — is driven by
  /// a Dart `Timer`, and Android freezes those the moment the process is
  /// suspended. The alarm that covers that is now armed at the *start* of
  /// every rest ([_armRestAlert]) rather than here, because this method used
  /// to be the only thing that armed it: a process suspended without a clean
  /// `paused` — or one whose timers were simply throttled behind a screen that
  /// stayed on — had nothing scheduled, and the tone played when the phone was
  /// picked back up, or never.
  ///
  /// What is left here are the two edges. On the way out, an alert this screen
  /// had already taken back for itself is handed to the OS again, so the
  /// 400 ms hand-over window cannot swallow it. On the way back in, the alarm
  /// and the hand-over are both re-scheduled against the wall clock, which
  /// moved while the timers did not.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _lifecycle = state;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Whatever was typed in the last 300ms goes in before the process can
        // be taken away. `dispose` flushes for every ordinary way of leaving
        // this screen, and Android's way of ending an app is not one of them:
        // backgrounded, the process is killed without ever unwinding the tree,
        // so the pending keystroke went with it. One digit, one set — the same
        // number the debounce exists to avoid writing eight times, lost for the
        // one reason it must not be.
        _flushWrite();
        if (_restStartedAt != null && !_restAlerted) _armRestAlert();
      case AppLifecycleState.resumed:
        // The clock kept running in the world while it was stopped in here, so
        // a rest that ended while the phone was away is settled on sight
        // rather than up to a second later.
        _checkRestElapsed();
        if (_restStartedAt != null && !_restAlerted) _armRestAlert();
      case AppLifecycleState.inactive:
        // A shade pulled halfway down, a call coming in. Nothing has stopped.
        break;
    }
    _postSessionNotification();
  }

  /// Keeps the ongoing lock-screen line in step with the session.
  ///
  /// Posted under one id every time, so it updates a single row rather than
  /// stacking one up per set. While a rest runs this is called once a second,
  /// from the clock in [initState]: the bar on that line is drained by the
  /// value posted to it and by nothing else, and the time left is written into
  /// the body beside it for the same reason.
  void _postSessionNotification() {
    final detail = _detail;
    if (detail == null) return;
    final startedAt = _restStartedAt;
    final resting = startedAt != null && _showRestBar && !_restAlerted;
    final done = _doneSets(detail);
    final total = _totalSets(detail);
    // The movement in front of you, which is the one thing the count could
    // never say. Glanced at from a bench, "1:47 · Incline press" says how long
    // and what is next; "3 of 12 sets" says where the session is, and that
    // belongs in the header line rather than in place of it.
    final exercise = _currentExerciseName(detail);
    final left = resting
        ? _restTargetSeconds - DateTime.now().difference(startedAt).inSeconds
        : null;
    WorkoutNotifications.instance
        .showSession(
          title: detail.session?.name ?? 'Workout',
          body: left != null
              ? [formatRestClock(left), ?exercise].join(' · ')
              : exercise ?? '$done of $total sets',
          done: done,
          total: total,
          restSecondsLeft: left,
          restTargetSeconds: resting ? _restTargetSeconds : null,
        )
        .ignore();
  }

  /// What the rest alert says under "Rest done": the movement it is a rest
  /// from, falling back to the session when the workout is still empty. The
  /// session's name was all it ever said, which on a phone in a pocket is the
  /// one thing you already know.
  String? _restAlertBody() {
    final detail = _detail;
    if (detail == null) return null;
    return _currentExerciseName(detail) ?? detail.session?.name;
  }

  /// The exercise the log is open on, or null for a workout with nothing in it
  /// yet.
  String? _currentExerciseName(WorkoutDetail detail) {
    if (detail.entries.isEmpty) return null;
    final page = math.max(0, math.min(detail.entries.length - 1, _page));
    return detail.entries[page].exercise.name;
  }

  /// Buzzes once when rest reaches zero. Without this the timer only ever
  /// turns green, which you can't see with the phone face down on a bench.
  void _checkRestElapsed() {
    final startedAt = _restStartedAt;
    if (startedAt == null) {
      _restAlerted = false;
      return;
    }
    final remaining =
        _restTargetSeconds - DateTime.now().difference(startedAt).inSeconds;
    if (remaining > 0) {
      // An extended target puts rest back on the clock, so re-arm the alert.
      _restAlerted = false;
      return;
    }
    if (_restAlerted) return;
    _restAlerted = true;
    _preFire?.cancel();
    _fireAt?.cancel();
    if (_alarmArmed) {
      // The OS still holds this one, which means it has already rung — or is
      // about to, within the second. This is the path a phone left face down
      // comes back on, and firing here as well is what used to make the tone
      // play a second time when it was picked up. Nothing to do but record
      // that the rest is over.
      _alarmArmed = false;
    } else {
      _fireInAppAlert();
    }
    // The countdown on the lock screen is over too, and nothing else rebuilds
    // this screen for another five seconds.
    _postSessionNotification();
    // Hold the "done" state briefly so picking the phone up right after the
    // buzz still shows what happened, then get out of the way.
    _restBarHide?.cancel();
    _restBarHide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showRestBar = false);
    });
  }

  /// How long the set being completed actually rested, or null when it is the
  /// first set of the exercise and there was nothing to rest from.
  ///
  /// Capped: a set completed forty minutes after the last one is a phone left
  /// on a bench, not a rest interval, and storing it would poison the default
  /// for next week.
  int? _restTakenSeconds() {
    final startedAt = _restStartedAt;
    if (startedAt == null) return null;
    final seconds = DateTime.now().difference(startedAt).inSeconds;
    if (seconds <= 0 || seconds > 1800) return null;
    return seconds;
  }

  /// Loads the rest target for the exercise now on screen.
  ///
  /// Per exercise rather than one number for the session: the target used to
  /// reset to 120 s every time the log opened, which is wrong for a heavy
  /// squat and wrong again for a cable fly.
  Future<void> _loadRestTarget(WorkoutDetail detail, int index) async {
    if (index < 0 || index >= detail.entries.length) return;
    final seconds = await ref
        .read(trainingRepositoryProvider)
        .restTargetFor(
          exerciseId: detail.entries[index].exercise.id,
          sessionId: detail.workout.sessionId,
        );
    if (!mounted) return;
    // A clock already counting down belongs to the set that started it. The
    // new exercise's target takes over at the next rest, not in the middle of
    // this one.
    if (_restRunning) {
      _pendingRestTarget = seconds;
      return;
    }
    setState(() {
      _pendingRestTarget = null;
      _restTargetSeconds = seconds;
    });
  }

  /// Whether rest is still on the clock. Past zero the bar says "Rest done"
  /// and the number is no longer being counted, so a new target may land.
  bool get _restRunning {
    final startedAt = _restStartedAt;
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt).inSeconds < _restTargetSeconds;
  }

  /// Everything Settings decides about rest. Read rather than watched: this
  /// screen does not redraw for a preference, it consults it at the moment a
  /// rest starts or ends.
  RestPrefs get _restPrefs =>
      ref.read(restPrefsProvider).valueOrNull ?? restPrefsDefaults;

  /// How long the rest after [setId] should run and whether it is the gap
  /// between two exercises, or null when there is nothing left to rest for.
  ///
  /// Two durations, because they are two different pauses. Another set of the
  /// same movement is the exercise's own rest. The last set of an exercise is
  /// the walk to the next machine, which has one number for the whole app —
  /// [RestPrefs.betweenExercises] — because it is a property of the gym rather
  /// than of the lift.
  ///
  /// [setId] is excluded by id rather than by its flag: the write marking it
  /// done is still in flight, so it is still open in the snapshot this reads.
  (int, bool)? _restDurationAfter(String setId) {
    final detail = _detail;
    if (detail == null) return null;

    var openHere = false;
    var openElsewhere = false;
    for (final entry in detail.entries) {
      if (entry.workoutExercise.skipReason != SkipReason.none) continue;
      final holdsIt = entry.sets.any((s) => s.id == setId);
      for (final set in entry.sets) {
        if (set.id == setId || set.isDone) continue;
        if (holdsIt) {
          openHere = true;
        } else {
          openElsewhere = true;
        }
      }
    }

    // A target held back by a page turn is the newest word on this exercise —
    // see [_pendingRestTarget].
    if (openHere) return (_pendingRestTarget ?? _restTargetSeconds, false);
    if (openElsewhere) return (_restPrefs.betweenExercises, true);
    return null;
  }

  void _startRest((int, bool) rest) {
    final (seconds, betweenExercises) = rest;
    _restBarHide?.cancel();
    setState(() {
      _restTargetSeconds = seconds;
      _restIsBetweenExercises = betweenExercises;
      _pendingRestTarget = null;
      _restStartedAt = DateTime.now();
      _restAlerted = false;
      _showRestBar = true;
    });
    _armRestAlert();
  }

  /// Hands the end of this rest to the OS, and books the moment to take it
  /// back.
  ///
  /// The alarm is the reliable half: `AlarmManager` fires whether or not this
  /// process is running, and it is armed here — at the start of the rest —
  /// precisely because there is no later moment this screen can count on
  /// reaching. [_preFire] then cancels it a blink before it is due, so a phone
  /// you are holding gets the in-app tone rather than a notification thrown
  /// across the log; if the process is asleep by then, that cancel never runs
  /// and the alarm rings on time.
  ///
  /// Safe to call again at any point in a rest: both the alarm and the timers
  /// are replaced rather than added to.
  void _armRestAlert() {
    final startedAt = _restStartedAt;
    if (startedAt == null || _restAlerted) return;
    final endsAt = startedAt.add(Duration(seconds: _restTargetSeconds));

    _alarmArmed = true;
    WorkoutNotifications.instance
        .scheduleRestDone(
          endsAt,
          body: _restAlertBody(),
          sound: _restPrefs.sound,
        )
        .ignore();

    _preFire?.cancel();
    _fireAt?.cancel();
    _preFire = Timer(_untilNow(endsAt.subtract(_handover)), _takeBackRestAlert);
  }

  /// Takes the alert back from the OS and fires it here instead, on the second.
  ///
  /// Refused unless this process is on screen. A backgrounded app still runs
  /// its timers for a while, so without this the alert would be taken off a
  /// working alarm and handed to audio playback from a process the system is
  /// about to freeze — silence at 0:00, which is the whole complaint. The
  /// alarm simply stays armed and rings; a later resume re-books the hand-over
  /// if there is still rest left to run.
  void _takeBackRestAlert() {
    final startedAt = _restStartedAt;
    if (!mounted || !_alarmArmed || _restAlerted || startedAt == null) return;
    if (_lifecycle != AppLifecycleState.resumed) return;
    _alarmArmed = false;
    WorkoutNotifications.instance.cancelRest().ignore();

    // Not left to the one-second clock: it is not aligned to the end of the
    // rest, so the tone would land up to a second after 0:00.
    final endsAt = startedAt.add(Duration(seconds: _restTargetSeconds));
    _fireAt?.cancel();
    _fireAt = Timer(_untilNow(endsAt.add(_fireMargin)), () {
      if (mounted) _checkRestElapsed();
    });
  }

  /// The in-app half of the alert, with the OS behind it.
  ///
  /// This runs only where the alarm has already been cancelled, so if the tone
  /// will not play there is nothing else left to make a sound — and a rest
  /// that ends in silence is the bug being fixed, not an acceptable outcome.
  /// So a refusal is answered by posting the alert that was taken back.
  void _fireInAppAlert() {
    final sound = _restPrefs.sound;
    final name = _restAlertBody();
    RestAlert.instance.fire(sound: sound).then((played) {
      // `sound` is checked again rather than leaned on: `fire` reports a silent
      // rest as discharged, so this is unreachable with the switch off — and a
      // fallback that could make a noise the switch forbids is not something
      // to leave resting on that.
      if (played || !sound) return;
      WorkoutNotifications.instance.showRestDoneNow(body: name).ignore();
    }).ignore();
  }

  /// A delay that is never negative — a `Timer` built from one fires late
  /// rather than immediately on some platforms, and every caller here means
  /// "now" by it.
  static Duration _untilNow(DateTime at) {
    final delay = at.difference(DateTime.now());
    return delay.isNegative ? Duration.zero : delay;
  }

  /// Drops a pending alert without ending the rest. The next [_armRestAlert]
  /// or [_checkRestElapsed] decides what happens instead.
  void _cancelRestAlert() {
    _preFire?.cancel();
    _fireAt?.cancel();
    if (!_alarmArmed) return;
    _alarmArmed = false;
    WorkoutNotifications.instance.cancelRest().ignore();
  }

  /// Nudging the timer sets the target for this exercise, for good: next week
  /// opens on the number you settled on.
  Future<void> _adjustRest(WorkoutDetail detail, int delta) async {
    final seconds = clampRest(_restTargetSeconds + delta);
    // A hand on the ± is the latest word on the target, so a value held back
    // by a page turn does not get to overwrite it at the next set.
    final startedAt = _restStartedAt;
    final stillRunning =
        startedAt != null &&
        DateTime.now().difference(startedAt).inSeconds < seconds;
    setState(() {
      _restTargetSeconds = seconds;
      _pendingRestTarget = null;
      // An extended target puts rest back on the clock, and the alert with it.
      if (stillRunning) _restAlerted = false;
    });
    // The alert is booked against an end time, and the end time just moved.
    _cancelRestAlert();
    if (stillRunning) {
      _armRestAlert();
    } else {
      _checkRestElapsed();
    }

    // **A nudge on this bar is not always about the exercise on screen.**
    // The gap between two exercises has one number for the whole app and it
    // lives in Settings; the ± writes itself down against the slot the page is
    // showing, which during that gap is the exercise you have just finished or
    // the one you are walking to. Writing there would quietly give a movement
    // a rest that was never about it. Today only, then, and the lasting
    // number stays a Settings decision.
    if (_restIsBetweenExercises) return;

    if (detail.entries.isEmpty) return;
    final page = math.max(0, math.min(detail.entries.length - 1, _page));
    final entry = detail.entries[page];
    final saved = await ref
        .read(trainingRepositoryProvider)
        .setRestTarget(
          exerciseId: entry.exercise.id,
          sessionId: detail.workout.sessionId,
          seconds: seconds,
        );

    // An exercise added mid-session has no slot in the template to hold this,
    // so the write matches nothing. Silently forgetting it is worse than
    // saying so: the timer would simply be back at 120s next week.
    if (saved || !mounted) return;
    showToast(
      context,
      'Rest set for today only. ${entry.exercise.name} is not in this '
      'session\'s template, so the change is not remembered.',
    );
  }

  void _dismissRestBar() {
    _restBarHide?.cancel();
    setState(() => _showRestBar = false);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref
        .watch(workoutDetailProvider(widget.workoutId))
        .valueOrNull;
    // Everything below reads the order the finger asked for, not the one the
    // database has got round to.
    final detail = loaded == null ? null : _withPendingOrder(loaded);
    // Null while it is still resolving, which is **not** the same as a workout
    // with no history behind it. Defaulting to an empty map made this screen
    // paint its rows with no ghosts in them and then fill them in a frame or
    // two later — last week's numbers appearing under a finger already on its
    // way to the keypad. There are two queries here, so the screen has to tell
    // loading from empty (RULES § Interface) and it waits for both below.
    final prefill = ref
        .watch(workoutPrefillProvider(widget.workoutId))
        .valueOrNull;
    _prefill = prefill ?? const {};
    _detail = detail;
    // Everything below the database speaks the display unit; everything at or
    // below the repository speaks kilograms.
    _unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    // Watched, though nothing on this screen draws it: [_restPrefs] reads it
    // at the moment a set is ticked, and a provider nobody has subscribed to
    // has not run its query yet — so the first rest of the session would have
    // used the shipped defaults rather than the numbers in Settings.
    ref.watch(restPrefsProvider);

    // The first page's rest target isn't known until the workout loads.
    if (detail != null && !_restTargetLoaded) {
      _restTargetLoaded = true;
      _loadRestTarget(detail, _page);
    }

    // Both, or neither. A set row without its ghost is a row that has to be
    // redrawn the moment the ghost lands, and the tap that opens this screen
    // has already resolved the prefill it needs — `startWorkout` hands it
    // forward — so on the path that matters this costs nothing.
    if (detail == null || prefill == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final wanted = _wantedPage;
    if (wanted != null && wanted < detail.entries.length) {
      _wantedPage = null;
      // After the frame: the PageView is being built with this exercise in it
      // right now, and animating to a page that does not exist yet does
      // nothing at all.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToPage(wanted);
      });
    }

    // The lock-screen line follows this screen's state rather than being
    // posted from each of the six places that change it. A signature, so a
    // build caused by a keystroke does not re-post a notification that says
    // exactly what it said a moment ago.
    final signature = [
      detail.session?.name,
      // A page turn changes what the line says, and nothing else in this list
      // moves when it does.
      _currentExerciseName(detail),
      _doneSets(detail),
      _totalSets(detail),
      _showRestBar,
      _restAlerted,
      _restStartedAt?.millisecondsSinceEpoch,
      _restTargetSeconds,
    ].join('|');
    if (signature != _notifiedSignature) {
      _notifiedSignature = signature;
      _postSessionNotification();
    }

    final cells = _buildCells(detail);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back dismisses the keypad first: it covers half the screen, and
        // losing the whole session to one stray swipe would be unforgivable.
        if (_editing != null) {
          setState(() => _editing = null);
          return;
        }
        // Leaving without finishing is fine — the session keeps running and
        // survives a force-stop — but it has to be said out loud, or the sets
        // logged so far look lost.
        showToast(context, 'Session still running. Resume it from Today.');
        Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Column(
          children: [
            _LogTopBar(
              title: detail.session?.name ?? 'Workout',
              isDeload: detail.workout.isDeload,
              startedAt: detail.workout.startedAt,
              done: _doneSets(detail),
              total: _totalSets(detail),
              onBack: () => Navigator.of(context).maybePop(),
              onFinish: () => _finish(detail),
            ),
            // No rail with nothing in it. An empty workout left a 68dp band of
            // nothing across the screen with one `+` floating at the far right
            // of it — a second, orphaned way to do exactly what the button in
            // the middle of the empty state does.
            if (detail.entries.isNotEmpty)
              ExerciseRail(
                entries: detail.entries,
                current: math.max(
                  0,
                  math.min(detail.entries.length - 1, _page),
                ),
                onSelect: _goToPage,
                onAdd: () => _addExercise(detail),
                onReorder: (ids) {
                  setState(() => _pendingOrder = ids);
                  ref
                      .read(trainingRepositoryProvider)
                      .reorderWorkoutExercises(ids);
                },
              ),
            Expanded(
              child: detail.entries.isEmpty
                  // Two words and a full stop, where every other empty state in
                  // the app says what will appear here and what it costs you.
                  // The thing worth saying is that adding one here is a change
                  // to today and not to the programme.
                  ? EmptyState(
                      icon: Icons.fitness_center_rounded,
                      title: 'Nothing to log yet',
                      message:
                          'This session has no exercises in it. Anything you '
                          'add goes into today only. The template keeps its '
                          'own list.',
                      action: PrimaryButton(
                        label: 'Add an exercise',
                        onPressed: () => _addExercise(detail),
                      ),
                    )
                  : PageView.builder(
                      controller: _pages,
                      itemCount: detail.entries.length,
                      onPageChanged: (i) => _onPageChanged(detail, i),
                      itemBuilder: (context, index) {
                        final entry = detail.entries[index];
                        return _ExercisePage(
                          key: ValueKey(entry.workoutExercise.id),
                          index: index,
                          total: detail.entries.length,
                          entry: entry,
                          nextName: index + 1 < detail.entries.length
                              ? detail.entries[index + 1].exercise.name
                              : null,
                          prefill: prefill[entry.exercise.id],
                          unit: _unit,
                          editing: _editing,
                          partialShownFor: _partialShownFor,
                          partialClosedFor: _partialClosedFor,
                          partialEditing: _partialField,
                          buffer: _buffer,
                          openSwipe: _openSwipe,
                          onEdit: _focus,
                          onEditPartial: _focusPartial,
                          rowKeyFor: _rowKey,
                          onToggleDone: _toggleDone,
                          onNextExercise: () => _goToPage(index + 1),
                          onReorder: () => _reorderExercises(detail),
                          workout: detail.workout,
                        );
                      },
                    ),
            ),
            // Every set ticked: the only thing left to do is end the session,
            // so it stops being a text action in the corner and becomes the
            // one white button on the screen. Finishing early is still
            // possible from the top bar — it just isn't advertised.
            if (_editing != null ||
                _allSets(detail) == 0 ||
                _doneSets(detail) < _totalSets(detail))
              const SizedBox.shrink()
            else
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.md,
                  Space.gutter,
                  Space.md,
                ),
                child: PrimaryButton(
                  label: 'Finish session',
                  onPressed: () => _finish(detail),
                ),
              ),
            if (_showRestBar && _restStartedAt != null && _editing == null)
              RestTimerBar(
                startedAt: _restStartedAt!,
                targetSeconds: _restTargetSeconds,
                onAdjust: (delta) => _adjustRest(detail, delta),
                onDismiss: _dismissRestBar,
              ),
            if (_editing != null) _keypad(detail, prefill, cells),
          ],
        ),
      ),
    );
  }

  // ── Keypad plumbing ───────────────────────────────────────────────────

  /// Every editable value in the workout, in the order a person fills them in.
  /// Drives the keypad's "Next" so the whole session can be logged without
  /// lifting a thumb.
  List<EditTarget> _buildCells(WorkoutDetail detail) {
    final cells = <EditTarget>[];
    for (final entry in detail.entries) {
      if (entry.workoutExercise.skipReason != SkipReason.none) continue;
      for (final set in entry.sets) {
        switch (entry.exercise.loadMode) {
          case LoadMode.bodyweight:
            break;
          case LoadMode.bodyweightPlus:
            cells.add(EditTarget(set.id, SetField.added));
          case LoadMode.total:
          case LoadMode.perSide:
            cells.add(EditTarget(set.id, SetField.weight));
        }
        cells.add(EditTarget(set.id, SetField.reps));
      }
    }
    return cells;
  }

  /// One key per set row, so the row being typed into can be scrolled back
  /// into view when the keypad takes half the screen.
  final _rowKeys = <String, GlobalKey>{};

  GlobalKey _rowKey(String setId) => _rowKeys.putIfAbsent(setId, GlobalKey.new);

  void _focus(SetLog set, SetField field) {
    _flushWrite();
    final located = _detail == null ? null : _locate(_detail!, set.id);
    final isTime =
        field == SetField.reps &&
        (located?.$1.exercise.measureMode.isHold ?? false);
    // Tapping the reps half of a split cell lands here. The digits follow the
    // tap — that is what tapping a field means — but the partial box stays
    // open, because only the pad's `F` closes it.
    final sameCell = _editing?.setId == set.id && _editing?.field == field;
    setState(() {
      // Leaving the partial half with keystrokes still settling: what is on
      // screen is newer than the row, which will not have caught up until the
      // write comes back through the stream. Coming back to this half has to
      // read this, not the row, or it reloads the number that was there before
      // and writes it straight back — which is how a `3` refused to become a
      // `2`.
      if (sameCell && _partialField) _partialStash = _buffer.value;
      _editing = EditTarget(set.id, field);
      _typeHold = false;
      _timeField = isTime;
      _partialField = false;
      if (!sameCell) {
        _fullStash = null;
        _partialStash = null;
        _partialShownFor = null;
        _partialClosedFor = null;
      }
      _buffer.value = switch (field) {
        SetField.weight => _fmtLoadIn(set.weight),
        SetField.added => _fmtLoadIn(set.addedWeight),
        SetField.reps =>
          isTime
              ? digitsFromSeconds(set.reps ?? 0)
              : set.reps?.toString() ?? '',
      };
    });
    _revealRow(set.id);
  }

  /// The partial half, by tapping it. Opens the count field with the digits
  /// going into the partials rather than the reps — the same state the pad's
  /// `P` puts it in.
  void _focusPartial(SetLog set) {
    _focus(set, SetField.reps);
    setState(() {
      _partialField = true;
      _partialShownFor = set.id;
      _partialClosedFor = null;
      _fullStash = _buffer.value;
      // The stash first: it is what was last typed here, and the row is a
      // build behind whenever a write is still in flight.
      _buffer.value =
          _partialStash ??
          ((set.partialReps ?? 0) == 0 ? '' : '${set.partialReps}');
    });
  }

  /// Opens the partial box, or puts it away — the pad's `F` / `P`.
  ///
  /// **The only control that closes it.** Tapping a half moves the digits into
  /// that half and leaves the split standing; this is the one that decides
  /// whether the set is being given partials at all. Opening lands the digits
  /// in the new box, which is the only reason to have pressed it.
  ///
  /// The pending keystroke is flushed first, because the buffer is about to
  /// mean a different column: switching with a write in flight would land the
  /// full reps in the partial count, or the other way about.
  void _togglePartial(SetLog set) {
    final wasOpen = _partialShownFor == set.id;
    // Where the digits were going, which is not the same question as whether
    // the box was open: the reps half can be the live one with the partial box
    // sitting open beside it.
    final wasInPartial = _partialField;
    final typed = _buffer.value;
    _flushWrite();
    setState(() {
      _partialShownFor = wasOpen ? null : set.id;
      _partialClosedFor = wasOpen ? set.id : null;
      _partialField = !wasOpen;
      // The other side comes back from the stash rather than from the row: the
      // flush above has only just been *sent*, so the row this build is holding
      // still has the number that was there before the last few keystrokes.
      if (wasOpen) {
        // Going back to full is a statement about the set, not just about the
        // pad: whatever partials it had are no longer claimed, so the count is
        // dropped rather than left behind a closed box. Empty rather than
        // null, so pressing `P` straight afterwards starts from nothing — the
        // row is still holding the old number until the clearing write below
        // comes back through the stream.
        _partialStash = '';
        // Closing from the reps half changes nothing about what is being
        // typed — the box going away is the other one.
        _buffer.value = wasInPartial
            ? (_fullStash ?? set.reps?.toString() ?? '')
            : typed;
      } else {
        _fullStash = typed;
        _buffer.value =
            _partialStash ??
            ((set.partialReps ?? 0) == 0 ? '' : '${set.partialReps}');
      }
    });
    if (wasOpen) {
      ref
          .read(trainingRepositoryProvider)
          .updateSet(set.id, partialReps: const Value(null));
    }
  }

  /// The keypad is a sibling in the Column, so opening it shrinks the page
  /// under it. Nothing scrolled the active row back, which on an exercise with
  /// five or more sets could leave you typing into a row you cannot see.
  ///
  /// **Only when the row cannot be seen.** It used to scroll to a fixed
  /// alignment every time, which on the four sets an exercise usually has —
  /// every one of them still on screen with the keypad up — meant the whole
  /// page lurched a little under the thumb on every tap, to reveal something
  /// that was never hidden. The check runs after the frame that inserts the
  /// keypad, so what it measures against is the shortened viewport rather than
  /// the one the row was tapped in.
  void _revealRow(String setId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _rowKeys[setId]?.currentContext;
      if (context == null) return;
      if (_isFullyVisible(context)) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: Motion.base,
        curve: Motion.curve,
      );
    });
  }

  /// Whether the widget at [context] is inside its scrollable's viewport, top
  /// and bottom both. Answers false when there is nothing to measure with,
  /// which puts the scroll back — the old behaviour, and the safe one.
  static bool _isFullyVisible(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box == null || !box.hasSize || viewport is! RenderBox) return false;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return top >= 0 && top + box.size.height <= viewport.size.height;
  }

  Widget _keypad(
    WorkoutDetail detail,
    Map<String, PrefillResult> prefill,
    List<EditTarget> cells,
  ) {
    final target = _editing!;
    final located = _locate(detail, target.setId);
    if (located == null) return const SizedBox.shrink();

    final (entry, set, setPosition) = located;
    final ghost = _ghostFor(
      prefill[entry.exercise.id],
      entry.sets,
      setPosition,
    );
    // Ghosts are stored in kg and shown in the display unit.
    final hint = switch (target.field) {
      SetField.weight => _fmtLoadIn(ghost?.weight),
      SetField.added => _fmtLoadIn(ghost?.addedWeight),
      SetField.reps =>
        ghost?.reps == null
            ? ''
            : entry.exercise.measureMode.isHold
            ? digitsFromSeconds(ghost!.reps!)
            : '${ghost!.reps}',
    };

    // A hold is timed, not typed: the count field on an isometric movement
    // gets a stopwatch in the keypad's slot unless the digits were asked for.
    if (target.field == SetField.reps &&
        entry.exercise.measureMode.isHold &&
        !_typeHold) {
      return HoldPad(
        current: set.reps,
        previous: ghost?.reps,
        onStop: (seconds) {
          _commit(digitsFromSeconds(seconds), target);
          _flushWrite();
          // The same path leaving a reps field takes: it ticks the set, keeps
          // the rest it was given and moves on.
          _advance(detail, cells, target);
        },
        onType: () => setState(() => _typeHold = true),
        onDismiss: () {
          _flushWrite();
          setState(() => _editing = null);
        },
      );
    }

    final isLast = cells.isNotEmpty && cells.last == target;
    // The key has to name what it does. On a reps field with nothing typed and
    // no ghost to borrow from, "Done" completes nothing at all. In partial mode
    // the buffer is not the reps, so the row answers for them.
    final needsReps =
        target.field == SetField.reps &&
        (_partialField
            ? (set.reps ?? 0) <= 0
            : (int.tryParse(_buffer.value) ?? 0) <= 0) &&
        ghost?.reps == null;

    // Partials belong to reps and to nothing else: a hold has no half-second,
    // and a load is not counted at all.
    final canBePartial =
        target.field == SetField.reps && !entry.exercise.measureMode.isHold;

    return SetKeypad(
      field: target.field,
      unit: _unit,
      // The count field only. A weighted plank still types its load in
      // kilograms on the same keypad.
      isTime: _timeField,
      buffer: _buffer,
      // Only for a load that *is* the bar. On `perSide` the number is one
      // dumbbell, and on bodyweight-plus it is what hangs off a belt — neither
      // is a barbell total, so neither gets a plate diagram even if somebody
      // has named a bar on the exercise.
      // The bar this set was logged on, not the bar the catalog names today.
      // A snapshot, like the muscle: null only on a row written before the
      // column existed, and those fall back to the catalog because it is the
      // only answer they ever had.
      barKg: entry.exercise.loadMode == LoadMode.total
          ? (entry.workoutExercise.barKind ?? entry.exercise.barKind).kg
          : null,
      // The key says whether the partial box is **open**, not which box the
      // digits are in. Tapping the reps half to correct them is not leaving
      // partial entry — the box is still there, waiting — and a key that
      // flipped back to `F` on that tap was reporting a mode change nobody
      // asked for.
      partial: _partialShownFor == target.setId,
      onTogglePartial: canBePartial ? () => _togglePartial(set) : null,
      // Last time's number is a full-rep number. Offering it while the digits
      // are going into the partial count would file it as halves.
      hint: hint.isEmpty || _partialField ? null : hint,
      onUseHint: hint.isEmpty || _partialField
          ? null
          : () => _commit(hint, target),
      nextLabel: needsReps
          ? (entry.exercise.measureMode.isHold ? 'Time?' : 'Reps?')
          : isLast
          ? 'Done'
          : 'Next',
      onKey: (key) {
        final next = applyKey(
          _buffer.value,
          key,
          field: target.field,
          unit: _unit,
          isTime: _timeField,
          hint: _timeField
              ? secondsFromDigits(hint).toDouble()
              : double.tryParse(hint),
        );
        _commit(next, target);
      },
      onNext: () => _advance(detail, cells, target),
      onDismiss: () {
        _flushWrite();
        setState(() => _editing = null);
      },
    );
  }

  /// Buffers the keystroke on screen immediately and the write shortly after.
  ///
  /// Every digit used to be its own `updateSet`, and every write re-ran the
  /// three queries behind `watchWorkoutDetail` for the whole workout. Invisible
  /// on a new phone, not on an old one, and it burns battery for an hour a
  /// session. The pending write is flushed on Next, on dismiss, on page turn
  /// and on dispose, so nothing typed can be lost.
  void _commit(String next, EditTarget target) {
    // No setState: the notifier repaints the one cell and the readout.
    _buffer.value = next;
    _pendingWrite?.cancel();
    _pending = (target: target, value: next);
    _pendingWrite = Timer(const Duration(milliseconds: 300), _flushWrite);
  }

  void _flushWrite() {
    _pendingWrite?.cancel();
    _pendingWrite = null;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;

    final repo = ref.read(trainingRepositoryProvider);
    final typed = double.tryParse(pending.value);
    // Typed in the display unit, stored in kilograms — always.
    final parsed = typed == null ? null : _unit.toKg(typed);

    switch (pending.target.field) {
      case SetField.weight:
        repo
            .updateSet(pending.target.setId, weight: Value(parsed))
            .reportOnError('That weight could not be saved.');
      case SetField.added:
        repo
            .updateSet(pending.target.setId, addedWeight: Value(parsed))
            .reportOnError('That weight could not be saved.');
      case SetField.reps:
        // A clock buffer is digits, not a number: `225` is 145 seconds, and
        // `int.parse` would store it as two hundred and twenty-five.
        final count = _timeField
            ? secondsFromDigits(pending.value)
            : typed?.round();
        final value = Value(count == 0 ? null : count);
        repo
            .updateSet(
              pending.target.setId,
              reps: _partialField ? const Value.absent() : value,
              partialReps: _partialField ? value : const Value.absent(),
            )
            .reportOnError('That count could not be saved.');
    }
  }

  /// Moves to the next value. Leaving a reps field marks that set complete and
  /// starts the rest clock — the two things you'd otherwise forget to do.
  void _advance(WorkoutDetail detail, List<EditTarget> cells, EditTarget from) {
    _flushWrite();

    if (from.field == SetField.reps) {
      // Read the buffer, not the row: the write for this keystroke may still be
      // in flight, and a stale row would silently skip marking the set done.
      //
      // Except in partial mode, where the buffer holds the partials and the
      // full reps are whatever was typed before the toggle — already flushed
      // above, so the row is the honest source for them.
      var reps = _partialField
          ? (_locate(detail, from.setId)?.$2.reps ?? 0)
          : _timeField
          ? secondsFromDigits(_buffer.value)
          : int.tryParse(_buffer.value) ?? 0;
      // A weight with no reps used to do nothing at all while the key said
      // "Done": the keypad simply closed. Fall back to last time's reps, which
      // is what adopting the ghost would have written anyway; with no ghost to
      // fall back on the key says "Reps?" and this never runs.
      // Not in partial mode: the buffer there is the partial count, and
      // committing last time's reps into it would file eight full reps as
      // eight halves.
      if (reps <= 0 && !_partialField) {
        final located = _locate(detail, from.setId);
        if (located != null) {
          final ghost = _ghostFor(
            _prefill[located.$1.exercise.id],
            located.$1.sets,
            located.$3,
          );
          if (ghost?.reps != null) {
            reps = ghost!.reps!;
            _commit(
              _timeField ? digitsFromSeconds(reps) : reps.toString(),
              from,
            );
            _flushWrite();
          }
        }
      }

      if (reps > 0) {
        // The count is settled — typed, timed, or taken from the ghost a few
        // lines up and already flushed. **The load may still be blank**, and
        // until now this path ticked anyway: on a movement you have never done
        // there is no ghost to adopt from, so a first-ever set went down with
        // reps and no weight. Same refusal the box has always made.
        //
        // `repsOverride` because the row is a build behind the buffer: the
        // count was written a moment ago and the watched query has not come
        // back with it, so asking the row would report reps missing when they
        // are not.
        if (_refuseIncomplete(from.setId, repsOverride: reps)) return;
        _adoptGhost(from.setId, skipCount: true);
        // Rest was already being measured; it was simply thrown away. Absent
        // rather than null when there is none to record: re-ticking a set an
        // hour later must not erase the rest it was actually given.
        final rest = _restTakenSeconds();
        ref
            .read(trainingRepositoryProvider)
            .updateSet(
              from.setId,
              isDone: const Value(true),
              restSeconds: rest == null ? const Value.absent() : Value(rest),
            )
            .reportOnError('That set could not be saved.');
        HapticFeedback.mediumImpact();
        // Not after the last one. The rest bar has nothing to count towards
        // with the work over, and it sits directly under the button asking you
        // to finish — the tick path already knew this and this one did not.
        final nextRest = _restDurationAfter(from.setId);
        if (nextRest != null) _startRest(nextRest);
      } else {
        // Nothing to complete the set with: keep the field, keep the keypad.
        return;
      }
    }

    final index = cells.indexOf(from);
    if (index < 0 || index + 1 >= cells.length) {
      setState(() => _editing = null);
      return;
    }

    final next = cells[index + 1];
    final located = _locate(detail, next.setId);
    if (located == null) {
      setState(() => _editing = null);
      return;
    }

    // Walking off the end of an exercise turns the page with you.
    final page = _pageOf(detail, next.setId);
    if (page >= 0 && page != _page) {
      _goToPage(page);
    }

    _focus(located.$2, next.field);
  }

  (ExerciseEntry, SetLog, int)? _locate(WorkoutDetail detail, String setId) {
    for (final entry in detail.entries) {
      for (var i = 0; i < entry.sets.length; i++) {
        if (entry.sets[i].id == setId) return (entry, entry.sets[i], i);
      }
    }
    return null;
  }

  // ── Mutations ─────────────────────────────────────────────────────────

  void _toggleDone(SetLog set, bool done) {
    if (done) {
      // Last time's numbers fill the blanks first: same weight as last week,
      // one more rep is the normal case and shouldn't need typing.
      _adoptGhost(set.id);

      // A set with nothing in it — and nothing coming from last time either —
      // cannot be ticked. Send the thumb to the empty field instead of arguing
      // about it. See [missingBeforeDone] for why.
      if (_refuseIncomplete(set.id)) return;
    }
    // The same write the keypad's "Next" makes. Ticking the box by hand used to
    // record no rest at all, so how long a set rested depended on which of two
    // ways you had marked it done.
    final rest = done ? _restTakenSeconds() : null;
    ref
        .read(trainingRepositoryProvider)
        .updateSet(
          set.id,
          isDone: Value(done),
          restSeconds: rest == null ? const Value.absent() : Value(rest),
        )
        .reportOnError('That set could not be saved.');
    if (!done) return;
    HapticFeedback.mediumImpact();

    final nextRest = _restDurationAfter(set.id);
    if (nextRest != null) _startRest(nextRest);
    _followTick(set.id);
  }

  /// Sends the thumb to the next set after one is ticked.
  ///
  /// Ticking a box used to leave the keypad wherever it was — usually on the
  /// row you had just finished — so the next set began with a tap to move and a
  /// tap to open. The next open set is the only thing you can do next, and past
  /// the last one on a page it is on the page after it.
  ///
  /// With nothing open left, the keypad goes away instead: the session is
  /// finished, and the screen's one remaining action is the button underneath
  /// it, which cannot be seen with the pad up.
  void _followTick(String setId) {
    final detail = _detail;
    if (detail == null) return;

    final open = _nextOpenSetAfter(detail, setId);
    if (open == null) {
      setState(() => _editing = null);
      return;
    }

    final page = _pageOf(detail, open.id);
    if (page >= 0 && page != _page) _goToPage(page);
    // The field standing between that set and being logged, or its count when
    // last time's numbers already fill the rest.
    _focus(open, _firstEmptyField(open.id) ?? SetField.reps);
  }

  /// The first set after [setId] still waiting to be logged, in the order the
  /// page turns. Skipped exercises are not in the walk — their sets are never
  /// going to be ticked, so landing on one is a dead end.
  SetLog? _nextOpenSetAfter(WorkoutDetail detail, String setId) {
    final ordered = [
      for (final entry in detail.entries)
        if (entry.workoutExercise.skipReason == SkipReason.none) ...entry.sets,
    ];
    final at = ordered.indexWhere((s) => s.id == setId);
    if (at < 0) return null;
    // Only forwards. A set ticked out of order in the middle of an exercise
    // should carry on down the table, not send the page back to a row above it.
    for (final set in ordered.skip(at + 1)) {
      if (!set.isDone) return set;
    }
    return null;
  }

  /// The field standing between this set and being logged, if any.
  ///
  /// Reps are always required. A load is required unless the movement is
  /// bodyweight, where there is nothing to enter.
  ///
  /// A blank the ghost is about to fill does not count. This read the row as it
  /// stood in the last build, but [_adoptGhost] runs immediately before it and
  /// its writes have not come back yet — so a set with last time's numbers
  /// waiting for it looked empty, and the first tap on the tick only filled the
  /// fields and opened the keypad. Logging the same numbers as last week, which
  /// is the single most common thing to do on this screen, took two taps on the
  /// same box and looked like the first one had missed.
  /// The rule itself is [missingBeforeDone]; this only finds the numbers to
  /// hand it. Both tick paths ask through here — see [_refuseIncomplete].
  SetField? _firstEmptyField(String setId, {int? repsOverride}) {
    final detail = _detail;
    if (detail == null) return null;
    final located = _locate(detail, setId);
    if (located == null) return null;
    final (entry, set, position) = located;
    final ghost = _ghostFor(_prefill[entry.exercise.id], entry.sets, position);

    return missingBeforeDone(
      loadMode: entry.exercise.loadMode,
      weight: set.weight,
      addedWeight: set.addedWeight,
      // The keypad's path knows the count from its buffer before the row has
      // caught up with it — see [_advance].
      reps: repsOverride ?? set.reps,
      ghostWeight: ghost?.weight,
      ghostAddedWeight: ghost?.addedWeight,
      ghostReps: ghost?.reps,
    );
  }

  /// Sends the thumb to what is missing rather than ticking an empty set, and
  /// says whether it did.
  ///
  /// Shared by the box and the keypad so the two cannot drift: the box has
  /// always refused an empty set, and Next never did, which is how a first-ever
  /// movement could be logged with reps and no load at all.
  bool _refuseIncomplete(String setId, {int? repsOverride}) {
    final empty = _firstEmptyField(setId, repsOverride: repsOverride);
    if (empty == null) return false;
    HapticFeedback.selectionClick();
    final located = _locate(_detail!, setId);
    if (located != null) _focus(located.$2, empty);
    return true;
  }

  /// Completes a set's blanks from last time's numbers.
  ///
  /// Typing only the reps is the normal case — same weight as last week, one
  /// more rep. Without this the set would be stored as reps against a null
  /// load: invisible to the progress chart, and unable to register as a PR.
  void _adoptGhost(String setId, {bool skipCount = false}) {
    final detail = _detail;
    if (detail == null) return;
    final located = _locate(detail, setId);
    if (located == null) return;

    final (entry, set, position) = located;
    final ghost = _ghostFor(_prefill[entry.exercise.id], entry.sets, position);
    if (ghost == null) return;

    final repo = ref.read(trainingRepositoryProvider);
    switch (entry.exercise.loadMode) {
      case LoadMode.bodyweightPlus:
        if (set.addedWeight == null && ghost.addedWeight != null) {
          repo
              .updateSet(setId, addedWeight: Value(ghost.addedWeight))
              .reportOnError('Last time\'s weight could not be filled in.');
        }
      case LoadMode.total:
      case LoadMode.perSide:
        if (set.weight == null && ghost.weight != null) {
          repo
              .updateSet(setId, weight: Value(ghost.weight))
              .reportOnError('Last time\'s weight could not be filled in.');
        }
      case LoadMode.bodyweight:
        break;
    }
    // [skipCount] because `set` here is one build behind: the count was
    // written a moment ago by the caller and the watched query has not come
    // back with it yet, so the row still reads null. Without this the ghost is
    // adopted straight over the number just recorded — which is how a hold
    // timed on the stopwatch was logged, and then immediately replaced by last
    // week's time.
    if (!skipCount && set.reps == null && ghost.reps != null) {
      repo
          .updateSet(setId, reps: Value(ghost.reps))
          .reportOnError('Last time\'s count could not be filled in.');
    }
  }

  // ── Paging ────────────────────────────────────────────────────────────

  void _goToPage(int index) {
    final detail = _detail;
    // A workout with nothing in it has no page to go to, and `clamp(0, -1)`
    // throws rather than returning anything. Adding the first exercise to an
    // empty session went straight through here.
    if (detail == null || detail.entries.isEmpty) return;
    final target = math.max(0, math.min(detail.entries.length - 1, index));
    if (!_pages.hasClients) {
      setState(() => _page = target);
      return;
    }
    _pages.animateToPage(target, duration: Motion.base, curve: Motion.curve);
  }

  /// Which page an exercise sits on, or -1 if the set is not in the workout.
  int _pageOf(WorkoutDetail detail, String setId) {
    for (var i = 0; i < detail.entries.length; i++) {
      if (detail.entries[i].sets.any((s) => s.id == setId)) return i;
    }
    return -1;
  }

  void _onPageChanged(WorkoutDetail detail, int index) {
    _flushWrite();
    _loadRestTarget(detail, index);
    setState(() {
      _page = index;
      // Turning the page by hand away from the value being typed dismisses the
      // keypad; the keypad's own "Next" lands on this page and keeps it open.
      final editing = _editing;
      if (editing != null && _pageOf(detail, editing.setId) != index) {
        _editing = null;
      }
    });
  }

  /// Arranges today's exercises, by dragging them.
  ///
  /// This was `Move earlier` / `Move later` on the ⋮ sheet — one nudge per
  /// visit, with the sheet closing between each. Two directions is a fine
  /// control for moving something once and a bad one for arranging six
  /// movements, which is what you have opened it to do. The rail's long-press
  /// drag still covers the single nudge.
  Future<void> _reorderExercises(WorkoutDetail detail) async {
    final current = [for (final e in detail.entries) e.workoutExercise.id];
    // Looked up while this widget is certainly alive. A `ref` read from inside
    // a callback that fires after the owning widget is gone throws from a
    // gesture handler, where the only symptom is a button that does nothing.
    final repo = ref.read(trainingRepositoryProvider);
    await showReorderSheet(
      context,
      title: 'Re-order exercises',
      subtitle: detail.session?.name ?? 'Today',
      items: [
        for (final e in detail.entries)
          (id: e.workoutExercise.id, label: e.exercise.name),
      ],
      onCommit: (ids) {
        if (!mounted) return;
        // Follow the exercise that was in front of you, wherever it landed.
        final was = current.isEmpty
            ? null
            : current[math.max(0, math.min(current.length - 1, _page))];
        setState(() => _pendingOrder = ids);
        repo.reorderWorkoutExercises(ids);
        final landed = was == null ? -1 : ids.indexOf(was);
        if (landed >= 0) _goToPage(landed);
      },
    );
  }

  /// The order the last move put things in, held until the database agrees.
  ///
  /// The rail holds its own while a *drag* is in flight, but `Move up` and
  /// `Move down` in the ⋮ sheet went straight to the repository — so the tab
  /// stayed where it was, the page animated to a neighbour that had not moved
  /// yet, and both jumped when the write landed a frame or two later. One
  /// optimistic order, owned here, covers the drag and both buttons: the rail,
  /// the pager and the cell map are all built from it.
  List<String>? _pendingOrder;

  /// [detail] with the pending order applied, or unchanged when there is none
  /// and when the database has caught up.
  WorkoutDetail _withPendingOrder(WorkoutDetail detail) {
    final pending = _pendingOrder;
    if (pending == null) return detail;

    final actual = [for (final e in detail.entries) e.workoutExercise.id];
    // Caught up: the guess is spent, and the database's own order is the truth
    // from here.
    if (actual.length == pending.length) {
      var same = true;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] != pending[i]) same = false;
      }
      if (same) {
        _pendingOrder = null;
        return detail;
      }
    }

    final byId = {for (final e in detail.entries) e.workoutExercise.id: e};
    final ordered = [for (final id in pending) ?byId[id]];
    // An exercise added, swapped or removed under the move invalidates it.
    if (ordered.length != detail.entries.length) {
      _pendingOrder = null;
      return detail;
    }

    return WorkoutDetail(
      workout: detail.workout,
      session: detail.session,
      entries: ordered,
    );
  }

  Future<void> _addExercise(WorkoutDetail detail) async {
    final exercise = await pickExercise(
      context,
      ref,
      alreadyIn: {for (final e in detail.entries) e.exercise.id},
    );
    if (exercise == null) return;
    await ref
        .read(trainingRepositoryProvider)
        .addExerciseToWorkout(detail.workout.id, exercise.id);
    // Land on the exercise that was just added rather than leaving it
    // somewhere off the end of the rail — once the build that has it arrives.
    _wantedPage = detail.entries.length;
  }

  Future<void> _finish(WorkoutDetail detail) async {
    // Whatever was typed in the last 300ms is part of this session. Without
    // this the debounce could still be in flight when `completeWorkout`
    // tombstones every unticked row, and the write would land on a set that
    // had already been thrown away.
    _flushWrite();
    final done = _doneSets(detail);
    // Work done under an exercise that was skipped afterwards is still work,
    // and it is what discarding would delete.
    final logged = _loggedSets(detail);
    final navigator = Navigator.of(context);
    // Captured before the first await, and used after it: this screen is
    // replaced by the summary at the end, and a `ref` read from a callback that
    // outlives it throws (RULES § Code).
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(trainingRepositoryProvider);

    if (logged == 0) {
      final discard = await confirmAction(
        context,
        title: 'Nothing logged',
        message: 'No sets were completed. Discard this session?',
        confirmLabel: 'Discard',
        cancelLabel: 'Keep logging',
      );
      if (!discard) return;
      await repo.abandonWorkout(detail.workout.id);
      navigator.pop();
      return;
    }

    // Finishing early is allowed — life gets in the way, and an app that
    // refuses to close a session is an app you stop logging in. It does have to
    // be deliberate, though: unfinished sets are dropped on the way out, and
    // whatever is left blank never happened as far as next week is concerned.
    final unfinished = _unfinished(detail);
    if (unfinished.isNotEmpty) {
      final outcome = await _confirmEarlyFinish(
        context,
        done: done,
        total: _totalSets(detail),
        unfinished: unfinished,
      );
      if (outcome == null || outcome == _FinishChoice.keepLogging) return;
      if (outcome == _FinishChoice.discard) {
        // Asked twice, because this is the one door in the app that throws
        // work away, and the sets behind it are already logged.
        if (!mounted) return;
        final sure = await confirmAction(
          context,
          title: 'Discard this session?',
          message:
              '$logged logged set${logged == 1 ? '' : 's'} '
              '${logged == 1 ? 'is' : 'are'} deleted. This cannot be undone.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep it',
          destructive: true,
        );
        if (!sure) return;
        await repo.abandonWorkout(detail.workout.id);
        navigator.pop();
        return;
      }
    }

    // False when the workout is no longer there — deleted from History while
    // this log was open. Opening a summary of it would show a spinner over a
    // session that does not exist, so this leaves the way it came instead.
    if (!await repo.completeWorkout(detail.workout.id)) {
      navigator.pop();
      return;
    }

    // Silent rolling snapshot. Finishing a session is the only moment the app
    // reliably has new data and idle time, so it is where the safety net gets
    // refreshed — failures here must never block leaving the screen.
    // `reportOnError` does the not-awaiting, and says why it is allowed to:
    // this must never block leaving the screen, and it must never disappear
    // either. The rolling snapshot is the safety net, and a net that has
    // quietly stopped being woven is worse than no net — Settings shows the
    // newest file's date, which simply stops advancing, with nothing anywhere
    // to say why.
    BackupService(ref.read(databaseProvider))
        .autoExport()
        // Settings reads the newest file once, at launch, because every tab
        // is built then — so a backup written after that was invisible until
        // the app was restarted.
        .then((_) => container.invalidate(lastBackupProvider))
        .reportOnError('The automatic backup did not run.');

    // Replaces the log rather than sitting on top of it: the session is closed,
    // and back from the summary belongs to Today, not to a set table that can
    // no longer be edited. Done on the summary is the same single pop.
    // Not awaited: this future completes when the summary is popped, which is
    // long after finishing is done.
    unawaited(
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionSummaryScreen(workoutId: detail.workout.id),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Sets that still count towards finishing the session. A skipped exercise
  /// is out of both counts: its sets are never going to be ticked, and leaving
  /// them in the denominator kept the Finish button off the screen for good.
  static Iterable<SetLog> _countedSets(WorkoutDetail d) => d.entries
      .where((e) => e.workoutExercise.skipReason == SkipReason.none)
      .expand((e) => e.sets);

  static int _doneSets(WorkoutDetail d) =>
      _countedSets(d).where((s) => s.isDone).length;

  /// Every set ticked today, skipped exercises included — what would actually
  /// be thrown away by discarding.
  static int _loggedSets(WorkoutDetail d) =>
      d.entries.expand((e) => e.sets).where((s) => s.isDone).length;

  /// Exercises with sets still open, named and counted. Skipped ones are
  /// deliberately absent: a skip is a decision already recorded, not an
  /// omission to be nagged about.
  static List<({String name, int done, int total})> _unfinished(
    WorkoutDetail d,
  ) {
    final out = <({String name, int done, int total})>[];
    for (final entry in d.entries) {
      if (entry.workoutExercise.skipReason != SkipReason.none) continue;
      final total = entry.sets.length;
      final done = entry.sets.where((s) => s.isDone).length;
      if (total == 0 || done == total) continue;
      out.add((name: entry.exercise.name, done: done, total: total));
    }
    return out;
  }

  static int _totalSets(WorkoutDetail d) => _countedSets(d).length;

  /// Sets on the card at all. Distinguishes a workout with nothing in it from
  /// one whose every exercise has been skipped — the second still finishes.
  static int _allSets(WorkoutDetail d) =>
      d.entries.expand((e) => e.sets).length;

  /// A stored kg value as the number this phone types in.
  String _fmtLoadIn(double? kg) => kg == null ? '' : formatInUnit(kg, _unit);
}

/// Prefill set aligned to a position in the current exercise, or null when
/// today has more sets than last time.
/// Which past set one of today's rows compares against.
///
/// Index for index broke the moment today's shape differed from last time's:
/// adding a single drop leg pushed every row under it onto the wrong ghost, so
/// the second working set started suggesting the first leg's dropped weight —
/// and adopting a blank row wrote that number in. Rows are matched inside their
/// own class instead: warm-ups against warm-ups, working sets against working
/// sets, legs against legs. An extra leg now costs that leg its ghost and
/// nothing else.
PastSet? _ghostFor(PrefillResult? prefill, List<SetLog> sets, int position) {
  if (prefill == null || position < 0 || position >= sets.length) return null;

  final want = _ghostClass(sets[position].setType);
  var rank = 0;
  for (var i = 0; i < position; i++) {
    if (_ghostClass(sets[i].setType) == want) rank++;
  }

  for (final past in prefill.sets) {
    if (_ghostClass(past.type) != want) continue;
    if (rank == 0) return past;
    rank--;
  }
  return null;
}

int _ghostClass(SetType type) => switch (type) {
  SetType.warmup => 0,
  _ when type.isContinuation => 2,
  _ => 1,
};

/// A single exercise, filling the screen.
///
/// The session used to be one long vertical stack, which meant scrolling past
/// finished work to reach the set in front of you. One exercise per page keeps
/// the thing you are actually doing at a fixed place on screen.
/// Session name, elapsed clock, and how far through the work you are.
///
/// The progress track replaces the `12 of 18 sets` line that used to sit under
/// the title. It is the same fact, and a bar answers "nearly done?" from across
/// a gym floor in a way two numbers never did.
class _LogTopBar extends StatelessWidget {
  const _LogTopBar({
    required this.title,
    required this.isDeload,
    required this.startedAt,
    required this.done,
    required this.total,
    required this.onBack,
    required this.onFinish,
  });

  final String title;
  final bool isDeload;

  /// Epoch milliseconds, UTC — the column's own storage format.
  final int startedAt;
  final int done;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final complete = total > 0 && done == total;

    return HeaderBand(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.sm,
              Space.sm,
              Space.gutter,
              0,
            ),
            child: Row(
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: onBack,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: context.t.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDeload) ...[
                            const SizedBox(width: Space.sm),
                            Pill('Deload', color: c.deload),
                          ],
                        ],
                      ),
                      // Its own clock, so the session timer advances without
                      // the rest of the screen rebuilding behind it once a
                      // second.
                      Ticking(
                        builder: (context) => Text(
                          _formatElapsed(startedAt),
                          style: context.t.labelSmall?.copyWith(
                            color: c.textSecondary,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Once everything is ticked this is the pinned white button at
                // the bottom instead, so it doesn't appear in two places.
                if (!complete) LinkAction('Finish', onTap: onFinish),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          // Full-bleed: inside the bar's padding, a finished session stopped a
          // gutter short at each end and the track never looked full.
          _ProgressTrack(done: done, total: total),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fraction = total == 0 ? 0.0 : done / total;
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Container(color: c.surfaceHigh),
            AnimatedContainer(
              duration: Motion.base,
              curve: Motion.curve,
              width: box.maxWidth * fraction,
              color: c.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExercisePage extends ConsumerWidget {
  const _ExercisePage({
    super.key,
    required this.index,
    required this.total,
    required this.entry,
    required this.nextName,
    required this.prefill,
    required this.unit,
    required this.editing,
    required this.partialShownFor,
    required this.partialClosedFor,
    required this.partialEditing,
    required this.buffer,
    required this.openSwipe,
    required this.onEdit,
    required this.onEditPartial,
    required this.rowKeyFor,
    required this.onToggleDone,
    required this.onNextExercise,
    required this.onReorder,
    required this.workout,
  });

  final int index;
  final int total;
  final ExerciseEntry entry;

  /// The session being trained, so the menu can open the day this exercise
  /// came from. Its `sessionId` is null for a workout that came from no
  /// template, and the menu shows one row fewer.
  final Workout workout;
  final String? nextName;
  final PrefillResult? prefill;

  /// Display unit for every weight on this page. Storage is always kg.
  final WeightUnit unit;

  final EditTarget? editing;

  /// The set showing its partial half, and whether the digits are going into
  /// that half rather than the reps.
  final String? partialShownFor;
  final String? partialClosedFor;
  final bool partialEditing;

  final ValueListenable<String> buffer;

  /// The one row swiped open across the whole screen.
  final ValueNotifier<String?> openSwipe;
  final void Function(SetLog, SetField) onEdit;
  final void Function(SetLog) onEditPartial;
  final GlobalKey Function(String setId) rowKeyFor;
  final void Function(SetLog, bool) onToggleDone;
  final VoidCallback onNextExercise;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final skipped = entry.workoutExercise.skipReason != SkipReason.none;

    // Warm-ups are not set 1, and a drop run is one set rather than three:
    // counting rows shifted every number away from the programme it came from.
    final groups = _groupSets(entry.sets);
    final counted = groups
        .where((g) => g.sets.first.setType != SetType.warmup)
        .toList();
    final countedDone = counted
        .where((g) => g.sets.every((s) => s.isDone))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.huge,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.exercise.name,
                    style: context.t.headlineSmall?.copyWith(
                      color: skipped ? c.textTertiary : c.textPrimary,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!skipped && counted.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Set ${math.min(countedDone + 1, counted.length)} '
                      'of ${counted.length}',
                      style: context.t.bodyMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Where today's numbers came from lives behind here, in one
            // sentence with the rest of the exercise's facts.
            //
            // It wore an amber dot while a session with no history of its own
            // was filled from another one: the ghosts in the table were
            // somebody else's day, and that is not something to leave a person
            // to notice. Nothing is borrowed now — a first time here opens
            // blank — so there is no warning left to carry.
            _InfoButton(
              onTap: () => showExerciseInfo(context, ref, entry, prefill),
            ),
            const SizedBox(width: Space.sm),
            CircleIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Exercise actions',
              onTap: () => showExerciseMenu(
                context,
                ref,
                entry,
                index: index,
                total: total,
                onReorder: onReorder,
                workout: workout,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        if (skipped)
          AppCard(
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline, size: 18, color: c.negative),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'Skipped: ${entry.workoutExercise.skipReason.label.toLowerCase()}',
                    style: context.t.bodySmall?.copyWith(color: c.negative),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // No card. The table was inset by the page gutter and then again by
          // the card's own padding, so the SET column started 32dp in while
          // the exercise name above it started at 16 — the two things a reader
          // scans down this screen were on different vertical lines. On the
          // page it is also one less surface behind a row that already has a
          // fill of its own per field.
          Column(
            children: [
              SetTableHeader(
                loadMode: entry.exercise.loadMode,
                measure: entry.exercise.measureMode,
                unit: unit,
              ),
              for (final group in groups)
                _SetGroup(
                  group: group,
                  entry: entry,
                  unit: unit,
                  editing: editing,
                  partialShownFor: partialShownFor,
                  partialClosedFor: partialClosedFor,
                  partialEditing: partialEditing,
                  buffer: buffer,
                  openSwipe: openSwipe,
                  onEdit: onEdit,
                  onEditPartial: onEditPartial,
                  rowKeyFor: rowKeyFor,
                  onToggleDone: onToggleDone,
                ),
              // The add button lives in the index column, directly under the
              // numbers it continues — no label, because a `+` under a
              // column of set numbers cannot mean anything else. The
              // `n of m done` line that used to sit here said what the
              // header already says.
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Row(
                  children: [
                    _RoundButton(
                      icon: Icons.add_rounded,
                      onTap: () => ref
                          .read(trainingRepositoryProvider)
                          .addSet(entry.workoutExercise.id),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.exercise.notes != null) ...[
            const SizedBox(height: Space.lg),
            Text(
              entry.exercise.notes!,
              style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
            ),
          ],
          // Today's note, written from the exercise menu. Kept visually
          // separate from the cue above: the cue is always true, this is only
          // true of this session.
          if (entry.workoutExercise.notes != null) ...[
            const SizedBox(height: Space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 16,
                  color: c.textTertiary,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    entry.workoutExercise.notes!,
                    style: context.t.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
        if (nextName != null) ...[
          const SizedBox(height: Space.section),
          // Turning the page works too; this is the discoverable version.
          SecondaryButton(
            label: 'Next: $nextName',
            icon: Icons.arrow_forward_rounded,
            onPressed: onNextExercise,
          ),
        ],
      ],
    );
  }
}

enum _FinishChoice { finish, discard, keepLogging }

/// What to do about a session with sets still open.
///
/// This was a two-button confirm built out of a paragraph of text: the counts,
/// the exercise list and the caveat all ran together in one message, and the
/// only ways out were "Finish anyway" and "Keep logging". There was no way to
/// throw the session away from here at all — you had to un-tick every set to
/// get the "nothing logged" prompt that offered it.
Future<_FinishChoice?> _confirmEarlyFinish(
  BuildContext context, {
  required int done,
  required int total,
  required List<({String name, int done, int total})> unfinished,
}) {
  return showModalBottomSheet<_FinishChoice>(
    // The route holds the system bars: a sheet that sizes itself can
    // otherwise run under the status bar. See [pickExercise].
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    // `AppSheet` draws its own grab handle, tighter than the framework's.
    showDragHandle: false,
    builder: (sheet) {
      final c = sheet.c;
      return AppSheet(
        title: 'Finish with sets left?',
        subtitle: '$done of $total sets logged',
        footer: Column(
          children: [
            PrimaryButton(
              label: 'Finish session',
              onPressed: () => Navigator.of(sheet).pop(_FinishChoice.finish),
            ),
            const SizedBox(height: Space.sm),
            SecondaryButton(
              label: 'Keep logging',
              onPressed: () =>
                  Navigator.of(sheet).pop(_FinishChoice.keepLogging),
            ),
          ],
        ),
        children: [
          ListCard(
            children: [
              for (final e in unfinished)
                AppRow(
                  title: e.name,
                  trailing: Text(
                    '${e.done} of ${e.total}',
                    style: sheet.t.labelLarge?.copyWith(color: c.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(
            // "Empty" was the wrong word and it cost a set: a row with a weight
            // typed into it but never ticked is thrown away too, and the sheet
            // promised it wasn't. Unticked is the rule everywhere else —
            // `completeWorkout` tombstones on `isDone`, not on blankness.
            'Any set you did not tick is discarded. The session is saved with '
            'exactly what you did.',
            style: sheet.t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          Center(
            child: Pressable(
              onTap: () => Navigator.of(sheet).pop(_FinishChoice.discard),
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Text(
                  'Discard this session',
                  style: sheet.t.titleMedium?.copyWith(color: c.negative),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// A run of rows that share one index chip.
///
/// A plain set is a group of one. Consecutive drop sets are a group of several:
/// they belong to the set above them, so they get a single `D` chip with a
/// spine running down beside them and a `+` at its foot to add another.
class _SetGroupData {
  const _SetGroupData(this.sets, this.positions, this.label, this.isDrop);

  final List<SetLog> sets;

  /// Each set's index in the exercise, needed to line a row up with its ghost.
  final List<int> positions;

  final String label;
  final bool isDrop;
}

/// Splits an exercise's sets into rows-with-a-chip and their drop legs.
///
/// A leg is a set whose `parentSetId` names the set above it. Grouping by
/// adjacency instead — every run of consecutive `drop` rows — could not tell
/// one drop set with two legs from two drop sets side by side, so converting
/// two sets in a row merged them into one.
List<_SetGroupData> _groupSets(List<SetLog> sets) {
  final at = {for (var i = 0; i < sets.length; i++) sets[i].id: i};

  /// A row that carries a chip of its own.
  ///
  /// Adjacency is not part of this. Legs were collected by walking forward from
  /// the head and stopping at the first row that was not its child, so a leg
  /// that ended up anywhere else — an orphan whose head was deleted, a leg of a
  /// leg — was skipped by the loop below *and* by the head that never reached
  /// it, and vanished from the table while still sitting in the database.
  bool isHead(SetLog s) {
    final parent = s.parentSetId;
    if (parent == null) return true;
    final i = at[parent];
    return i == null || sets[i].parentSetId != null;
  }

  final legsOf = <String, List<int>>{};
  for (var i = 0; i < sets.length; i++) {
    if (isHead(sets[i])) continue;
    legsOf.putIfAbsent(sets[i].parentSetId!, () => <int>[]).add(i);
  }

  final groups = <_SetGroupData>[];
  var counted = 0;

  for (var i = 0; i < sets.length; i++) {
    final set = sets[i];
    if (!isHead(set)) continue; // collected with its head

    final positions = <int>[i, ...?legsOf[set.id]];
    final legs = [for (final p in positions) sets[p]];

    final isDrop = set.setType == SetType.drop || legs.length > 1;
    final label = switch (set.setType) {
      SetType.warmup => 'W',
      // A drop is a set you dropped weight inside, so it takes a number of
      // its own — the reference numbers W, D, 2.
      SetType.drop => 'D',
      _ => '',
    };
    if (set.setType != SetType.warmup) counted++;

    groups.add(
      _SetGroupData(
        legs,
        positions,
        label.isEmpty ? '$counted' : label,
        isDrop,
      ),
    );
  }
  return groups;
}

class _SetGroup extends ConsumerWidget {
  const _SetGroup({
    required this.group,
    required this.entry,
    required this.unit,
    required this.editing,
    required this.partialShownFor,
    required this.partialClosedFor,
    required this.partialEditing,
    required this.buffer,
    required this.openSwipe,
    required this.onEdit,
    required this.onEditPartial,
    required this.rowKeyFor,
    required this.onToggleDone,
  });

  final _SetGroupData group;
  final ExerciseEntry entry;
  final WeightUnit unit;
  final EditTarget? editing;

  /// The set showing its partial half, and whether the digits are going into
  /// that half rather than the reps.
  final String? partialShownFor;
  final String? partialClosedFor;
  final bool partialEditing;

  final ValueListenable<String> buffer;

  /// The one row swiped open across the whole screen.
  final ValueNotifier<String?> openSwipe;
  final void Function(SetLog, SetField) onEdit;
  final void Function(SetLog) onEditPartial;
  final GlobalKey Function(String setId) rowKeyFor;
  final void Function(SetLog, bool) onToggleDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefill = ref
        .watch(workoutPrefillProvider(entry.workoutExercise.workoutId))
        .valueOrNull?[entry.exercise.id];
    final repo = ref.read(trainingRepositoryProvider);
    final last = group.sets.length - 1;

    void addLeg() => repo.addDropLeg(
      entry.workoutExercise.id,
      headSetId: group.sets.first.id,
    );

    // One index cell per row, always the same height as the row beside it.
    // The previous version stacked chip / spine / plus in a column of its own
    // and let [IntrinsicHeight] size the group, which stretched the first row
    // taller than the rest and slid every chip out of line with its row.
    //
    // No row wash. A completed set is said by its fields and its checkbox
    // (THEME → Components); a full-width band behind the row was the loudest thing in
    // the table, and the table is mostly completed rows by the end.
    return Column(
      children: [
        for (var k = 0; k < group.sets.length; k++)
          // The whole row travels — chip, capsule segment and fields together.
          // Wrapped around the fields alone this slid the numbers out from
          // under a chip that stayed put, which reads as the table coming
          // apart rather than as one row moving aside.
          SwipeToDelete(
            rowId: group.sets[k].id,
            open: openSwipe,
            onDelete: () => repo.deleteSets(_deleteIds(k)),
            child: Row(
              children: [
                _IndexCell(
                  // The spine only exists to tie a drop run together. A group of
                  // one head keeps its square foot for the `+` row below it.
                  spine: !group.isDrop
                      ? _Spine.none
                      : (k == 0
                            ? _Spine.top
                            : (k == last ? _Spine.bottom : _Spine.middle)),
                  child: switch (k) {
                    0 => SetIndexChip(
                      type: group.sets.first.setType,
                      label: group.label,
                      done: group.sets.first.isDone,
                      onTap: () => _openActions(context, ref, k),
                    ),
                    // The `+` rides in the last leg's cell, level with the row
                    // it continues. Given a row of its own it left a cell-high
                    // gap under a dot that marked nothing, which on a two-row
                    // drop set was half the height of the group.
                    //
                    // Long-press is that leg's own actions: its cell is spoken
                    // for, and every other row in this column opens a sheet.
                    _ when k == last => _RoundButton(
                      icon: Icons.add_rounded,
                      onTap: addLeg,
                      onLongPress: () => _openActions(context, ref, k),
                    ),
                    // A middle leg's way into its type, note and delete.
                    _ => _LegMarker(onTap: () => _openActions(context, ref, k)),
                  },
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: KeyedSubtree(
                    key: rowKeyFor(group.sets[k].id),
                    child: SetRow(
                      set: group.sets[k],
                      loadMode: entry.exercise.loadMode,
                      measure: entry.exercise.measureMode,
                      unit: unit,
                      ghost: _ghostFor(prefill, entry.sets, group.positions[k]),
                      editing: editing,
                      partialShownFor: partialShownFor,
                      partialClosedFor: partialClosedFor,
                      partialEditing: partialEditing,
                      buffer: buffer,
                      onEdit: onEdit,
                      onEditPartial: onEditPartial,
                      onToggleDone: onToggleDone,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // A drop set whose last leg has been deleted has no cell to put the `+`
        // in but still has to offer one, or it can never be a drop set again.
        // This is the only case that costs a row.
        if (group.isDrop && group.sets.length == 1)
          Row(
            children: [
              _IndexCell(
                spine: _Spine.bottom,
                height: _footHeight,
                child: _RoundButton(icon: Icons.add_rounded, onTap: addLeg),
              ),
            ],
          ),
      ],
    );
  }

  /// Shorter than a set row: it holds a button, not a number to read. Exactly
  /// the button's own diameter, so the capsule's foot closes on its edge.
  static const _footHeight = SetRow.indexColumn;

  /// Everything deleting row [k] removes. Deleting the head of a drop group
  /// takes the whole group: its legs are continuations of that set and mean
  /// nothing without it.
  List<String> _deleteIds(int k) =>
      k == 0 ? [for (final s in group.sets) s.id] : [group.sets[k].id];

  void _openActions(BuildContext context, WidgetRef ref, int k) {
    showSetActions(
      context,
      ref,
      group.sets[k],
      // The number the chip prints, not the raw position. Tapping the set
      // marked `1` used to open a sheet headed "Set 2" whenever a warm-up or
      // a drop sat above it. The sheet names the type itself.
      label: group.label,
      leg: k == 0 ? null : k + 1,
      deleteIds: _deleteIds(k),
    );
  }
}

enum _Spine { none, top, middle, bottom }

/// The fixed-width column down the left of the table. For a drop group the
/// cells join into one capsule behind the chip, the legs and the `+`.
class _IndexCell extends StatelessWidget {
  const _IndexCell({
    required this.spine,
    required this.child,
    this.height = SetRow.rowHeight,
  });

  final _Spine spine;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The full width of the column, with the chip flat on it. A narrower
    // capsule with a filled chip proud of it read as beads on a string —
    // three bulges down the left of the table instead of one run.
    const spineWidth = SetRow.indexColumn;
    const r = Radius.circular(spineWidth / 2);

    // The cap stops on the chip's own edge, not on the row's. A row is taller
    // than the chip in it, so a capsule drawn to the full height of the top row
    // reached half a chip above the `D` and ended in a rounded shoulder with
    // nothing under it — the same at the foot, around the `+`. Inset by the
    // gap between the two and the cap circumscribes the circle exactly.
    final inset = math.max(
      0.0,
      math.min(height / 2, (height - SetRow.indexColumn) / 2),
    );

    return SizedBox(
      width: SetRow.indexColumn,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (spine != _Spine.none)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  top: spine == _Spine.top ? inset : 0,
                  bottom: spine == _Spine.bottom ? inset : 0,
                ),
                child: Container(
                  width: spineWidth,
                  decoration: BoxDecoration(
                    color: c.surfaceHighest,
                    borderRadius: BorderRadius.vertical(
                      top: spine == _Spine.top ? r : Radius.zero,
                      bottom: spine == _Spine.bottom ? r : Radius.zero,
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// The width of the index column, so a capsule's foot closes on its edge.
  static const size = SetRow.indexColumn;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surfaceHigh, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.6, color: c.textSecondary),
      ),
    );
  }
}

/// A drop leg's index cell. The capsule already says the row belongs to the set
/// above it, so this is only a mark that something is here to press — and, like
/// every other chip in this column, the way into that row's type, note and
/// delete.
class _LegMarker extends StatelessWidget {
  const _LegMarker({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: SetRow.indexColumn,
        height: SetRow.rowHeight,
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: c.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Session length, as `m:ss` or `h:mm:ss`. Top-level because both the screen
/// and its top bar need it and neither owns the other.
String _formatElapsed(int startedAtMs) {
  final start = DateTime.fromMillisecondsSinceEpoch(
    startedAtMs,
    isUtc: true,
  ).toLocal();
  final d = DateTime.now().difference(start);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The ⓘ, with a dot on it when the numbers in the table were borrowed.
///
/// The header used to carry a caption instead — `Last time · 12 Jul`, or
/// `Borrowed from Push 2 · 3 Aug` in amber. It said what the info sheet already
/// says, on the screen with the least room for a second line, so it moved
/// inside. What could not move is the *warning*: numbers prefilled from another
/// session are the one case where ignoring where they came from means chasing
/// somebody else's day, so the button wears a dot and the sheet spells it out.
class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CircleIconButton(
      icon: Icons.info_outline_rounded,
      tooltip: 'About this exercise',
      onTap: onTap,
    );
  }
}
