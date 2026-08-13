import 'package:deltoid/core/widgets/trend_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// The x axis every chart in the app is drawn on.
///
/// Its one rule: **the right edge is today.** Ranges roll back from the day you
/// are standing in, so the last label is that day and the rest are counted back
/// from it — not laid out from whichever day the data happened to start on,
/// which is what made `1W` print a week that ended three days ago.
void main() {
  DateTime dayOf(double x) =>
      DateTime.fromMillisecondsSinceEpoch((x * 86400000).round());

  /// The labels the axis would print, oldest first.
  List<DateTime> ticks(TimeAxis axis) {
    // The same ladder `fl_chart` walks: phased on the baseline, stepping by the
    // interval, inside the padded bounds.
    final out = <DateTime>[];
    for (var v = axis.baseline; v > axis.minX; v -= axis.interval) {
      out.insert(0, dayOf(v));
    }
    return out;
  }

  test('a week is seven days ending today', () {
    final axis = TimeAxis.of(const TrendWindow.rolling(ChartRange.week));
    final days = ticks(axis);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    expect(days, hasLength(7));
    expect(days.last.difference(today).inHours.abs(), lessThan(2),
        reason: 'the last label is today');
    expect(days.first.difference(today).inDays.abs(), 6);
    // Named by weekday at this range — `Fri Sat Sun … Thu`.
    expect(axis.format, 'EEE');
    expect(
      DateFormat(axis.format).format(days.last),
      DateFormat('EEE').format(today),
    );
  });

  test('every rolling range prints seven labels and ends today', () {
    for (final range in ChartRange.values) {
      final axis = TimeAxis.of(TrendWindow.rolling(range));
      final days = ticks(axis);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      expect(days, hasLength(7), reason: '${range.label} drew ${days.length}');
      expect(days.last.difference(today).inHours.abs(), lessThan(2),
          reason: '${range.label} does not end today');
      expect(days.first.difference(today).inDays.abs(), range.days,
          reason: '${range.label} does not reach back ${range.days} days');
    }
  });

  test('the labels sit inside the plot, never on its edges', () {
    for (final range in ChartRange.values) {
      final axis = TimeAxis.of(TrendWindow.rolling(range));
      for (final t in ticks(axis)) {
        final x = t.millisecondsSinceEpoch / 86400000;
        expect(x, greaterThan(axis.minX));
        expect(x, lessThan(axis.maxX));
      }
    }
  });

  test('a calendar year is that year, whatever today is', () {
    final axis = TimeAxis.of(const TrendWindow.calendar(2019));
    final days = ticks(axis);

    expect(days.last.year, 2019);
    expect(days.last.month, 12);
    expect(days.first.year, 2019);
    expect(days.first.month, 1);
    expect(axis.format, 'MMM');
  });

  test('All reaches back to the first day there is, and names the years', () {
    final axis = TimeAxis.of(
      const TrendWindow.all(),
      earliest: DateTime(1996, 4, 2),
    );
    final days = ticks(axis);

    expect(days, hasLength(7));
    expect(days.first.year, 1996);
    // Thirty years of months would print `Apr` thirty times over.
    expect(axis.format, 'yyyy');
  });

  test('All with nothing logged is a year rather than an inverted axis', () {
    final axis = TimeAxis.of(const TrendWindow.all());
    expect(axis.maxX, greaterThan(axis.minX));
    expect(ticks(axis), hasLength(7));
  });

  test('All on a log one day old still has width', () {
    final now = DateTime.now();
    final axis = TimeAxis.of(const TrendWindow.all(), earliest: now);
    expect(axis.maxX, greaterThan(axis.minX));
  });
}
