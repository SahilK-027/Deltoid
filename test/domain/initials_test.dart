import 'package:deltoid/domain/initials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialsOf', () {
    test('two words take the first letter of each', () {
      expect(initialsOf(name: 'Ada Lovelace', email: 'a@x.com'), 'AL');
    });

    test('more than two words take the first and the last', () {
      expect(initialsOf(name: 'Ada King Lovelace'), 'AL');
    });

    test('one word gives one letter', () {
      expect(initialsOf(name: 'Ada', email: 'z@x.com'), 'A');
    });

    test('no name falls back to the email', () {
      expect(initialsOf(email: 'lifter@example.com'), 'L');
      expect(initialsOf(name: '   ', email: 'lifter@example.com'), 'L');
    });

    test('letters are upper-cased and spacing ignored', () {
      expect(initialsOf(name: '  ada   lovelace '), 'AL');
    });

    test('nothing at all gives nothing', () {
      expect(initialsOf(), '');
    });
  });
}
