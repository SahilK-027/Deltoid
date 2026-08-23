import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/sync_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every merge rule, without a database.
///
/// [SYNC.md § 17](SYNC.md#17-the-architecture): which version of a row wins,
/// which free index a loser takes, which regime keeps the active flag and which
/// workout stays open are all functions of plain values — which is what makes
/// [§ 9](SYNC.md#9-collision--two-rows-one-slot)'s twelve rows twelve unit tests
/// rather than twelve integration tests.
///
/// **Symmetry is asserted, not assumed.** Every rule here runs on two devices
/// that never speak to each other, and a rule that answers *whichever I saw
/// first* converges on nothing. So each test that decides between two rows also
/// asks the same question with the arguments swapped.
void main() {
  Stamp stamp(int updatedAt, [String device = 'a', String fingerprint = '']) =>
      (updatedAt: updatedAt, deviceId: device, fingerprint: fingerprint);

  group('which version of a row survives', () {
    test('a clean local row is a copy, so the server always wins', () {
      // Older on the wire and still taken: local was not edited — every local
      // write sets dirty — so there is nothing to lose.
      expect(
        resolveRow(
          localDirty: false,
          local: stamp(9000),
          remote: stamp(1000),
        ),
        RowVerdict.takeRemote,
      );
    });

    test('a dirty local row weighs the two clocks', () {
      expect(
        resolveRow(localDirty: true, local: stamp(1000), remote: stamp(2000)),
        RowVerdict.takeRemote,
      );
      expect(
        resolveRow(localDirty: true, local: stamp(2000), remote: stamp(1000)),
        RowVerdict.keepLocal,
      );
    });

    test('a month offline loses to a newer server row — § 12 row 10', () {
      const june = 1750000000000;
      const july = 1752592000000;
      expect(
        resolveRow(
          localDirty: true,
          local: stamp(june, 'the-phone-in-a-drawer'),
          remote: stamp(july, 'the-phone-in-use'),
        ),
        RowVerdict.takeRemote,
      );
    });

    test('the same millisecond breaks on the device id, both ways', () {
      const same = 1750000000000;
      expect(
        resolveRow(
          localDirty: true,
          local: stamp(same, 'aaa'),
          remote: stamp(same, 'bbb'),
        ),
        RowVerdict.takeRemote,
      );
      // The mirror image on the other phone: same pair, opposite roles, and the
      // same row wins. Without this each device keeps its own and neither ever
      // learns the other wrote.
      expect(
        resolveRow(
          localDirty: true,
          local: stamp(same, 'bbb'),
          remote: stamp(same, 'aaa'),
        ),
        RowVerdict.keepLocal,
      );
    });
  });

  group('two rows, one position', () {
    test('the row created later moves, and both devices agree which', () {
      // UUID v7, so the greater string is the later creation.
      const early = '019820aa-0000-7000-8000-000000000001';
      const late = '019820bb-0000-7000-8000-000000000002';

      final fromA = resolveSlot(
        incomingId: late,
        occupantId: early,
        liveIndexes: const [0, 1, 2],
      );
      final fromB = resolveSlot(
        incomingId: early,
        occupantId: late,
        liveIndexes: const [0, 1, 2],
      );

      expect(fromA.moveId, late);
      expect(fromB.moveId, late, reason: 'the other phone must agree');
      expect(fromA.toIndex, 3);
      expect(fromB.toIndex, 3);
    });

    test('the next free index is one past the highest, not the count', () {
      // A tombstoned row left a hole at 1: appending goes above the highest
      // live position, exactly as every append in the app already does.
      expect(
        resolveSlot(
          incomingId: 'b',
          occupantId: 'a',
          liveIndexes: const [0, 2, 3],
        ).toIndex,
        4,
      );
      expect(
        resolveSlot(incomingId: 'b', occupantId: 'a', liveIndexes: const [])
            .toIndex,
        0,
      );
    });
  });

  group('two days, one name', () {
    test('the suffix counts up until it is free', () {
      expect(disambiguateName('Push 1', {'pull 1'}), 'Push 1');
      expect(disambiguateName('Push 1', {'push 1'}), 'Push 1 (2)');
      expect(
        disambiguateName('Push 1', {'push 1', 'push 1 (2)'}),
        'Push 1 (3)',
      );
    });

    test('compared the way a person compares them', () {
      expect(disambiguateName('  Push 1  ', {'push 1'}), 'Push 1 (2)');
      expect(disambiguateName('PUSH 1', {'push 1'}), 'PUSH 1 (2)');
    });

    test('a suffix never pushes a legal name over the column CHECK', () {
      final long = 'P' * 60;
      final result = disambiguateName(long, {long.toLowerCase()});
      expect(result.length, lessThanOrEqualTo(60));
      expect(result, endsWith(' (2)'));
    });
  });

  group('two rows, both open', () {
    test('the newer stays open; the older is completed, not discarded', () {
      const morning = (id: 'a', startedAt: 1000);
      const evening = (id: 'b', startedAt: 2000);

      expect(staysOpen(a: morning, b: evening), 'b');
      expect(staysOpen(a: evening, b: morning), 'b');
    });

    test('two sessions started in the same millisecond break on the id', () {
      const a = (id: 'aaa', startedAt: 1000);
      const b = (id: 'bbb', startedAt: 1000);
      expect(staysOpen(a: a, b: b), 'bbb');
      expect(staysOpen(a: b, b: a), 'bbb');
    });
  });

  test('the active flag is last write wins, and the loser survives', () {
    expect(
      remoteKeepsActive(local: stamp(1000), remote: stamp(2000)),
      isTrue,
    );
    expect(
      remoteKeepsActive(local: stamp(2000), remote: stamp(1000)),
      isFalse,
    );
  });

  group('identity slots', () {
    test('the lowest free one, exactly as a new regime is given', () {
      expect(freeIdentitySlot({0, 1, 3}), 2);
      expect(freeIdentitySlot({}), 0);
    });

    test('a full shelf has no answer, and says so', () {
      final full = {for (var i = 0; i < identitySlots; i++) i};
      expect(
        freeIdentitySlot(full),
        isNull,
        reason: 'seven live regimes do not fit six slots, whatever § 12 row 15 '
            'says — the applier lands the seventh tombstoned instead',
      );
    });
  });

  test('a renumbered cycle takes the next number, never a hole', () {
    expect(freeCycleIndex([1, 2, 3]), 4);
    // Cycles count from 1: `planNextCycle` reads the last one, and a zeroth
    // cycle would make "Cycle 0" a thing Today can say.
    expect(freeCycleIndex([]), 1);
    expect(freeCycleIndex([7]), 8);
  });

  test('one day, one bodyweight: last write wins and the loser is tombstoned',
      () {
    expect(remoteWinsTheDay(local: stamp(1000), remote: stamp(2000)), isTrue);
    expect(remoteWinsTheDay(local: stamp(2000), remote: stamp(1000)), isFalse);
    // Symmetric on the tie, like everything else here.
    expect(
      remoteWinsTheDay(local: stamp(1000, 'a'), remote: stamp(1000, 'b')),
      isTrue,
    );
    expect(
      remoteWinsTheDay(local: stamp(1000, 'b'), remote: stamp(1000, 'a')),
      isFalse,
    );
  });

  group('two installs writing under one device id', () {
    /// **The tie-break has to break.**
    ///
    /// `device_id` is minted once into `app_settings`, inside the database
    /// file, and nothing re-mints it — so a copy of that file opened on a
    /// second phone writes under the first one's name. Both then walk `nowMs`
    /// from one restored floor, which makes an equal `updated_at` between them
    /// ordinary rather than a coincidence.
    ///
    /// Every rule in this file is asserted with its arguments swapped because
    /// two phones never speak: the property is that both compute the *same*
    /// winner. On an exhausted order they do not. Each keeps its own version,
    /// which is the one answer a merge may not give — and it is silent, because
    /// nothing about either row is wrong.
    test('two versions on one stamp still resolve to one winner', () {
      const mine = (updatedAt: 5000, deviceId: 'twin', fingerprint: 'aaa');
      const theirs = (updatedAt: 5000, deviceId: 'twin', fingerprint: 'bbb');

      // The phone holding `mine` asks about `theirs`, and the phone holding
      // `theirs` asks about `mine`. Exactly one of them must give way.
      final iTakeTheirs =
          resolveRow(localDirty: true, local: mine, remote: theirs) ==
              RowVerdict.takeRemote;
      final theyTakeMine =
          resolveRow(localDirty: true, local: theirs, remote: mine) ==
              RowVerdict.takeRemote;

      expect(iTakeTheirs, isNot(theyTakeMine),
          reason: 'both kept their own copy, and neither ever learns');
    });

    test('the same two versions always pick the same winner', () {
      const a = (updatedAt: 5000, deviceId: 'twin', fingerprint: 'aaa');
      const b = (updatedAt: 5000, deviceId: 'twin', fingerprint: 'bbb');

      expect(resolveRow(localDirty: true, local: a, remote: b),
          RowVerdict.takeRemote);
      expect(resolveRow(localDirty: true, local: b, remote: a),
          RowVerdict.keepLocal);
    });

    test('identical content on one stamp is not a conflict at all', () {
      const same = (updatedAt: 5000, deviceId: 'twin', fingerprint: 'aaa');

      expect(resolveRow(localDirty: true, local: same, remote: same),
          RowVerdict.keepLocal,
          reason: 'nothing to take: the two rows are the same row');
    });
  });
}
