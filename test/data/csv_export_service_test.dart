import 'dart:convert';
import 'dart:io';

import 'package:deltoid/data/backup/csv_export_service.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/units.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late Directory dir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    dir = Directory.systemTemp.createTempSync('deltoid-csv-');
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// Starts [session], ticks every set of its first exercise at [weight] and
  /// leaves the rest blank, then finishes it unless [finish] is false.
  Future<String> logSession(
    String session, {
    double weight = 22.5,
    bool finish = true,
  }) async {
    final regime =
        await (db.select(db.regimes)..where((t) => t.isActive.equals(true)))
            .getSingle();
    final day = await (db.select(db.sessions)
          ..where((t) => t.name.equals(session)))
        .getSingle();
    final id = await repo.startWorkout(regimeId: regime.id, sessionId: day.id);
    final detail = await repo.workoutDetail(id);
    for (final set in detail!.entries.first.sets) {
      await repo.updateSet(
        set.id,
        weight: Value(weight),
        reps: const Value(8),
        isDone: const Value(true),
      );
    }
    if (finish) await repo.completeWorkout(id);
    return id;
  }

  /// The file's lines, the byte order mark checked and removed.
  List<String> linesOf(File file) {
    final bytes = file.readAsBytesSync();
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    return utf8.decode(bytes.skip(3).toList()).split('\r\n')..removeLast();
  }

  test('one row per ticked set of a finished session, numbered from one',
      () async {
    await logSession('Push 1');
    final file = await CsvExportService(db)
        .writeSets(File('${dir.path}/sets.csv'), WeightUnit.kg);

    final lines = linesOf(file);
    expect(lines.first, startsWith('Date,Time,Duration (min),Regime,Session'));
    expect(lines, hasLength(4));
    for (final (i, line) in lines.skip(1).indexed) {
      final cells = line.split(',');
      expect(cells[4], 'Push 1');
      expect(cells[10], '1', reason: 'exercise order');
      expect(cells[11], '${i + 1}', reason: 'set number');
      expect(cells[12], 'Working');
      expect(cells[13], '22.5');
      expect(cells[15], '8');
    }
    expect(File('${file.path}.part').existsSync(), isFalse);
  });

  test('a session still being logged is not history yet', () async {
    await logSession('Push 1');
    await logSession('Pull 1', finish: false);
    final file = await CsvExportService(db)
        .writeSets(File('${dir.path}/sets.csv'), WeightUnit.kg);

    final lines = linesOf(file);
    expect(lines, hasLength(4));
    expect(lines.skip(1).every((l) => l.contains(',Push 1,')), isTrue);
  });

  test('sessions arrive oldest first across a page boundary', () async {
    await logSession('Push 1', weight: 20);
    await logSession('Pull 1', weight: 30);
    await logSession('Leg 1', weight: 40);
    final file = await CsvExportService(db, workoutsPerPage: 1)
        .writeSets(File('${dir.path}/sets.csv'), WeightUnit.kg);

    final sessions = [
      for (final line in linesOf(file).skip(1)) line.split(',')[4],
    ];
    expect(sessions, [
      ...List.filled(3, 'Push 1'),
      ...List.filled(3, 'Pull 1'),
      ...List.filled(3, 'Leg 1'),
    ]);
  });

  test('an empty log is a header and nothing else', () async {
    final file = await CsvExportService(db)
        .writeSets(File('${dir.path}/sets.csv'), WeightUnit.lb);
    expect(linesOf(file), [contains('Weight (lb)')]);
  });

  test('weigh-ins are written oldest first, deleted ones left out', () async {
    await repo.logBodyweight(DateTime(2026, 7, 21), 72.8);
    await repo.logBodyweight(DateTime(2026, 7, 20), 72.4);
    await repo.logBodyweight(DateTime(2026, 7, 22), 90);
    await repo.deleteBodyweight(20260722);
    final file = await CsvExportService(db)
        .writeBodyweight(File('${dir.path}/bw.csv'), WeightUnit.kg);

    expect(linesOf(file), [
      'Date,Bodyweight (kg)',
      '2026-07-20,72.4',
      '2026-07-21,72.8',
    ]);
  });
}
