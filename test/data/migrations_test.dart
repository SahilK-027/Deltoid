import 'dart:io';

import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/migrations.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ladder, and the one property every rung of it has to have.
///
/// A device handed an earlier build and then the newer one again comes back
/// with the structure already in place and the version stamp behind it. Drift
/// replays the step, and a bare `m.addColumn` or `m.createIndex` throws at open
/// — before a screen is drawn, on a phone holding the only copy of a history.
/// So every step is run twice here, over a database that already has
/// everything, and is held to changing nothing.
void main() {
  setUpAll(() {
    // Several databases at once by design: a fresh one to compare against, and
    // the same file opened twice to make an upgrade happen.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  /// A file nothing else is using, deleted with the test.
  File aFile() {
    final file =
        File('${Directory.systemTemp.path}/deltoid_ladder_${newId()}.sqlite');
    addTearDown(() {
      for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      }
    });
    return file;
  }

  /// Every index the file actually carries, by name and by the SQL that made
  /// it. `sqlite_master` rather than the generated schema: the question is what
  /// is on disk, not what was asked for.
  Future<Map<String, String?>> indexesOf(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'index'",
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('name'): row.readNullable<String>('sql'),
    };
  }

  Future<Set<String>> tablesOf(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        )
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }

  test('an upgrade over a database that already has everything changes nothing',
      () async {
    final file = aFile();

    // A database created at today's version, so every index the ladder is about
    // to ask for is already there. This is the shape a phone is in when it is
    // handed an older build and then the newer one again.
    final created = AppDatabase.forTesting(NativeDatabase(file));
    final before = (await indexesOf(created), await tablesOf(created));
    // Wind the stamp back so the next open runs the ladder from the bottom.
    await created.customStatement('PRAGMA user_version = 1');
    await created.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);

    // The whole point: opening does not throw. A bare `m.createIndex` here
    // fails with "index idx_exercises_dirty already exists" before first paint.
    final after = (await indexesOf(upgraded), await tablesOf(upgraded));
    expect(after.$1, before.$1, reason: 'the ladder altered an index');
    expect(after.$2, before.$2, reason: 'the ladder altered a table');

    final stamp = await upgraded.customSelect('PRAGMA user_version').getSingle();
    expect(stamp.data.values.first, upgraded.schemaVersion);
  });

  test('a database created fresh and one walked up the ladder are the same '
      'shape', () async {
    // The other half of the same claim. The step above proved replaying is
    // safe; this proves the two populations — installed today, and upgraded
    // into today — end up with one schema rather than two that differ by an
    // index nobody notices until a query plan does.
    final fresh = AppDatabase.forTesting(NativeDatabase(aFile()));
    addTearDown(fresh.close);

    final file = aFile();
    final old = AppDatabase.forTesting(NativeDatabase(file));
    // A v1 database is today's minus everything the ladder adds. The `phases`
    // table goes with its indexes, which is also what proves the first rung
    // does not reach for `idx_phases_dirty` before the table exists.
    for (final name in (await indexesOf(old)).keys) {
      if (name.endsWith('_dirty')) {
        await old.customStatement('DROP INDEX $name');
      }
    }
    await old.customStatement('DROP TABLE phases');
    await old.customStatement('PRAGMA user_version = 1');
    await old.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);

    expect(await indexesOf(upgraded), await indexesOf(fresh));
    expect(await tablesOf(upgraded), await tablesOf(fresh));
  });

  test('a phone on schema 6 gains phases and keeps everything it had',
      () async {
    final fresh = AppDatabase.forTesting(NativeDatabase(aFile()));
    addTearDown(fresh.close);

    final file = aFile();
    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.into(old.bodyweightLogs).insert(
          BodyweightLogsCompanion.insert(dayKey: 20261001, weightKg: 72.5),
        );
    // Schema 6 is today's without the `phases` table; dropping the table
    // takes its two indexes with it.
    await old.customStatement('DROP TABLE phases');
    await old.customStatement('PRAGMA user_version = 6');
    await old.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);

    Future<String?> createOf(AppDatabase db) async => (await db
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'phases'",
            )
            .getSingle())
        .read<String?>('sql');

    expect(await createOf(upgraded), await createOf(fresh),
        reason: 'the table the ladder creates is the one a fresh install has');
    expect(await indexesOf(upgraded), await indexesOf(fresh));

    final kept = await upgraded.select(upgraded.bodyweightLogs).getSingle();
    expect(kept.weightKg, 72.5, reason: 'the upgrade lost a row');

    // And the new table takes a row, which is the launch that follows.
    await upgraded.into(upgraded.phases).insert(
          PhasesCompanion.insert(kind: PhaseKind.cut, dayKey: 20261001),
        );
    expect(await upgraded.select(upgraded.phases).get(), hasLength(1));

    final stamp = await upgraded.customSelect('PRAGMA user_version').getSingle();
    expect(stamp.data.values.first, 7);
  });

  test('what is owed is counted through an index rather than a scan', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // `set_logs` is the one that matters: 168k rows at fifty years, and sync's
    // state is derived — so this question is asked every time a set is ticked.
    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT COUNT(*) FROM set_logs WHERE dirty = 1',
        )
        .get();
    final detail = plan.map((r) => r.read<String>('detail')).join(' ');
    expect(detail, contains('idx_set_logs_dirty'));
    expect(detail, isNot(contains('SCAN set_logs')));
  });

  test('every syncable table can be asked what it owes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final indexes = await indexesOf(db);
    final dirty = indexes.keys.where((n) => n.endsWith('_dirty')).toList();
    expect(dirty, hasLength(10),
        reason: 'ten syncable tables, ten partial indexes — SYNC.md § 17');

    for (final name in dirty) {
      // Partial, so the index is *empty* whenever nothing is owed. An unpartial
      // index on a boolean would carry every row of `set_logs` forever to
      // answer a question that is usually "none".
      expect(indexes[name], contains('WHERE dirty = 1'),
          reason: '$name indexes rows that are not owed');
    }
  });

  test('addColumnIfMissing is a no-op on a column that is already there',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final m = Migrator(db);
    // The guard, run against a column every database has had since v1. Without
    // it this is `duplicate column name: notes`.
    await addColumnIfMissing(db, m, db.exercises, db.exercises.notes);
    await addColumnIfMissing(db, m, db.exercises, db.exercises.notes);

    expect(await hasColumn(db, 'exercises', 'notes'), isTrue);
    expect(await hasColumn(db, 'exercises', 'a_column_nobody_added'), isFalse);
  });
}
