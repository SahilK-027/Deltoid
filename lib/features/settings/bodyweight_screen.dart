import 'package:drift/drift.dart' hide Column, Table;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/calendar.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/trend_chart.dart';
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

/// The log, as a shape rather than as a scroll.
///
/// It was one row per weighing, newest first, forever: a year of daily weights
/// is 365 rows, and the question you open this screen with — "where is it
/// going" — was the one thing 365 dated numbers could not answer. The trend is
/// on top now, and the past is a month at a time, collapsed: `March 2026 ·
/// 76.4 avg · −0.8`, opening to its days when you want one.
class _MonthList extends StatefulWidget {
  const _MonthList({required this.log, required this.unit});

  final List<BodyweightLog> log;
  final WeightUnit unit;

  @override
  State<_MonthList> createState() => _MonthListState();
}

class _MonthListState extends State<_MonthList> {
  /// The current month, open. Every other month is a summary until asked —
  /// the days you might correct are the ones you just logged.
  final _open = <String>{};
  bool _seeded = false;

  /// How far back the chart looks. Not a filter on the list: the list is the
  /// record, the chart is the reading.
  TrendWindow _window = const TrendWindow.rolling(ChartRange.threeMonths);

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final unit = widget.unit;
    final months = groupByMonth(log);
    if (!_seeded && months.isNotEmpty) {
      _seeded = true;
      _open.add(months.first.label);
    }

    // Where each month begins in [log], so a month's first row still reads
    // against the last entry of the month before it rather than losing its
    // delta at the seam.
    final starts = <int>[];
    var offset = 0;
    for (final month in months) {
      starts.add(offset);
      offset += month.entries.length;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, Space.lg, Space.gutter, Space.huge),
      children: [
        const SectionHeader('Trend'),
        _TrendCard(
          log: log,
          unit: unit,
          window: _window,
          onWindow: (w) => setState(() => _window = w),
        ),
        const SizedBox(height: Space.section),
        SectionHeader(
          'By month',
          trailing: Text(
            '${log.length} logged',
            style: context.t.bodySmall,
          ),
        ),
        ListCard(
          inset: Space.lg,
          children: [
            for (var m = 0; m < months.length; m++) ...[
              _MonthRow(
                month: months[m],
                previous: m + 1 < months.length ? months[m + 1] : null,
                unit: unit,
                open: _open.contains(months[m].label),
                onTap: () => setState(() {
                  final label = months[m].label;
                  _open.contains(label)
                      ? _open.remove(label)
                      : _open.add(label);
                }),
              ),
              if (_open.contains(months[m].label))
                _MonthDays(
                  entries: months[m].entries,
                  // The entry before each one in time, wherever it lives — a
                  // month's first row still reads against the last of the
                  // month before it rather than losing its delta at the seam.
                  previousOf: (i) => starts[m] + i + 1 < log.length
                      ? log[starts[m] + i + 1]
                      : null,
                  unit: unit,
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A month's days, opened.
///
/// On `surfaceHigh` and indented, because as plain rows in the same card they
/// were indistinguishable from the months around them: `July 2026` and
/// `Fri 31 Jul` in the same type, on the same ground, with the same divider
/// between them, so a list of five months and twenty days read as twenty-five
/// peers. A child has to look like a child.
class _MonthDays extends StatelessWidget {
  const _MonthDays({
    required this.entries,
    required this.previousOf,
    required this.unit,
  });

  final List<BodyweightLog> entries;
  final BodyweightLog? Function(int index) previousOf;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.surfaceHigh,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: Space.xxxl),
                child: Divider(color: c.border, height: 1),
              ),
            _EntryRow(
              entry: entries[i],
              previous: previousOf(i),
              unit: unit,
            ),
          ],
        ],
      ),
    );
  }
}

