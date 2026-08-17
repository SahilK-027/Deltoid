import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/failure.dart';
import '../db/database.dart';
import '../db/table_spec.dart';
import 'push.dart';
import 'sync_backend.dart';

/// When a push runs, and what happens when one fails.
///
/// [SYNC.md § 6](SYNC.md#6-push): debounced after a write settles, on app
/// resume, on connectivity regained, and on a long idle timer as a backstop.
/// **Never on the frame of a keystroke** — every trigger here goes through a
/// timer, and the drain itself only ever awaits, so nothing on this path can
/// stand between a thumb and a set.
///
/// One drain at a time. A trigger that arrives while one is running is answered
/// by one more pass afterwards rather than by a second drain overlapping the
/// first — the same shape `watchQuery` uses, and for the same reason: two
/// drains would read the same rows and push them twice.
///
/// It runs on the UI isolate and that is deliberate. Drift already does its
/// work on a background isolate and HTTP is not arithmetic, so there is nothing
/// here to move; `Isolate.run` would only capture `this`, and an `AppDatabase`
/// wrapping an FFI handle fails at the send
/// ([SYNC.md § 17](SYNC.md#17-the-architecture)).
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required SyncBackend backend,
    this.debounce = const Duration(seconds: 4),
    this.backstop = const Duration(minutes: 20),
    this.minBackoff = const Duration(seconds: 30),
    this.maxBackoff = const Duration(minutes: 30),
    PushService? push,
  })  : _db = db,
        _push = push ?? PushService(db, backend);

  final AppDatabase _db;
  final PushService _push;

  /// How long a write has to settle before it is pushed. Long enough that a set
  /// logged and immediately corrected is one push, short enough that putting
  /// the phone down after the last set gets the session out before the screen
  /// is off.
  final Duration debounce;

  /// The idle backstop, for the triggers that do not fire: a write whose push
  /// failed silently, a process that has been resident for hours.
  /// [SYNC.md § 16](SYNC.md#16-still-to-decide) leaves the real number to a
  /// phone and a real week; this is the placeholder it is chosen against.
  final Duration backstop;

  final Duration minBackoff;
  final Duration maxBackoff;

  /// Whether there is an account to push to. Nothing runs while this is false:
  /// a `Local` install fills `dirty` and owes it to nobody.
  bool _signedIn = false;

  StreamSubscription<void>? _writes;
  StreamSubscription<void>? _network;
  StreamSubscription<bool>? _account;
  Timer? _debounce;
  Timer? _backstop;
  Timer? _retry;

  bool _running = false;
  bool _again = false;
  int _failures = 0;
  var _disposed = false;

  /// Starts listening. [signedIn] is the account, [networkRegained] fires when
  /// the phone has an interface again — both injected rather than reached for,
  /// so a test drives them without a socket or a platform channel.
  void start({
    required Stream<bool> signedIn,
    Stream<void>? networkRegained,
  }) {
    _account = signedIn.listen((value) {
      final was = _signedIn;
      _signedIn = value;
      // Signing in is itself a trigger: everything logged before the account
      // existed is owed the moment there is somewhere to owe it to.
      if (value && !was) trigger();
      if (!value) _cancelTimers();
    });

    // Any write to a syncable table. `app_settings` is excluded on purpose —
    // it never syncs, and the push's own `last_push_at` stamp landing here
    // would make every drain schedule the next one.
    _writes = _db
        .tableUpdates(
          TableUpdateQuery.onAllTables(
            tableSpecs(_db).where((s) => s.syncs).map((s) => s.table),
          ),
        )
        .listen((_) => trigger());

    _network = networkRegained?.listen((_) {
      // Whatever the backoff was waiting for has probably just arrived.
      _failures = 0;
      _retry?.cancel();
      trigger();
    });

    _backstop = Timer.periodic(backstop, (_) => _drainSoon(Duration.zero));
  }

  /// Something happened that a push should follow. Debounced.
  void trigger() => _drainSoon(debounce);

  /// Called from the root's lifecycle observer when the app comes forward.
  ///
  /// Immediate rather than debounced: a resume is not a burst of writes, and
  /// the window in which the user is looking at the app is exactly when a
  /// failure is worth having behind us.
  void resumed() {
    _failures = 0;
    _retry?.cancel();
    _drainSoon(Duration.zero);
  }

  void _drainSoon(Duration delay) {
    if (_disposed || !_signedIn) return;
    _debounce?.cancel();
    if (delay == Duration.zero) {
      unawaited(_drain());
    } else {
      _debounce = Timer(delay, () => unawaited(_drain()));
    }
  }

  Future<void> _drain() async {
    if (_disposed || !_signedIn) return;
    if (_running) {
      // Let the pass in flight answer for this trigger too — but come back
      // once, because a row written after it read its last batch is owed and
      // nothing else will say so.
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _push.drain();
        if (_disposed) return;
      } while (_again);
      _failures = 0;
      _retry?.cancel();
    } on Object catch (error, stack) {
      _onFailure(error, stack);
    } finally {
      _running = false;
    }
  }

  /// Backed off, and — for now — silent.
  ///
  /// [SYNC.md § 13](SYNC.md#13-when-it-fails): no network means the rows stay
  /// dirty and the user sees nothing, because a phone in a basement is not a
  /// broken phone. A rejection is different in kind and is the one worth a
  /// sentence, which is why [SyncTransportFailure] carries [transient] at all;
  /// the sentence itself is phase 6's, where every row of that table reaches
  /// `core/failure.dart` with the wording decided in one place.
  void _onFailure(Object error, StackTrace stack) {
    _failures++;
    final permanent = error is SyncTransportFailure && !error.transient;
    // **Once per run of failures, not once per retry.** § 13's column says *the
    // failure channel says it once*, and a rejection that repeats every thirty
    // seconds for an hour would say it a hundred and twenty times, over
    // whatever screen the user is on. The streak resets on the next success.
    if (permanent && _failures == 1) {
      reportFailure(
        error,
        stack,
        what: "Your training couldn't be backed up just now.",
      );
    }

    var wait = minBackoff;
    for (var i = 1; i < _failures && wait < maxBackoff; i++) {
      wait *= 2;
    }
    _retry?.cancel();
    _retry = Timer(wait > maxBackoff ? maxBackoff : wait, () {
      unawaited(_drain());
    });
  }

  void _cancelTimers() {
    _debounce?.cancel();
    _retry?.cancel();
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelTimers();
    _backstop?.cancel();
    await _writes?.cancel();
    await _network?.cancel();
    await _account?.cancel();
  }
}
