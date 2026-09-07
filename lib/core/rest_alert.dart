import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// The end-of-rest alert: a vibration transmitted through the surface the
/// device rests on, and a tone audible over any audio already playing.
///
/// It exists as a service rather than two lines in the log screen for one
/// reason: the player is expensive to build and the tone has to be audible
/// *over* music, which means an audio context — alarm usage on Android so it
/// rides the alarm stream instead of being muted with notifications, and a
/// transient-may-duck focus request so Spotify dips and comes back rather than
/// stopping. Both are per-player settings that want to be configured once.
///
/// Every method is best-effort. There is no audio plugin in a widget test and
/// no reason for a missing beep to take a logged set down with it, so failures
/// are swallowed.
///
/// Two kinds of failure, deliberately treated differently: *this platform has
/// no audio at all* (a widget test) latches off permanently, while *this
/// attempt failed* (audio focus refused during a phone call, which happens in
/// a gym) is retried on the next rest. One shared latch meant a single call
/// silenced the app until it was next launched.
class RestAlert {
  RestAlert._();

  static final RestAlert instance = RestAlert._();

  static final _asset = AssetSource('audio/rest_done.mp3');

  AudioPlayer? _player;

  /// Set only when the platform has no audio support to build against.
  bool _unsupported = false;

  /// Builds the player and pulls the asset into memory. Called when a workout
  /// opens so the first rest of the session isn't the one that stutters.
  Future<void> warmUp() async {
    if (_unsupported || _player != null) return;
    try {
      final player = AudioPlayer();
      // Fire and forget: the release mode is applied before anything can play,
      // and awaiting it buys nothing but a slower warm-up.
      unawaited(player.setReleaseMode(ReleaseMode.stop));
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      await player.setSource(_asset);
      _player = player;
    } on MissingPluginException {
      // No audio plugin at all — a widget test, or a platform without one.
      // Nothing will change that within this process, so stop trying.
      _unsupported = true;
    } catch (_) {
      // Something else went wrong building the player. Leave it null and try
      // again on the next rest rather than going silent for the session.
    }
  }

  /// Fires the alert. Haptics first — they are the half that works with the
  /// phone in a pocket, on silent, and with headphones in someone else's ears.
  ///
  /// [sound] is the Settings switch. It silences the tone and nothing else:
  /// the two pulses still fire, so a muted rest is still felt by a phone lying
  /// on a nearby surface.
  ///
  /// Returns whether the alert was fully delivered: the tone played, or
  /// none was owed. False means the haptics fired and the tone did not, which
  /// the caller answers by handing the alert back to the OS rather than
  /// letting a rest end in silence. Every failure here is a real one seen in a
  /// gym: audio focus refused during a call, a player that would not build, a
  /// process the system has stopped giving audio to.
  Future<bool> fire({bool sound = true, bool vibrate = true}) async {
    if (vibrate) {
      unawaited(HapticFeedback.heavyImpact());
      // A second pulse a beat later: one is easy to miss mid-set. Deliberately
      // not awaited — the alert must not hold the caller for 220ms.
      unawaited(
        Future.delayed(
          const Duration(milliseconds: 220),
          HapticFeedback.heavyImpact,
        ),
      );
    }

    // Nothing owed: the switch is off, or this platform has no audio to play
    // through. Neither is a failure, and neither wants a notification thrown
    // at it as a substitute.
    if (!sound || _unsupported) return true;
    try {
      await warmUp();
      final player = _player;
      if (player == null) return false;
      // Rewind rather than re-load: rest can end twice in quick succession
      // when the target is nudged down.
      await player.stop();
      await player.resume();
      return true;
    } on MissingPluginException {
      _unsupported = true;
      return true;
    } catch (_) {
      // A refused audio focus, a device busy on a call. The haptics above
      // already fired, and the caller still has the OS to fall back on.
      return false;
    }
  }

  /// Drops the player when the workout closes. Holding an audio session open
  /// for a screen that has been left is how an application ends up ducking
  /// audio indefinitely.
  Future<void> release() async {
    final player = _player;
    _player = null;
    // Not a permanent state: opening another workout builds a fresh player.
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {
      // Nothing to recover; the session is being torn down anyway.
    }
  }
}
