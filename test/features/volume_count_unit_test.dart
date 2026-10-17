import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/domain/chart_buckets.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:deltoid/domain/volume_history.dart';
import 'package:deltoid/features/progress/widgets/volume_bars.dart';
import 'package:deltoid/features/progress/widgets/volume_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A count of one takes the singular unit wherever a volume count is printed.
///
/// The weekly volume list printed `1 sets` for a muscle trained once, from at
/// least 1.18.0 until the unit was chosen by the count.
void main() {
  MuscleVolume row(MuscleRegion region, int sets) => MuscleVolume(
        region: region,
        sets: sets,
        parts: [for (final m in region.parts) (muscle: m, sets: sets)],
      );

  testWidgets('the weekly volume list prints 1 set, 0 sets and 2 sets',
      (tester) async {
    final volume = WeeklyVolume(
      windowDays: 7,
      rows: [
        row(MuscleRegion.chest, 1),
        row(MuscleRegion.back, 2),
        for (final r in MuscleRegion.values.skip(2)) row(r, 0),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(child: VolumeBars(volume: volume)),
      ),
    ));

    expect(find.text('set'), findsOneWidget);
    // Back at 2 and the four untrained regions at 0.
    expect(find.text('sets'), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  test('a bar readout of one set takes the singular', () {
    final week = VolumeBar(
      start: DateTime(2026, 6, 15),
      end: DateTime(2026, 6, 21),
      weeks: 1,
      totalSets: 1,
    );
    expect(weekReadout(week, Granularity.weekly), '15–21 Jun · 1 set');

    final month = VolumeBar(
      start: DateTime(2026, 6, 1),
      end: DateTime(2026, 6, 28),
      weeks: 4,
      totalSets: 4,
    );
    expect(weekReadout(month, Granularity.monthly),
        'June 2026 · 1 set a week');

    final busier = VolumeBar(
      start: DateTime(2026, 6, 1),
      end: DateTime(2026, 6, 28),
      weeks: 4,
      totalSets: 6,
    );
    expect(weekReadout(busier, Granularity.monthly),
        'June 2026 · 1.5 sets a week');
  });
}
