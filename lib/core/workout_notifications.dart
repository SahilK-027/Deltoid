import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/rest.dart';
import '../domain/set_format.dart';

/// Lock-screen presentation of an open workout.
///
/// Two notifications are posted, serving different purposes.
///
/// * The session notification is a silent foreground service reporting the
///   movement being trained, progress through the session and, while a rest is
///   running, the rest itself as a bar counting down with the remaining time
///   beside it. A service is required because a notification progress bar has
///   no clock of its own: it retains the last value posted to it, and an
///   ordinary application is suspended within seconds of the screen going off,
///   so a bar updated from within the process would stop at its last value. A
///   foreground service is not suspended.
/// * The rest alert is scheduled with the operating system rather than fired by
///   the application. This is the primary reason this file exists. A Dart
///   `Timer` is suspended as soon as Android suspends the process, so a device
///   left face down does not signal at the end of the rest; it signals when the
///   device is next handled, which is too late to be useful. An alarm
///   registered with `AlarmManager` fires on schedule whether or not the
///   application is running.
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
  // Four channels are required because vibration is a property of the channel.
  // From Android 8 a channel's sound and vibration are fixed at creation and
  // cannot subsequently be altered by the application, only by the user in the
  // system settings. Two switches therefore require four channels rather than
  // two booleans on the notification, and a device that has used every
  // combination accumulates four entries under the application's notification
  // settings. This is imposed by the platform.
  static const _restChannel = 'rest_done';
  static const _restSilentChannel = 'rest_done_silent';
  static const _restStillChannel = 'rest_done_still';
  static const _restSilentStillChannel = 'rest_done_silent_still';

  /// The status bar renders a small icon from its alpha channel alone, painting
  /// every opaque pixel in a single flat colour. The launcher icon is a fully
  /// opaque square, so supplying it — as the Flutter template does — produces a
  /// featureless block. This asset is the mark alone, transparent everywhere
  /// outside the shape.
  static const _smallIcon = '@drawable/ic_stat_deltoid';

  /// `DeltoidColors.dark.surface`, spelled out rather than imported: the shade
  /// paints this row itself, from a number, with no theme behind it and no
  /// chance to ask which one is in force.
  ///
  /// The app's own charcoal rather than a colour invented for the lock screen.
  /// A purple fails at both ends: the palette's lavender is 2.6:1 against white,
  /// so Android reads it as a light surface and prints black text on it, and
  /// taking the hue down far enough to earn white text produces a colour this
  /// app does not otherwise contain. White sits on this at 15.8:1, and the row
  /// looks like the app it came from.
  static const _tint = Color(0xFF1F1F1F);

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
    required DateTime startedAt,
    int? restSecondsLeft,
    int? restTargetSeconds,
  }) async {
    if (!await init()) return;
    // What the clock reports depends on which mechanism is holding the
    // notification.
    //
    // With the service running, the seconds are posted individually and the
    // value beneath the movement is current. Without it, where no form of
    // foreground service was accepted, nothing remains awake to post a further
    // update, so the notification omits the clock and leaves the end of the
    // rest to the alarm. A stale 1:47 displayed beside a completed rest would
    // be worse than no value.
    final resting = restSecondsLeft != null;
    final live = resting && !_serviceUnavailable;

    // A single line, led by the clock.
    //
    // Two lines in a big-text style extend the row to five: the app's name,
    // the title, the bar, the clock, the movement. Nothing on that fifth line
    // is worth the height it costs — the clock and the movement are two short
    // facts, and they fit one line with a separator between them.
    //
    // The clock goes first because the end of this line is not guaranteed: a
    // long enough movement name ellipsizes, and it is the end that falls off.
    // What is still running is the half that cannot be cut.
    final clock = live ? formatRestClock(restSecondsLeft) : null;
    final line = clock == null ? body : '$clock · $body';
    final details = _sessionDetails(
      done: done,
      total: total,
      startedAt: startedAt,
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
      // Posted before the service adopts it, otherwise it is not displayed for
      // ten seconds.
      //
      // From Android 12 the system withholds a foreground service's
      // notification for up to ten seconds when the service starts while the
      // application is in the foreground, which is the case whenever a workout
      // is opened. The notification for a session that has just started is
      // precisely the one that must not be delayed, and the platform's own
      // opt-out,
      // `setForegroundServiceBehavior(FOREGROUND_SERVICE_IMMEDIATE)`, is not
      // something this plugin exposes. A notification already showing under
      // that id is not deferred, so it is posted first and the service takes
      // it over. Once only: after that the service owns the line and every
      // update goes through it.
      if (!_serviceRunning) {
        await _plugin.show(
          id: _sessionId,
          title: title,
          body: line,
          notificationDetails: details,
        );
      }

      // Three mechanisms are available for posting this notification, and the
      // first that succeeds is used.
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
      // service behind it. On that last rung nothing is awake to drain a bar
      // from, so the bar is dropped and everything else about the line
      // survives.
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
      // trained and how far through the session it is.
      _serviceUnavailable = true;
      await _plugin.show(
        id: _sessionId,
        title: title,
        // Composed again: the clock in it was written on the understanding
        // that something would keep it moving, and nothing will.
        body: resting ? 'Resting · $body' : body,
        notificationDetails: _sessionDetails(
          done: done,
          total: total,
          startedAt: startedAt,
        ),
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
    DateTime? startedAt,
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
        // Colourised, which requires a foreground service.
        //
        // `colorized` paints the whole notification rather than tinting the
        // application name, and Android permits it only for a foreground
        // service. This notification is already one, for the rest bar, so the
        // permission is available without further cost.
        color: _tint,
        colorized: true,
        // The header's small grey line, next to the app name: where the
        // session stands, which is the one number that is true whether or not
        // a rest is running.
        subText: total > 0 ? setsOfTotal(done, total) : null,
        // The progress bar represents the rest and nothing else.
        //
        // A notification's progress bar holds whatever value was last posted
        // to it — it has no clock, and there is no way to hand it one. The
        // seconds it counts down are therefore posted, one a second, by the
        // service holding this line up; that is what the service is for.
        //
        // Giving it a second job — the session's own fraction, between sets —
        // makes one bar mean two things, and a bar that changes meaning has to
        // jump: a rest drains to empty and immediately grows back as something
        // else. So there is no bar at all when no rest is running, and the set
        // count lives in the header, which never animates.
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
        // The session's elapsed time is rendered by the system, in minutes.
        //
        // `when` is the moment the workout started, and the shade renders it as
        // "42m" beside the application name, matching every other ongoing
        // notification on the device.
        //
        // No chronometer. Asking for one gets a clock ticking in seconds, and
        // a clock ticking in seconds cannot survive this line: a rest re-posts
        // it once a second, every post rebuilds the row, and the clock
        // restarts with it. Standing it down for the rest only moves the
        // problem: the header then swaps between a ticking clock and a static
        // "42m" at both ends of every rest, which is a twitch a minute rather
        // than one a second. Elapsed session time requires no
        // precision. The number that does is on the bar.
        showWhen: startedAt != null,
        when: startedAt?.millisecondsSinceEpoch,
        usesChronometer: false,
      ),
    );
  }

  /// Registers one notification with the operating system's alarm clock,
  /// degrading rather than failing silently when an exact alarm is refused.
  ///
  /// Exact is what is wanted: Doze batches ordinary alarms into windows
  /// minutes wide, and a rest alert arriving two minutes late conveys nothing.
  /// Exact alarms are, however, a permission, and a
  /// permission can be absent — revoked by hand on Android 14, or on an
  /// Android 12 phone where `USE_EXACT_ALARM` is a string the OS has never
  /// heard of. The plugin
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
  /// silently, a rest alert that was never once scheduled looks exactly like
  /// one that was scheduled and ignored.
  void _log(String what, Object error) {
    if (kDebugMode) debugPrint('WorkoutNotifications: $what — $error');
  }

  /// Hands the end of this rest to the OS alarm clock.
  ///
  /// Exact and allowed while idle: Doze batches ordinary alarms into windows
  /// minutes wide, and a rest alert arriving two minutes late conveys nothing.
  /// Re-scheduling replaces the pending alarm, because
  /// the id is the same.
  Future<void> scheduleRestDone(
    DateTime at, {
    String? body,
    bool sound = true,
    bool vibrate = true,
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
      details: _restDetails(sound: sound, vibrate: vibrate),
      what: 'rest alert',
    );
  }

  NotificationDetails _restDetails({
    required bool sound,
    required bool vibrate,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        switch ((sound, vibrate)) {
          (true, true) => _restChannel,
          (true, false) => _restStillChannel,
          (false, true) => _restSilentChannel,
          (false, false) => _restSilentStillChannel,
        },
        switch ((sound, vibrate)) {
          (true, true) => 'Rest finished',
          (true, false) => 'Rest finished (no vibration)',
          (false, true) => 'Rest finished (silent)',
          (false, false) => 'Rest finished (silent, no vibration)',
        },
        channelDescription: 'Fires when a rest period is up.',
        icon: _smallIcon,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        // The alarm stream, and the same tone the app plays in the
        // foreground, so that it is audible over any audio in progress and is
        // not silenced along with ordinary notifications.
        playSound: sound,
        sound: sound
            ? const RawResourceAndroidNotificationSound('rest_done')
            : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: vibrate,
        // The following set begins when the user begins it. A "rest done"
        // notification still present twenty minutes later is noise.
        timeoutAfter: 120000,
      ),
    );
  }

  /// Posts the rest alert immediately, on the alarm channel.
  ///
  /// The fallback for the one case the hand-over cannot cover: this screen
  /// took the alert back from the OS, and then the tone would not play — a
  /// refused audio focus, a call, a process the system has stopped giving
  /// audio to. The rest still has to end audibly, so what was taken back is
  /// handed straight to the notification that would have fired anyway.
  Future<void> showRestDoneNow({String? body, bool vibrate = true}) async {
    if (!await init()) return;
    try {
      await _plugin.show(
        id: _restId,
        title: 'Rest finished',
        body: body,
        notificationDetails: _restDetails(sound: true, vibrate: vibrate),
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
  /// screen closes, since a workout that is no longer open should not retain a
  /// row on the lock screen.
  Future<void> clear() async {
    if (!_ready || _unsupported) return;
    try {
      await _plugin.cancel(id: _restId);
      // Stopping the service takes its notification with it. The plain cancel
      // still runs behind it, for the platforms that never had a service and
      // for a line left behind by a build that did not use one.
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
