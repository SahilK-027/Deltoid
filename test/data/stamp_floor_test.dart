import 'dart:io';

import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The clamp in `nowMs` has to survive a launch.
///
/// It always protected one run of the app, and the failure it exists for is
/// precisely the one that spans a launch: a phone off a flat battery, its clock
/// at the build date, a session logged, the network correcting an hour later.
/// Every row from that session is stamped in the past, loses to the version it
/// replaced, and keeps losing — `resolveRow` never revisits a verdict. So these
/// are about the mark on disk, not about the arithmetic in the clamp, which
/// `ids` has always got right within a process.
void main() {
  late Directory dir;
  late File file;

  setUpAll(() {
    // Two opens of one file is the thing under test, one at a time and the
    // first closed before the second — not the concurrent pair the warning is
    // about.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('deltoid-stamp');
    file = File('${dir.path}/deltoid.sqlite');
    resetStampsForTesting();
  });

  tearDown(() async {
    resetStampsForTesting();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AppDatabase openOnDisk() =>
      AppDatabase.forTesting(NativeDatabase(file));

  Future<int?> storedMark(AppDatabase db) async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(lastStampKey)))
        .getSingleOrNull();
    return row == null ? null : int.parse(row.value);
  }

  test('the floor raises the clamp and never lowers it', () {
    final ahead = DateTime.now().toUtc().millisecondsSinceEpoch + 3600 * 1000;
    seedStampFloor(ahead);
    // Above the floor even though the wall clock is an hour below it. This is
    // the whole mechanism: a stamp a previous run used is never handed out a
    // second time.
    expect(nowMs(), greaterThan(ahead));

    final reached = nowMs();
    // A mark from an older export, or a second seed with a stale value, cannot
    // drag the clamp back down.
    seedStampFloor(1000);
    expect(nowMs(), greaterThan(reached));
  });

  test('opening writes a lease ahead of the clock', () async {
    final db = openOnDisk();
    addTearDown(db.close);
    // `beforeOpen` runs on the first statement, not on construction.
    await db.customSelect('SELECT 1').get();

    final wall = DateTime.now().toUtc().millisecondsSinceEpoch;
    expect(await storedMark(db), greaterThan(wall));
    expect(await storedMark(db), lessThanOrEqualTo(wall + stampLeaseMs));
  });

  test('closing writes down where the session actually reached', () async {
    final db = openOnDisk();
    await db.customSelect('SELECT 1').get();
    final lease = (await storedMark(db))!;

    // A session that ran past its lease, which is the case the close is for.
    seedStampFloor(lease + 60 * 1000);
    final reached = nowMs();
    await db.close();

    final reopened = openOnDisk();
    addTearDown(reopened.close);
    expect(await storedMark(reopened), reached);
  });

  test('a reopened database hands out stamps above the ones it already used',
      () async {
    final first = openOnDisk();
    await first.customSelect('SELECT 1').get();
    seedStampFloor((await storedMark(first))! + 60 * 1000);
    final highest = nowMs();
    await first.close();

    // A fresh process: the in-memory mark is gone and only the row is left.
    resetStampsForTesting();
    final second = openOnDisk();
    addTearDown(second.close);
    await second.customSelect('SELECT 1').get();

    expect(nowMs(), greaterThan(highest));
  });

  test('relaunching does not walk the mark into the future', () async {
    // `max(wall + lease, stored)`, never `stored + lease`. The second
    // compounds, and a phone whose mark had walked a day ahead would beat every
    // row from every other device until real time caught up.
    var mark = 0;
    for (var i = 0; i < 5; i++) {
      resetStampsForTesting();
      final db = openOnDisk();
      await db.customSelect('SELECT 1').get();
      mark = (await storedMark(db))!;
      await db.close();
    }

    final wall = DateTime.now().toUtc().millisecondsSinceEpoch;
    expect(mark, lessThanOrEqualTo(wall + stampLeaseMs));
  });
}
