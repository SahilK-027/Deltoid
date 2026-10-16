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
import 'home_providers.dart';
import 'widgets/heatmap.dart';
import 'widgets/year_heatmap.dart';

/// The newest weight and how many there are. The trend card leads with the
/// first, and the screen shows its empty state while there is none.
typedef BodyweightSummary = ({BodyweightLog? latest, int count});

/// One row and a number, rather than the whole table to work them out from.
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

/// Every weigh-in: where the weight is going, then how often it was taken.
///
/// Pushed from the Weigh-ins habit tile on Home, in the place of the
/// Bodyweight screen Settings used to open (THEME → The destinations). The
/// trend card leads because "where is it going" is what the screen is opened
/// with. The year maps under it answer the habit's own question, how often a
/// weight was taken, in the design Consistency answers it for training.
///
/// There is no list of entries. An old weigh-in is reached through the
/// calendar in the app bar, which finds a day by its date where a list made
/// it a scroll through months.
class WeighInsScreen extends ConsumerWidget {
  const WeighInsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(bodyweightSummaryProvider).valueOrNull;
    final days = ref.watch(weighInDaysProvider).valueOrNull;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final latest = summary?.latest;

    return Scaffold(
      // Pushed, not a destination: the small centred title, not a masthead (THEME → Components).
      appBar: AppBar(
        title: const Text('Weigh-ins'),
        actions: [
          CircleIconButton(
            icon: Icons.edit_calendar_outlined,
            tooltip: 'Correct a weigh-in',
            onTap: () => correctWeighInPrompt(context, ref),
          ),
          const SizedBox(width: Space.gutter),
        ],
      ),
      // One more entry in what the screen lists, so it floats as the compact
      // primary rather than spanning the foot (THEME → Buttons). Hidden while
      // the empty state is up, whose own button is the same action.
      floatingActionButton: latest == null
          ? null
          : PrimaryButton(
              compact: true,
              label: 'Log weight',
              icon: Icons.add_rounded,
              onPressed: () => logTodaysWeight(context, ref),
            ),
      body: switch ((summary, days)) {
        // Local disk: a spinner here would show for two frames.
        (null, _) || (_, null) => const SizedBox.shrink(),
        _ when latest == null => EmptyState(
            icon: Icons.monitor_weight_outlined,
            title: 'No weights logged',
            message: 'Needed to score bodyweight and bodyweight-plus '
                'lifts. Seven pull-ups at your lightest are not the '
                'same lift as seven at your heaviest.',
            action: PrimaryButton(
              label: 'Log weight',
              onPressed: () => logTodaysWeight(context, ref),
            ),
          ),
        (_, final d?) => _WeighIns(latest: latest, days: d, unit: unit),
      },
    );
  }
}

class _WeighIns extends ConsumerWidget {
  const _WeighIns({
    required this.latest,
    required this.days,
    required this.unit,
  });

  final BodyweightLog latest;

  /// Every day with a weigh-in, as day keys.
  final Set<int> days;

  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final first = dateFromDayKey(days.reduce((a, b) => a < b ? a : b));
    final total = days.length;

    // Weigh-ins per year, counted once here rather than by each year block
    // walking the whole set.
    final byYear = <int, int>{};
    for (final key in days) {
      byYear[key ~/ 10000] = (byYear[key ~/ 10000] ?? 0) + 1;
    }
    // Newest first, as on Consistency: scrolling down goes back in time.
    final years = [for (var y = now.year; y >= first.year; y--) y];
    // The years the trend's picker offers: only those with a weigh-in in them.
    final logged = [for (final y in years) if (byYear.containsKey(y)) y];
    final maps = WeighInYearDays(days);

