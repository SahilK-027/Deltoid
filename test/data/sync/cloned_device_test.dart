import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'two_devices.dart';

/// Two installs that share one `device_id`, which Android Auto Backup makes
/// possible.
///
/// `device_id` is minted once in `AppDatabase._ensureDeviceId` and lives in
/// `app_settings`, inside the database file. Nothing re-mints it — not a
/// restore, not adoption. So a database file copied to a second phone and
/// opened there is a second install writing rows under the first one's name,
/// and the app cannot tell.
///
/// The merge assumes the pair is unique in two places, and this is the second
/// of them — the one that loses a row rather than merely failing to break a
/// tie. `pull.dart`'s short-circuit skips a clean local row whose `updated_at`
/// and `device_id` both match the incoming one, on the stated grounds that "no
/// local edit can produce the same pair, because every one of them stamps
/// both". A clone produces it.
///
/// **And produces it easily.** `nowMs` returns `_lastStamp + 1` whenever the
/// wall clock is behind the mark, and the mark is restored out of
/// `app_settings` with the rest of the file. Two clones start from one floor
/// and walk one integer sequence, so equal stamps are the expected case
/// immediately after the copy rather than a lottery.
void main() {
  late TwoDevices devices;
  late AppDatabase a;
  late AppDatabase b;

  setUp(() {
    devices = TwoDevices();
    a = devices.a;
    b = devices.b;
  });
  tearDown(() => devices.close());

  /// The id both phones write under, because one was copied from the other.
  const clone = 'device-clone';

  Future<String> sessionName(AppDatabase db, String id) async {
    final row = await db
        .customSelect('SELECT name FROM sessions WHERE id = ?',
            variables: [Variable<String>(id)])
        .getSingle();
    return row.read<String>('name');
  }

  /// **This one passes with or without the fingerprint tie-break, and is kept
  /// for what it does prove.** Two clones editing one row still converge
  /// without it, because both keep their own copy, both push, and the server
  /// serialises them — the next pull finds each row clean and takes the
  /// account's. What is lost on an exhausted order is not convergence but
  /// determinism: the winner becomes whoever pushed last rather than a
  /// property of the rows. `sync_merge_test` is where that is asserted, and it
  /// is red without the tie-break. This asserts only that a shared id does not
  /// split the two phones outright.
  test('two clones editing one row still converge', () async {
    await devices.as(clone, () async {
      await ensureStarterCatalog(a);
      await createRegimeFromTemplate(
        a,
        regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
      );
    });
    await devices.push(a);
    await devices.pull(b);

    final id = (await a
            .customSelect('SELECT id FROM sessions ORDER BY id LIMIT 1')
            .getSingle())
        .read<String>('id');

    // The same millisecond, the same name, two different edits, and both owed.
    // Inside `stampSkewToleranceMs`, or the oracle calls the row absurd and a
    // repair restamps it — which breaks the tie by itself and leaves the test
    // green over a merge that cannot break it.
    final shared = DateTime.now().millisecondsSinceEpoch;
    for (final (db, name) in [(a, 'Mine'), (b, 'Theirs')]) {
      await db.customStatement(
        "UPDATE sessions SET name = ?, updated_at = ?, "
        "device_id = ?, dirty = 1 WHERE id = ?",
        [name, shared, clone, id],
      );
    }

    await devices.converge();

    final onA = await sessionName(a, id);
    expect(onA, await sessionName(b, id));
    expect(onA, anyOf('Mine', 'Theirs'));
  });

  test('a clone does not eat the row it should have taken', () async {
    await devices.as(clone, () async {
      await ensureStarterCatalog(a);
      await createRegimeFromTemplate(
        a,
        regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
      );
    });
    await devices.push(a);
    await devices.pull(b);

    final id = (await a
            .customSelect('SELECT id FROM sessions ORDER BY id LIMIT 1')
            .getSingle())
        .read<String>('id');

    // The stamp both clones walk to independently. A real pair reaches it by
    // running the same clamp from the same restored floor; writing it directly
    // is the same state without waiting for the clocks to line up. Inside the
    // skew tolerance, or a repair restamps the row and decides the test.
    final shared = DateTime.now().millisecondsSinceEpoch;

    // Phone B renames the day and pushes it. This is the row the account holds.
    await b.customStatement(
      "UPDATE sessions SET name = 'Pull B', updated_at = ?, "
      "device_id = ?, dirty = 1 WHERE id = ?",
      [shared, clone, id],
    );
    await devices.push(b);

    // Phone A holds a different name at the same stamp, and is settled: it
    // believes this row is the account's, because the pair says so.
    await a.customStatement(
      "UPDATE sessions SET name = 'Pull A', updated_at = ?, "
      "device_id = ?, dirty = 0 WHERE id = ?",
      [shared, clone, id],
    );

    await devices.pull(a);

    // A clean local row always loses — `resolveRow` has no weighing to do. So
    // the account's name is the one that must survive on both phones.
    expect(await sessionName(a, id), 'Pull B');
  });
}
