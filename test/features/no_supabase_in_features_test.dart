import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The client library stays behind our own interface.
///
/// [SYNC.md § 16](SYNC.md#16-still-to-decide) chose `supabase_flutter` for the
/// parts worth not hand-rolling — Google sign-in, a persisted session, silent
/// refresh — and § 17 put it behind an interface so that swapping the backend,
/// or testing without one, is a constructor argument rather than an excavation.
/// That only stays true while nothing above `data/sync/` knows the package
/// exists.
///
/// A comment cannot fail a build ([RULES § 7](RULES.md#7-working-on-it)), and
/// the violation is one autocomplete away: a screen that wants the signed-in
/// email is two characters from importing `supabase_flutter` and reading
/// `Supabase.instance.client.auth.currentUser`. It would work, and every screen
/// after it would be untestable without a network.
void main() {
  const forbidden = ['package:supabase_flutter', 'package:google_sign_in'];

  /// Where each package is allowed to appear.
  const allowed = 'lib/data/sync/supabase_backend.dart';

  test('nothing outside data/sync knows which backend this is', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      if (file.path == allowed) continue;
      final source = file.readAsStringSync();
      for (final package in forbidden) {
        if (source.contains("import '$package") ||
            source.contains('import "$package')) {
          offenders.add('${file.path} imports $package');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'only $allowed may import the client library. Everything else '
          'takes `SyncAuth`, or the transport interface, so it can be tested '
          'against a fake that never opens a socket — SYNC.md § 17:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the one file that may import it still does', () {
    // Otherwise the test above passes forever by describing nothing, which is
    // how a boundary check quietly stops being one.
    final source = File(allowed).readAsStringSync();
    for (final package in forbidden) {
      expect(source, contains("import '$package"));
    }
  });
}
