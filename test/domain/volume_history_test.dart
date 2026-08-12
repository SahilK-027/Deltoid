import 'package:deltoid/core/ids.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// The weekly fold, which is where every off-by-one about "which week was that"
/// lives. The rules about what counts as a set are `muscle_volume_test.dart`'s.
void main() {
  ({int dayKey, MuscleGroup muscle, int sets}) on(
    DateTime day,
    MuscleGroup muscle,
    int sets,
  ) =>
      (dayKey: dayKeyOf(day), muscle: muscle, sets: sets);

  VolumeHistory of(
    List<({int dayKey, MuscleGroup muscle, int sets})> daily, {
    required DateTime from,
    required DateTime to,
  }) =>
      computeVolumeHistory(daily: daily, from: from, to: to);

  group('weeks', () {
    test('a week starts on Monday, whichever day you ask about', () {
      // 2026-07-30 is a Thursday; its Monday is the 27th.
      expect(weekStartOf(DateTime(2026, 7, 30)), DateTime(2026, 7, 27));
      expect(weekStartOf(DateTime(2026, 7, 27)), DateTime(2026, 7, 27));
      // Sunday belongs to the week behind it, not the one ahead.
      expect(weekStartOf(DateTime(2026, 8, 2)), DateTime(2026, 7, 27));
      expect(weekStartOf(DateTime(2026, 8, 3)), DateTime(2026, 8, 3));
    });

    test('a Sunday session and the Monday after it are different weeks', () {
      final h = of(
        [
          on(DateTime(2026, 8, 2), MuscleGroup.chest, 4),
          on(DateTime(2026, 8, 3), MuscleGroup.chest, 6),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 9),
      );

      final chest = h.byRegion[MuscleRegion.chest]!;
      expect(chest.weeks.length, 2);
      expect(chest.weeks[0].sets, 4);
      expect(chest.weeks[1].sets, 6);
    });

    test('the span widens to whole weeks at both ends', () {
      // Thursday to Wednesday: two Mondays are covered, so two weeks.
      final h = of(
        const [],
        from: DateTime(2026, 7, 30),
        to: DateTime(2026, 8, 5),
      );
      expect(h.weekStarts, [DateTime(2026, 7, 27), DateTime(2026, 8, 3)]);
    });

    test('every week in the span is present, including the empty ones', () {
      final h = of(
        [on(DateTime(2026, 7, 27), MuscleGroup.back, 10)],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 16),
      );

      final back = h.byRegion[MuscleRegion.back]!;
      expect(back.weeks.map((w) => w.sets), [10, 0, 0]);
    });

    test('a week runs Monday to Sunday', () {
      final h = of(
        const [],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 7, 27),
      );
      expect(h.weekStarts.single, DateTime(2026, 7, 27));
      expect(h.byRegion[MuscleRegion.core]!.weeks.single.end,
          DateTime(2026, 8, 2));
    });
  });

  group('folding', () {
    test('muscles roll into their region and keep their own row', () {
      final h = of(
        [
          on(DateTime(2026, 7, 27), MuscleGroup.quads, 6),
          on(DateTime(2026, 7, 28), MuscleGroup.hamstrings, 2),
          on(DateTime(2026, 7, 29), MuscleGroup.calves, 1),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 2),
      );

      expect(h.byRegion[MuscleRegion.legs]!.weeks.single.sets, 9);
      expect(h.byMuscle[MuscleGroup.quads]!.weeks.single.sets, 6);
      expect(h.byMuscle[MuscleGroup.hamstrings]!.weeks.single.sets, 2);
      expect(h.byMuscle[MuscleGroup.glutes]!.weeks.single.sets, 0);
    });

    test('two muscles logged on the same day add up inside one week', () {
      final h = of(
        [
          on(DateTime(2026, 7, 27), MuscleGroup.biceps, 3),
          on(DateTime(2026, 7, 27), MuscleGroup.triceps, 4),
          on(DateTime(2026, 7, 30), MuscleGroup.forearms, 2),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 2),
      );
      expect(h.byRegion[MuscleRegion.arms]!.weeks.single.sets, 9);
    });

    test('all six regions are present even with nothing logged', () {
      final h = of(
        const [],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 2),
      );
      expect(h.byRegion.keys, MuscleRegion.values);
      expect(h.isEmpty, isTrue);
    });

    test('`other` is counted nowhere rather than borrowing a region', () {
      final h = of(
        [
          on(DateTime(2026, 7, 27), MuscleGroup.other, 8),
          on(DateTime(2026, 7, 27), MuscleGroup.chest, 3),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 2),
      );

      expect(h.byMuscle.containsKey(MuscleGroup.other), isFalse);
      final total =
          h.byRegion.values.fold(0, (s, r) => s + r.totalSets);
      expect(total, 3);
    });

    test('a day outside the span is dropped, not folded into the edge', () {
      final h = of(
        [
          on(DateTime(2026, 7, 26), MuscleGroup.chest, 99),
          on(DateTime(2026, 7, 28), MuscleGroup.chest, 5),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 2),
      );
      expect(h.byRegion[MuscleRegion.chest]!.weeks.single.sets, 5);
    });
  });

  group('figures', () {
    test('the average divides by every week, not by the ones you trained', () {
      // Six sets in one week of three. Dividing by the weeks that had
      // something in them would report 6.0 and call a neglected muscle fine.
      final h = of(
        [on(DateTime(2026, 7, 27), MuscleGroup.hamstrings, 6)],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 16),
      );

      final hams = h.byMuscle[MuscleGroup.hamstrings]!;
      expect(hams.weeks.length, 3);
      expect(hams.averagePerWeek, 2.0);
    });

    test('weeks trained is what the average cannot say', () {
      // Twelve sets over three weeks is `4.0 per week` whether it was four
      // every week or twelve in one. The rate is the same and the block is not.
      final steady = of(
        [
          on(DateTime(2026, 7, 27), MuscleGroup.chest, 4),
          on(DateTime(2026, 8, 3), MuscleGroup.chest, 4),
          on(DateTime(2026, 8, 10), MuscleGroup.chest, 4),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 16),
      ).byRegion[MuscleRegion.chest]!;

      final lumpy = of(
        [on(DateTime(2026, 7, 27), MuscleGroup.chest, 12)],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 16),
      ).byRegion[MuscleRegion.chest]!;

      expect(steady.averagePerWeek, lumpy.averagePerWeek);
      expect(steady.weeksTrained, 3);
      expect(lumpy.weeksTrained, 1);
    });

    test('the latest week is the one you are standing in', () {
      final h = of(
        [on(DateTime(2026, 8, 10), MuscleGroup.chest, 7)],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 16),
      );
      final chest = h.byRegion[MuscleRegion.chest]!;
      expect(chest.latest!.sets, 7);
      expect(chest.latest!.start, DateTime(2026, 8, 10));
    });

    test('peak is the tallest week, and it is what bars scale against', () {
      final h = of(
        [
          on(DateTime(2026, 7, 27), MuscleGroup.chest, 4),
          on(DateTime(2026, 8, 3), MuscleGroup.chest, 19),
          on(DateTime(2026, 8, 10), MuscleGroup.chest, 11),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 16),
      );
      expect(h.byRegion[MuscleRegion.chest]!.peakSets, 19);
    });

    test('an empty span reports zero rather than dividing by it', () {
      final h = of(
        const [],
        from: DateTime(2026, 8, 3),
        to: DateTime(2026, 8, 2),
      );
      expect(h.weekCount, 0);
      expect(h.averagePerWeek, 0);
      expect(h.isEmpty, isTrue);
    });

    test('the screen total counts every region across the span', () {
      final h = of(
        [
          on(DateTime(2026, 7, 27), MuscleGroup.chest, 10),
          on(DateTime(2026, 7, 27), MuscleGroup.back, 10),
          on(DateTime(2026, 8, 3), MuscleGroup.core, 20),
        ],
        from: DateTime(2026, 7, 27),
        to: DateTime(2026, 8, 9),
      );
      expect(h.averagePerWeek, 20.0);
    });
  });

  test('a year of daily rows folds into 52 or 53 weeks', () {
    final from = DateTime(2025, 8, 12);
    final to = DateTime(2026, 8, 11);
    final daily = [
      for (var d = from;
          !d.isAfter(to);
          d = DateTime(d.year, d.month, d.day + 2))
        on(d, MuscleGroup.chest, 3),
    ];

    final h = of(daily, from: from, to: to);
    expect(h.weekCount, inInclusiveRange(52, 54));
    // Nothing lost in the fold: every counted set lands in exactly one week.
    expect(
      h.byRegion[MuscleRegion.chest]!.totalSets,
      daily.length * 3,
    );
  });
}
