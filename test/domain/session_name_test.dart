import 'package:deltoid/domain/session_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('day names', () {
    test('the custom session name is refused in any case and spacing', () {
      for (final name in [
        'Custom session',
        'custom session',
        '  CUSTOM SESSION ',
      ]) {
        expect(isReservedSessionName(name), isTrue, reason: name);
        expect(dayNameProblem(name, const {}), isNotNull, reason: name);
      }
    });

    test('a name already in the regime is refused, and a new one is not', () {
      const taken = {'push 1', 'pull 1'};
      expect(dayNameProblem(' Push 1', taken),
          'This regime already has a day called Push 1');
      expect(dayNameProblem('Leg 1', taken), isNull);
      expect(isReservedSessionName('Custom sessions'), isFalse);
    });
  });

  test('a custom session reads as a description inside a sentence', () {
    expect(sessionInSentence(null), 'this custom session');
    expect(sessionInSentence('Push 1'), 'Push 1');
  });
}
