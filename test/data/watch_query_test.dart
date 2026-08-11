import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/watch.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// `watchQuery` is what every screen in the app reads through, and the two
/// things it has to get right are both about *timing*: a write that lands while
/// a read is in flight must still be seen, and a burst of writes must not cost
/// a read each.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> logWeight(int dayKey) => db.into(db.bodyweightLogs).insert(
        BodyweightLogsCompanion.insert(dayKey: dayKey, weightKg: 80),
      );

  test('a write that lands mid-read is still seen', () async {
    // A slow read, so the write below is guaranteed to arrive while it is
    // running. `tableUpdates` is a broadcast stream: the old `await for` loop
    // paused it for exactly this window and the event was dropped, leaving the
    // screen one write behind with nothing coming to correct it.
    final seen = <int>[];
    final sub = db.watchQuery([db.bodyweightLogs], () async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      return (await db.select(db.bodyweightLogs).get()).length;
    }).listen(seen.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await logWeight(20260810);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen.last, 1, reason: 'the row written during the read is missing');
  });

  test('a burst of writes costs one more pass, not one each', () async {
    var reads = 0;
    final seen = <int>[];
    final sub = db.watchQuery([db.bodyweightLogs], () async {
      reads++;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return (await db.select(db.bodyweightLogs).get()).length;
    }).listen(seen.add);
    addTearDown(sub.cancel);

    // Ten rows in one go — what a sync pull looks like from this side.
    for (var i = 0; i < 10; i++) {
      await logWeight(20260810 + i);
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(seen.last, 10, reason: 'the last state has to be the true one');
    expect(reads, lessThan(5), reason: 'a read per row is the thing to avoid');
  });

  test('a read that throws does not end the stream', () async {
    var fail = true;
    final errors = <Object>[];
    final seen = <int>[];
    final sub = db.watchQuery([db.bodyweightLogs], () async {
      if (fail) throw StateError('nope');
      return (await db.select(db.bodyweightLogs).get()).length;
    }).listen(seen.add, onError: errors.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(errors, hasLength(1));

    // The next write is still answered: a screen that failed one read is not a
    // screen that stops updating for the rest of the session.
    fail = false;
    await logWeight(20260810);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(seen, [1]);
  });
}
