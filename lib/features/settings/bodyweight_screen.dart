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

/// Every bodyweight entry, newest first.
///
/// Unlimited on purpose. Settings used to read a query capped at 30, which was
/// fine as a readout and wrong the moment entries became editable: a typo from
/// two months ago was unreachable, and bodyweight silently scales the score of
/// every bodyweight and weighted lift. It also made the count under the figure
/// stop at "30 logged" forever.
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

/// One month of entries under its own heading.
typedef BodyweightMonth = ({String label, List<BodyweightLog> entries});

/// Groups a newest-first log by calendar month.
///
/// A flat list of two hundred dated rows has nothing to hold on to — the year
/// is repeated on every line and the gap where you stopped weighing yourself
/// is invisible. Months give the list its headings and, missing, say the same
/// thing by absence.
List<BodyweightMonth> groupByMonth(List<BodyweightLog> log) {
  final months = <BodyweightMonth>[];
  for (final entry in log) {
    final label =
        DateFormat('MMMM yyyy').format(dateFromDayKey(entry.dayKey));
    if (months.isEmpty || months.last.label != label) {
      months.add((label: label, entries: [entry]));
    } else {
      months.last.entries.add(entry);
    }
  }
  return months;
}

class BodyweightScreen extends ConsumerWidget {
  const BodyweightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(bodyweightHistoryProvider).valueOrNull;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    return Scaffold(
      // Pushed, not a destination: the small centred title, not a masthead (§5).
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
              : _MonthList(log: log, unit: unit),
    );
  }
}

class _MonthList extends StatelessWidget {
  const _MonthList({required this.log, required this.unit});

  final List<BodyweightLog> log;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final months = groupByMonth(log);
    // Where each month begins in [log], so a month's first row still reads
    // against the last entry of the month before it rather than losing its
    // delta at the seam.
    final starts = <int>[];
    var offset = 0;
    for (final month in months) {
      starts.add(offset);
      offset += month.entries.length;
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, Space.lg, Space.gutter, Space.huge),
      itemCount: months.length,
      itemBuilder: (context, m) {
        final month = months[m];
        final start = starts[m];
        return Padding(
          padding: EdgeInsets.only(top: m == 0 ? 0 : Space.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(month.label),
              ListCard(
                inset: Space.lg,
                children: [
                  for (var i = 0; i < month.entries.length; i++)
                    _EntryRow(
                      entry: month.entries[i],
                      // The entry before it in time, wherever it lives.
                      previous: start + i + 1 < log.length
                          ? log[start + i + 1]
                          : null,
                      unit: unit,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One dated weight. Tapping it opens the same sheet the `+` does, which is
/// where correcting and deleting both live — a delete button on every row is
/// eighty tap targets for a thing done twice a year (§7).
class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.entry,
    required this.previous,
    required this.unit,
  });

  final BodyweightLog entry;
  final BodyweightLog? previous;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final delta = previous == null
        ? null
        : formatDeltaInUnit(entry.weightKg, previous!.weightKg, unit);

    return AppRow(
      title: DateFormat('EEE d MMM').format(dateFromDayKey(entry.dayKey)),
      onTap: () => logBodyweightPrompt(
        context,
        ref,
        date: dateFromDayKey(entry.dayKey),
        initial: entry.weightKg,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (delta != null) ...[
            Text(
              delta,
              style: context.t.labelSmall?.copyWith(color: c.textTertiary),
            ),
            const SizedBox(width: Space.md),
          ],
          Text(
            '${formatInUnit(entry.weightKg, unit)} ${unit.label}',
            style: context.t.titleSmall?.copyWith(fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}

/// Logs or corrects one weight.
///
/// [date] and [initial] are set when correcting an existing entry;
/// `logBodyweight` upserts by day, so editing is simply a re-log.
///
/// A sheet, not a dialog: it is a text field, and a centred `AlertDialog`
/// opens in the middle of the screen and then fights the keyboard for the same
/// space (§5).
Future<void> logBodyweightPrompt(
  BuildContext context,
  WidgetRef ref, {
  DateTime? date,
  double? initial,
}) async {
  final unit = ref.read(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

  final result = await showModalBottomSheet<_BodyweightResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: _BodyweightSheet(
        unit: unit,
        date: date,
        initial: initial,
      ),
    ),
  );
  if (result == null) return;

  final repo = ref.read(trainingRepositoryProvider);

  if (result.delete) {
    await repo.deleteBodyweight(dayKeyOf(date!));
    return;
  }

  // Moving an entry to another date is a delete plus a re-log, since the day
  // is this table's key.
  if (date != null && dayKeyOf(result.day) != dayKeyOf(date)) {
    await repo.deleteBodyweight(dayKeyOf(date));
  }
  // Typed in whatever this phone shows, stored in kilograms.
  await repo.logBodyweight(result.day, unit.toKg(result.value));
}

/// What the sheet came back with: a weight on a day, or a deletion.
typedef _BodyweightResult = ({DateTime day, double value, bool delete});

class _BodyweightSheet extends StatefulWidget {
  const _BodyweightSheet({
    required this.unit,
    required this.date,
    required this.initial,
  });

  final WeightUnit unit;
  final DateTime? date;
  final double? initial;

  @override
  State<_BodyweightSheet> createState() => _BodyweightSheetState();
}

class _BodyweightSheetState extends State<_BodyweightSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatInUnit(widget.initial!, widget.unit),
  );
  late DateTime _day = widget.date ?? DateTime.now();

  bool get _editing => widget.date != null;

  double? get _value {
    final parsed = double.tryParse(_controller.text.trim());
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _value;
    if (value == null) return;
    Navigator.of(context)
        .pop((day: _day, value: value, delete: false));
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'Delete this weight?',
      message: '${DateFormat('d MMM yyyy').format(_day)} will no longer be '
          'used to score bodyweight lifts.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop((day: _day, value: 0.0, delete: true));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppSheet(
      title: _editing ? 'Edit bodyweight' : 'Log bodyweight',
      footer: PrimaryButton(
        label: 'Save',
        onPressed: _value == null ? null : _save,
      ),
      // Full-width rows with the field carrying its own gutter, which is how
      // every other sheet that mixes the two is built. A card in here would be
      // a panel inside a panel.
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.lg, Space.lg, Space.sm),
          child: TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            style: context.t.displaySmall?.copyWith(fontFeatures: tabular),
            cursorColor: c.textPrimary,
            decoration: InputDecoration(
              suffixText: widget.unit.label,
              suffixStyle:
                  context.t.titleSmall?.copyWith(color: c.textSecondary),
              filled: true,
              fillColor: c.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
                borderSide: BorderSide(color: c.textPrimary, width: 2),
              ),
              contentPadding: const EdgeInsets.all(Space.lg),
            ),
          ),
        ),
        // Weighing yourself and logging it are rarely the same moment.
        AppRow(
          title: DateFormat('EEE d MMM yyyy').format(_day),
          icon: Icons.calendar_today_outlined,
          onTap: _pickDay,
          chevron: true,
        ),
        if (_editing)
          AppRow(
            title: 'Delete this weight',
            icon: Icons.delete_outline,
            tint: c.negative,
            onTap: _delete,
          ),
      ],
    );
  }
}
