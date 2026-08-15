/// Calendar arithmetic, run in whatever timezone the process was started in.
///
/// Dart reads the local zone from `TZ` once, at process start, and offers no
/// way to change it afterwards — so a clock change cannot be reached from
/// inside a test on a machine sitting in a zone that has none (this one is
/// `Asia/Kolkata`). `dst_calendar_test.dart` runs this file as a child process
/// under a list of zones that do, and reads the lines it prints.
///
/// Not a test file: it must not be picked up by `flutter test` on its own,
/// which is why it lives in `test/tools/` and is named `_probe` rather than
/// `_test`.
///
/// Prints one `FAIL <check> | <detail>` line per finding and nothing else on
/// success. Exits 0 either way; the parent decides.
///
/// `print` is this file's entire interface — stdout is how the parent reads the
/// findings back out of the child process — so the lint is off for the file
/// rather than silenced three times.
// ignore_for_file: avoid_print
library;

import 'package:deltoid/core/ids.dart';
import 'package:deltoid/domain/consistency.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/volume_history.dart';

/// Wide enough to contain every transition the zones under test have scheduled,
/// and short enough that the whole sweep is a fraction of a second.
const _firstYear = 2020;
const _lastYear = 2030;

void main() {
  final fails = <String>[];
  void check(bool ok, String name, String detail) {
    if (!ok) fails.add('FAIL $name | $detail');
  }

  // Does this process actually believe it is somewhere with a clock change? A
  // zone the host has no tzdata for silently resolves to UTC, and every check
  // below would then pass without having tested anything.
  final offsets = {
    for (var m = 1; m <= 12; m++) DateTime(2026, m, 1).timeZoneOffset,
  };
  print('OFFSETS ${offsets.map((o) => o.inMinutes).toList()..sort()}');

  for (var y = _firstYear; y <= _lastYear; y++) {
    for (var i = 1; i <= 366; i++) {
      final day = DateTime(y, 1, i);
      if (day.year != y) break;
      final iso = '${day.year}-${day.month}-${day.day}';

      // The map key. `computeVolumeHistory` builds its index by walking
      // Mondays as `DateTime(y, m, d)`, so a week start has to be a Monday and
      // has to be *that* instant, or the lookup misses.
      //
      // Not "hour == 0": in a zone that moves its clock at midnight there are
      // days with no 00:00 at all, and `DateTime(y, m, d)` on one of them is
      // 01:00 — which is still the right key, because the walk names the date
      // the same way. Re-naming the result is the honest test of that.
      final ws = weekStartOf(day);
      check(ws == DateTime(ws.year, ws.month, ws.day), 'weekStartOf-canonical',
          '$iso -> $ws');
      check(ws.weekday == DateTime.monday, 'weekStartOf-monday', '$iso -> $ws');

      // Every span the app goes back from a date somewhere.
      for (final n in [1, 6, 7, 27, 364, 365]) {
        final back = daysBefore(day, n);
        check(back == DateTime(back.year, back.month, back.day),
            'daysBefore-canonical', '$iso - $n -> $back');
        check(daysBetween(back, day) == n, 'daysBetween-roundtrip',
            '$iso - $n -> $back, back ${daysBetween(back, day)}');
      }

      // The number the date strip reads out. Yesterday is one day ago on every
      // day of the year, including the two that are 23 and 25 hours long.
      check(daysBetweenKeys(dayKeyOf(daysBefore(day, 1)), dayKeyOf(day)) == 1,
          'yesterday-is-one-day-ago', iso);

      // The fortnight boundary, where `historyDays` decides whether a rate is
      // reported at all.
      final firstKey = dayKeyOf(daysBefore(day, 13));
      final c = computeConsistency(
        completedDayKeys: [firstKey, dayKeyOf(day)],
        today: day,
      );
      check(c.historyDays == 14, 'consistency-historyDays',
          '$iso -> ${c.historyDays}');

      // And the row that gets dropped. One counted day inside the span has to
      // come out the other side.
      final history = computeVolumeHistory(
        daily: [(dayKey: dayKeyOf(day), muscle: MuscleGroup.chest, sets: 5)],
        from: daysBefore(day, 7),
        to: daysBefore(day, -7),
      );
      final landed = history.byMuscle[MuscleGroup.chest]?.weeks
              .fold<int>(0, (a, w) => a + w.sets) ??
          -1;
      check(landed == 5, 'volumeHistory-keeps-row', '$iso -> $landed sets');
    }
  }

  for (final line in fails.take(20)) {
    print(line);
  }
  if (fails.length > 20) print('FAIL ... | ${fails.length - 20} more');
}