/// One month, closed: what it averaged and which way it went.
///
/// The average rather than the latest weight, because a month is a period and
/// the last day of it is a measurement — a single morning after a salty dinner
/// is the number least worth summarising a month with.
class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.month,
    required this.previous,
    required this.unit,
    required this.open,
    required this.onTap,
  });

  final BodyweightMonth month;

  /// The month before it in time, for the change between the two averages.
  final BodyweightMonth? previous;

  final WeightUnit unit;
  final bool open;
  final VoidCallback onTap;

  static double _average(BodyweightMonth m) =>
      m.entries.fold(0.0, (sum, e) => sum + e.weightKg) / m.entries.length;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final average = _average(month);
    final before = previous == null ? null : _average(previous!);
    final delta =
        before == null ? null : formatDeltaInUnit(average, before, unit);

    return AppRow(
      title: month.label,
      subtitle: '${month.entries.length} '
          'weigh-in${month.entries.length == 1 ? '' : 's'}',
      onTap: onTap,
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
            '${formatInUnit(average, unit)} ${unit.label}',
            style: context.t.titleSmall?.copyWith(fontFeatures: tabular),
          ),
          const SizedBox(width: Space.sm),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: Motion.fast,
            curve: Motion.curve,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: c.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// How far back the trend looks.
/// Weight over time, on the same chart and the same range control as an
/// exercise's history — `1W 1M 3M 1Y` and a year picker, not a second dialect
/// (`3m 6m 1y All`) invented for this one screen.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.log,
    required this.unit,
    required this.window,
    required this.onWindow,
  });

  /// Newest first, as the provider gives it.
  final List<BodyweightLog> log;

  final WeightUnit unit;
  final TrendWindow window;
  final ValueChanged<TrendWindow> onWindow;

  @override
  Widget build(BuildContext context) {
    // Oldest first, which is the direction a chart reads.
    final points = [
      for (final e in log.reversed)
        if (window.contains(e.dayKey)) e,
    ];

    final latest = log.first;
    final change = points.length < 2
        ? null
        : formatDeltaInUnit(points.last.weightKg, points.first.weightKg, unit);

    // Only years there is something to look at.
    final years = {for (final e in log) e.dayKey ~/ 10000}.toList()
      ..sort((a, b) => b.compareTo(a));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The number leads and the date is the caption: this is a metric
          // card, not a session (THEME §5, the metric screen).
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatInUnit(latest.weightKg, unit),
                style: context.t.displaySmall,
              ),
              const SizedBox(width: Space.xs),
              Text(unit.label, style: context.t.bodyMedium),
              const Spacer(),
              if (change != null)
                Text('$change over the range', style: context.t.bodySmall),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            DateFormat('EEE d MMM yyyy').format(dateFromDayKey(latest.dayKey)),
            style: context.t.bodyMedium,
          ),
          const SizedBox(height: Space.lg),
          if (points.length < 2)
            EmptyBox(
              icon: Icons.timeline,
              message: points.isEmpty
                  ? 'Nothing logged in this range.'
                  : 'One weigh-in in this range — a second one gives this a '
                      'shape.',
            )
          else
            TrendChart(
              height: 190,
              series: [
                TrendSeries(
                  name: 'Bodyweight',
                  color: context.c.data,
                  spots: [
                    for (final e in points)
                      FlSpot(trendX(e.dayKey), unit.fromKg(e.weightKg)),
                  ],
                ),
              ],
              formatValue: (v) => formatInUnit(unit.toKg(v), unit),
              tooltip: (v) => '${formatInUnit(unit.toKg(v), unit)} '
                  '${unit.label}',
            ),
          const SizedBox(height: Space.lg),
          TrendRangeBar(window: window, years: years, onChanged: onWindow),
        ],
      ),
    );
  }
}

/// One dated weight, inside its month.
///
/// Tapping it opens the same sheet the `+` does, which is where correcting and
/// deleting both live — a delete button on every row is eighty tap targets for
/// a thing done twice a year (§7).
///
/// Not an [AppRow]: a row nested under another row has to *read* as nested, so
/// the date is `body` where its month is `title`, and it starts a column in
/// from the month's text rather than on the same vertical.
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

    return Pressable(
      scale: 0.99,
      onTap: () => logBodyweightPrompt(
        context,
        ref,
        date: dateFromDayKey(entry.dayKey),
        initial: entry.weightKg,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.xxxl, Space.md, Space.lg, Space.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEE d MMM').format(dateFromDayKey(entry.dayKey)),
                style: context.t.bodyMedium,
              ),
            ),
            if (delta != null) ...[
              Text(
                delta,
                style: context.t.labelSmall?.copyWith(color: c.textTertiary),
              ),
              const SizedBox(width: Space.md),
            ],
            Text(
              '${formatInUnit(entry.weightKg, unit)} ${unit.label}',
              style: context.t.labelLarge,
            ),
          ],
        ),
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
    final picked = await pickDay(
      context,
      initial: _day,
      title: 'When was this weight?',
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
