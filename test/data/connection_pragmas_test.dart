import 'dart:io';

import 'package:deltoid/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four pragmas `beforeOpen` sets, read back off a real file.
///
/// In-memory sqlite is always `journal_mode = memory`, so none of this can be
/// asserted on the executor every other test uses.
void main() {
  late Directory dir;
  late AppDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('deltoid_pragma');
    db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/deltoid.sqlite')));
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<Object?> pragma(String name) async {
    final row = await db.customSelect('PRAGMA $name').getSingle();
    return row.data.values.single;
  }

  test('a commit is fsynced, so a power cut cannot cost the last set', () async {
    // 2 is FULL. Under WAL this is what makes the durability contract "never
    // loses a committed transaction" rather than "loses the last one to a
    // power cut" — 1 (NORMAL) is the faster setting that gives that up.
    expect(await pragma('synchronous'), 2);
  });

  test('a reader and a writer overlap', () async {
    expect(await pragma('journal_mode'), 'wal');
  });

  test('referential integrity is real', () async {
    expect(await pragma('foreign_keys'), 1);
  });

  test('a busy lock waits rather than throwing at the screen', () async {
    expect(await pragma('busy_timeout'), 5000);
  });
}
