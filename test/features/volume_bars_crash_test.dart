import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/workouts/widgets/volume_history_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picking `All` on a fifty-year log froze the volume screen: 2 600 weekly bars
/// in a 138pt tile is a slot of 0.05pt, and `clamp(1.0, slot)` throws when the
/// lower bound passes the upper one — a painter that kills the frame, on every
/// repaint, with no way back to the screen.
void main() {
  List<VolumeWeek> weeksOf(int count) => [
        for (var i = 0; i < count; i++)
          VolumeWeek(
            start: DateTime(1976, 1, 5).add(Duration(days: 7 * i)),
            sets: i % 5,
          ),
      ];

  testWidgets('more bars than pixels paints rather than throwing',
      (tester) async {
    // The exact shape from the crash: a tile 138 wide, fifty years of weeks.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 138,
              height: 44,
              child: WeeklyBars(
                bars: foldWeeks(weeksOf(2600), Granularity.weekly),
                hue: const Color(0xFF00E5FF),
                height: 44,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  test('the fold is coarsened against the marks in hand, not the window', () {
    // What the screen asks for while the range says `All` and the query that
    // knows where `All` starts has not come back yet.
    expect(
      autoGranularityFor(2600, Granularity.weekly),
      Granularity.yearly,
    );
    // 52 weeks is a year of weekly bars, which is a chart, so it stays put.
    expect(autoGranularityFor(52, Granularity.weekly), Granularity.weekly);
    // Never refined below the fold the data already has.
    expect(autoGranularityFor(3, Granularity.monthly), Granularity.monthly);
  });

  testWidgets('a box under a pixel tall paints rather than throwing',
      (tester) async {
    // The other half of the same bug, and the one DEBT § 5 names: the bar
    // height was `clamp(1.0, size.height)`, whose lower bound is a constant and
    // whose upper bound is the layout. A tile shorter than the minimum ink
    // inverts the pair and `clamp` throws — on every repaint, from inside
    // `paint`, which is not a frame you can navigate away from.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 138,
              height: 0.5,
              child: WeeklyBars(
                bars: foldWeeks(weeksOf(8), Granularity.weekly),
                hue: const Color(0xFF00E5FF),
                height: 0.5,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a single bar in a wide box is still drawn', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            height: 44,
            child: WeeklyBars(
              bars: foldWeeks(weeksOf(1), Granularity.weekly),
              hue: const Color(0xFF00E5FF),
              height: 44,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
