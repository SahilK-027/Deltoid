import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/muscle_volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WeeklyVolume fold(Map<MuscleGroup, int> sets) =>
      computeWeeklyVolume(setsByMuscle: sets);

  MuscleVolume rowFor(WeeklyVolume v, MuscleRegion r) =>
      v.rows.firstWhere((row) => row.region == r);

  group('regions', () {
    test('every muscle but `other` lands in exactly one region', () {
      final mapped = <MuscleGroup>{};
      for (final region in MuscleRegion.values) {
        for (final m in region.parts) {
          expect(mapped.add(m), isTrue, reason: '$m is in two regions');
          expect(regionOf(m), region);
        }
      }
      expect(mapped, MuscleGroup.values.toSet()..remove(MuscleGroup.other));
    });

    test('`other` counts toward nothing', () {
      expect(regionOf(MuscleGroup.other), isNull);
      final v = fold({MuscleGroup.other: 9, MuscleGroup.chest: 3});
      expect(v.totalSets, 3);
      expect(v.maxSets, 3);
    });

    test('only arms and legs open', () {
      expect(MuscleRegion.arms.isCompound, isTrue);
      expect(MuscleRegion.legs.isCompound, isTrue);
      for (final r in [
        MuscleRegion.chest,
        MuscleRegion.back,
        MuscleRegion.shoulders,
        MuscleRegion.core,
      ]) {
        expect(r.isCompound, isFalse, reason: '$r would open onto itself');
      }
    });
  });

  group('the fold', () {
    test('all six rows exist in order, whatever the week held', () {
      for (final v in [fold(const {}), fold({MuscleGroup.chest: 4})]) {
        expect(v.rows.map((r) => r.region), MuscleRegion.values);
      }
    });

    test('a region is the sum of its muscles', () {
      final v = fold({
        MuscleGroup.biceps: 6,
        MuscleGroup.triceps: 4,
        MuscleGroup.quads: 12,
        MuscleGroup.hamstrings: 2,
      });
      expect(rowFor(v, MuscleRegion.arms).sets, 10);
      expect(rowFor(v, MuscleRegion.legs).sets, 14);
      expect(v.totalSets, 24);
    });

    test('an opened region keeps its zero muscles — the zero is the point', () {
      final v = fold({MuscleGroup.quads: 12});
      final legs = rowFor(v, MuscleRegion.legs);
      expect(legs.parts.map((p) => p.muscle), MuscleRegion.legs.parts);
      expect(
        legs.parts.firstWhere((p) => p.muscle == MuscleGroup.hamstrings).sets,
        0,
      );
    });

    test('a muscle absent from the count is zero, not missing', () {
      final v = fold({MuscleGroup.chest: 5});
      expect(rowFor(v, MuscleRegion.core).sets, 0);
      expect(rowFor(v, MuscleRegion.core).isEmpty, isTrue);
    });

    test('the maximum is the biggest row, and an empty week has none', () {
      expect(fold(const {}).maxSets, 0);
      expect(fold(const {}).isEmpty, isTrue);
      // Normalised to the biggest *region*, not to the biggest muscle: legs at
      // 14 outranks a chest of 10 even though no single leg muscle does.
      final v = fold({
        MuscleGroup.chest: 10,
        MuscleGroup.quads: 8,
        MuscleGroup.hamstrings: 6,
      });
      expect(v.maxSets, 14);
    });
  });

  group('what counts as a set', () {
    test('working, amrap and backoff are volume; warmups and legs of a set '
        'are not', () {
      expect(countsAsVolume(SetType.working), isTrue);
      expect(countsAsVolume(SetType.amrap), isTrue);
      // Deliberately unlike `countsForProgress`: a backoff set is work done
      // even though it must never enter an e1RM comparison.
      expect(countsAsVolume(SetType.backoff), isTrue);
      expect(SetType.backoff.countsForProgress, isFalse);

      expect(countsAsVolume(SetType.warmup), isFalse);
      // A drop leg is the set above it continued — counting it turns one set
      // taken to failure into three.
      expect(countsAsVolume(SetType.drop), isFalse);
      expect(countsAsVolume(SetType.restPause), isFalse);
    });

    test('every continuation is excluded', () {
      for (final t in SetType.values.where((t) => t.isContinuation)) {
        expect(countsAsVolume(t), isFalse, reason: '$t is not its own set');
      }
    });
  });
}
