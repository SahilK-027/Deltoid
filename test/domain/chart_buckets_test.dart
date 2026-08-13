import 'package:deltoid/core/ids.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The maths every chart in the app now draws through. A wrong average here is
/// wrong on six screens at once and looks exactly like a right one.
void main() {
  ({int dayKey, double value}) at(int y, int m, int d, double v) =>
      (dayKey: dayKeyOf(DateTime(y, m, d)), value: v);

  group('bucket boundaries', () {
    test('a week starts on Monday, the rule the whole app uses', () {
      // 12 Aug 2026 is a Wednesday.
      expect(
        bucketStartOf(DateTime(2026, 8, 12), Granularity.weekly),
        DateTime(2026, 8, 10),
      );
      // A Sunday belongs to the week that opened six days earlier, not to the
      // one starting tomorrow.
      expect(
        bucketStartOf(DateTime(2026, 8, 16), Granularity.weekly),
        DateTime(2026, 8, 10),
      );
    });

    test('a month and a year start where the calendar says', () {
      expect(bucketStartOf(DateTime(2026, 8, 31), Granularity.monthly),
          DateTime(2026, 8));
      expect(bucketStartOf(DateTime(2026, 12, 31), Granularity.yearly),
          DateTime(2026));
    });

    test('walking buckets survives February, a 31st and a leap year', () {
      expect(nextBucket(DateTime(2026, 1, 31), Granularity.monthly),
          DateTime(2026, 2));
      expect(nextBucket(DateTime(2024, 2), Granularity.monthly),
          DateTime(2024, 3));
      expect(nextBucket(DateTime(2024, 2, 28), Granularity.daily),
          DateTime(2024, 2, 29));
      expect(nextBucket(DateTime(2023, 2, 28), Granularity.daily),
          DateTime(2023, 3));
    });

    test('a bucket ends on the last day it covers', () {
      final months = bucketize(
        rows: [at(2024, 2, 1, 1)],
        by: Granularity.monthly,
        from: DateTime(2024, 2),
        to: DateTime(2024, 2, 29),
      );
      expect(months, hasLength(1));
      expect(months.single.end, DateTime(2024, 2, 29), reason: 'leap February');
    });
  });

  group('folding', () {
    test('a measurement averages', () {
      final weeks = bucketize(
        rows: [
          at(2026, 8, 10, 70),
          at(2026, 8, 12, 72),
          at(2026, 8, 16, 74),
        ],
        by: Granularity.weekly,
        from: DateTime(2026, 8, 10),
        to: DateTime(2026, 8, 16),
      );

      expect(weeks, hasLength(1));
      expect(weeks.single.value, 72);
      expect(weeks.single.count, 3);
    });

    test('a count totals — "4.2 sets in March" is a lie about March', () {
      final months = bucketize(
        rows: [
          at(2026, 3, 2, 12),
          at(2026, 3, 9, 15),
          at(2026, 3, 30, 9),
        ],
        by: Granularity.monthly,
        from: DateTime(2026, 3),
        to: DateTime(2026, 3, 31),
        fold: BucketFold.sum,
      );

      expect(months.single.value, 36);
    });

    test('an empty bucket keeps its place and carries null, never zero', () {
      final months = bucketize(
        rows: [at(2026, 1, 5, 10), at(2026, 3, 5, 20)],
        by: Granularity.monthly,
        from: DateTime(2026),
        to: DateTime(2026, 3, 31),
      );

      expect(months, hasLength(3));
      expect(months[0].value, 10);
      // February is not a month you weighed nothing. It is a month with no
      // reading in it, and the two draw differently.
      expect(months[1].value, isNull);
      expect(months[1].isEmpty, isTrue);
      expect(months[2].value, 20);
    });

    test('rows outside the span are dropped, not folded into the edges', () {
      final weeks = bucketize(
        rows: [
          at(2026, 8, 3, 100), // the week before
          at(2026, 8, 12, 70),
          at(2026, 8, 24, 100), // the week after
        ],
        by: Granularity.weekly,
        from: DateTime(2026, 8, 10),
        to: DateTime(2026, 8, 16),
      );

      expect(weeks, hasLength(1));
      expect(weeks.single.value, 70);
      expect(weeks.single.count, 1);
    });

    test('the span decides the buckets, so an empty log is still a span', () {
      final weeks = bucketize(
        rows: const [],
        by: Granularity.weekly,
        from: DateTime(2026, 7, 6),
        to: DateTime(2026, 8, 16),
      );

      // Mondays 6, 13, 20, 27 July and 3, 10 August.
      expect(weeks, hasLength(6));
      expect(weeks.every((w) => w.value == null), isTrue);
      expect(weeks.first.start, DateTime(2026, 7, 6));
      expect(weeks.last.start, DateTime(2026, 8, 10));
    });

    test('a span running backwards is no buckets rather than a crash', () {
      expect(
        bucketize(
          rows: const [],
          by: Granularity.daily,
          from: DateTime(2026, 8, 16),
          to: DateTime(2026, 8, 10),
        ),
        isEmpty,
      );
    });

    test('order in is irrelevant; the buckets come out oldest first', () {
      final days = bucketize(
        rows: [at(2026, 8, 12, 3), at(2026, 8, 10, 1), at(2026, 8, 11, 2)],
        by: Granularity.daily,
        from: DateTime(2026, 8, 10),
        to: DateTime(2026, 8, 12),
      );

      expect([for (final d in days) d.value], [1, 2, 3]);
    });
  });

  group('picking a granularity', () {
    test('the finest that stays under the ceiling, not the coarsest', () {
      expect(autoGranularity(7), Granularity.daily);
      expect(autoGranularity(60), Granularity.daily);
      expect(autoGranularity(90), Granularity.weekly);
      expect(autoGranularity(365), Granularity.weekly);
      expect(autoGranularity(365 * 3), Granularity.monthly);
      expect(autoGranularity(365 * 50), Granularity.yearly);
    });

    test('nothing ever draws more marks than the ceiling', () {
      for (final span in [7, 31, 90, 180, 365, 365 * 5, 365 * 50]) {
        final by = autoGranularity(span);
        final marks = bucketize(
          rows: const [],
          by: by,
          from: DateTime(2026, 8, 13).subtract(Duration(days: span)),
          to: DateTime(2026, 8, 13),
        ).length;
        expect(marks, lessThanOrEqualTo(62),
            reason: '$span days at ${by.label} draws $marks marks');
      }
    });
  });

  group('what the picker may offer', () {
    test('a level that draws one mark is not a choice', () {
      // A month cannot be averaged yearly — that is one dot.
      expect(granularitiesFor(30), isNot(contains(Granularity.yearly)));
      expect(granularitiesFor(30), isNot(contains(Granularity.monthly)));
      expect(granularitiesFor(30), contains(Granularity.daily));
      expect(granularitiesFor(30), contains(Granularity.weekly));
    });

    test('a level the data can answer is offered even when it is dense', () {
      // Dense is a taste you are allowed to have — you can pinch into it. Only
      // the impossible is withheld.
      expect(granularitiesFor(365), contains(Granularity.daily));
      expect(granularitiesFor(365), contains(Granularity.weekly));
      expect(granularitiesFor(365), contains(Granularity.monthly));
      expect(granularitiesFor(365), isNot(contains(Granularity.yearly)));
    });

    test('fifty years offers everything down to the drawing limit', () {
      final all = granularitiesFor(365 * 50);
      expect(all, contains(Granularity.yearly));
      expect(all, contains(Granularity.monthly));
      expect(all, contains(Granularity.weekly));
      // 18 000 marks is not a chart at any zoom, and it is a hang on the way.
      expect(all, isNot(contains(Granularity.daily)));
    });

    test('a chart of bars asks for a tighter limit than a line does', () {
      // A bar needs a point of width; a line does not.
      final bars = granularitiesFor(365 * 50, ceiling: 400);
      expect(bars, contains(Granularity.yearly));
      expect(bars, isNot(contains(Granularity.weekly)));
    });

    test('a span too short for anything still answers', () {
      expect(granularitiesFor(0), isNotEmpty);
      expect(granularitiesFor(1), isNotEmpty);
    });

    test('a choice survives a range change while it still fits', () {
      // Monthly picked on a year, then widened — still monthly.
      expect(resolveGranularity(Granularity.monthly, 365 * 3),
          Granularity.monthly);
      // Yearly picked on All, then 1M selected: stood down rather than drawing
      // a single dot.
      expect(resolveGranularity(Granularity.yearly, 30), isNot(Granularity.yearly));
      // Nothing chosen is the automatic one.
      expect(resolveGranularity(null, 30), Granularity.daily);
    });

    test('a screen may forbid a level outright, and the fallback obeys it', () {
      const noDaily = [
        Granularity.weekly,
        Granularity.monthly,
        Granularity.yearly,
      ];
      // 30 days would auto to daily, which volume does not have.
      expect(resolveGranularity(null, 30, allowed: noDaily), Granularity.weekly);
      expect(
        resolveGranularity(Granularity.daily, 30, allowed: noDaily),
        isNot(Granularity.daily),
      );
    });
  });
}
