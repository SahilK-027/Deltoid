import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/rest.dart';

/// The workout, on the lock screen.
///
/// Two notifications, and they answer two different questions.
///
/// * **The session** is a silent foreground service: what you are training,
///   how far through it you are, and — while a rest is running — the rest
///   itself, as a bar draining towards zero with the time left written beside
///   it. It is a service because a progress bar has no clock. It holds the
///   last value posted to it, and an ordinary app is frozen within seconds of
///   the screen going off, so a bar drained from in here would stop where it
///   was and stay there. A foreground service is not frozen.
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

  /// The status bar draws a small icon from its **alpha channel alone**, every
  /// opaque pixel painted one flat colour by the system. The launcher icon is
  /// a full square of opaque pixels, so handing that over — which is what the
  /// Flutter template does — draws a featureless white blob. This is the mark
  /// on its own: transparent everywhere it is not the shape.
  static const _smallIcon = '@drawable/ic_stat_deltoid';

  bool _ready = false;
  bool _unsupported = false;

  /// Whether the session's foreground service is up, so [clear] only asks for
  /// it to be torn down when there is something to tear down.
  bool _serviceRunning = false;

  /// The service types that were accepted, once one set has been. Kept so the
  /// per-second updates during a rest do not re-walk the ladder — and so a
  /// phone that refuses `specialUse` pays for that refusal once a workout
  /// rather than once a second.
  Set<AndroidServiceForegroundType>? _serviceTypes;

  /// Set when no shape of foreground service was accepted at all. The line is
  /// posted as an ordinary notification from then on, and the rest bar goes
  /// with the service: nothing is awake to drain it.
  bool _serviceUnavailable = false;

  /// The Android half of the plugin, or null off Android — where a foreground
  /// service is neither available nor meaningful, and the session line falls
  /// back to an ordinary posted notification.
  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

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
          // The mark, flat and alpha-only — see `_smallIcon`.
          android: AndroidInitializationSettings(_smallIcon),
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
  /// [restSecondsLeft] and [restTargetSeconds] are the rest now running, and
  /// they are what the bar is drawn from — full at the start of the rest,
  /// empty at zero. The caller re-posts this once a second while a rest is on
  /// the clock; between sets nothing changes but the set count, so nothing is
  /// posted but a set count.
  ///
  /// Updating is the same call: `startForegroundService` with the same id
  /// replaces the notification the service is holding up.
  Future<void> showSession({
    required String title,
    required String body,
    required int done,
    required int total,
    int? restSecondsLeft,
    int? restTargetSeconds,
  }) async {
    if (!await init()) return;
    // **What the clock says depends on who is holding the line up.**
    //
    // With the service, the seconds are posted one at a time and the number
    // beside the movement is current. Without it — no shape of foreground
    // service was accepted — nothing here is awake to post a second one, so
    // the line says that a rest is running and leaves the number to the alarm
    // that ends it. A stale `1:47` sitting next to a finished rest would be
    // worse than no number at all.
    final resting = restSecondsLeft != null;
    final live = resting && !_serviceUnavailable;
    final line = switch (true) {
      _ when live => '${formatRestClock(restSecondsLeft)} · $body',
      _ when resting => 'Resting · $body',
      _ => body,
    };
    final details = _sessionDetails(
      done: done,
      total: total,
      restSecondsLeft: live ? restSecondsLeft : null,
      restTargetSeconds: live ? restTargetSeconds : null,
    );
    try {
      final android = _android;
      if (android == null || _serviceUnavailable) {
        // Not Android, or a phone that would not take the service. Nothing
        // here needs a service to be *correct*, only to be current while the
        // process is asleep.
        await _plugin.show(
          id: _sessionId,
          title: title,
          body: line,
          notificationDetails: details,
        );
        return;
      }
      // **Three ways to put this line up, and it takes the first that works.**
      //
      // `specialUse` is an API 34 constant being handed to
      // `startForeground(id, notification, type)` on phones as old as API 24,
      // and what a framework does with a type it has never heard of is not
      // something this can know for every one of them. Measured on an Android
      // 12 phone, the typed call is accepted — the type is declared in the
      // manifest and the platform takes it — so the first rung is the one that
      // holds there. This is a guard against the versions nobody has run it
      // on, not a fix for a failure that was seen.
      //
      // Each rung is tried until one holds: the typed service, the untyped one
      // (`startForeground` without a type is legal, and below API 34 there is
      // nothing to declare), and finally an ordinary notification with no
      // service behind it. That last rung is the line as it was before the
      // service existed — nothing is awake to drain a bar from, so the bar is
      // dropped there and everything else about the line survives.
      //
      // A rung that fails says so in a debug build. Silence here means the
      // first one was taken.
      for (final types
          in _serviceRunning
              ? [_serviceTypes]
              : const [
                  {
                    AndroidServiceForegroundType
                        .foregroundServiceTypeSpecialUse,
                  },
                  null,
                ]) {
        try {
          await android.startForegroundService(
            id: _sessionId,
            title: title,
            body: line,
            notificationDetails: details.android,
            // Restarted by the system if it is ever killed under memory
            // pressure, because the workout it is counting is still open
            // behind it.
            startType: AndroidServiceStartType.startSticky,
            foregroundServiceTypes: types,
          );
          _serviceRunning = true;
          _serviceTypes = types;
          return;
        } on MissingPluginException {
          rethrow;
        } catch (error) {
          _log('starting the session service with types=$types', error);
        }
      }

      // No service will take it. A plain notification still says what is being
      // trained and how far through it you are.
      _serviceUnavailable = true;
      await _plugin.show(
        id: _sessionId,
        title: title,
        // Composed again: the clock in it was written on the understanding
        // that something would keep it moving, and nothing will.
        body: resting ? 'Resting · $body' : body,
        notificationDetails: _sessionDetails(done: done, total: total),
      );
    } on MissingPluginException {
      _unsupported = true;
    } catch (error) {
      // Nothing here is worth failing a set over.
      _log('posting the session line', error);
    }
  }

  NotificationDetails _sessionDetails({
    required int done,
    required int total,
    int? restSecondsLeft,
    int? restTargetSeconds,
  }) {
    final resting =
        restSecondsLeft != null &&
        restTargetSeconds != null &&
        restTargetSeconds > 0;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _sessionChannel,
        'Session in progress',
        channelDescription: 'The session you are training, and the rest clock.',
        icon: _smallIcon,
        // The header's small grey line, next to the app name: where the
        // session stands, which is the one number that is true whether or not
        // a rest is running.
        subText: total > 0 ? '$done of $total sets' : null,
        // **The bar is the rest, and nothing else is ever drawn in it.**
        //
        // A notification's progress bar holds whatever value was last posted
        // to it — it has no clock, and there is no way to hand it one. The
        // seconds it counts down are therefore posted, one a second, by the
        // service holding this line up; that is what the service is for.
        //
        // It had a second job for one build: the session's own fraction,
        // between sets. One bar meaning two things has to jump when the
        // meaning changes, and what that looked like was a rest draining to
        // empty and then immediately growing back as something else. So there
        // is no bar at all when no rest is running, and the set count lives in
        // the header, which never animates.
        showProgress: resting,
        maxProgress: resting ? restTargetSeconds : 0,
        progress: resting ? restSecondsLeft.clamp(0, restTargetSeconds) : 0,
        // Low and silent, deliberately: this line is a place to look, not
        // an interruption. Every buzz this app makes is the rest alert.
        importance: Importance.low,
        priority: Priority.low,
        silent: true,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        ongoing: true,
        autoCancel: false,
        category: AndroidNotificationCategory.workout,
        // No chronometer. The system draws that in the header's top corner and
        // nowhere else, which puts the number that matters furthest from the
        // bar it belongs to. The time left is written into the body instead,
        // on the line above the bar, by the same second-by-second post that
        // moves the bar.
        showWhen: false,
      ),
    );
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
      title: 'Rest finished',
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
        icon: _smallIcon,
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
        title: 'Rest finished',
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
      // Stopping the service takes its notification with it. The plain cancel
      // still runs behind it, for the platforms that never had a service and
      // for a line left over from a build that did not use one.
      if (_serviceRunning) {
        _serviceRunning = false;
        await _android?.stopForegroundService();
      }
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
