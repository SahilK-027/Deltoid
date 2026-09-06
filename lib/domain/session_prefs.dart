/// What the app does to the phone while a session is open.
///
/// Two switches, both about the app taking something the phone would rather
/// keep: a permanent line in the shade, and the screen staying lit. Neither
/// changes a number that is stored, which is why they sit in `app_settings`
/// with the theme and the units — local, and never synced (SYNC § 15 rule 8).
/// Whether a phone keeps its screen on is a property of that phone.
library;

/// The two `app_settings` keys session behaviour is configured through.
const sessionNotificationKey = 'session_notification';
const keepScreenOnKey = 'keep_screen_on';

/// Whether the ongoing session line is posted. On unless turned off.
///
/// It is a foreground service, and Android will not run one without a
/// notification — so off means the service does not start at all, and the
/// rest bar stops draining a second at a time while the screen is off. The
/// end-of-rest alert is a scheduled alarm rather than part of that service, so
/// it still arrives; what is lost is the live clock, not the alert.
bool parseSessionNotification(String? raw) => raw?.trim() != 'off';

/// Whether the screen is held awake while a session is open. On unless turned
/// off — a phone that sleeps between sets is a phone unlocked again every two
/// minutes with chalk on your hands.
bool parseKeepScreenOn(String? raw) => raw?.trim() != 'off';
