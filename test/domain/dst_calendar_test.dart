@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Calendar arithmetic across a clock change.
///
/// **Why this runs a subprocess.** Dart resolves the local timezone from `TZ`
/// once, when the VM starts, and nothing can change it afterwards — so a bug
/// that only appears on the two days a year a zone shifts its clock is
/// unreachable from a test running in a zone that never does. Every check here
/// is therefore `test/tools/dst_probe.dart`, run under a zone that does, with
/// its findings read back off stdout.
///
/// **Why these zones.** The failures are not the same everywhere, and the spread
/// is the reason there is more than one:
///
/// - `Asia/Gaza` moves on a **Saturday**, which for a Monday-start week is
///   mid-week — the only shape that breaks `weekStartOf`. It is also the only
///   group that loses rows off the volume chart.
/// - `America/Santiago` moves **at midnight**, so the transition day has no
///   00:00 at all and a named date normalises to 01:00.
/// - `Pacific/Chatham` sits at a **:45 offset**, `Australia/Lord_Howe` shifts by
///   **thirty minutes** — the case an hour-shaped assumption misses entirely.
/// - `America/New_York` is the ordinary Sunday 02:00 rule. Its `weekStartOf` is
///   fine, exactly as the Sunday-transition argument predicts; its
///   **`historyDays` is not**, which that argument does not reach. Every DST
///   zone on earth got that one wrong.
/// - `UTC` is the control, and must come back clean.
void main() {
  const probe = 'test/tools/dst_probe.dart';

  /// **Not `Platform.resolvedExecutable`.** Under `flutter test` that is
  /// `flutter_tester`, the engine binary — which accepts `run <file>`, boots a
  /// whole Flutter engine for it and then hangs, one process per zone, until
  /// something kills it. The probe is plain Dart and wants the Dart SDK, which
  /// ships inside the Flutter install and is what `dart` on the path resolves
  /// to here.
  final dart = Platform.resolvedExecutable.endsWith('dart')
      ? Platform.resolvedExecutable
      : 'dart';

  /// Zone to "must have more than one offset in the year". The control does not.
  const zones = <String, bool>{
    'Asia/Gaza': true,
    'America/Santiago': true,
    'Pacific/Chatham': true,
    'Australia/Lord_Howe': true,
    'America/New_York': true,
    'UTC': false,
  };

  for (final entry in zones.entries) {
    test('calendar arithmetic holds in ${entry.key}', () async {
      final result = await Process.run(
        dart,
        ['run', probe],
        environment: {'TZ': entry.key},
        workingDirectory: Directory.current.path,
      );

      expect(result.exitCode, 0, reason: 'probe failed to run: ${result.stderr}');

      // Matched anywhere in stdout rather than at the start of a line: `dart
      // run` writes `Running build hooks...` with no newline after it, so it
      // glues itself onto whatever the program prints first.
      final out = result.stdout as String;

      // Guard against a vacuous pass. A zone the host has no tzdata for
      // resolves to UTC, and then every check below would pass having tested
      // nothing at all.
      if (entry.value) {
        final offsets = RegExp(r'OFFSETS \[([^\]]*)\]').firstMatch(out)?.group(1);
        expect(
          offsets?.split(',').length ?? 0,
          greaterThan(1),
          reason: 'TZ=${entry.key} reported offsets "$offsets" — one offset all '
              'year means the host has no tzdata for it, so nothing here was '
              'actually tested',
        );
      }

      expect(
        RegExp(r'FAIL .*').allMatches(out).map((m) => m.group(0)).toList(),
        isEmpty,
        reason: 'in ${entry.key}',
      );
    });
  }
}
