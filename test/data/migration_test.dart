import 'dart:io';

import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A migration has to survive being right twice.
///
/// A phone that has run a *later* build of the schema and is then given an
/// earlier one comes back with the structure already in place and the version
/// stamp behind it. `ALTER TABLE ... ADD COLUMN` on a column that exists is
/// `duplicate column name`, and a bare `CREATE INDEX` on one that exists is
/// `index idx_bodyweight_day already exists` — either of which throws on
/// launch, before any screen, with no way back into the app.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('deltoid_migration');
    file = File('${dir.path}/deltoid.sqlite');
  });

  tearDown(() => dir.delete(recursive: true));

  /// Winds the stamp back without touching anything it describes.
  Future<void> stampVersion(int version) async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customStatement('PRAGMA user_version = $version');
    await db.close();
  }

  test('an upgrade over structure that is already there is a no-op', () async {
    final fresh = AppDatabase(NativeDatabase(file));
    await ensureStarterCatalog(fresh);
    await fresh.close();

    // Everything a v7 database has, claiming to be a v1 one: every step of
    // `onUpgrade` runs, and every one of them has its work already done.
    await stampVersion(1);

    final reopened = AppDatabase(NativeDatabase(file));
    // The migration runs lazily, on the first statement.
    final plank = await (reopened.select(reopened.exercises)
          ..where((t) => t.name.equals('Plank')))
        .getSingle();
    expect(plank.measureMode, MeasureMode.hold);
    await reopened.close();
  });

  test('the real upgrade still adds what is missing', () async {
    // The column dropped back out from under a v6 stamp, which is the shape a
    // genuine v6 → v7 upgrade arrives in.
    final fresh = AppDatabase(NativeDatabase(file));
    await ensureStarterCatalog(fresh);
    await fresh.customStatement(
      'ALTER TABLE exercises DROP COLUMN measure_mode',
    );
    await fresh.close();
    await stampVersion(6);

    final reopened = AppDatabase(NativeDatabase(file));
    final plank = await (reopened.select(reopened.exercises)
          ..where((t) => t.name.equals('Plank')))
        .getSingle();
    // Added, defaulted to reps, and then backfilled onto the hold it has
    // always been.
    expect(plank.measureMode, MeasureMode.hold);
    await reopened.close();
  });
}
