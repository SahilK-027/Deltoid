import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/prefill.dart';
import 'package:flutter_test/flutter_test.dart';

PastPerformance perf(
  String sessionId,
  String sessionName,
  int dayKey,
  List<PastSet> sets, {
  bool isDeload = false,
}) {
  return PastPerformance(
    workoutId: 'w-$sessionName-$dayKey',
    sessionId: sessionId,
    sessionName: sessionName,
    dayKey: dayKey,
    isDeload: isDeload,
    sets: sets,
  );
}

PastSet working(double? w, int reps, {double? added}) =>
    PastSet(type: SetType.working, weight: w, reps: reps, addedWeight: added);

void main() {
  group('resolvePrefill', () {
    test('prefers the same session even when another session is more recent',
        () {
      // The whole reason this app exists: incline press is heavy in Push 1 and
      // lighter in Push 2, and Push 2 being more recent must not leak into
      // Push 1's suggestion.
      final result = resolvePrefill(
        candidates: [
          perf('push2', 'Push 2', 20260720, [working(20, 12)]),
          perf('push1', 'Push 1', 20260715, [working(22.5, 12)]),
        ],
        sessionId: 'push1',
      );

      expect(result.source, PrefillSource.sameSession);
      expect(result.sets.single.weight, 22.5);
      expect(result.reference!.sessionName, 'Push 1');
    });

    test('falls back to another session and flags where it came from', () {
      final result = resolvePrefill(
        candidates: [
          perf('push2', 'Push 2', 20260720, [working(20, 12)]),
        ],
        sessionId: 'push1',
      );

      expect(result.source, PrefillSource.otherSession);
      expect(result.reference!.sessionName, 'Push 2');
      expect(result.sets.single.weight, 20);
    });

    test('skips deload performances of the same session when a normal one exists',
        () {
      final result = resolvePrefill(
        candidates: [
          perf('push1', 'Push 1', 20260722, [working(18, 12)], isDeload: true),
          perf('push1', 'Push 1', 20260715, [working(22.5, 12)]),
        ],
        sessionId: 'push1',
      );

      expect(result.source, PrefillSource.sameSession);
      expect(result.sets.single.weight, 22.5);
    });

    test('uses a same-session deload before reaching to another session', () {
      final result = resolvePrefill(
        candidates: [
          perf('push2', 'Push 2', 20260724, [working(20, 12)]),
          perf('push1', 'Push 1', 20260722, [working(18, 12)], isDeload: true),
        ],
        sessionId: 'push1',
      );

      expect(result.source, PrefillSource.sameSessionDeload);
      expect(result.sets.single.weight, 18);
    });

    test('returns nothing for an exercise with no history', () {
      final result = resolvePrefill(candidates: const [], sessionId: 'push1');
      expect(result.source, PrefillSource.none);
      expect(result.hasSuggestion, isFalse);
    });

    test('ignores candidates that recorded no sets', () {
      final result = resolvePrefill(
        candidates: [
          perf('push1', 'Push 1', 20260720, const []),
          perf('push1', 'Push 1', 20260713, [working(22.5, 10)]),
        ],
        sessionId: 'push1',
      );

      expect(result.sets.single.weight, 22.5);
      expect(result.reference!.dayKey, 20260713);
    });

    test('applies the deload transform when the target workout is a deload', () {
      final result = resolvePrefill(
        candidates: [
          perf('push1', 'Push 1', 20260715, [
            working(22.5, 12),
            working(22.5, 8),
            working(22.5, 8),
          ]),
        ],
        sessionId: 'push1',
        targetIsDeload: true,
        deloadSetDelta: -1,
        deloadWeightPct: 80,
      );

      expect(result.deloadApplied, isTrue);
      expect(result.sets.length, 2);
      expect(result.sets.first.weight, 18); // 22.5 * 0.8
    });
  });

  group('applyDeload', () {
    test('keeps warmups, trims working sets, scales the load', () {
      final out = applyDeload(
        [
          const PastSet(type: SetType.warmup, weight: 40, reps: 8),
          working(100, 6),
          working(100, 5),
          working(100, 5),
        ],
        setDelta: -1,
        weightPct: 80,
      );

      expect(out.length, 3); // 1 warmup + 2 working
      expect(out.first.type, SetType.warmup);
      expect(out.first.weight, 40); // warmups untouched
      expect(out.where((s) => s.type == SetType.working).length, 2);
      expect(out.last.weight, 80);
    });

    test('drops rest-pause and drop-set extensions entirely', () {
      final out = applyDeload(
        [
          working(60, 9),
          const PastSet(type: SetType.restPause, weight: 60, reps: 3),
          working(60, 8),
        ],
        setDelta: -1,
        weightPct: 80,
      );

      expect(out.any((s) => s.type.isContinuation), isFalse);
      expect(out.length, 1);
    });

    test('never trims below a single working set', () {
      final out = applyDeload(
        [working(20, 10)],
        setDelta: -3,
        weightPct: 80,
      );

      expect(out.length, 1);
      expect(out.single.weight, 16);
    });

    test('scales added weight on bodyweight-plus lifts, not the bodyweight', () {
      final out = applyDeload(
        [working(null, 4, added: 10)],
        setDelta: -1,
        weightPct: 80,
      );

      expect(out.single.weight, isNull);
      expect(out.single.addedWeight, 8);
    });

    test('rounds scaled loads to a half kilo', () {
      final out = applyDeload(
        [working(93, 10)],
        setDelta: 0,
        weightPct: 80,
      );

      expect(out.single.weight, 74.5); // 74.4 → 74.5
    });
  });
}
