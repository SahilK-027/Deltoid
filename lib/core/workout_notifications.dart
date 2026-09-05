import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The workout, on the lock screen.
///
/// Two notifications, and they answer two different questions.
///
/// * **The session** is ongoing and silent: what you are training, how far
///   through it you are, and — while a rest is running — a live countdown the
///   *system* draws, so it keeps ticking with the app asleep behind it.
/// * **The rest alert** is scheduled with the OS rather than fired by the app.
///   This is the whole point of this file: a Dart `Timer` is frozen the moment
///   Android suspends the process, so a phone put face down on a bench did not
///   buzz at the end of the rest — it buzzed when it was picked back up, which
///   is exactly late enough to be useless. An alarm handed to `AlarmManager`
///   goes off on time whether or not this app is running.
///
/// Every call is best-effort. There is no notification plugin in a widget test,
/// and a missing notification must never take a logged set down with it — so
/// failures are swallowed, and a platform with no plugin at all latches off
/// rather than retrying on every keystroke.
class WorkoutNotifications {
  WorkoutNotifications._();

  static final WorkoutNotifications instance = WorkoutNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// One id per notification: posting the same id again *replaces* it, which
  /// is how the session line updates in place instead of stacking up a row per
  /// set.
  static const _sessionId = 1001;
  static const _restId = 1002;

  static const _sessionChannel = 'workout_session';

  /// Two channels for one alert, because an Android channel's sound is fixed
  /// the moment the channel is created and cannot be changed by the app
  /// afterwards. Turning the tone off in Settings therefore cannot mute
  /// `rest_done`; it has to post on a channel that never had a sound. Both
  /// vibrate — the buzz is the half that works with the phone in a pocket, and
  /// it is not what the setting is about.
  static const _restChannel = 'rest_done';
  static const _restSilentChannel = 'rest_done_silent';

  bool _ready = false;
  bool _unsupported = false;

  /// Whether a replacement for the session line is sitting in the OS alarm
  /// queue. Tracked so the cancel that clears it — which would also take the
  /// *visible* session line down, since both carry [_sessionId] — is only paid
  /// for when there is something to clear.
  bool _sessionUpdatePending = false;

