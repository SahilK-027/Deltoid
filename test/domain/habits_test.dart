import 'package:deltoid/core/ids.dart';
import 'package:deltoid/domain/consistency.dart';
import 'package:deltoid/domain/habits.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two habit tiles on Home: a thirty-day grid and `N/7 this week`.
void main() {
  // A Thursday, so the week so far is Monday 27 to Thursday 30 July.
  final thursday = DateTime(2026, 7, 30);

  group('the week', () {
    test('counts days from Monday to today', () {
      final keys = [20260727, 20260728, 20260730];
      expect(daysKeptThisWeek(keys, today: thursday), 3);
    });

    test('counts a day once however many entries it holds', () {
      // Two sessions on a Tuesday are one cell on the grid, so they are one
      // day kept. A figure the grid contradicts is worse than none.
      final keys = [20260728, 20260728, 20260728];
      expect(daysKeptThisWeek(keys, today: thursday), 1);
    });

    test('ignores last Sunday and anything after today', () {
      final keys = [20260726, 20260731, 20260802];
      expect(daysKeptThisWeek(keys, today: thursday), 0);
    });

    test('on a Monday the week is that one day', () {
      final monday = DateTime(2026, 7, 27);
      expect(daysKeptThisWeek([20260726, 20260727], today: monday), 1);
    });

    test('can never pass seven', () {
      final everyDay = [
        for (var d = 1; d <= 31; d++) dayKeyOf(DateTime(2026, 8, d)),
      ];
      expect(daysKeptThisWeek(everyDay, today: DateTime(2026, 8, 30)), 7);
    });

    test('is the count the Workouts tile reads off Consistency', () {
      // The Workouts tile prints `Consistency.thisWeek`, so the two counts
      // must be one function or the tile and the Consistency screen disagree.
      final keys = [20260720, 20260727, 20260728, 20260728, 20260730];
      expect(
        computeConsistency(completedDayKeys: keys, today: thursday).thisWeek,
        daysKeptThisWeek(keys, today: thursday),
      );
    });
  });

  group('the grid', () {
    test('is thirty days, oldest first, ending today', () {
      final days = habitWindow(thursday);
      expect(days, hasLength(30));
      expect(days.first, 20260701);
      expect(days.last, 20260730);
      expect(days, orderedEquals([...days]..sort()));
    });

    test('repeats no day across a daylight-saving change', () {
      // The spring change in Europe falls on 29 March 2026. Subtracting
      // whole days as durations lands on 23:00 the day before there, and a
      // day appears twice.
      final days = habitWindow(DateTime(2026, 4, 10));
      expect(days.toSet(), hasLength(30));
      expect(days.first, 20260312);
    });
  });
}
