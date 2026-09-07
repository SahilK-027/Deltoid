import 'package:connectivity_plus/connectivity_plus.dart';

/// Fires when the phone has an interface again after having none.
///
/// One of [SYNC.md § 6](SYNC.md#6-push)'s four triggers, and the one that turns
/// *a session logged in a basement* into *a session that arrives when the
/// signal does* rather than one that waits out the backstop.
///
/// Transitions only. `onConnectivityChanged` also reports Wi-Fi to mobile
/// and back, and a phone in a lift emits both several times a minute; a push
/// per event would be a radio kept awake to send nothing. Off-to-on is the only
/// edge that changes what a failed push would do.
///
/// This is a hint, never a gate. Nothing asks whether there is a network before
/// pushing — the drain simply tries, and an interface that exists is not an
/// internet that works. Behind here so the engine takes a plain `Stream<void>`
/// and a test drives it without a platform channel.
Stream<void> networkRegained([Connectivity? connectivity]) {
  var online = true;
  return (connectivity ?? Connectivity())
      .onConnectivityChanged
      .where((results) {
    final now = results.any((r) => r != ConnectivityResult.none);
    final regained = now && !online;
    online = now;
    return regained;
  });
}
