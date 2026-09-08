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
import '../../data/db/watch.dart';
import '../../domain/chart_buckets.dart';
import '../../domain/units.dart';

/// One month of the log, summarised — never its entries.
///
/// [ym] is the day key with the day dropped: `202608`. It is the month's
/// identity everywhere, including as the key of the provider that loads its
/// days.
typedef BodyweightMonth = ({
  int ym,
  String label,
  int count,
  double averageKg,
});

String monthLabel(int ym) =>
    DateFormat('MMMM yyyy').format(DateTime(ym ~/ 100, ym % 100));

/// Every month with a weigh-in in it, newest first, averaged **in SQLite**.
///
/// Holding the whole table in memory and grouping it in Dart means one row per
/// day for as long as the app has been owned. At fifty years that is 18 250
/// rows — a hundred milliseconds to fetch and map, and another hundred to
/// group, because grouping formats a month label *per row*. Both would run on
/// the UI isolate and re-run on every weigh-in, which is a wait every time this
/// screen opens. `GROUP BY` does the same work in eight, and the count and
/// average are exactly what a closed month shows.
///
/// A month's *days* are a separate query, made when the month is opened
/// ([bodyweightMonthProvider]).
final bodyweightMonthsProvider = StreamProvider<List<BodyweightMonth>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchQuery([db.bodyweightLogs], () async {
    final rows = await db.customSelect(
      'SELECT day_key / 100 AS ym, AVG(weight_kg) AS avg_kg, COUNT(*) AS n '
      'FROM bodyweight_logs WHERE deleted_at IS NULL '
      'GROUP BY ym ORDER BY ym DESC',
      readsFrom: {db.bodyweightLogs},
    ).get();
    return [
      for (final r in rows)
        (
          ym: r.read<int>('ym'),
          label: monthLabel(r.read<int>('ym')),
          count: r.read<int>('n'),
          averageKg: r.read<double>('avg_kg'),
        ),
    ];
  });
});

/// The newest weight and how many there are — the two figures Settings shows
/// and the two the header of this screen leads with.
typedef BodyweightSummary = ({BodyweightLog? latest, int count});

/// Settings read the whole table for this. It wanted one row and a number.
final bodyweightSummaryProvider = StreamProvider<BodyweightSummary>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchQuery([db.bodyweightLogs], () async {
    final latest = await (db.select(db.bodyweightLogs)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.dayKey, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
    final count = await db.customSelect(
      'SELECT COUNT(*) AS n FROM bodyweight_logs WHERE deleted_at IS NULL',
      readsFrom: {db.bodyweightLogs},
    ).getSingle();
    return (latest: latest, count: count.read<int>('n'));
  });
});

/// Every weigh-in, oldest first — the log, not the window.
///
/// **Not keyed on the window, deliberately.** A `.family` per [TrendWindow]
/// makes changing range a *different provider*, so the chart card loses its
/// data for a frame and `TrendChart` is unmounted and rebuilt — throwing away
/// the zoom in [TrendChart.didUpdateWidget] that every other chart in the app
/// gets. One provider, filtered in Dart, keeps the same chart on screen
/// across a range change, exactly as `exercise_trend.dart` does.
///
/// It reads the two columns the chart plots positionally off a `QueryRow`
/// rather than hydrating a whole `BodyweightLog` per point, which is drift's
/// most expensive path and pays for columns nothing here reads. `All` already
/// asked for the whole log, so this is the cost that window already had.
final bodyweightRangeProvider = StreamProvider.autoDispose<
    List<({int dayKey, double weightKg})>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchQuery([db.bodyweightLogs], () async {
    final rows = await db.customSelect(
      'SELECT day_key AS day_key, weight_kg AS weight_kg '
      'FROM bodyweight_logs WHERE deleted_at IS NULL ORDER BY day_key',
      readsFrom: {db.bodyweightLogs},
    ).get();
    return [
      for (final r in rows)
        (dayKey: r.read<int>('day_key'), weightKg: r.read<double>('weight_kg')),
    ];
  });
});

/// One month's days, newest first, and the entry immediately before them.
///
/// [before] is what keeps a month's first row from losing its delta at the
/// seam: the change it shows is against the last weigh-in of the month before,
/// wherever that is.
typedef BodyweightDays = ({List<BodyweightLog> entries, BodyweightLog? before});

