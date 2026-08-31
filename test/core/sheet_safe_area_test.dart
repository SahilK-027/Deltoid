import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Every `showModalBottomSheet` says `useSafeArea: true`.**
///
/// It defaults to *false*, and with `isScrollControlled` — which every sheet in
/// this app passes, because they size themselves to their content — that lets a
/// sheet take the whole screen, status bar included. The catalog picker did
/// exactly that: `Exercises` was drawn across the clock and the battery.
///
/// It cannot be fixed inside the sheet, which is what makes this mechanical
/// rather than advisory. A modal route reports **both** `padding` and
/// `viewPadding` as zero to its own child — measured on a phone with the
/// keyboard up, `padding=(t0.0,b0.0) viewPadding=(t0.0,b0.0)` — so every
/// arithmetic version of the fix was reserving `max(0, 0)` and three of them
/// shipped before anyone measured. The inset is the route's to know.
///
/// The bug is also latent almost everywhere: a sheet only reaches the status
/// bar once its content is tall enough, so a three-row confirm looks fine
/// forever and the one sheet with a focused field and forty-six rows does not.
/// Seventeen call sites were one long list away from the same defect.
///
/// Like `clamp_bounds_test`, this reads source text rather than understanding
/// Dart. It catches the accident, which is the only way this has ever happened.
void main() {
  test('every modal bottom sheet in lib/ opts into the safe area', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('showModalBottomSheet')) continue;

        // The argument list, to its closing paren or a sane bound.
        var guarded = false;
        for (var j = i + 1; j < lines.length && j < i + 30; j++) {
          if (lines[j].contains('useSafeArea')) {
            guarded = true;
            break;
          }
          if (RegExp(r'^\s*\);').hasMatch(lines[j])) break;
        }

        if (!guarded) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these sheets can draw under the status bar — add '
          '`useSafeArea: true`:\n${offenders.join('\n')}',
    );
  });
}
