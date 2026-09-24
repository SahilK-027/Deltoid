import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/failure.dart';
import '../db/database.dart';
import '../db/table_spec.dart';
import 'catalog_dedup.dart';
import 'pull.dart';
import 'push.dart';
import 'sync_backend.dart';

/// When a push runs, and what happens when one fails.
///
/// [SYNC.md § 6](SYNC.md#6-push): debounced after a write settles, on app
/// resume, on connectivity regained, and on a long idle timer as a backstop.
/// Never on the frame of a keystroke: every trigger here passes through a
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
/// Why the last attempt did not land, for the one screen that says so.
///
/// Not an error channel. Everything reportable already passes through
/// `core/failure.dart` and says itself once ([SYNC.md § 13](SYNC.md#13-when-it-fails));
/// this is the standing answer to *why is this still pending*, which is a
/// different question with a different lifetime — a toast is gone in four
/// seconds and a phone can be offline for a week.
enum SyncTrouble {
  /// No signal, a timeout, a token that could not be refreshed. The ordinary
  /// state of a phone in a basement, and not an error.
  offline,

  /// The server was reached and refused the request — a policy, a column, a row
  /// it will not take. Retrying changes nothing until something else does.
  refused,
}

class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required SyncBackend backend,
    this.debounce = const Duration(seconds: 4),
    this.backstop = const Duration(minutes: 20),
    this.minBackoff = const Duration(seconds: 30),
    this.maxBackoff = const Duration(minutes: 30),
    this.reconnectRetry = const Duration(seconds: 5),
    PushService? push,
    PullService? pull,
  })  : _db = db,
        _push = push ?? PushService(db, backend),
        _pull = pull ?? PullService(db, backend);

  final AppDatabase _db;
  final PushService _push;
  final PullService _pull;

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

  /// How soon to try again when an attempt fails just after the network came
  /// back. Android reports an interface before it can resolve a name, so the
  /// first push after reconnecting often fails, and the ordinary backoff would
  /// then leave the header yellow for half a minute over a phone that has
  /// signal. The next few attempts after a reconnection wait this long instead.
  final Duration reconnectRetry;

  /// How many failures after a reconnection still retry at [reconnectRetry].
  int _quickRetries = 0;

  /// Whether there is an account to push to. Nothing runs while this is false:
  /// a `Local` install fills `dirty` and owes it to nobody.
  bool _signedIn = false;

  StreamSubscription<void>? _writes;
  StreamSubscription<void>? _network;
  StreamSubscription<bool>? _account;
  Timer? _debounce;
  Timer? _backstop;
  Timer? _retry;

  /// Why the last drain did not land, or null when the last one did.
  ///
  /// Seeded onto the stream for a screen that starts watching after the fact:
  /// the failure happened whether or not anyone was listening at the time.
  SyncTrouble? get trouble => _trouble;
  SyncTrouble? _trouble;

  Stream<SyncTrouble?> get troubles => _troubles.stream;
  final _troubles = StreamController<SyncTrouble?>.broadcast();

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
    }, onError: (Object _) {
      // An account stream that fails has not signed anyone in or out. Left
      // unhandled, the error escapes to the zone handler in `main` and is
      // announced as a lost change — over a log that lost nothing.
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
      _quickRetries = 3;
      // *No connection* was the reason, and it has just gone. Holding on to it
      // until a push lands kept the header yellow over a phone with signal;
      // a push that fails again says so again. A refusal is not about the
      // network and stays.
      if (_trouble == SyncTrouble.offline) _setTrouble(null);
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
        // Pull always precedes push. A conflict is resolved before it is
        // propagated ([SYNC.md § 7](SYNC.md#7-pull)): a local row that wins one
        // stays dirty, and the push immediately behind this is what tells the
        // account about it. The other order sends a version that has not met
        // the account's yet, and the two phones take turns overwriting each
        // other.
        await _pull.pull();
        if (_disposed) return;
        // Between the two, so a duplicate catalog is folded before the rows
        // that repoint it are sent. Two phones reach the same answer over the
        // same union, so this converges rather than ping-ponging
        // ([SYNC.md § 10](SYNC.md#10-adoption)).
        await dedupeCatalog(_db);
        if (_disposed) return;
        await _push.drain();
        if (_disposed) return;
      } while (_again);
      _failures = 0;
      _quickRetries = 0;
      _retry?.cancel();
      _setTrouble(null);
    } on Object catch (error, stack) {
      _onFailure(error, stack);
    } finally {
      _running = false;
    }
  }

  /// Backed off, said once, and remembered.
  ///
  /// [SYNC.md § 13](SYNC.md#13-when-it-fails): no network means the rows stay
  /// dirty and the user sees nothing, because a phone in a basement is not a
  /// broken phone — it changes [trouble] and announces nothing. A rejection is
  /// different in kind and is the one worth a sentence, which is why
  /// [SyncTransportFailure] carries [transient] at all.
  void _onFailure(Object error, StackTrace stack) {
    _failures++;
    final permanent = error is SyncTransportFailure && !error.transient;
    _setTrouble(permanent ? SyncTrouble.refused : SyncTrouble.offline);
    // Once per run of failures rather than once per retry. § 13's column
    // specifies that the
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
    if (!permanent && _quickRetries > 0) {
      _quickRetries--;
      wait = reconnectRetry;
    }
    _retry?.cancel();
    _retry = Timer(wait > maxBackoff ? maxBackoff : wait, () {
      unawaited(_drain());
    });
  }

  void _setTrouble(SyncTrouble? trouble) {
    if (_trouble == trouble) return;
    _trouble = trouble;
    if (!_troubles.isClosed) _troubles.add(trouble);
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
    await _troubles.close();
  }
}
