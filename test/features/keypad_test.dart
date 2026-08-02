import 'package:deltoid/features/log/widgets/keypad.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyKey', () {
    test('digits append, and a leading zero is replaced', () {
      expect(applyKey('', '2', field: SetField.weight), '2');
      expect(applyKey('2', '5', field: SetField.weight), '25');
      expect(applyKey('0', '7', field: SetField.weight), '7');
    });

    test('backspace on an empty buffer is a no-op', () {
      expect(applyKey('', '⌫', field: SetField.weight), '');
      expect(applyKey('22.5', '⌫', field: SetField.weight), '22.');
    });

    test('the decimal point is refused for reps and never doubled', () {
      expect(applyKey('8', '.', field: SetField.reps), '8');
      expect(applyKey('22.5', '.', field: SetField.weight), '22.5');
      expect(applyKey('', '.', field: SetField.weight), '0.');
    });

    test('a load stops at 1000, and stops on the value not the digit count', () {
      expect(applyKey('100', '0', field: SetField.weight), '1000');
      // 10000 is over the ceiling, so the keystroke is dropped.
      expect(applyKey('1000', '0', field: SetField.weight), '1000');
      // The old rule counted characters and would have refused this for being
      // six long, though 999.5 is a perfectly ordinary number.
      expect(applyKey('999.', '5', field: SetField.weight), '999.5');
      // And it lets nothing over the line by way of a decimal.
      expect(applyKey('1000.', '5', field: SetField.weight), '1000.');
    });

    test('reps have their own, tighter ceiling', () {
      expect(applyKey('99', '9', field: SetField.reps), '999');
      expect(applyKey('999', '9', field: SetField.reps), '999');
    });

    test('stepping comes to rest on the ceiling rather than refusing', () {
      expect(applyKey('999', '+', field: SetField.weight), '1000');
      expect(applyKey('1000', '+', field: SetField.weight), '1000');
    });

    group('+ / − with a typed buffer', () {
      test('steps by a plate for weight and by one for reps', () {
        expect(applyKey('20', '+', field: SetField.weight), '22.5');
        expect(applyKey('22.5', '-', field: SetField.weight), '20');
        expect(applyKey('8', '+', field: SetField.reps), '9');
      });

      test('never goes below zero', () {
        expect(applyKey('1', '-', field: SetField.weight), '0');
      });
    });

    group('+ / − on an empty buffer', () {
      test('steps from last time when there is a hint', () {
        expect(
          applyKey('', '+', field: SetField.weight, hint: 22.5),
          '25',
        );
        expect(
          applyKey('', '-', field: SetField.weight, hint: 22.5),
          '20',
        );
        expect(applyKey('', '+', field: SetField.reps, hint: 8), '9');
      });

      test('falls back to the step itself when there is no hint', () {
        expect(applyKey('', '+', field: SetField.weight), '2.5');
      });

      test('a typed zero wins over the hint', () {
        // The buffer is what the user said; only silence means "use last time".
        expect(applyKey('0', '+', field: SetField.weight, hint: 22.5), '2.5');
      });

      test('the hint is ignored once anything is typed', () {
        expect(applyKey('30', '+', field: SetField.weight, hint: 22.5), '32.5');
      });
    });
  });

  group('a hold is typed as a clock', () {
    String key(String buffer, String k, {double? hint}) =>
        applyKey(buffer, k, field: SetField.reps, isTime: true, hint: hint);

    test('digits fill from the right, the way every timer is typed', () {
      expect(key('', '2'), '2');
      expect(formatDigits('2'), '0:02');
      expect(key('2', '5'), '25');
      expect(formatDigits('25'), '0:25');
      expect(key('25', '5'), '255');
      expect(formatDigits('255'), '2:55');
      expect(formatDigits('225'), '2:25');
    });

    test('there is no 75th second', () {
      // `0:75` is not a time, and carrying it silently into `1:15` would
      // change a number being watched as it is typed.
      expect(key('7', '5'), '7');
      expect(key('1', '9'), '19');
    });

    test('four digits is the width of the field', () {
      expect(key('9959', '9'), '9959');
      expect(secondsFromDigits('9959'), 99 * 60 + 59);
    });

    test('the step keys move by half a minute, in seconds', () {
      expect(key('45', '+'), '115');
      expect(formatDigits(key('45', '+')), '1:15');
      expect(formatDigits(key('115', '-')), '0:45');
      // Stepping down off the bottom clears the field rather than going
      // negative.
      expect(key('20', '-'), '');
    });

    test('an empty buffer steps from last time', () {
      expect(formatDigits(key('', '+', hint: 60)), '1:30');
    });

    test('the decimal key does nothing on a clock', () {
      expect(key('130', '.'), '130');
    });

    test('digits and seconds convert both ways', () {
      expect(secondsFromDigits('225'), 145);
      expect(digitsFromSeconds(145), '225');
      expect(digitsFromSeconds(45), '45');
      expect(digitsFromSeconds(0), '');
      expect(formatDigits(''), '');
    });
  });
}
