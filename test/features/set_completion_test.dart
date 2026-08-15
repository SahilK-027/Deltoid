import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/features/log/set_completion.dart';
import 'package:deltoid/features/log/widgets/keypad.dart' show SetField;
import 'package:flutter_test/flutter_test.dart';

/// The rule that stops a ticked set being empty — see [missingBeforeDone].
///
/// It lived as a private method on the log screen and only one of the two tick
/// paths called it, so a set logged the normal way (type reps, press Next)
/// could be marked done with no load at all. These cases pin the rule itself;
/// the log screen now asks it from both paths.
void main() {
  group('a set is not done until it says what happened', () {
    test('a barbell set needs its weight', () {
      expect(
        missingBeforeDone(
          loadMode: LoadMode.total,
          weight: null,
          addedWeight: null,
          reps: 8,
        ),
        SetField.weight,
      );
    });

    test('a dumbbell set needs its per-side weight', () {
      expect(
        missingBeforeDone(
          loadMode: LoadMode.perSide,
          weight: null,
          addedWeight: null,
          reps: 8,
        ),
        SetField.weight,
      );
    });

    test('either kind needs its reps', () {
      expect(
        missingBeforeDone(
          loadMode: LoadMode.total,
          weight: 100,
          addedWeight: null,
          reps: null,
        ),
        SetField.reps,
      );
    });

    test('a complete set is missing nothing', () {
      expect(
        missingBeforeDone(
          loadMode: LoadMode.total,
          weight: 100,
          addedWeight: null,
          reps: 5,
        ),
        isNull,
      );
    });

    test('a pull-up has no weight to ask for', () {
      // LoadMode.bodyweight carries no load field at all, so demanding one
      // would make every bodyweight set in the app impossible to tick.
      expect(
        missingBeforeDone(
          loadMode: LoadMode.bodyweight,
          weight: null,
          addedWeight: null,
          reps: 10,
        ),
        isNull,
      );
    });

    test('a plank needs its seconds, which live in reps', () {
      expect(
        missingBeforeDone(
          loadMode: LoadMode.bodyweight,
          weight: null,
          addedWeight: null,
          reps: null,
        ),
        SetField.reps,
      );
    });

    group('a weighted pull-up', () {
      test('needs an answer about the belt', () {
        expect(
          missingBeforeDone(
            loadMode: LoadMode.bodyweightPlus,
            weight: null,
            addedWeight: null,
            reps: 6,
          ),
          SetField.added,
        );
      });

      test('and zero is one of the answers', () {
        // An unweighted set of a movement you sometimes load is a complete
        // fact, and a different one from a belt you forgot to record. Only one
        // of those should score as bodyweight alone.
        expect(
          missingBeforeDone(
            loadMode: LoadMode.bodyweightPlus,
            weight: null,
            addedWeight: 0,
            reps: 6,
          ),
          isNull,
        );
      });

      test('and last week answering zero answers for this week too', () {
        // Which is why the friction is once per movement, not once per set:
        // the ghost carries the zero forward and the tick adopts it.
        expect(
          missingBeforeDone(
            loadMode: LoadMode.bodyweightPlus,
            weight: null,
            addedWeight: null,
            reps: 6,
            ghostAddedWeight: 0,
          ),
          isNull,
        );
      });
    });

    group('last time answers for a blank cell', () {
      test('because the tick adopts the ghost before it writes', () {
        expect(
          missingBeforeDone(
            loadMode: LoadMode.total,
            weight: null,
            addedWeight: null,
            reps: null,
            ghostWeight: 100,
            ghostReps: 5,
          ),
          isNull,
        );
      });

      test('but a ghost for the wrong field does not', () {
        expect(
          missingBeforeDone(
            loadMode: LoadMode.total,
            weight: null,
            addedWeight: null,
            reps: 8,
            ghostAddedWeight: 20,
          ),
          SetField.weight,
        );
      });
    });
  });
}
