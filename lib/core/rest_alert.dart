import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// The end-of-rest alert: a buzz you feel through the bench and a tone that
/// survives whatever is playing in your ears.
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
class RestAlert {
  RestAlert._();

  static final RestAlert instance = RestAlert._();

  static final _asset = AssetSource('audio/rest_done.mp3');

  AudioPlayer? _player;
  bool _failed = false;

  /// Builds the player and pulls the asset into memory. Called when a workout
  /// opens so the first rest of the session isn't the one that stutters.
  Future<void> warmUp() async {
    if (_failed || _player != null) return;
    try {
      final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
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
    } catch (_) {
      // No audio on this platform or in this test harness; haptics still fire.
      _failed = true;
    }
  }

  /// Fires the alert. Haptics first — they are the half that works with the
  /// phone in a pocket, on silent, and with headphones in someone else's ears.
  Future<void> fire() async {
    HapticFeedback.heavyImpact();
    // A second pulse a beat later: one is easy to miss mid-set.
    Future.delayed(
      const Duration(milliseconds: 220),
      HapticFeedback.heavyImpact,
    );

    if (_failed) return;
    try {
      await warmUp();
      final player = _player;
      if (player == null) return;
      // Rewind rather than re-load: rest can end twice in quick succession
      // when the target is nudged down.
      await player.stop();
      await player.resume();
    } catch (_) {
      _failed = true;
    }
  }

  /// Drops the player when the workout closes. Holding an audio session open
  /// for a screen you have left is how an app ends up ducking music forever.
  Future<void> release() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {
      // Nothing to recover; the session is being torn down anyway.
    }
  }
}
