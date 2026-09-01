// Builds a seeded database file on this machine, for `tool/seed_device.sh` to
// install on a device.
//
// It is a test rather than a script because the importer reaches into Flutter —
// it decodes off the main isolate — so it needs a Flutter test binding, which
// plain `dart run` cannot give it. Nothing here asserts anything about the app;
// the test framework is only the runtime.
//
// Driven by environment variables, because a test takes no arguments:
//
//   SEED_YEARS=20 SEED_SEED=7 SEED_OUT=build/seed.sqlite \
//     flutter test tool/test/seed_device_test.dart
//
// It is under tool/test/ so that `flutter test` never runs it by accident.

import 'dart:convert';
import 'dart:io';

import 'package:deltoid/data/backup/backup_service.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../seed_years.dart' show buildSeedPayload;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('writes a seeded database through the real importer', () async {
    final years = int.parse(Platform.environment['SEED_YEARS'] ?? '20');
    final seed = int.parse(Platform.environment['SEED_SEED'] ?? '7');
    final path = Platform.environment['SEED_OUT'] ??
        'build/deltoid-seed-${years}y.sqlite';

    final out = File(path);
    await out.parent.create(recursive: true);
    for (final f in [out, File('$path-wal'), File('$path-shm')]) {
      if (f.existsSync()) f.deleteSync();
    }

    final payload = jsonEncode(buildSeedPayload(years: years, seed: seed));

    final db = AppDatabase.forTesting(NativeDatabase(out));
    final result = await BackupService(db).restore(payload);
    final workouts = await db.select(db.workouts).get();
    await db.close();

    expect(workouts, isNotEmpty);
    stdout.writeln('SEEDED ${result.rowsWritten} rows, '
        '${workouts.length} workouts -> $path');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