    // `.builder` for the reason Consistency uses it: a year map per year,
    // and only the ones on screen are painted.
    return ListView.builder(
      // Room under the last year for the floating button to clear it. The
      // page runs under the system navigation bar and the button sits above
      // it, so the bar's height is added: without it the last year stopped
      // under the button on a phone with three-button navigation.
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.huge * 2 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: years.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Trend'),
              _TrendCard(
                latest: latest,
                years: logged,
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
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.section),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total weigh-in${total == 1 ? '' : 's'} since '
                  '${DateFormat('MMMM y').format(first)}',
                  style: context.t.titleMedium,
                ),
                const SizedBox(height: Space.md),
                const HeatmapLegend.weighIns(),
              ],
            ),
          );
        }

        final year = years[i - 2];
        final count = byYear[year] ?? 0;
        return Padding(
          padding: EdgeInsets.only(
            bottom: i == years.length + 1 ? 0 : Space.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                '$year',
                trailing: Text(
                  '$count weigh-in${count == 1 ? '' : 's'}',
                  style: context.t.bodySmall,
                ),
              ),
              AppCard(
                // The padding Consistency's year cards use, for the reason
                // given there: the month strip carries its own slack.
                padding: const EdgeInsets.fromLTRB(
                    Space.md, Space.md, Space.md, Space.sm),
                child: YearHeatmap(year: year, days: maps),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Today's weight: logs it, or opens it for correcting if it is already there.
///
/// What the `+` on the Weigh-ins tile and `Log weight` on this screen both
/// open. A second weigh-in on the same day replaces the first, so offering an
/// empty field over a weight already logged today would overwrite it without
/// showing what it replaced.
Future<void> logTodaysWeight(BuildContext context, WidgetRef ref) async {
  final series = await ref.read(trainingRepositoryProvider).bodyweightSeries();
  if (!context.mounted) return;
  final today = dayKeyOf(DateTime.now());
  final kg = series.where((p) => p.dayKey == today).firstOrNull?.weightKg;
  await logBodyweightPrompt(
    context,
    ref,
    date: kg == null ? null : dateFromDayKey(today),
    initial: kg,
  );
}

/// The way to an old weigh-in: the day picker with every weighed day ringed in
/// [DeltoidColors.weighIn], then the weigh-in sheet on the day picked.
///
/// A weighed day opens its entry as `Edit bodyweight`, with the row that
/// deletes it. Any other day opens `Log bodyweight` dated that day, for a
/// weigh-in that was taken and never entered. Days after today are out of
/// range.
Future<void> correctWeighInPrompt(BuildContext context, WidgetRef ref) async {
  final series = await ref.read(trainingRepositoryProvider).bodyweightSeries();
  if (!context.mounted) return;
  final weights = {for (final p in series) p.dayKey: p.weightKg};
  final mark = context.c.weighIn;

  final day = await pickDay(
    context,
    initial: DateTime.now(),
    marks: {for (final key in weights.keys) key: mark},
    title: 'Correct a weigh-in',
  );
  if (day == null || !context.mounted) return;

  await logBodyweightPrompt(
    context,
    ref,
    date: day,
    initial: weights[dayKeyOf(day)],
  );
}

/// How far back the bodyweight chart looks, and how it averages.
///
/// Providers rather than `State`, because the route is what disposes it: held
/// in the screen's state, picking 1M and coming back to the screen later draws
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
                  color: context.c.progress,
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

/// Logs or corrects one weight.
///
/// [date] and [initial] are set when correcting an existing entry;
/// `logBodyweight` upserts by day, so editing is simply a re-log. [date] alone
/// dates a new entry, which is how the correction calendar logs a missed day.
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

  final result = await showAppSheet<_BodyweightResult>(
    context,
    builder: (sheet) => _BodyweightSheet(
      unit: unit,
      date: date,
      initial: initial,
      logged: logged,
    ),
  );
  if (result == null) return;

  if (result.delete) {
    await repo.deleteBodyweight(dayKeyOf(date ?? result.day));
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

  /// Correcting an entry that exists, rather than logging one on a day that
  /// may be in the past. The correction calendar opens a day with no weigh-in
  /// dated, and that sheet has nothing to delete.
  bool get _editing => widget.initial != null;

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
      // Ringed, as the session pickers ring a trained day, in the weigh-in
      // colour rather than the trained day's blue. A weigh-in calendar is
      // opened to find the day that was missed, and a grid of identical white
      // numbers is the one thing that cannot answer that.
      marks: {
        for (final key in widget.logged) key: context.c.weighIn,
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
