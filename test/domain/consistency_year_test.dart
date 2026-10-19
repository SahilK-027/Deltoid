import 'package:deltoid/core/ids.dart';
import 'package:deltoid/domain/consistency_year.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Consistency screen's year: a bar per week, the two figures over them,
/// and the counts in the two headings.
void main() {
  // A Monday.
  final today = DateTime(2026, 10, 19);

  Map<int, LoggedDayCount> logged(Map<DateTime, int> sessions,
          {Set<DateTime> deload = const {}}) =>
      {
        for (final MapEntry(:key, :value) in sessions.entries)
          dayKeyOf(key): (sessions: value, deload: deload.contains(key)),
      };

  group('weeks', () {
    test('run Monday to Sunday and start at the first session', () {
      final y = foldConsistencyYear(
        logged({DateTime(2026, 3, 4): 1, DateTime(2026, 3, 12): 2}),
        year: 2026,
        today: today,
      );

      // 4 March 2026 is a Wednesday, so the first week begins on the 2nd.
      expect(y.weeks.first.start, DateTime(2026, 3, 2));
      expect(y.weeks.first.sessions, 1);
      expect(y.weeks[1].sessions, 2);
      // Through the week holding today, and no further.
      expect(y.weeks.last.start, DateTime(2026, 10, 19));
    });

    test('a later year starts on its first week, not at the first session', () {
      final y = foldConsistencyYear(
        logged({DateTime(2024, 6, 3): 1, DateTime(2026, 1, 5): 1}),
        year: 2026,
        today: today,
      );

      // 1 January 2026 is a Thursday; its week starts in December 2025.
      expect(y.weeks.first.start, DateTime(2025, 12, 29));
      expect(y.weeks.first.first, DateTime(2026, 1, 1));
    });

    test('a week across New Year counts only its own year\'s days', () {
      final days = logged({
        DateTime(2025, 12, 30): 1,
        DateTime(2026, 1, 2): 1,
      });

      final y26 = foldConsistencyYear(days, year: 2026, today: today);
      final y25 = foldConsistencyYear(days, year: 2025, today: today);

      expect(y26.weeks.first.sessions, 1);
      expect(y25.weeks.last.sessions, 1);
      expect(y25.weeks.last.last, DateTime(2025, 12, 31));
      expect(y26.sessions + y25.sessions, 2);
    });

    test('a past year runs to its last week', () {
      final y = foldConsistencyYear(
        logged({DateTime(2025, 1, 6): 1}),
        year: 2025,
        today: today,
      );

      expect(y.weeks.last.last, DateTime(2025, 12, 31));
      expect(y.weeks.length, 52);
    });

    test('a year before the first session has no weeks', () {
      final y = foldConsistencyYear(
        logged({DateTime(2026, 2, 2): 1}),
        year: 2025,
        today: today,
      );

      expect(y.weeks, isEmpty);
      expect(y.averagePerWeek, isNull);
    });

    test('a week with a deload session is a deload week', () {
      final y = foldConsistencyYear(
        logged(
          {DateTime(2026, 10, 5): 1, DateTime(2026, 10, 7): 1},
          deload: {DateTime(2026, 10, 7)},
        ),
        year: 2026,
        today: today,
      );

      expect(y.weeks.first.deload, isTrue);
      expect(y.weeks.last.deload, isFalse);
    });

    test('walks a clock change without losing a week', () {
      // Europe and North America both change clocks in late March and
      // October; stepping by 7 × 24 hours drifts off midnight across them.
      final y = foldConsistencyYear(
        logged({DateTime(2026, 3, 23): 1, DateTime(2026, 3, 30): 1}),
        year: 2026,
        today: today,
      );

      expect(y.weeks.take(2).map((w) => w.sessions), [1, 1]);
      for (final w in y.weeks) {
        expect(w.start.hour, 0);
        expect(w.start.weekday, DateTime.monday);
      }
    });
  });

  group('figures', () {
    test('the week under way is left out of the average', () {
      final y = foldConsistencyYear(
        logged({
          DateTime(2026, 10, 5): 2,
          DateTime(2026, 10, 12): 4,
          // Today: counted in the year, not in the rate.
          DateTime(2026, 10, 19): 1,
        }),
        year: 2026,
        today: today,
      );

      expect(y.weeksCounted, 2);
      expect(y.weeksTrained, 2);
      expect(y.averagePerWeek, 3);
      expect(y.sessions, 7);
      expect(y.weeks.last.sessions, 1);
    });

    test('a week without a session is counted and not trained', () {
      final y = foldConsistencyYear(
        logged({DateTime(2026, 9, 28): 3, DateTime(2026, 10, 12): 3}),
        year: 2026,
        today: today,
      );

      expect(y.weeksCounted, 3);
      expect(y.weeksTrained, 2);
      expect(y.averagePerWeek, 2);
    });

    test('nothing to average in the first week of use', () {
      final y = foldConsistencyYear(
        logged({DateTime(2026, 10, 19): 1}),
        year: 2026,
        today: today,
      );

      expect(y.weeks, hasLength(1));
      expect(y.averagePerWeek, isNull);
    });

    test('two sessions on a day are two sessions and one training day', () {
      final y = foldConsistencyYear(
        logged({DateTime(2026, 10, 6): 2}),
        year: 2026,
        today: today,
      );

      expect(y.sessions, 2);
      expect(y.trainingDays, 1);
      expect(y.peak, 2);
    });
  });

  group('years', () {
    test('run from the first session to this year, newest first', () {
      final years = consistencyYears(
        [dayKeyOf(DateTime(2024, 5, 1)), dayKeyOf(DateTime(2026, 1, 1))],
        today: today,
      );

      expect(years, [2026, 2025, 2024]);
    });

    test('this year is offered before anything is logged in it', () {
      expect(
        consistencyYears([dayKeyOf(DateTime(2025, 5, 1))], today: today),
        [2026, 2025],
      );
      expect(consistencyYears(const [], today: today), [2026]);
    });
  });

  group('week range', () {
    TrainingWeek week(DateTime first, DateTime last) => TrainingWeek(
          start: first,
          first: first,
          last: last,
          sessions: 0,
          deload: false,
        );

    test('names the month once when both ends share it', () {
      expect(
        weekRangeLabel(week(DateTime(2026, 1, 19), DateTime(2026, 1, 25))),
        '19–25 Jan',
      );
    });

    test('names both months across a month end', () {
      expect(
        weekRangeLabel(week(DateTime(2026, 1, 26), DateTime(2026, 2, 1))),
        '26 Jan–1 Feb',
      );
    });

    test('a single day is one date', () {
      expect(
        weekRangeLabel(week(DateTime(2026, 2, 1), DateTime(2026, 2, 1))),
        '1 Feb',
      );
    });
  });
}
