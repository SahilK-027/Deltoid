import 'dart:async';

import 'package:flutter/foundation.dart';

/// Something went wrong that the person using the app is entitled to know
/// about.
///
/// [what] is written for them, not for a log: "That set could not be saved",
/// not `SqliteException(275)`. The cause travels with it for the console.
@immutable
class AppFailure {
  const AppFailure({
    required this.what,
    required this.error,
    required this.stack,
  });

  /// One short sentence, already in the app's voice.
  final String what;

  final Object error;
  final StackTrace stack;

  @override
  String toString() => 'AppFailure($what): $error';
}

/// Where every failure the user should hear about is announced.
///
/// **The app had no such channel, and the hole it left was the worst kind.**
/// The log screen writes without awaiting — it has to, the keypad cannot block
/// on a disk — so a write that threw dropped its error on the floor. The tick
/// stayed on screen because the tick came from the local buffer, the rest timer
/// started, the summary counted the set, and the number simply was not in the
/// database. You would find out weeks later, looking at a chart with a hole in
/// it, with nothing to connect the hole to the evening it happened.
///
/// A broadcast stream rather than a provider, because the producers are not all
/// in the provider graph: `watchQuery` lives in `data/`, the zone handler
/// installed in `main` is not in the tree at all, and both have to be able to
/// speak without knowing who is listening.
///
/// Deliberately **not** an error-reporting service. Nothing leaves the phone —
/// the app makes no network calls and this does not change that. It exists so
/// the screen can say "that did not save", which is the whole of the
/// requirement.
final _failures = StreamController<AppFailure>.broadcast();

Stream<AppFailure> get failures => _failures.stream;

/// Announces a failure, and prints it where a developer will see it.
///
/// Safe to call from anywhere, including from inside an error handler: it never
/// throws, because a reporter that can fail is a second silent failure sitting
/// on top of the first.
void reportFailure(Object error, StackTrace stack, {required String what}) {
  // The console still gets everything, unchanged. `debugPrint` rather than
  // `print` so a burst during a bad write is rate-limited instead of dropping
  // lines from the middle of the trace.
  if (kDebugMode) {
    debugPrint('$what\n$error\n$stack');
  }
  if (!_failures.isClosed) {
    _failures.add(AppFailure(what: what, error: error, stack: stack));
  }
}

/// Fire-and-forget, but never fail-and-forget.
///
/// The log screen's writes cannot be awaited — `_flushWrite` runs from a
/// `Timer` and from `dispose`, neither of which can wait on a disk — so the
/// choice is not "await or not", it is "hear about a failure or not". This is
/// how a write says it is not being watched *and* that it still has to report.
extension ReportFailure<T> on Future<T> {
  void reportOnError(String what) {
    // `then` with an `onError`, not `catchError`. `catchError` has to return a
    // value of the future's own type to recover with, and there is no such
    // value to invent for a `Future<String>` — the honest one is null, and
    // `null as T` throws for anything non-nullable, which would turn a reported
    // failure back into an unreported one. Mapping to `Future<void>` first
    // means the handler has nothing to produce.
    //
    // `unawaited` on the result, because this is the one place in the app where
    // not awaiting is the point, and it should say so rather than look like an
    // omission.
    unawaited(then<void>((_) {}, onError: (Object error, StackTrace stack) {
      reportFailure(error, stack, what: what);
    }));
  }
}
