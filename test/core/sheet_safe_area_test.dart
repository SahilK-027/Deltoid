import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Every sheet opens through `showAppSheet`, and it says `useSafeArea: true`.**
///
/// `useSafeArea` defaults to *false*, and with `isScrollControlled` — which
/// every sheet in this app passes, because they size themselves to their
/// content — that lets a sheet take the whole screen, status bar included — a
/// catalog picker drawing `Exercises` across the clock and the battery.
///
/// It cannot be answered inside the sheet, which is what makes this mechanical
/// rather than advisory. A modal route reports **both** `padding` and
/// `viewPadding` as zero to its own child — measured on a phone with the
/// keyboard up, `padding=(t0.0,b0.0) viewPadding=(t0.0,b0.0)` — so any
/// arithmetic version reserves `max(0, 0)` and looks correct. The inset is the
/// route's to know.
///
/// It is also latent almost everywhere: a sheet only reaches the status bar
/// once its content is tall enough, so a three-row confirm looks right forever
/// and the one sheet with a focused field and forty-six rows does not.
///
/// So the route is written once. Thirty-one call sites each spelling out the
/// same four flags is how three of them came to leave one out; a call to
/// `showModalBottomSheet` anywhere but `showAppSheet` is a sheet that can come
/// out different from its neighbours.
///
/// Like `clamp_bounds_test`, this reads source text rather than understanding
/// Dart. It catches the accident, which is the only way this has ever happened.
void main() {
  const home = 'lib/core/widgets/primitives.dart';

  test('only showAppSheet opens a modal bottom sheet', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('showModalBottomSheet')) continue;
        if (file.path == home) continue;
        offenders.add('${file.path}:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'open these sheets with `showAppSheet` instead:\n'
          '${offenders.join('\n')}',
    );
  });

  test('showAppSheet opts into the safe area', () {
    final source = File(home).readAsStringSync();
    final start = source.indexOf('Future<T?> showAppSheet<T>(');
    expect(start, isNot(-1), reason: '`showAppSheet` has moved out of $home');

    final body = source.substring(start, source.indexOf('\n}\n', start));
    expect(body, contains('showModalBottomSheet'));
    expect(body, contains('useSafeArea: true'));
  });
}
