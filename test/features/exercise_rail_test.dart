import 'package:flutter_test/flutter_test.dart';

import 'package:deltoid/features/log/widgets/exercise_rail.dart';

void main() {
  group('rail monograms', () {
    test('two words give one letter each', () {
      expect(monogramFor('Incline DB Press'), 'ID');
      expect(monogramFor('Lateral Raise'), 'LR');
    });

    test('one word gives its first two letters', () {
      expect(monogramFor('Squat'), 'SQ');
      expect(monogramFor('Pull-up'), 'PU');
    });

    test('a parenthesised qualifier is not a word', () {
      // `Skullcrusher (EZ)` took its second letter from the bracket and came
      // out as `S(` on the rail.
      expect(monogramFor('Skullcrusher (EZ)'), 'SK');
      expect(monogramFor('Chest Fly (Machine)'), 'CF');
    });

    test('a leading measurement is skipped', () {
      expect(monogramFor('45° Cable Rear Delt'), 'CR');
    });

    test('a nameless exercise still renders something', () {
      expect(monogramFor(''), '?');
      expect(monogramFor('(machine)'), '?');
    });
  });
}
