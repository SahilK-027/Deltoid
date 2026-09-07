/// Device behaviour while a training session is open.
///
/// Two settings, each governing something the application takes from the
/// device: a persistent notification in the shade, and the screen remaining
/// lit. Neither affects stored data, which is why both reside in `app_settings`
/// alongside the theme and unit preferences — local, and never synchronised
/// (SYNC § 15 rule 8). Whether a device keeps its screen on is a property of
/// that device rather than of the account.
library;

/// The `app_settings` keys through which session behaviour is configured.
const sessionNotificationKey = 'session_notification';
const keepScreenOnKey = 'keep_screen_on';

/// Whether the ongoing session notification is posted. Enabled unless
/// explicitly disabled.
///
/// The notification is backed by a foreground service, and Android will not run
/// one without a notification. Disabling it therefore prevents the service from
/// starting, and the rest bar no longer counts down while the screen is off.
/// The end-of-rest alert is a scheduled alarm rather than part of that service
/// and still arrives; only the live clock is lost.
bool parseSessionNotification(String? raw) => raw?.trim() != 'off';

/// Whether the screen is held awake while a session is open. Enabled unless
/// explicitly disabled.
///
/// A device that sleeps between sets must be unlocked again every two minutes
/// during training.
bool parseKeepScreenOn(String? raw) => raw?.trim() != 'off';
