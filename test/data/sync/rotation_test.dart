import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/regime_repository.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/domain/cycle_engine.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'two_devices.dart';

/// Days that alternate, across two phones.
///
/// A rotation is one column on `sessions`, and which day is due is derived
/// from the log on each phone rather than sent
/// ([SYNC.md § 4](SYNC.md#4-what-the-server-holds)). These hold the two
/// consequences: the column arrives like any other, and a session logged on
/// one phone moves the rotation on the other by arriving.
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

  Future<void> bothInStep() async {
    await devices.as('device-a', () async {
      await ensureStarterCatalog(a);
      await createRegimeFromTemplate(
        a,
        regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
      );
    });
    await devices.push(a);
    await devices.pull(b);
  }

  Future<Session> sessionNamed(AppDatabase db, String name) =>
      (db.select(db.sessions)..where((t) => t.name.equals(name))).getSingle();

  Future<Regime> activeRegime(AppDatabase db) =>
      (db.select(db.regimes)..where((t) => t.isActive.equals(true))).getSingle();

  Future<List<String>> dayOrder(AppDatabase db) async {
    final rows = await (db.select(db.sessions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    return [for (final s in rows) s.name];
  }

  Future<void> alternate(
    String device,
    AppDatabase db,
    String day,
    String partner,
  ) =>
      devices.as(device, () async {
        await RegimeRepository(db).alternateSessions(
          (await sessionNamed(db, day)).id,
          (await sessionNamed(db, partner)).id,
        );
      });

  Future<void> train(String device, AppDatabase db, String day) =>
      devices.as(device, () async {
        final repo = TrainingRepository(db);
        final regime = await activeRegime(db);
        final id = await repo.startWorkout(
          regimeId: regime.id,
          sessionId: (await sessionNamed(db, day)).id,
        );
        final detail = await repo.workoutDetail(id);
        await repo.updateSet(
          detail!.entries.first.sets.first.id,
          weight: const Value(20),
          reps: const Value(8),
          isDone: const Value(true),
        );
        await repo.completeWorkout(id);
      });

  Future<CycleStatus> statusOn(AppDatabase db) async =>
      (await TrainingRepository(db).cycleStatus((await activeRegime(db)).id))!;

  String dueLeg(CycleStatus status) =>
      status.positions.firstWhere((p) => p.alternates).dueSessionId;

  test('a rotation made on one phone alternates on the other', () async {
    await bothInStep();

    await alternate('device-a', a, 'Leg 2', 'Leg 1');
    await devices.converge();

    final leg1 = await sessionNamed(b, 'Leg 1');
    final leg2 = await sessionNamed(b, 'Leg 2');
    expect(leg1.rotationId, isNotNull);
    expect(leg2.rotationId, leg1.rotationId);
    expect(await dayOrder(b),
        ['Push 1', 'Pull 1', 'Leg 1', 'Leg 2', 'Push 2', 'Pull 2']);

    final status = await statusOn(b);
    expect(status.total, 5);
    expect(dueLeg(status), leg1.id);
  });

  test('a cycle trained on one phone moves the rotation on the other',
      () async {
    await bothInStep();
    await alternate('device-a', a, 'Leg 2', 'Leg 1');
    await devices.converge();

    for (final day in ['Push 1', 'Pull 1', 'Leg 1', 'Push 2', 'Pull 2']) {
      await train('device-a', a, day);
    }
    await devices.converge();

    // Phone B logged nothing and was told nothing about whose turn it is. It
    // holds the workouts now, and reads the turn off them.
    final status = await statusOn(b);
    expect(status.cycleIndex, 2);
    expect(dueLeg(status), (await sessionNamed(b, 'Leg 2')).id);
    expect(dueLeg(await statusOn(a)), dueLeg(status));
  });

  test('two phones pairing a day differently settle on one answer', () async {
    await bothInStep();

    // Offline, each phone gives Leg 1 a different partner. Both rewrite the
    // Leg 1 row and both renumber the days.
    await alternate('device-a', a, 'Leg 2', 'Leg 1');
    await alternate('device-b', b, 'Pull 2', 'Leg 1');
    await devices.converge();

    expect(await devices.rowsOf(b), await devices.rowsOf(a),
        reason: 'both devices must reach the same answer, not each their own');

    for (final db in [a, b]) {
      final status = await statusOn(db);
      final placed = [for (final p in status.positions) ...p.sessionIds];
      // Every day is in exactly one position, whichever pairing won, and no
      // day was lost to the collision.
      expect(placed, hasLength(6));
      expect(placed.toSet(), hasLength(6));
      expect(status.total, inInclusiveRange(4, 6));
      // No two live days share a place in the order.
      expect((await dayOrder(db)).toSet(), hasLength(6));
    }
    expect(
      [for (final p in (await statusOn(a)).positions) p.sessionIds],
      [for (final p in (await statusOn(b)).positions) p.sessionIds],
    );
  });

  test('a rotation stopped on one phone stops on the other', () async {
    await bothInStep();
    await alternate('device-a', a, 'Leg 2', 'Leg 1');
    await devices.converge();

    await devices.as('device-b', () async {
      await RegimeRepository(b)
          .stopAlternating((await sessionNamed(b, 'Leg 1')).id);
    });
    await devices.converge();

    expect((await statusOn(a)).total, 6);
    expect((await sessionNamed(a, 'Leg 2')).rotationId, isNull);
  });
}
