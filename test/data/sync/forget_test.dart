import 'package:deltoid/core/providers.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/table_spec.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/forget.dart';
import 'package:deltoid/data/sync/pull.dart';
import 'package:deltoid/data/sync/push.dart';
import 'package:deltoid/domain/units.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The second door of [SYNC.md § 11](SYNC.md#11-signing-out): sign out *and*
/// remove the history from this phone.
///
/// The rows go without a trace to push. This is not *the user deleted their
/// training* — which the account would hear about and apply everywhere — it is
/// *this phone is no longer carrying it*.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await setWeightUnit(db, WeightUnit.kg);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: lastPullKey, value: 'a-cursor'),
        );
  });

  tearDown(() => db.close());

  Future<int> rowsIn(String table) => db
      .customSelect('SELECT COUNT(*) AS n FROM $table')
      .map((row) => row.read<int>('n'))
      .getSingle();

  test('everything that syncs goes, and nothing is left owed', () async {
    await forgetLocalHistory(db);

    for (final spec in tableSpecs(db).where((s) => s.syncs)) {
      if (spec.name == 'exercises') continue;
      expect(await rowsIn(spec.name), 0, reason: '${spec.name} survived');
    }
    // Hard-deleted, so there is nothing left to tell the account about.
    final owed = await db
        .customSelect('SELECT COUNT(*) AS n FROM regimes WHERE dirty = 1')
        .map((row) => row.read<int>('n'))
        .getSingle();
    expect(owed, 0);
  });

  test('a catalog is left to train from', () async {
    await forgetLocalHistory(db);

    expect(await rowsIn('exercises'), greaterThan(0));
  });

  test('a pull about to arrive brings its own catalog instead', () async {
    await forgetLocalHistory(db, seed: false);

    expect(await rowsIn('exercises'), 0);
  });

  test('this phone keeps being this phone', () async {
    await forgetLocalHistory(db);

    // The unit, the theme and the device id are facts about the phone rather
    // than about the training — SYNC.md § 4.
    final unit = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(unitsKey)))
        .getSingle();
    expect(unit.value, WeightUnit.kg.name);
    // The cursors are not: they point into a history this phone no longer has.
    final cursor = await (db.select(db.appSettings)
          ..where((t) => t.key.isIn([lastPullKey, lastPushKey])))
        .get();
    expect(cursor, isEmpty);
  });

  test('the prompt can name what it is about to remove', () async {
    expect(await localSessionCount(db), 0);
  });
}
