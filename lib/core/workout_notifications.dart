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
  static const _restChannel = 'rest_done';

  bool _ready = false;
  bool _unsupported = false;

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
    } catch (_) {
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
  }) async {
    if (!await init()) return;
    try {
      await _plugin.show(
        id: _sessionId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _sessionChannel,
            'Session in progress',
            channelDescription:
                'The session you are training, and the rest clock.',
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
            showWhen: restEndsAt != null,
            when: restEndsAt?.millisecondsSinceEpoch,
            usesChronometer: restEndsAt != null,
            chronometerCountDown: restEndsAt != null,
          ),
        ),
      );
    } on MissingPluginException {
      _unsupported = true;
    } catch (_) {
      // Nothing here is worth failing a set over.
    }
  }

  /// Hands the end of this rest to the OS alarm clock.
  ///
  /// Exact and allowed while idle: Doze batches ordinary alarms into windows
  /// minutes wide, and a rest alert that lands two minutes late has told you
  /// nothing you didn't know. Re-scheduling replaces the pending one, because
  /// the id is the same.
  Future<void> scheduleRestDone(DateTime at, {String? body}) async {
    if (!await init()) return;
    // Already gone. `zonedSchedule` throws on a date in the past, and the
    // caller — a lifecycle handler — cannot always know which side of zero the
    // clock is on.
    if (!at.isAfter(DateTime.now().add(const Duration(seconds: 1)))) return;
    try {
      await _plugin.zonedSchedule(
        id: _restId,
        title: 'Rest done',
        body: body,
        // UTC, not the device's zone. The instant is what is being scheduled
        // and it is minutes away, so naming a zone would buy nothing but a
        // dependency on looking one up.
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _restChannel,
            'Rest finished',
            channelDescription: 'Fires when a rest period is up.',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            // The alarm stream, and the same tone the app plays in the
            // foreground — so it is audible over whatever is in your ears and
            // it is not silenced along with the rest of the day's pings.
            sound: RawResourceAndroidNotificationSound('rest_done'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: true,
            // The set after it starts when you start it. A "rest done" still
            // sitting there twenty minutes later is noise.
            timeoutAfter: 120000,
          ),
        ),
      );
    } on MissingPluginException {
      _unsupported = true;
    } catch (_) {
      // A refused exact-alarm permission, most likely. The in-app buzz still
      // covers the case where the phone is awake in front of you.
    }
  }

  /// Drops a pending rest alarm — the rest was dismissed, extended, or the app
  /// came back to the foreground and will do its own buzzing.
  Future<void> cancelRest() async {
    if (!_ready || _unsupported) return;
    try {
      await _plugin.cancel(id: _restId);
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
