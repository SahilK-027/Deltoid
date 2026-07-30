import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../domain/enums.dart';

/// One day on the consistency heatmap.
class HeatDay {
  const HeatDay({required this.workouts, required this.isDeload});

  final int workouts;

  /// Deload days render in a different hue — an easy week should be visibly an
  /// easy week, not a gap in the record.
  final bool isDeload;
}

class HeatmapData {
  const HeatmapData({required this.days, required this.perWeekLast4});

  final Map<int, HeatDay> days;

  /// Rolling sessions-per-week over the last 4 weeks. The number that used to
  /// live in a second app.
  final double perWeekLast4;
}

/// Heatmap covering the last [weeks] weeks.
final heatmapProvider =
    StreamProvider.family<HeatmapData, int>((ref, weeks) {
  final db = ref.watch(databaseProvider);
  final from = dayKeyOf(
    DateTime.now().subtract(Duration(days: weeks * 7 + 7)),
  );

  final query = db.select(db.workouts)
    ..where((t) =>
        t.dayKey.isBiggerOrEqualValue(from) &
        t.status.equalsValue(WorkoutStatus.completed) &
        t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]);

  return query.watch().map((rows) {
    final days = <int, HeatDay>{};
    for (final w in rows) {
      final existing = days[w.dayKey];
      days[w.dayKey] = HeatDay(
        workouts: (existing?.workouts ?? 0) + 1,
        isDeload: (existing?.isDeload ?? false) || w.isDeload,
      );
    }

    final cutoff = dayKeyOf(DateTime.now().subtract(const Duration(days: 28)));
    final recent = rows.where((w) => w.dayKey >= cutoff).length;

    return HeatmapData(days: days, perWeekLast4: recent / 4);
  });
});
