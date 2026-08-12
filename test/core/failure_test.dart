import 'package:deltoid/core/failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel a failed write speaks through.
///
/// The hole this fills was the worst kind the app had: the log screen writes
/// without awaiting — it has to, the keypad cannot block on a disk — so a write
/// that threw dropped its error on the floor. The tick stayed on screen because
/// the tick came from the local buffer, and the number simply was not in the
/// database.
void main() {
  test('a failed future is announced rather than dropped', () async {
    final heard = <AppFailure>[];
    final sub = failures.listen(heard.add);
    addTearDown(sub.cancel);

    Future<void>.error(StateError('disk full'), StackTrace.current)
        .reportOnError('That set could not be saved.');

    // The stream is asynchronous, so give it the turn it needs.
    await Future<void>.delayed(Duration.zero);

    expect(heard, hasLength(1));
    expect(heard.single.what, 'That set could not be saved.');
    expect(heard.single.error, isA<StateError>());
  });

  test('a future that succeeds says nothing', () async {
    final heard = <AppFailure>[];
    final sub = failures.listen(heard.add);
    addTearDown(sub.cancel);

    Future<void>.value().reportOnError('never seen');
    await Future<void>.delayed(Duration.zero);

    expect(heard, isEmpty);
  });

  test('a non-void future is reported without a cast that throws', () async {
    // `catchError` has to return a value of the future's own type to recover
    // with, and `null as String` throws — inside the error handler, which would
    // turn a reported failure straight back into an unreported one.
    final heard = <AppFailure>[];
    final sub = failures.listen(heard.add);
    addTearDown(sub.cancel);

    Future<String>.error(StateError('nope'), StackTrace.current)
        .reportOnError('That name could not be saved.');
    await Future<void>.delayed(Duration.zero);

    expect(heard, hasLength(1));
    expect(heard.single.what, 'That name could not be saved.');
  });

  test('reporting never throws, whatever is listening', () {
    // A reporter that can fail is a second silent failure sitting on top of the
    // first, so this is called from inside error handlers.
    expect(
      () => reportFailure(
        StateError('x'),
        StackTrace.current,
        what: 'nobody is listening',
      ),
      returnsNormally,
    );
  });
}
