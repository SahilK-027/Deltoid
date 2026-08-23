import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/invariants.dart';
import 'package:flutter_test/flutter_test.dart';

export 'package:deltoid/data/db/invariants.dart'
    show InvariantViolation, invariantRuleNames, invariantViolations;

/// The test-facing half of the oracle. **The rules themselves moved to
/// `lib/data/db/invariants.dart`** — a judge that only runs in CI judges the
/// databases the tests build and never the one on the phone, and the restore
/// and the pull applier both call it now. This file is what is left: the one
/// thing a test wants that the app does not, which is a failed expectation
/// instead of a returned list.

/// Fails the test if anything in [db] breaks a structural rule.
///
/// [after] names what was just done, so a failure in a long sequence says which
/// operation left the database wrong rather than only that it is.
Future<void> expectInvariants(AppDatabase db, {String? after}) async {
  final found = await invariantViolations(db);
  expect(
    found,
    isEmpty,
    reason: [
      if (after != null) 'after $after:',
      for (final v in found) '  $v',
    ].join('\n'),
  );
}
