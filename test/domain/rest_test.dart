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

  group('RestClock', () {
    final start = DateTime(2026, 10, 20, 18);
    final clock = RestClock(
      workoutId: 'w',
      startedAt: start,
      targetSeconds: 120,
      betweenExercises: false,
    );

    test('counts down against the wall clock', () {
      expect(clock.endsAt, start.add(const Duration(minutes: 2)));
      expect(clock.remainingAt(start.add(const Duration(seconds: 30))), 90);
      expect(clock.runningAt(start.add(const Duration(seconds: 119))), isTrue);
      expect(clock.runningAt(start.add(const Duration(seconds: 120))), isFalse);
    });

    test('a new target moves the end and keeps the start', () {
      final longer = clock.withTarget(180);
      expect(longer.startedAt, start);
      expect(longer.workoutId, 'w');
      expect(longer.remainingAt(start.add(const Duration(seconds: 150))), 30);
    });
  });

  group('restKindAfter', () {
    RestSet open(String id) => (id: id, done: false, completedAtMs: null);
    RestSet done(String id, int at) => (id: id, done: true, completedAtMs: at);

    test('another open set of the movement is the exercise rest', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [done('a1', 1), open('a2')]),
        (skipped: false, sets: [open('b1')]),
      ];
      expect(restKindAfter(slots, 'a1'), RestKind.sameExercise);
    });

    test('the last set of a movement is the walk to the next one', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [done('a1', 1), done('a2', 2)]),
        (skipped: false, sets: [open('b1')]),
      ];
      expect(restKindAfter(slots, 'a2'), RestKind.betweenExercises);
    });

    test('the set itself counts as done while its write is in flight', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [open('a1')]),
      ];
      expect(restKindAfter(slots, 'a1'), isNull);
    });

    test('a skipped exercise leaves nothing to rest for', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [done('a1', 1)]),
        (skipped: true, sets: [open('b1')]),
      ];
      expect(restKindAfter(slots, 'a1'), isNull);
    });
  });

  group('lastRestStarted', () {
    final now = DateTime(2026, 10, 20, 18, 30);
    int ago(int seconds) =>
        now.subtract(Duration(seconds: seconds)).millisecondsSinceEpoch;
    RestSet open(String id) => (id: id, done: false, completedAtMs: null);
    RestSet done(String id, int at) => (id: id, done: true, completedAtMs: at);

    test('is read off the newest completed set, wherever it sits', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [done('a1', ago(300)), open('a2')]),
        (skipped: false, sets: [done('b1', ago(40)), open('b2')]),
      ];
      final rest = lastRestStarted(slots, now)!;
      expect(rest.setId, 'b1');
      expect(rest.slot, 1);
      expect(rest.startedAt.millisecondsSinceEpoch, ago(40));
      expect(rest.kind, RestKind.sameExercise);
    });

    test('says when the newest set closed its movement', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [done('a1', ago(90))]),
        (skipped: false, sets: [open('b1')]),
      ];
      expect(lastRestStarted(slots, now)!.kind, RestKind.betweenExercises);
    });

    test('is nothing before the first set is completed', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [open('a1')]),
      ];
      expect(lastRestStarted(slots, now), isNull);
    });

    test('is nothing once every set is done', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [done('a1', ago(30))]),
      ];
      expect(lastRestStarted(slots, now), isNull);
    });

    test('ignores a stamp left on a set that is no longer done', () {
      final slots = <RestSlot>[
        (
          skipped: false,
          sets: [
            done('a1', ago(200)),
            (id: 'a2', done: false, completedAtMs: ago(10)),
            open('a3'),
          ],
        ),
      ];
      expect(lastRestStarted(slots, now)!.setId, 'a1');
    });

    test('is nothing for a set completed longer ago than a rest can be', () {
      final slots = <RestSlot>[
        (
          skipped: false,
          sets: [done('a1', ago(kMaxRestTakenSeconds + 1)), open('a2')],
        ),
      ];
      expect(lastRestStarted(slots, now), isNull);
    });

    test('is nothing for a stamp from the future', () {
      final slots = <RestSlot>[
        (skipped: false, sets: [done('a1', ago(-60)), open('a2')]),
      ];
      expect(lastRestStarted(slots, now), isNull);
    });
  });
}
