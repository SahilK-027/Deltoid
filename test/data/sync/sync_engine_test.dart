import 'dart:async';

import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/data/sync/pull.dart';
import 'package:deltoid/data/sync/push.dart';
import 'package:deltoid/data/sync/sync_backend.dart';
import 'package:deltoid/data/sync/sync_engine.dart';
import 'package:deltoid/core/failure.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

/// When a push runs, and what happens when one fails.
///
/// Real timers at small durations rather than a fake clock: the engine's whole
/// job is timers, and a test that replaces them tests something else. Every
/// interval here is milliseconds, so the suite pays nothing for it.
void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late _CountingPush push;
  late _CountingPull pull;
  late StreamController<bool> signedIn;
  late StreamController<void> network;
  SyncEngine? engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeBackend();
    push = _CountingPush(db, backend);
    pull = _CountingPull(db, backend);
    signedIn = StreamController<bool>.broadcast();
    network = StreamController<void>.broadcast();
  });

  tearDown(() async {
    await engine?.dispose();
    await signedIn.close();
    await network.close();
    await db.close();
  });

  SyncEngine start({
    Duration debounce = const Duration(milliseconds: 20),
    Duration minBackoff = const Duration(milliseconds: 20),
  }) {
    final started = SyncEngine(
      db: db,
      backend: backend,
      push: push,
      pull: pull,
      debounce: debounce,
      backstop: const Duration(milliseconds: 200),
      minBackoff: minBackoff,
      maxBackoff: const Duration(milliseconds: 80),
    )..start(signedIn: signedIn.stream, networkRegained: network.stream);
    return engine = started;
  }

  /// Long enough for a debounce and the drain behind it.
  Future<void> settle([int ms = 120]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// Waits for something the engine does on a timer, rather than sleeping for
  /// however long it ought to take.
  ///
  /// The intervals here are milliseconds so the suite pays nothing for real
  /// timers, and that makes a fixed sleep a race on a loaded machine: this file
  /// runs beside every other test file, and a 60ms sleep is not 60ms of CPU.
  /// Polling waits exactly as long as it has to and fails with the condition
  /// rather than with a count that was nearly right.
  Future<void> waitUntil(
    FutureOr<bool> Function() done, {
    Duration timeout = const Duration(seconds: 5),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!await done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail(reason ?? 'the engine never got there');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('a Local install pushes nothing, however much it writes', () async {
    start();
    signedIn.add(false);
    await ensureStarterCatalog(db);
    await settle();

    expect(push.drains, 0);
    expect(pull.pulls, 0);
    expect(backend.calls, isEmpty);
  });

  test('signing in is itself a trigger', () async {
    await ensureStarterCatalog(db);
    start();

    signedIn.add(true);
    await waitUntil(() => backend.table('exercises').isNotEmpty,
        reason: 'signing in never triggered a push');
  });

  test('every drain pulls before it pushes', () async {
    await ensureStarterCatalog(db);
    start();

    signedIn.add(true);
    await waitUntil(() => push.drains > 0);

    // A conflict has to be resolved before it is propagated — SYNC.md § 7. The
    // other order sends a version that has not met the account's yet, and the
    // two phones take turns overwriting each other.
    expect(pull.pulls, greaterThan(0));
    expect(backend.reads.first, lessThan(backend.writes.first),
        reason: 'the first request of a drain must be a read');
  });

  test('a burst of writes is one push', () async {
    start(debounce: const Duration(milliseconds: 60));
    signedIn.add(true);
    await settle(10);

    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(
      db,
      regimeTemplates.firstWhere((t) => t.key == 'ppl6'),
    );
    await settle(200);

    expect(
      push.drains,
      lessThanOrEqualTo(2),
      reason: 'the debounce coalesces a burst; the second drain is the one the '
          'push\'s own dirty-clearing writes provoke, and it sends nothing',
    );
    expect(await _owed(db), 0);
  });

  test('a resume pushes at once, without waiting for the debounce', () async {
    await ensureStarterCatalog(db);
    start(debounce: const Duration(seconds: 30));
    signedIn.add(true);
    await settle(10);
    expect(push.drains, 0);

    engine!.resumed();
    await waitUntil(() => push.drains > 0,
        reason: 'a resume must not wait out a thirty-second debounce');
    await waitUntil(() async => await _owed(db) == 0,
        reason: 'and the drain behind it must actually finish');
  });

  test('a failed push is backed off, then retried on its own', () async {
    await ensureStarterCatalog(db);
    backend.failEverything =
        const SyncTransportFailure('no signal', transient: true);

    start();
    signedIn.add(true);
    await waitUntil(() => pull.pulls > 0);
    expect(await _owed(db), greaterThan(0), reason: 'rows stay dirty');

    // The retry timer is the only thing left to fire: nothing writes, nothing
    // resumes, and the backstop is longer than this wait.
    final tries = pull.pulls;
    backend.failEverything = null;
    await waitUntil(() => pull.pulls > tries,
        reason: 'the backoff never retried on its own');
    await waitUntil(() async => await _owed(db) == 0,
        reason: 'and the retry must land the rows it backed off over');
  });

  test('connectivity regained pushes without waiting out the backoff',
      () async {
    await ensureStarterCatalog(db);
    backend.failEverything =
        const SyncTransportFailure('no signal', transient: true);

    start(minBackoff: const Duration(seconds: 30));
    signedIn.add(true);
    await waitUntil(() => pull.pulls > 0);
    final tries = pull.pulls;

    backend.failEverything = null;
    network.add(null);
    await waitUntil(() => pull.pulls > tries,
        reason: 'a thirty-second backoff must not outlast the signal coming '
            'back');
    await waitUntil(() async => await _owed(db) == 0);
  });

  test('a rejection is reported; no signal is not', () async {
    await ensureStarterCatalog(db);
    final reported = <String>[];
    // `reportFailure` is the app's one error channel — SYNC.md § 13 gives sync
    // no second one.
    final sub = _listenToFailures(reported);

    backend.failEverything =
        const SyncTransportFailure('no signal', transient: true);
    start(minBackoff: const Duration(seconds: 30));
    signedIn.add(true);
    await waitUntil(() => pull.pulls > 0);
    expect(reported, isEmpty, reason: 'a phone in a basement is not an error');

    backend.failEverything =
        const SyncTransportFailure('row rejected', transient: false);
    engine!.resumed();
    await waitUntil(() => reported.isNotEmpty,
        reason: 'a rejection is the one failure worth a sentence');

    await sub.cancel();
  });
}

Future<int> _owed(AppDatabase db) => db
    .customSelect('SELECT COUNT(*) AS n FROM exercises WHERE dirty = 1')
    .map((row) => row.read<int>('n'))
    .getSingle();

/// Counts drains, so *how often* is assertable rather than only *whether*.
class _CountingPush extends PushService {
  _CountingPush(super.db, super.backend);

  int drains = 0;

  @override
  Future<PushReport> drain() {
    drains++;
    return super.drain();
  }
}

/// The same for the pull, which is what a failing backend fails first.
///
/// The engine pulls before it pushes, so a test about backoff has to count the
/// attempt rather than the push — with the account unreachable, the push is
/// never reached at all.
class _CountingPull extends PullService {
  _CountingPull(super.db, super.backend);

  int pulls = 0;

  @override
  Future<PullReport> pull() {
    pulls++;
    return super.pull();
  }
}

StreamSubscription<void> _listenToFailures(List<String> into) {
  // The app's own channel, listened to rather than mocked: a report that
  // stopped reaching it would not fail a test that watched the engine instead.
  return failures.listen((failure) => into.add(failure.what));
}
