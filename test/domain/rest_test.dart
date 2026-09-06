import 'package:deltoid/domain/rest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clampRest', () {
    test('holds a duration inside what a person may dial', () {
      expect(clampRest(120), 120);
      expect(clampRest(0), kMinRestSeconds);
      expect(clampRest(-90), kMinRestSeconds);
      expect(clampRest(4000), kMaxRestSeconds);
    });

    test('the bounds are the ones the ± controls stop at', () {
      expect(clampRest(kMinRestSeconds), kMinRestSeconds);
      expect(clampRest(kMaxRestSeconds), kMaxRestSeconds);
    });
  });

  group('parseRestSeconds', () {
    test('reads a stored number', () {
      expect(parseRestSeconds('180'), 180);
      expect(parseRestSeconds(' 90 '), 90);
    });

    test('falls back rather than throwing on anything else', () {
      // `app_settings` is a text table and a restore can put any string in it.
      // A rest timer is not the place to throw.
      expect(parseRestSeconds(null), kDefaultRestSeconds);
      expect(parseRestSeconds(''), kDefaultRestSeconds);
      expect(parseRestSeconds('two minutes'), kDefaultRestSeconds);
      expect(parseRestSeconds('12.5'), kDefaultRestSeconds);
      expect(parseRestSeconds(null, fallback: 90), 90);
    });

    test('a value from outside the range still opens a usable timer', () {
      // The column accepts 1–3600 because a merge has to be able to carry
      // anything in. What is dialable is narrower, and the reader clamps
      // instead of refusing.
      expect(parseRestSeconds('3600'), kMaxRestSeconds);
      expect(parseRestSeconds('1'), kMinRestSeconds);
    });
  });

  group('parseRestSound', () {
    test('the tone is on unless it has been turned off', () {
      expect(parseRestSound(null), isTrue);
      expect(parseRestSound('on'), isTrue);
      expect(parseRestSound('anything else'), isTrue);
      expect(parseRestSound('off'), isFalse);
      expect(parseRestSound(' off '), isFalse);
    });
  });

  group('formatRestClock', () {
    test('reads as a clock', () {
      expect(formatRestClock(120), '2:00');
      expect(formatRestClock(45), '0:45');
      expect(formatRestClock(90), '1:30');
      expect(formatRestClock(900), '15:00');
    });

    test('never draws a negative rest', () {
      // The bar says "Rest finished" past zero and the lock screen is
      // replaced at the crossing, so nothing should ever reach here with a
      // negative — and if something does, `-1:-5` is not what it prints.
      expect(formatRestClock(0), '0:00');
      expect(formatRestClock(-30), '0:00');
    });
  });
}