  /// Builds the plugin and asks for the notification permission, once.
  ///
  /// Returns false when there is nothing to notify with, so callers can skip
  /// the rest of their work rather than dressing up a no-op.
  Future<bool> init() async {
    if (_unsupported) return false;
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Declined is not a failure to retry — the user said no, and the app
      // carries on without the lock screen. The in-app buzz still works.
      await android?.requestNotificationsPermission();
      _ready = true;
      return true;
    } on MissingPluginException {
      _unsupported = true;
      return false;
    } catch (error) {
      _log('starting up', error);
      return false;
    }
  }

  /// Posts, or updates, the ongoing line for the session.
  ///
  /// [restEndsAt] draws the system's own countdown chronometer next to the
  /// text. It is drawn by the notification shade, not by this app, so it keeps
  /// counting with the process suspended — which is the only reason the number
  /// on the lock screen can be trusted.
  Future<void> showSession({
    required String title,
    required String body,
    DateTime? restEndsAt,
    String? afterRestBody,
  }) async {
    if (!await init()) return;
    try {
      final replacing = restEndsAt != null && afterRestBody != null;
      // Any replacement queued for the previous rest is now describing a rest
      // that has been dismissed, extended or superseded. It carries the same
      // id, so leaving it there would let the OS overwrite this line with a
      // stale one minutes from now.
      //
      // Only when nothing is about to take its place: a `zonedSchedule` under
      // the same id replaces the pending alarm by itself, and cancelling first
      // would take the *visible* line down and put it back on every set.
      if (_sessionUpdatePending && !replacing) {
        _sessionUpdatePending = false;
        await _plugin.cancel(id: _sessionId);
      }
      await _plugin.show(
        id: _sessionId,
        title: title,
        body: body,
        notificationDetails: _sessionDetails(restEndsAt: restEndsAt),
      );

      // **The countdown has to be stopped by something that is awake.**
      //
      // The chronometer above is drawn by the system, which is the only reason
      // it can be trusted while this process is suspended — and also the
      // reason it does not stop at zero. Nothing was re-posting the line at
      // the end of the rest, so a phone left face down went on counting into
      // `-1:23`. The fix is the same trick as the alert itself: hand the OS a
      // second, chronometer-less copy of this line, timed to land the instant
      // the rest is up. Same id, so it replaces rather than stacks.
      if (replacing) {
        await _scheduleSessionAfterRest(
          at: restEndsAt,
          title: title,
          body: afterRestBody,
        );
      }
    } on MissingPluginException {
      _unsupported = true;
    } catch (error) {
      // Nothing here is worth failing a set over.
      _log('posting the session line', error);
    }
  }

  NotificationDetails _sessionDetails({
    DateTime? restEndsAt,
    bool ongoing = true,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _sessionChannel,
        'Session in progress',
        channelDescription: 'The session you are training, and the rest clock.',
        // Low and silent, deliberately: this line is a place to look, not
        // an interruption. Every buzz this app makes is the rest alert.
        importance: Importance.low,
        priority: Priority.low,
        silent: true,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        ongoing: ongoing,
        autoCancel: !ongoing,
        category: AndroidNotificationCategory.workout,
        showWhen: restEndsAt != null,
        when: restEndsAt?.millisecondsSinceEpoch,
        usesChronometer: restEndsAt != null,
        chronometerCountDown: restEndsAt != null,
      ),
    );
  }

  /// Queues the post-rest version of the session line. Exact, like the alert:
  /// a countdown that stops "some minutes after" zero is the bug, not the fix.
  Future<void> _scheduleSessionAfterRest({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (!at.isAfter(DateTime.now().add(const Duration(seconds: 1)))) return;
    // Worst case a failure here leaves the line holding a countdown it should
    // have dropped. The rest alert itself is a separate id and is unaffected.
    final queued = await _schedule(
      id: _sessionId,
      title: title,
      body: body,
      at: at,
      // Dismissible, unlike the line it replaces. This one is posted by the
      // OS at a moment this app may not exist any more — swipe the workout
      // away mid-rest and `clear` never runs — and an ongoing notification
      // for a session nobody is in cannot be got rid of by hand.
      details: _sessionDetails(ongoing: false),
      what: 'session line after rest',
    );
    if (queued) _sessionUpdatePending = true;
  }

  /// Hands one notification to the OS clock, and **degrades rather than going
  /// silent** when it will not take an exact one.
  ///
  /// Exact is what is wanted: Doze batches ordinary alarms into windows
  /// minutes wide, and a rest alert that lands two minutes late has told you
  /// nothing you didn't know. But exact alarms are a permission, and a
  /// permission can be absent — revoked by hand on Android 14, or, the case
  /// that sent this whole file silent for a year, an Android 12 phone where
  /// `USE_EXACT_ALARM` is a string the OS has never heard of. The plugin
  /// answers that by throwing, and a rest that ends in silence is worse than
  /// one that rings a minute late.
  ///
  /// Returns whether anything is now queued.
  Future<bool> _schedule({
    required int id,
    required String title,
    required String? body,
    required DateTime at,
    required NotificationDetails details,
    required String what,
  }) async {
    // UTC, not the device's zone. The instant is what is being scheduled and
    // it is minutes away, so naming a zone would buy nothing but a dependency
    // on looking one up.
    final when = tz.TZDateTime.from(at.toUtc(), tz.UTC);
    for (final mode in const [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]) {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: when,
          androidScheduleMode: mode,
          notificationDetails: details,
        );
        return true;
      } on MissingPluginException {
        _unsupported = true;
        return false;
      } catch (error) {
        // Not a fallback worth taking twice, and the second mode asks for no
        // permission at all — if that fails too, the platform is the problem.
        _log('scheduling $what as $mode failed', error);
      }
    }
    return false;
  }

  /// Says what went wrong, in debug builds only.
  ///
  /// Every failure in this file is swallowed on purpose — a missing
  /// notification must never take a logged set down with it — but swallowed
  /// silently is how a rest alert that had never once been scheduled looked
  /// exactly like one that was scheduled and ignored.
  void _log(String what, Object error) {
    if (kDebugMode) debugPrint('WorkoutNotifications: $what — $error');
  }

  /// Hands the end of this rest to the OS alarm clock.
  ///
  /// Exact and allowed while idle: Doze batches ordinary alarms into windows
  /// minutes wide, and a rest alert that lands two minutes late has told you
  /// nothing you didn't know. Re-scheduling replaces the pending one, because
  /// the id is the same.
  Future<void> scheduleRestDone(
    DateTime at, {
    String? body,
    bool sound = true,
  }) async {
    if (!await init()) return;
    // Already gone. `zonedSchedule` throws on a date in the past, and the
    // caller — a lifecycle handler — cannot always know which side of zero the
    // clock is on.
    if (!at.isAfter(DateTime.now().add(const Duration(seconds: 1)))) return;
    await _schedule(
      id: _restId,
      title: 'Rest done',
      body: body,
      at: at,
      details: _restDetails(sound: sound),
      what: 'rest alert',
    );
  }

  NotificationDetails _restDetails({required bool sound}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        sound ? _restChannel : _restSilentChannel,
        sound ? 'Rest finished' : 'Rest finished (silent)',
        channelDescription: 'Fires when a rest period is up.',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        // The alarm stream, and the same tone the app plays in the
        // foreground — so it is audible over whatever is in your ears and
        // it is not silenced along with the rest of the day's pings.
        playSound: sound,
        sound: sound
            ? const RawResourceAndroidNotificationSound('rest_done')
            : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        // The set after it starts when you start it. A "rest done" still
        // sitting there twenty minutes later is noise.
        timeoutAfter: 120000,
      ),
    );
  }

  /// Posts the rest alert **now**, on the alarm channel.
  ///
  /// The fallback for the one case the hand-over cannot cover: this screen
  /// took the alert back from the OS, and then the tone would not play — a
  /// refused audio focus, a call, a process the system has stopped giving
  /// audio to. The rest still has to end audibly, so what was taken back is
  /// handed straight to the notification that would have fired anyway.
  Future<void> showRestDoneNow({String? body}) async {
    if (!await init()) return;
    try {
      await _plugin.show(
        id: _restId,
        title: 'Rest done',
        body: body,
        notificationDetails: _restDetails(sound: true),
      );
    } on MissingPluginException {
      _unsupported = true;
    } catch (error) {
      // Out of fallbacks. The haptics fired.
      _log('posting the rest alert', error);
    }
  }

  /// Drops a pending rest alarm — the rest was dismissed, extended, or the app
  /// came back to the foreground and will do its own buzzing.
  Future<void> cancelRest() async {
    if (!_ready || _unsupported) return;
    try {
      await _plugin.cancel(id: _restId);
      // Not the session line: this is called a beat *before* the alert would
      // fire, with the workout still open behind it.
    } catch (_) {
      // Nothing pending, or no plugin. Either way there is nothing to undo.
    }
  }

  /// Takes the session line and any pending alarm away. Called when the log
  /// screen closes: a workout you are no longer in has no business holding a
  /// row on the lock screen.
  Future<void> clear() async {
    if (!_ready || _unsupported) return;
    try {
      await _plugin.cancel(id: _restId);
      // Takes the queued post-rest copy with it — same id, one cancel.
      _sessionUpdatePending = false;
      await _plugin.cancel(id: _sessionId);
    } catch (_) {
      // The session is being torn down anyway.
    }
  }

  /// Test seam: pretends the platform has no notifications at all, so a widget
  /// test never reaches the channel.
  @visibleForTesting
  void disableForTests() => _unsupported = true;
}