/// Loaded when a month is opened, dropped when it is closed — `autoDispose`,
/// because a fifty-year log opened month by month should not accumulate.
final bodyweightMonthProvider =
    StreamProvider.autoDispose.family<BodyweightDays, int>((ref, ym) {
  final db = ref.watch(databaseProvider);
  final first = ym * 100;
  final last = ym * 100 + 31;
  return db.watchQuery([db.bodyweightLogs], () async {
    final entries = await (db.select(db.bodyweightLogs)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.dayKey.isBiggerOrEqualValue(first) &
              t.dayKey.isSmallerOrEqualValue(last))
          ..orderBy([
            (t) => OrderingTerm(expression: t.dayKey, mode: OrderingMode.desc)
          ]))
        .get();
    final before = await (db.select(db.bodyweightLogs)
          ..where((t) =>
              t.deletedAt.isNull() & t.dayKey.isSmallerThanValue(first))
          ..orderBy([
            (t) => OrderingTerm(expression: t.dayKey, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
    return (entries: entries, before: before);
  });
});

class BodyweightScreen extends ConsumerWidget {
  const BodyweightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(bodyweightMonthsProvider).valueOrNull;
    final summary = ref.watch(bodyweightSummaryProvider).valueOrNull;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    return Scaffold(
      // Pushed, not a destination: the small centred title, not a masthead (THEME → Components).
      appBar: AppBar(
        title: const Text('Bodyweight'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Log bodyweight',
            onPressed: () => logBodyweightPrompt(context, ref),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: months == null || summary == null
          ? const Center(child: CircularProgressIndicator())
          : summary.latest == null
              ? EmptyState(
                  icon: Icons.monitor_weight_outlined,
                  title: 'No weights logged',
                  message: 'Needed to score bodyweight and bodyweight-plus '
                      'lifts. Seven pull-ups at your lightest are not the '
                      'same lift as seven at your heaviest.',
                  action: FilledButton(
                    onPressed: () => logBodyweightPrompt(context, ref),
                    child: const Text('Log bodyweight'),
                  ),
                )
              : _MonthList(
                  months: months,
                  latest: summary.latest!,
                  total: summary.count,
                  unit: unit,
                ),
    );
  }
}

/// The log, as a shape rather than as a scroll.
///
/// One row per weighing, newest first, forever, is 365 rows for a year of daily
/// weights — and the question this screen is opened with, "where is it going",
/// is the one thing 365 dated numbers cannot answer. So the trend sits on top,
/// and the past is a month at a time, collapsed: `March 2026 · 76.4 avg ·
/// −0.8`, opening to its days when you want one.
/// How far back the bodyweight chart looks, and how it averages.
///
/// Providers rather than `State`, because the route is what disposes it: held
/// in `_MonthListState`, picking 1M and coming back to the screen later draws
/// 3M again, the widget having been rebuilt from its initialiser. A range is a
/// way of looking at the log, and it should still be how you are looking at it
/// when you return.
///
/// Not shared with `chartRangeProvider`: a bodyweight range and an exercise's
/// range are two questions, and moving one to move the other is a surprise.
/// Deliberately not persisted to `app_settings` either — this is where you
/// left the screen, not a setting you chose, and a fresh launch may as well
/// open on the default.
final bodyweightWindowProvider = StateProvider<TrendWindow>(
  (ref) => const TrendWindow.rolling(ChartRange.threeMonths),
);

/// The averaging the user picked, or null for "let the range decide". See
/// [chartGranularityProvider] for why the choice is stored and not the
/// granularity it resolved to.
final bodyweightGranularityProvider = StateProvider<Granularity?>((ref) => null);

class _MonthList extends ConsumerStatefulWidget {
  const _MonthList({
    required this.months,
    required this.latest,
    required this.total,
    required this.unit,
  });

  final List<BodyweightMonth> months;
  final BodyweightLog latest;
  final int total;
  final WeightUnit unit;

  @override
  ConsumerState<_MonthList> createState() => _MonthListState();
}

class _MonthListState extends ConsumerState<_MonthList> {
  /// The months that are open, by [BodyweightMonth.ym]. Every other month is a
  /// summary until asked — the days you might correct are the ones you just
  /// logged — and only an open month's days are ever queried.
  final _open = <int>{};
  bool _seeded = false;

  /// Years there is something to look at, for the picker. Derived from the
  /// month summaries, which is at most one entry per month rather than one per
  /// weigh-in, and recomputed only when those change.
  List<int> _years = const [];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_MonthList old) {
    super.didUpdateWidget(old);
    if (!identical(old.months, widget.months)) _sync();
  }

  void _sync() {
    _years = {for (final m in widget.months) m.ym ~/ 100}.toList()
      ..sort((a, b) => b.compareTo(a));
    if (!_seeded && widget.months.isNotEmpty) {
      _seeded = true;
      _open.add(widget.months.first.ym);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;

    // `.builder`, and one card per month rather than one card holding every
    // month. A `ListView` with a `children:` list builds every one of them
    // before the first frame: fifty years is six hundred month rows, each with
    // its own average and delta, all constructed to show the eight that fit on
    // screen. That is the whole of this screen's slowness.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, Space.lg, Space.gutter, Space.huge),
      // Two headers and the chart, then a card per month.
      itemCount: widget.months.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Trend'),
              _TrendCard(
                latest: widget.latest,
                years: _years,
                unit: unit,
                window: ref.watch(bodyweightWindowProvider),
                onWindow: (w) =>
                    ref.read(bodyweightWindowProvider.notifier).state = w,
                granularity: ref.watch(bodyweightGranularityProvider),
                onGranularity: (g) =>
                    ref.read(bodyweightGranularityProvider.notifier).state = g,
              ),
              const SizedBox(height: Space.section),
            ],
          );
        }
        if (i == 1) {
          return SectionHeader(
            'By month',
            trailing: Text(
              '${widget.total} logged',
              style: context.t.bodySmall,
            ),
          );
        }

        final m = i - 2;
        final month = widget.months[m];
        final last = m == widget.months.length - 1;
        final open = _open.contains(month.ym);
        return Padding(
          // The hairline between months, drawn as a gap: one card each, so a
          // month that is closed costs one row and nothing else.
          padding: EdgeInsets.only(bottom: last ? 0 : 1),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(m == 0 ? Radii.card : 0),
              bottom: Radius.circular(last ? Radii.card : 0),
            ),
            child: ColoredBox(
              color: context.c.surface,
              child: Column(
                children: [
                  _MonthRow(
                    month: month,
                    previous: last ? null : widget.months[m + 1],
                    unit: unit,
                    open: open,
                    onTap: () => setState(() {
                      open ? _open.remove(month.ym) : _open.add(month.ym);
                    }),
                  ),
                  // Animated to its height rather than appearing: the days are
                  // what the month row opens, and a fold that arrives in one
                  // frame reads as a different list rather than as this one
                  // opening.
                  AnimatedSize(
                    duration: Motion.base,
                    curve: Motion.emphasized,
                    alignment: Alignment.topCenter,
                    child: !open
                        ? const SizedBox(width: double.infinity)
                        : _MonthDays(ym: month.ym, unit: unit),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A month's days, opened.
///
/// On `surfaceHigh` and indented: as plain rows in the same card they are
/// indistinguishable from the months around them — `July 2026` and `Fri 31 Jul`
/// in the same type, on the same ground, with the same divider between them, so
/// a list of five months and twenty days reads as twenty-five peers. A child
/// has to look like a child.
/// Its days are queried when it opens and dropped when it closes, so the cost
/// of this screen is the months you are looking at rather than every weighing
/// you have ever recorded. Nothing is drawn until they arrive: a month is
/// thirty rows off an indexed key, and a spinner for that flashes.
class _MonthDays extends ConsumerWidget {
  const _MonthDays({required this.ym, required this.unit});

  final int ym;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final days = ref.watch(bodyweightMonthProvider(ym)).valueOrNull;
    if (days == null) return const SizedBox(width: double.infinity);

    final entries = days.entries;
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
            _WeighInRow(
              entry: entries[i],
              // The entry before this one in time — the last of the month
              // before, once the list runs out — so a month's first row keeps
              // its delta at the seam.
              previous: i + 1 < entries.length ? entries[i + 1] : days.before,
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

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Both averages came out of `AVG(weight_kg)`; nothing here reads a row.
    final average = month.averageKg;
    // A month holding one weigh-in has no trend of its own, and its "average"
    // is that single measurement. Printing a month-on-month change beside it
    // put two answers to one question two lines apart: the month read
    // `+0.2 · 168.7` over its only entry reading `−0.2 · 168.7`. Both were
    // right — the month compared averages, the entry compared itself to the
    // weigh-in before it — and a reader has no way to know that, so the app
    // simply looked as though it could not add up. Where there is no month
    // shaped change to report, the row says nothing and the entry underneath
    // carries the one comparison that is local and unambiguous.
    final delta = previous == null || month.count == 1
        ? null
        : formatBodyweightDelta(average, previous!.averageKg, unit);

    return AppRow(
      title: month.label,
      subtitle: '${month.count} weigh-in${month.count == 1 ? '' : 's'}',
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
            '${formatBodyweight(average, unit)} ${unit.label}',
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
class _TrendCard extends ConsumerWidget {
  const _TrendCard({
    required this.latest,
    required this.years,
    required this.unit,
    required this.window,
    required this.onWindow,
    required this.granularity,
    required this.onGranularity,
  });

  /// The newest weigh-in, which the card leads with whatever the window is.
  final BodyweightLog latest;

  /// Years there is something to look at, for the picker.
  final List<int> years;

  final WeightUnit unit;
  final TrendWindow window;
  final ValueChanged<TrendWindow> onWindow;

  /// Null means auto.
  final Granularity? granularity;
  final ValueChanged<Granularity?> onGranularity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Oldest first, which is the direction a chart reads — and the query
    // returns the window rather than the log, though on `All` those are the
    // same thing.
    final all = ref.watch(bodyweightRangeProvider).valueOrNull;
    if (all == null) {
      return const AppCard(
        child: SizedBox(height: 260, child: Center(child: SizedBox.shrink())),
      );
    }

    // The window is cut here rather than in the query so that changing range
    // keeps the same chart on screen and zooms it.
    final points = window.isAll
        ? all
        : [for (final p in all) if (window.contains(p.dayKey)) p];

    // The change over the range is the *log's* first and last reading, not the
    // first and last bucket: averaging is how the line is drawn, and this line
    // is a fact about two weigh-ins.
    final change = points.length < 2
        ? null
        : formatBodyweightDelta(
            points.last.weightKg, points.first.weightKg, unit);

    // `All` starts where the log does. Every other window knows its own left
    // edge, and for `All` the query returned everything, so the first row is it.
    final earliest = !window.isAll || points.isEmpty
        ? null
        : dateFromDayKey(points.first.dayKey);
    final (from, to) = window.xBoundsSince(earliest);
    final by = resolveGranularity(granularity, daysBetween(from, to));

    // Plotted in display units, which is what the axis and the tooltip read in.
    // The mean of a week of weigh-ins is a weigh-in; the sum of them is not a
    // weight anybody has ever been.
    final marks = [
      for (final b in bucketize(
        rows: [
          for (final e in points)
            (dayKey: e.dayKey, value: unit.fromKg(e.weightKg)),
        ],
        by: by,
        from: from,
        to: to,
      ))
        if (b.value != null) b,
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The number leads and the date is the caption: this is a metric
          // card, not a session (THEME → Components → Charts).
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              ValueUnit(
                value: formatBodyweight(latest.weightKg, unit),
                unit: unit.label,
              ),
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
          if (marks.length < 2)
            // The chart, empty, rather than a box where the chart was: the
            // range chips under it stay a zoom rather than a thing that
            // resizes the card (THEME → Charts).
            EmptyTrendChart(
              height: 190,
              window: window,
              earliest: earliest,
              // Scaled around the last weigh-in, in the same display units the
              // real chart plots in. An axis with no numbers on it reads as a
              // chart that failed to draw (THEME → Charts).
              scale: (
                unit.fromKg(latest.weightKg) - 5,
                unit.fromKg(latest.weightKg) + 5,
              ),
              formatValue: (v) => formatBodyweight(unit.toKg(v), unit),
              message: marks.isEmpty
                  ? 'Nothing logged in this range.'
                  : 'Only one ${by.noun} has a weigh-in. A second one is '
                      'needed before a trend can be drawn.',
            )
          else
            TrendChart(
              height: 190,
              window: window,
              earliest: earliest,
              series: [
                TrendSeries(
                  name: 'Bodyweight',
                  color: context.c.seriesPrimary,
                  spots: [
                    for (final b in marks) FlSpot(bucketX(b), b.value!),
                  ],
                ),
              ],
              formatValue: (v) => formatBodyweight(unit.toKg(v), unit),
              tooltip: (v) => '${formatBodyweight(unit.toKg(v), unit)} '
                  '${unit.label}',
            ),
          const SizedBox(height: Space.lg),
          TrendRangeBar(
            window: window,
            years: years,
            onChanged: onWindow,
            earliest: earliest,
            granularity: by,
            granularityIsAuto: granularity == null,
            onGranularity: onGranularity,
          ),
        ],
      ),
    );
  }
}

/// One dated weight, inside its month.
///
/// Tapping it opens the same sheet the `+` does, which is where correcting and
/// deleting both live — a delete button on every row is eighty tap targets for
/// a thing done twice a year (THEME → Composing a screen).
///
/// Not an [AppRow]: a row nested under another row has to *read* as nested, so
/// the date is `body` where its month is `title`, and it starts a column in
/// from the month's text rather than on the same vertical.
class _WeighInRow extends ConsumerWidget {
  const _WeighInRow({
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
        : formatBodyweightDelta(entry.weightKg, previous!.weightKg, unit);

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
              '${formatBodyweight(entry.weightKg, unit)} ${unit.label}',
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
/// space (THEME → Components).
Future<void> logBodyweightPrompt(
  BuildContext context,
  WidgetRef ref, {
  DateTime? date,
  double? initial,
}) async {
  final unit = ref.read(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
  final repo = ref.read(trainingRepositoryProvider);

  // The days already weighed, so the picker can say which they are. The same
  // series the chart plots — two columns per day, read before the sheet opens
  // rather than from inside it, because the picker is a dialog over a sheet and
  // a day that appears once its query lands is a grid that changes under the
  // thumb.
  final logged = {for (final p in await repo.bodyweightSeries()) p.dayKey};
  if (!context.mounted) return;

  final result = await showModalBottomSheet<_BodyweightResult>(
    // The route holds the system bars: a sheet that sizes itself can
    // otherwise run under the status bar. See [pickExercise].
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) => _BodyweightSheet(
      unit: unit,
      date: date,
      initial: initial,
      logged: logged,
    ),
  );
  if (result == null) return;

  if (result.delete) {
    await repo.deleteBodyweight(dayKeyOf(date!));
    return;
  }

  // The day the sheet was opened over has no bearing on the day it saves to.
  // Correcting the date used to *move* the entry, so opening the sheet over
  // today's weight and picking yesterday deleted today's — and a missing
  // weigh-in shows up nowhere, it is simply interpolated across, quietly
  // rescoring every bodyweight lift around it. A day is cleared by deleting it.
  //
  // Typed in whatever this phone shows, stored in kilograms.
  await repo.logBodyweight(result.day, unit.toKg(result.value));
}

/// Past this and it is a typo, not a bodyweight. Matches the check on
/// `bodyweight_logs.weight_kg`, which is what makes this a guard rather than
/// the only thing standing between a slip and a rewritten history.
const _maxBodyweightKg = 500.0;

/// What the sheet came back with: a weight on a day, or a deletion.
typedef _BodyweightResult = ({DateTime day, double value, bool delete});

class _BodyweightSheet extends StatefulWidget {
  const _BodyweightSheet({
    required this.unit,
    required this.date,
    required this.initial,
    required this.logged,
  });

  final WeightUnit unit;
  final DateTime? date;
  final double? initial;

  /// The day keys already weighed, marked in the picker.
  final Set<int> logged;

  @override
  State<_BodyweightSheet> createState() => _BodyweightSheetState();
}

class _BodyweightSheetState extends State<_BodyweightSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatBodyweight(widget.initial!, widget.unit),
  );
  late DateTime _day = widget.date ?? DateTime.now();

  bool get _editing => widget.date != null;

  /// The typed weight, or null when it is not one.
  ///
  /// Bounded at both ends, and the ceiling earns its place as much as the
  /// floor: this number is not read on its own. It is interpolated between its
  /// neighbours and multiplied into every pull-up and dip around it, so a
  /// mistyped `1850` silently rescales weeks of history either side of the day
  /// it lands on while showing one figure that merely looks wrong. The column
  /// refuses it outright, so without this the Save button would simply fail.
  double? get _value {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed <= 0) return null;
    return widget.unit.toKg(parsed) >= _maxBodyweightKg ? null : parsed;
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
      // The same marking the session pickers use. A weigh-in calendar is opened
      // to find the day that was missed, and a grid of identical white numbers
      // is the one thing that cannot answer that.
      marks: {
        for (final key in widget.logged) key: context.c.heatOn,
      },
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
            // `valueSm`, the size every other number you type in this app is
            // entered at — the set row's load and reps, the rest seconds. Not
            // `value` (22), the size a number is *displayed* at once it is a
            // fact on a card: a field wearing a readout's type reads as a
            // headline being edited.
            style: context.t.labelLarge,
            cursorColor: c.textPrimary,
            // The app's only suffix, and the second named exception in
            // THEME → Fields: `kg` sits beside the number at `labelSmall` so it
            // reads as a unit rather than as part of the value.
            decoration: InputDecoration(
              suffixText: widget.unit.label,
              suffixStyle:
                  context.t.labelSmall?.copyWith(color: c.textSecondary),
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
