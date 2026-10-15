import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/home/widgets/volume_history_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The zoom between two ranges was implemented and tested by nothing, because
/// "it looked smooth" needs a golden or a frame timeline.
///
/// What can be tested without either is the part that would be *visibly* wrong:
/// the chart must not resize while it animates. A bar strip that grows a few
/// points mid-zoom shoves everything under it down and back, and that reads as
/// the screen glitching rather than as a chart changing range. Every frame of
/// the transition is measured here, not just its two ends.
void main() {
  List<VolumeWeek> weeksOf(int count) => [
        for (var i = 0; i < count; i++)
          VolumeWeek(
            start: DateTime(2026, 1, 5).add(Duration(days: 7 * i)),
            sets: (i % 7) * 3,
          ),
      ];

  Widget wrap(List<VolumeBar> bars) => MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WeeklyBars(
                    bars: bars,
                    hue: const Color(0xFF00E5FF),
                    height: 44,
                  ),
                  const Text('under the chart'),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('the chart keeps its size for every frame of a range switch',
      (tester) async {
    await tester.pumpWidget(wrap(foldWeeks(weeksOf(13), Granularity.weekly)));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(WeeklyBars));
    final captionAt = tester.getTopLeft(find.text('under the chart'));

    // Thirteen weeks to three years, which is the widest jump the range
    // control offers and the one the zoom was written for.
    await tester.pumpWidget(wrap(foldWeeks(weeksOf(156), Granularity.weekly)));

    // Frame by frame through the whole animation rather than settling: the
    // failure this is looking for happens in the middle and is gone by the end.
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.getSize(find.byType(WeeklyBars)), size,
          reason: 'the chart resized on frame $frame of the zoom');
      expect(tester.getTopLeft(find.text('under the chart')), captionAt,
          reason: 'the caption moved on frame $frame of the zoom');
      expect(tester.takeException(), isNull);
    }

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(WeeklyBars)), size);
  });

  testWidgets('the switch is animated rather than instant', (tester) async {
    // The other half: a test that only checked the size would pass just as
    // happily if the zoom had been deleted. `WeeklyBars` repaints while the
    // controller runs, so a frame scheduled mid-transition is the evidence
    // there is a transition.
    await tester.pumpWidget(wrap(foldWeeks(weeksOf(13), Granularity.weekly)));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(wrap(foldWeeks(weeksOf(156), Granularity.weekly)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'nothing is animating: the range changed in a single frame',
    );

    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
