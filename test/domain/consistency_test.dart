import 'package:deltoid/core/ids.dart';
import 'package:deltoid/domain/consistency.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rate on Today is not `sessionsInLast29Days / 4`: that is wrong in both
/// halves, a fixed four-week denominator regardless of how long the app has
/// been in use, over a window that is actually 29 days long.
void main() {
  final today = DateTime(2026, 7, 30);

  int keyDaysAgo(int days) =>
      dayKeyOf(today.subtract(Duration(days: days)));

  Consistency of(List<int> daysAgo) => computeConsistency(
        completedDayKeys: daysAgo.map(keyDaysAgo),
        today: today,
      );

  test('one session on day two is a count, not a rate', () {
    final c = of([1]);

    // "0.3 / week" here would be a fabrication: it divides by three weeks that
    // have not happened.
    expect(c.perWeek, isNull);
    expect(c.sessions, 1);
    expect(c.historyDays, 2);
  });

  test('short history averages over the days it has, not over four weeks', () {
    // Three sessions across a fortnight is three a fortnight, or 1.5 a week.
    final c = of([13, 7, 1]);

    expect(c.historyDays, 14);
    expect(c.windowDays, 14);
    expect(c.perWeek, closeTo(1.5, 0.01));
  });

  test('a session exactly two weeks in is enough history to average', () {
    expect(of([13]).perWeek, isNotNull);
    expect(of([12]).perWeek, isNull);
  });

  test('the window is 28 days, not 29', () {
    // Long history, so the window is the full four weeks. A session 28 days
    // back falls outside it; a 29-day cutoff would let it in and then divide
    // by 4.
    final c = of([200, 28, 27]);

    expect(c.windowDays, consistencyWindowDays);
    expect(c.sessions, 1, reason: 'only the 27-day-old session is in window');
    expect(c.perWeek, closeTo(0.25, 0.001));
  });

  test('twice a week over a long history reads as twice a week', () {
    final c = of([
      120,
      for (var d = 0; d < 28; d += 7) ...[d, d + 3],
    ]);

    expect(c.sessions, 8);
    expect(c.perWeek, closeTo(2.0, 0.01));
  });

  test('two sessions in one day count twice', () {
    final c = of([100, 3, 3]);

    expect(c.sessions, 2);
  });

  test('a long layoff reports zero rather than the last good number', () {
    final c = of([90, 60, 40]);

    expect(c.sessions, 0);
    expect(c.perWeek, 0);
    expect(c.isEmpty, isTrue);
  });

  group('this week', () {
    // 30 July 2026 is a Thursday, so Monday of the current week is the 27th —
    // anything up to three days ago counts, anything older does not.
    test('counts back to Monday, not back seven days', () {
      final c = of([100, 4, 3, 0]);

      expect(c.thisWeek, 2, reason: '4 days ago is last Sunday');
    });

    test('two sessions in one day are one day trained', () {
      // The window count is a rate and counts both; this one is a row of days
      // on a grid, and that grid has one cell for the pair.
      expect(of([1, 1]).sessions, 2);
      expect(of([1, 1]).thisWeek, 1);
    });

    test('a fresh Monday starts at zero rather than carrying Sunday over', () {
      final monday = DateTime(2026, 7, 27);
      final c = computeConsistency(
        completedDayKeys: [dayKeyOf(monday.subtract(const Duration(days: 1)))],
        today: monday,
      );

      expect(c.thisWeek, 0);
    });

    test('a session logged today counts on a Monday', () {
      final monday = DateTime(2026, 7, 27);
      final c = computeConsistency(
        completedDayKeys: [dayKeyOf(monday)],
        today: monday,
      );

      expect(c.thisWeek, 1);
    });

    test('nothing logged is zero, not null', () {
      expect(
        computeConsistency(completedDayKeys: const [], today: today).thisWeek,
        0,
      );
    });
  });

  test('nothing logged has no history and no rate', () {
    final c = computeConsistency(completedDayKeys: const [], today: today);

    expect(c.historyDays, 0);
    expect(c.sessions, 0);
    expect(c.perWeek, isNull);
  });
}
