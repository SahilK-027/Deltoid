import 'package:deltoid/domain/session_diff.dart';
import 'package:flutter_test/flutter_test.dart';

ExerciseRef ref(String id) => (exerciseId: id, name: id);

List<ExerciseRef> refs(List<String> ids) => [for (final id in ids) ref(id)];

void main() {
  group('diffSession', () {
    test('a session trained as written has nothing to offer', () {
      expect(
        diffSession(
          template: refs(['bench', 'ohp', 'dips']),
          logged: refs(['bench', 'ohp', 'dips']),
        ),
        isEmpty,
      );
    });

    test('names what was added', () {
      final changes = diffSession(
        template: refs(['bench', 'ohp']),
        logged: refs(['bench', 'ohp', 'legraise']),
      );
      expect(changes, hasLength(1));
      expect(changes.single.kind, SessionChangeKind.added);
      expect(changes.single.exerciseIds, ['legraise']);
    });

    test('adding at the end is not also a reorder', () {
      // Appending changes the list, but it is one decision and must be asked
      // about once.
      final changes = diffSession(
        template: refs(['bench', 'ohp']),
        logged: refs(['bench', 'ohp', 'legraise']),
      );
      expect(
        changes.where((c) => c.kind == SessionChangeKind.reordered),
        isEmpty,
      );
    });

    test('names what was dropped', () {
      final changes = diffSession(
        template: refs(['bench', 'ohp', 'dips']),
        logged: refs(['bench', 'ohp']),
      );
      expect(changes.single.kind, SessionChangeKind.removed);
      expect(changes.single.exerciseIds, ['dips']);
    });

    test('reordering the same movements is one change, in today order', () {
      final changes = diffSession(
        template: refs(['bench', 'ohp', 'dips']),
        logged: refs(['dips', 'bench', 'ohp']),
      );
      expect(changes.single.kind, SessionChangeKind.reordered);
      expect(changes.single.exerciseIds, ['dips', 'bench', 'ohp']);
    });

    test('an add and a reorder are two separate offers', () {
      // The whole point: keep the leg raises, throw the shuffle away.
      final changes = diffSession(
        template: refs(['bench', 'ohp', 'dips']),
        logged: refs(['dips', 'bench', 'ohp', 'legraise']),
      );
      expect(changes.map((c) => c.kind), [
        SessionChangeKind.added,
        SessionChangeKind.reordered,
      ]);
    });

    test('a swap reads as one out and one in', () {
      final changes = diffSession(
        template: refs(['bench', 'ohp']),
        logged: refs(['bench', 'inclinedb']),
      );
      expect(changes.map((c) => c.kind), [
        SessionChangeKind.added,
        SessionChangeKind.removed,
      ]);
    });

    test('a movement done twice in one day is offered once', () {
      // Bench at the start and a back-off set of it at the end is one
      // decision, and two adds would write two slots for one movement.
      final changes = diffSession(
        template: refs(['ohp']),
        logged: refs(['bench', 'ohp', 'bench']),
      );
      expect(
        changes.where((c) => c.kind == SessionChangeKind.added),
        hasLength(1),
      );
    });

    test('a workout logged with no template offers everything as an add', () {
      final changes = diffSession(template: const [], logged: refs(['bench']));
      expect(changes.single.kind, SessionChangeKind.added);
    });
  });

  group('diffSetCounts', () {
    SetTarget target(String id, int sets) =>
        (exerciseId: id, name: id, targetSets: sets);
    SetTally tally(String id, int done, {bool skipped = false}) =>
        (exerciseId: id, workingDone: done, skipped: skipped);

    test('fewer working sets than programmed are offered as a count', () {
      final changes = diffSetCounts(
        template: [target('deadlift', 3), target('row', 3)],
        logged: [tally('deadlift', 1), tally('row', 3)],
        isDeload: false,
      );
      expect(changes, hasLength(1));
      expect(changes.single.kind, SessionChangeKind.setCount);
      expect(changes.single.exerciseIds, ['deadlift']);
      expect(changes.single.setCount, 1);
      expect(changes.single.label, 'Did 1 of 3 working sets of deadlift');
    });

    test('the label counts against the programmed total', () {
      // A count is offered only for 1 <= done < programmed, so the smallest
      // total a label can name is two, and the unit is plural there.
      final changes = diffSetCounts(
        template: [target('row', 2), target('curl', 1)],
        logged: [tally('row', 1), tally('curl', 0)],
        isDeload: false,
      );
      expect(changes.single.label, 'Did 1 of 2 working sets of row');
    });

    test('more working sets than programmed are not offered', () {
      // They carry forward already: the next workout mirrors last time's
      // shape, and the template's count is only a floor.
      expect(
        diffSetCounts(
          template: [target('deadlift', 3)],
          logged: [tally('deadlift', 4)],
          isDeload: false,
        ),
        isEmpty,
      );
    });

    test('a deload asks for fewer sets and is never offered', () {
      expect(
        diffSetCounts(
          template: [target('deadlift', 3)],
          logged: [tally('deadlift', 2)],
          isDeload: true,
        ),
        isEmpty,
      );
    });

    test('a skip, or no working set at all, is not a count', () {
      expect(
        diffSetCounts(
          template: [target('deadlift', 3), target('row', 3)],
          logged: [tally('deadlift', 1, skipped: true), tally('row', 0)],
          isDeload: false,
        ),
        isEmpty,
      );
    });

    test('a movement the day runs twice is not offered', () {
      expect(
        diffSetCounts(
          template: [target('squat', 3), target('squat', 2)],
          logged: [tally('squat', 1), tally('squat', 1)],
          isDeload: false,
        ),
        isEmpty,
      );
    });

    test('a movement added today has no programmed count', () {
      expect(
        diffSetCounts(
          template: [target('deadlift', 3)],
          logged: [tally('deadlift', 3), tally('curl', 1)],
          isDeload: false,
        ),
        isEmpty,
      );
    });
  });
}
