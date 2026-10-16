import 'package:deltoid/core/ids.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/invariants.dart';
import 'package:deltoid/data/repositories/phase_repository.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/phases.dart';
import 'package:flutter_test/flutter_test.dart';

import 'two_devices.dart';

/// Phases across two phones: [SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does)
/// rows 19 to 21, and the wire they travel on.
///
/// A phase is a statement about a span of days rather than work done in it, so
/// its one collision is settled by tombstoning rather than re-slotting, and its
/// end is derived on each phone rather than sent. What both claims come to is
/// the same check: once the phones have synced, they hold the same rows and
/// read the same phase off every day.
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

  final sep3 = DateTime(2026, 9, 3);
  final sep17 = DateTime(2026, 9, 17);

  Future<List<PhaseSpan>> spansOn(AppDatabase db) async =>
      phaseSpans(await PhaseRepository(db).phases());

  test('a phase reaches the account with every column, and the other phone '
      'without a stamp of its own', () async {
    final id = await devices.as(
      'device-a',
      () => PhaseRepository(a).startPhase(
        PhaseKind.cut,
        from: sep3,
        plannedWeeks: 12,
      ),
    );
    await devices.as('device-a', () => devices.push(a));

    final sent = devices.backend.table('phases').single;
    expect(sent['id'], id);
    expect(sent['kind'], 'cut');
    expect(sent['day_key'], 20260903);
    expect(sent['planned_weeks'], 12);
    expect(sent['end_day_key'], isNull);
    expect(sent['kept_day_key'], isNull);

    final owed = await (a.select(a.phases)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(owed.dirty, isFalse, reason: 'the push acknowledged the phase');

    await devices.as('device-b', () => devices.pull(b));
    final landed = await (b.select(b.phases)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(landed.kind, PhaseKind.cut);
    expect(landed.plannedWeeks, 12);
    expect(landed.dirty, isFalse,
        reason: 'a pulled row is not owed back to the account');
    expect(landed.deviceId, sent['device_id'],
        reason: 'a pulled row keeps the writer it came from');
    expect(landed.updatedAt, owed.updatedAt);
  });

  test('§ 12 row 19 — both start a phase on one day: one stands, the other '
      'is tombstoned', () async {
    await devices.as(
      'device-a',
      () => PhaseRepository(a).startPhase(PhaseKind.bulk, from: sep3),
    );
    await devices.as(
      'device-b',
      () => PhaseRepository(b).startPhase(PhaseKind.cut, from: sep3),
    );

    await devices.converge();

    for (final db in [a, b]) {
      final rows = await db.select(db.phases).get();
      expect(rows.length, 2, reason: 'nothing is hard-deleted');
      expect(rows.where((r) => r.deletedAt == null).length, 1,
          reason: 'one declaration made twice is one phase');
      expect(await invariantViolations(db), isEmpty);
    }
    expect(await devices.rowsOf(b), await devices.rowsOf(a));

    final onA = phaseOn(20260910, await spansOn(a))!.kind;
    final onB = phaseOn(20260910, await spansOn(b))!.kind;
    expect(onB, onA, reason: 'both phones tint the day the same');
  });

  test('§ 12 row 20 — both start a phase on different days: both stand, and '
      'the earlier ends where the later starts on both phones', () async {
    await devices.as(
      'device-a',
      () => PhaseRepository(a).startPhase(PhaseKind.bulk, from: sep3),
    );
    await devices.as(
      'device-b',
      () => PhaseRepository(b).startPhase(PhaseKind.cut, from: sep17),
    );

    await devices.converge();

    for (final db in [a, b]) {
      final spans = await spansOn(db);
      expect([for (final s in spans) s.kind], [PhaseKind.bulk, PhaseKind.cut]);
      expect(spans.first.lastKey, 20260916,
          reason: 'the end is derived from the next start, never written');
      expect(spans.last.lastKey, isNull);

      final bulk = await (db.select(db.phases)
            ..where((t) => t.kind.equalsValue(PhaseKind.bulk)))
          .getSingle();
      expect(bulk.endDayKey, isNull,
          reason: 'starting a phase never edits the one before it');
    }
    expect(await devices.rowsOf(b), await devices.rowsOf(a));
  });

  test('§ 12 row 21 — one phone clears the phase while the other changes its '
      'length: one whole edit stands', () async {
    final id = await devices.as(
      'device-a',
      () => PhaseRepository(a).startPhase(
        PhaseKind.cut,
        from: sep3,
        plannedWeeks: 12,
      ),
    );
    await devices.as('device-a', () => devices.sync(a));
    await devices.as('device-b', () => devices.sync(b));

    await devices.as(
      'device-a',
      () => PhaseRepository(a).clearPhase(id, on: DateTime(2026, 10, 1)),
    );
    await devices.as(
      'device-b',
      () => PhaseRepository(b).editPhase(id, from: sep3, plannedWeeks: 16),
    );

    await devices.converge();

    final onA = await (a.select(a.phases)..where((t) => t.id.equals(id)))
        .getSingle();
    final onB = await (b.select(b.phases)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(onB.endDayKey, onA.endDayKey);
    expect(onB.plannedWeeks, onA.plannedWeeks);

    // Row-level, never a field merge: either the clear stands with the length
    // it was made against, or the new length stands on a phase still running.
    final cleared = onA.endDayKey == 20261001 && onA.plannedWeeks == 12;
    final lengthened = onA.endDayKey == null && onA.plannedWeeks == 16;
    expect(cleared || lengthened, isTrue,
        reason: 'end ${onA.endDayKey}, ${onA.plannedWeeks} weeks is a phase '
            'neither phone set');
  });

  test('a prompt answered on one phone is answered on the other', () async {
    final id = await devices.as(
      'device-a',
      () => PhaseRepository(a).startPhase(
        PhaseKind.bulk,
        from: sep3,
        plannedWeeks: 8,
      ),
    );
    await devices.as('device-a', () async {
      await PhaseRepository(a).keepGoingPastPlan(id);
      await PhaseRepository(a)
          .keepGoingAgainstWeighIns(id, on: DateTime(2026, 11, 2));
    });

    await devices.converge();

    final span = (await spansOn(b)).single;
    expect(span.phase.plannedWeeks, isNull);
    expect(span.phase.keptKey, 20261102);
    expect(
      plannedLengthPassed(span, todayKey: dayKeyOf(DateTime(2026, 12, 1))),
      isFalse,
      reason: 'the other phone must not ask the question again',
    );
  });
}
