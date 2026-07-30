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

    test('a stuck finger cannot write a six-digit weight', () {
      expect(applyKey('12345', '6', field: SetField.weight), '12345');
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
}
