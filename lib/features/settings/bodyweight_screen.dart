import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/units.dart';

/// Every bodyweight entry, oldest last.
///
/// Unlimited on purpose. Settings shows a six-row peek off a query capped at
/// 30, which was fine as a readout and wrong the moment entries became
/// editable: a typo from two months ago was unreachable, and bodyweight
/// silently scales the score of every bodyweight and weighted lift.
final bodyweightHistoryProvider =
    StreamProvider<List<BodyweightLog>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.bodyweightLogs)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([
      (t) => OrderingTerm(expression: t.dayKey, mode: OrderingMode.desc)
    ]);
  return query.watch();
});

class BodyweightScreen extends ConsumerWidget {
  const BodyweightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(bodyweightHistoryProvider).valueOrNull;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final c = context.c;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bodyweight'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Log a weight',
            onPressed: () => logBodyweightPrompt(context, ref),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: log == null
          ? const Center(child: CircularProgressIndicator())
          : log.isEmpty
              ? EmptyState(
                  icon: Icons.monitor_weight_outlined,
                  title: 'No weights logged',
                  message: 'Needed to score bodyweight and BW+ lifts — 7 '
                      'pull-ups at 70kg and 7 at 76kg are not the same lift.',
                  action: FilledButton(
                    onPressed: () => logBodyweightPrompt(context, ref),
                    child: const Text('Log bodyweight'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Space.lg, Space.sm, Space.lg, Space.huge),
                  itemCount: log.length,
                  itemBuilder: (context, i) {
                    final entry = log[i];
                    // Against the entry before it, so a trend is readable
                    // without a chart.
                    final previous = i + 1 < log.length ? log[i + 1] : null;
                    final delta = previous == null
                        ? null
                        : entry.weightKg - previous.weightKg;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                          vertical: Space.md,
                        ),
                        onTap: () => logBodyweightPrompt(
                          context,
                          ref,
                          date: dateFromDayKey(entry.dayKey),
                          initial: entry.weightKg,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('EEE d MMM yyyy')
                                    .format(dateFromDayKey(entry.dayKey)),
                                style: context.t.bodyMedium,
                              ),
                            ),
                            if (delta != null && delta.abs() >= 0.05) ...[
                              Text(
                                '${delta > 0 ? '+' : '−'}'
                                '${formatInUnit(delta.abs(), unit)}',
                                style: context.t.labelSmall?.copyWith(
                                  color: c.textTertiary,
                                ),
                              ),
                              const SizedBox(width: Space.md),
                            ],
                            Text(
                              '${formatInUnit(entry.weightKg, unit)} '
                              '${unit.label}',
                              style: context.t.titleSmall?.copyWith(
                                fontFeatures: tabular,
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: c.textTertiary),
                              onPressed: () =>
                                  _delete(context, ref, entry.dayKey),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    int dayKey,
  ) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this weight?',
      message: '${DateFormat('d MMM yyyy').format(dateFromDayKey(dayKey))} '
          'will no longer be used to score bodyweight lifts.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await ref.read(trainingRepositoryProvider).deleteBodyweight(dayKey);
  }
}

/// Logs or corrects one weight.
///
/// [date] and [initial] are set when correcting an existing entry;
/// `logBodyweight` upserts by day, so editing is simply a re-log.
Future<void> logBodyweightPrompt(
  BuildContext context,
  WidgetRef ref, {
  DateTime? date,
  double? initial,
}) async {
  final unit = ref.read(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
  final controller = TextEditingController(
    text: initial == null ? '' : formatInUnit(initial, unit),
  );
  var day = date ?? DateTime.now();

  final value = await showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(date == null ? 'Log bodyweight' : 'Edit bodyweight'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(suffixText: unit.label),
              onSubmitted: (v) => Navigator.of(ctx).pop(double.tryParse(v)),
            ),
            const SizedBox(height: Space.md),
            // Weighing yourself and logging it are rarely the same moment.
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: day,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => day = picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14),
                    const SizedBox(width: Space.sm),
                    Text(DateFormat('d MMM yyyy').format(day)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (value == null || value <= 0) return;
  // Typed in whatever this phone shows, stored in kilograms.
  final kg = unit.toKg(value);

  final repo = ref.read(trainingRepositoryProvider);
  // Moving an entry to another date is a delete plus a re-log, since the day
  // is this table's key.
  if (date != null && dayKeyOf(day) != dayKeyOf(date)) {
    await repo.deleteBodyweight(dayKeyOf(date));
  }
  await repo.logBodyweight(day, kg);
}
