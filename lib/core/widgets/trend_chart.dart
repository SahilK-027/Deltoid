import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/chart_buckets.dart';
import '../ids.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// The one line chart in the app, and the one range control above it.
///
/// One of each, because a chart is a language rather than a widget written per
/// screen. Written twice — once for an exercise's e1RM, once for bodyweight —
/// the second copy comes out with a different range control (`3m 6m 1y All` in
/// a segmented pill against `1W 1M 3M 1Y` in chips), no edge suppression on the
/// axes and no calendar-aware tick spacing, printing `Dec 19Jul 26` and
/// `330 Jul` on top of themselves.

// ─── Range ──────────────────────────────────────────────────────────────────

/// The rolling windows, shortest first.
///
/// Whole calendar years and the complete log are separate selections, presented
/// as the chips at the end of the row.
///
/// [days] is how far back the window extends from today, inclusive of today, so
/// that a week is six days back and seven days on the axis. `1W` therefore
/// labels the seven days ending with the current one rather than eight days
/// with a partial period at each end.
enum ChartRange {
  week('1W', 6),
  month('1M', 30),
  threeMonths('3M', 90),
  sixMonths('6M', 182),
  year('1Y', 365);

  const ChartRange(this.label, this.days);

  final String label;
  final int days;
}

/// What a chart is showing: a window ending today, one calendar year, or the
/// whole log.
class TrendWindow {
  const TrendWindow.rolling(ChartRange this.range)
      : year = null,
        isAll = false;
  const TrendWindow.calendar(int this.year)
      : range = null,
        isAll = false;

  /// Everything there is. Its left edge is not a date this class knows — it is
  /// wherever the log starts — so a chart drawing it hands its earliest day to
  /// [xBoundsSince]. Asked for bounds without one, it falls back to a year,
  /// which is what an empty log's "All" honestly is.
  const TrendWindow.all()
      : range = null,
        year = null,
        isAll = true;

  /// Set when the window rolls back from today.
  final ChartRange? range;

  /// Set when the window is a whole calendar year.
  final int? year;

  final bool isAll;

  bool get isRolling => range != null;

  /// What the chip says.
  String get label => isAll ? 'All' : (range?.label ?? '$year');

  bool contains(int dayKey) => dayKey >= fromDayKey && dayKey <= toDayKey;

  /// The window expressed as x-axis bounds, which allows a chart with no data
  /// to render the requested time axis.
  ///
  /// [earliest] is the first day for which the chart has data, and is read only
  /// by `All`. [toDayKey] is deliberately unbounded above for a rolling window,
  /// since every such window ends today and an axis cannot be drawn to the year
  /// 9999.
  (DateTime, DateTime) xBoundsSince([DateTime? earliest]) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (year != null) {
      return (DateTime(year!, 1, 1), DateTime(year!, 12, 31));
    }
    if (isAll) {
      final first = earliest == null
          ? daysBefore(today, 365)
          : DateTime(earliest.year, earliest.month, earliest.day);
      // Never inverted and never a single day: "All" on a log with one entry in
      // it is still a chart, and a span of zero has no width to divide.
      return first.isBefore(today) ? (first, today) : (daysBefore(today, 6), today);
    }
    return (daysBefore(today, range!.days), today);
  }

  /// The window as day-key bounds, so a query can ask for it rather than a
  /// screen filtering everything it has ever stored.
  int get fromDayKey => switch (this) {
        _ when isAll => 0,
        _ when year != null => year! * 10000,
        _ => dayKeyOf(daysBefore(DateTime.now(), range!.days)),
      };

  int get toDayKey => year != null ? year! * 10000 + 1231 : 99999999;

  @override
  bool operator ==(Object other) =>
      other is TrendWindow &&
      other.range == range &&
      other.year == year &&
      other.isAll == isAll;

  @override
  int get hashCode => Object.hash(range, year, isAll);
}

// ─── The time axis ──────────────────────────────────────────────────────────

/// A gridline's dash: four points drawn, four left out. One pattern for every
/// chart, line or bar, since THEME has them share their gridlines.
const gridlineDash = <int>[4, 4];

/// How many date labels a chart draws, whatever it is showing.
///
/// Seven, always. It is enough to read a year by its months and few enough that
/// a phone can print them without collision, and holding it constant is what
/// makes changing range read as a zoom rather than as a different chart: the
/// labels stay where they are and only their words change.
///
/// Public because the bar charts print the same seven, so both kinds of chart
/// are read at the same rhythm.
const axisLabelCount = 7;

/// The x axis of a window: where it starts, where it ends, and where the labels
/// go.
///
/// Anchored on the right. Every rolling range ends today, so the last label is
/// today and the remainder are counted back from it. Laying labels out from the
/// left edge instead causes `1W` to print whichever day the data happens to
/// begin on, and never to print today.
class TimeAxis {
  const TimeAxis({
    required this.minX,
    required this.maxX,
    required this.interval,
    required this.baseline,
    required this.format,
  });

  /// Built for [window], padded outward by half a step so the first and last
  /// labels are strictly inside the plot and have room to print. Without the
  /// padding they sit on the edges, where a label has half a line of space and
  /// prints over its neighbour.
  /// [zoom] is the pinch scale: `1` denotes the whole window and `4` a quarter
  /// of it on screen. The label sequence is derived from the visible span, so
  /// zooming into a decade converts years into months rather than emptying the
  /// axis. The label count remains seven and only the resolution changes.
  factory TimeAxis.of(
    TrendWindow window, {
    DateTime? earliest,
    double zoom = 1,
  }) {
    final (start, end) = window.xBoundsSince(earliest);
    final from = _x(start);
    final to = _x(end);
    final span = (to - from).abs();
    final visible = zoom > 1 ? span / zoom : span;
    final step = visible <= 0 ? 1.0 : visible / (axisLabelCount - 1);
    return TimeAxis(
      minX: from - step / 2,
      maxX: to + step / 2,
      interval: step,
      // The ladder hangs off the last day rather than the first — see the class
      // doc. `fl_chart` phases its ticks against `baselineX`, so this is the
      // one number that decides whether today gets a label.
      baseline: to,
      format: axisDateFormat(visible),
    );
  }

  final double minX;
  final double maxX;
  final double interval;
  final double baseline;

  /// An `intl` pattern, chosen by how much time is on screen.
  final String format;

  String label(double value) => DateFormat(format).format(
        DateTime.fromMillisecondsSinceEpoch((value * 86400000).round()),
      );

  static double _x(DateTime d) => d.millisecondsSinceEpoch / 86400000;
}

/// The one control every chart in the app is driven by: how much time, which
/// year, and how finely it is averaged.
///
/// Chips, not a segmented pill: the pill is for a control that governs the page
/// under it, and this one governs a card. It is also eight choices wide once the
/// years and the averaging arrive, which is a scroll rather than a track.
///
/// The averaging chip is a chart control rather than a preference. It occupies
/// the same row as the range because it answers the same question — how much
/// time one mark represents — and placing it in a separate menu would leave the
/// chart smoothed with no on-screen indication.
class TrendRangeBar extends StatelessWidget {
  const TrendRangeBar({
    super.key,
    required this.window,
    required this.years,
    required this.onChanged,
    this.ranges = ChartRange.values,
    this.showAll = true,
    this.granularity,
    this.granularityIsAuto = true,
    this.onGranularity,
    this.granularities = Granularity.values,
    this.granularityCeiling = 3000,
    this.earliest,
  });

  final TrendWindow window;

  /// The first day there is data for, which only `All` reads — the same value
  /// the chart under this bar is drawn against, so the two agree about how much
  /// time `All` is.
  final DateTime? earliest;

  /// Whether `All` is offered. A screen whose query cannot honestly answer
  /// "everything" leaves it out rather than showing a chip that lies.
  final bool showAll;

  /// The averaging currently in force: the value the chip displays and the
  /// chart renders.
  ///
  /// Null on a chart that does not average, in which case the chip is omitted
  /// rather than displayed inert.
  final Granularity? granularity;

  /// Whether [granularity] was selected automatically rather than by the user.
  ///
  /// The chip renders identically in both cases, since what the chart is doing
  /// is the relevant fact rather than how that was arrived at. The picker
  /// requires the distinction in order to mark the correct row.
  final bool granularityIsAuto;

  /// Called with null when `Auto` is selected. The caller stores the absence of
  /// a choice rather than the granularity automatic selection resolved to at
  /// that moment; otherwise a subsequent window change would find the chart
  /// fixed at a level the user did not request.
  final ValueChanged<Granularity?>? onGranularity;

  /// The averaging levels the calling screen is able to render at all. Weekly
  /// volume has no daily reading, so that screen omits it permanently.
  ///
  /// The picker offers this list narrowed to the levels the selected range can
  /// display; see [granularitiesFor]. Yearly granularity over one month yields
  /// a single point, and a picker offering it would misrepresent the result.
  final List<Granularity> granularities;

  /// The most marks this screen's chart can draw at all — see
  /// [granularitiesFor]. A line carries thousands; a bar needs width.
  final int granularityCeiling;

  /// The levels on offer right now: what this screen supports, kept to what the
  /// window can show.
  List<Granularity> get _offered {
    final (from, to) = window.xBoundsSince(earliest);
    final fits = granularitiesFor(
      daysBetween(from, to),
      ceiling: granularityCeiling,
    );
    final out = [
      for (final g in granularities)
        if (fits.contains(g)) g,
    ];
    // Never empty, and never without the one in force — a picker that cannot
    // display the level currently in force is worse than one offering a short
    // list.
    if (out.isEmpty) return [?granularity, ...fits.take(1)];
    return out;
  }

  /// The rolling windows offered, shortest first.
  ///
  /// All of them, unless a screen cannot meaningfully render one: weekly volume
  /// bars over `1W` produce a single bar, so that screen supplies only the three
  /// that yield a chart.
  ///
  /// A subset rather than a per-screen control, so that the chips, the year
  /// picker and the sheet remain a single component and a screen cannot acquire
  /// a second range control with different spacing (THEME → Charts).
  final List<ChartRange> ranges;

  /// The years containing data, newest first. A picker offering 2019 for a log
  /// beginning in 2024 would list empty charts.
  final List<int> years;

  final ValueChanged<TrendWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    // A track rather than a scrolling strip. Eight chips in a row exceed the
    // width of a phone, and a control that must be dragged sideways before it
    // can be read conceals half its options: `All` cannot be selected if its
    // presence is not apparent. The ranges form a segmented track that fits by
    // construction, with equal segments at any width and no scrolling.
    //
    // The two pickers go underneath rather than beside, because they are a
    // different question. The track asks *how much time*; the row under it says
    // which slice and how finely, and both of those open a sheet.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedPill<TrendWindow>(
          expand: true,
          value: _trackValue,
          onChanged: onChanged,
          segments: [
            for (final r in ranges)
              (value: TrendWindow.rolling(r), label: r.label),
            if (showAll) (value: const TrendWindow.all(), label: 'All'),
          ],
        ),
        if (years.isNotEmpty || (granularity != null && onGranularity != null))
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Row(
              children: [
                if (years.isNotEmpty) ...[
                  AppChip(
                    label: '${window.year ?? years.first}',
                    icon: Icons.calendar_today_rounded,
                    selected: window.year != null,
                    caret: true,
                    onTap: () => _pickYear(context),
                  ),
                  // Side by side, not pushed to opposite edges. They are two
                  // halves of the same question — which slice, how finely — and
                  // a gap between them reads as two unrelated controls that
                  // happen to share a line.
                  const SizedBox(width: Space.sm),
                ],
                if (granularity != null && onGranularity != null)
                  AppChip(
                    label: granularity!.label,
                    icon: Icons.stacked_line_chart_rounded,
                    // Never *selected*: averaging is always on — there is no
                    // state in which a chart draws raw rows — so a filled chip
                    // would be lit permanently and stop meaning anything.
                    caret: true,
                    onTap: () => _pickGranularity(context),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Which segment reads as selected. A calendar year is not one of them — it is
  /// the chip underneath — so while a year is showing, the track shows none.
  TrendWindow get _trackValue =>
      window.year != null ? const TrendWindow.calendar(-1) : window;

  Future<void> _pickGranularity(BuildContext context) async {
    final picked = await showAppSheet<Object>(
      context,
      builder: (sheet) => AppSheet(
        title: 'Average by',
        contentPadding: const EdgeInsets.fromLTRB(
            Space.gutter, 0, Space.gutter, Space.lg),
        children: [
          AppRow(
            title: 'Auto',
            // Named, because "auto" with nothing after it is a setting whose
            // effect cannot be verified. It also varies with the range, which
            // is its purpose and is not apparent without this line.
            subtitle: 'Currently ${granularity?.label.toLowerCase()}',
            onTap: () => Navigator.of(sheet).pop(_auto),
            trailing: AppRadio(selected: granularityIsAuto),
          ),
          for (final g in _offered)
            AppRow(
              title: g.label,
              onTap: () => Navigator.of(sheet).pop(g),
              trailing: AppRadio(selected: !granularityIsAuto && granularity == g),
            ),
        ],
      ),
    );
    if (picked == null) return;
    onGranularity?.call(picked is Granularity ? picked : null);
  }

  /// The sentinel `Auto` pops, since `null` already means "dismissed".
  static const _auto = Object();

  Future<void> _pickYear(BuildContext context) async {
    final picked = await showAppSheet<int>(
      context,
      // Twenty years of training is a list longer than a phone.
      capped: true,
      builder: (sheet) => AppSheet(
        title: 'Which year?',
        // The default padding, minus the top the header already provides.
        // `only(bottom:)` would drop the sheet's side gutter as well, running
        // these rows edge to edge while every other sheet's stay inset.
        contentPadding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.lg,
        ),
        children: [
          for (final year in years)
            AppRow(
              title: '$year',
              onTap: () => Navigator.of(sheet).pop(year),
              trailing: AppRadio(selected: year == window.year),
            ),
        ],
      ),
    );
    if (picked == null) return;
    onChanged(TrendWindow.calendar(picked));
  }
}

// ─── The plot ───────────────────────────────────────────────────────────────

/// One line on a [TrendChart].
class TrendSeries {
  const TrendSeries({
    required this.name,
    required this.color,
    required this.spots,
  });

  final String name;
  final Color color;

  /// x is [trendX] of a day key, y is the value in display units.
  final List<FlSpot> spots;
}

/// Day key → days since the epoch, so the x axis is real time. Otherwise a
/// six-week gap in the log looks identical to a week.
double trendX(int dayKey) =>
    dateFromDayKey(dayKey).millisecondsSinceEpoch / 86400000;

/// The position of a bucket on the time axis: its midpoint rather than its
/// first day.
///
/// A month plotted on the 1st is drawn half a month early, and at yearly
/// granularity a mark for 2019 would land on New Year's Day and read as the
/// wrong year entirely. Daily buckets are a single day, so the middle is the
/// day and nothing moves.
double bucketX(Bucket bucket) =>
    (bucket.start.millisecondsSinceEpoch + bucket.end.millisecondsSinceEpoch) /
    2 /
    86400000;

/// The chart from THEME → Components: dashed horizontal gridlines only, labels
/// on the right, no border, markers while they still mark something, horizontal
/// zoom.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.series,
    required this.formatValue,
    this.window,
    this.earliest,
    this.tooltip,
    this.yRange,
    this.height = 220,
  });

  /// The range the chart is *of*, rather than the range its data happens to
  /// cover. Given one, the axis runs the whole window — so an untrained
  /// fortnight is visible as an untrained fortnight, the last label is today,
  /// and changing range zooms a fixed frame instead of re-fitting to whatever
  /// came back. Without one the chart fits its own data, which is what a
  /// sparkline with no axis wants.
  final TrendWindow? window;

  /// The first day the chart has anything for, which only `All` reads.
  final DateTime? earliest;

  final List<TrendSeries> series;

  /// A y value as it should be read — with its unit applied, without its unit
  /// printed. The axis is inches from the tooltip, and one of them rendering
  /// kilograms while the other says pounds is the worst kind of units bug.
  final String Function(double value) formatValue;

  /// The whole tooltip line, unit and all. Null disables touch entirely.
  final String Function(double value)? tooltip;

  final double height;

  /// The band the value axis covers, when the caller knows better than the
  /// spots do.
  ///
  /// A chart that plots its complete history and uses the window only to
  /// choose what is on screen — which is what makes changing range a zoom
  /// rather than a redraw — cannot scale its axis to its spots, because its
  /// spots are all of them. So the screen works out what is visible and says so
  /// here, and the axis animates between the two rather than jumping.
  final (double, double)? yRange;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart>
    with SingleTickerProviderStateMixin {
  /// Changing the range is rendered as a change of scale rather than as a
  /// redraw.
  ///
  /// Two things change when a new range is selected, and they conflict: the
  /// bounds must travel, and the data must be re-aggregated at a resolution
  /// suited to the new span. A year of weeks is not the same list of points as
  /// three months of days, and no interpolation exists between two lists of
  /// different lengths. Applying both at once reads as a rebuild.
  ///
  /// They are therefore separated in time. The bounds animate while the
  /// previously rendered line is retained and scaled with them, which produces
  /// the zoom; the new resolution is applied at the end of that motion, where a
  /// change of detail within the same shape is largely imperceptible.
  /// THEME → Charts specifies that axis furniture cross-fades rather than
  /// travels, and this applies the same rule at one level up.
  late final AnimationController _zoomTo = AnimationController(
    vsync: this,
    duration: Motion.base,
    value: 1,
  )..addListener(_onZoom);

  /// The bounds the chart is travelling *from*, and the series drawn while it
  /// travels. Null once it has arrived.
  ({double minX, double maxX, double minY, double maxY})? _from;
  List<TrendSeries>? _held;

  /// Held rather than left to `fl_chart` so the axis can *listen* to it. The
  /// labels belong to what is on screen, and after a pinch what is on screen is
  /// no longer the window — see [_visibleAxis].
  final _zoom = TransformationController();

  /// The bounds actually drawn last frame, so a change mid-flight travels from
  /// where it is rather than from where the last one started.
  ({double minX, double maxX, double minY, double maxY})? _drawn;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
  }

  @override
  void dispose() {
    _zoom.removeListener(_onZoom);
    _zoom.dispose();
    _zoomTo.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrendChart old) {
    super.didUpdateWidget(old);
    // Only a change of *range* zooms. New data in the same window moves a point
    // and nothing else — animating a zoom when a set is ticked would make
    // logging look like navigating (THEME → Charts).
    if (old.window == widget.window) return;

    _from = _drawn;
    _held = old.series;
    _zoomTo.forward(from: 0);
    _zoomTo.addStatusListener(_release);
  }

  void _release(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _zoomTo.removeStatusListener(_release);
    if (!mounted) return;
    setState(() {
      _held = null;
      _from = null;
    });
  }

  void _onZoom() {
    if (mounted) setState(() {});
  }

  /// How far in the pinch currently is. `1` is the whole window.
  double get _scale {
    final s = _zoom.value.entry(0, 0);
    return s.isFinite && s > 0 ? s : 1;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The line being drawn: the one held from before the range changed while it
    // is still travelling, the real one once it has arrived.
    final series = _held ?? widget.series;
    final height = widget.height;
    final formatValue = widget.formatValue;
    final tooltip = widget.tooltip;
    final window = widget.window;
    final all = [for (final s in series) ...s.spots];

    final xs = [for (final s in all) s.x];
    final ys = [for (final s in all) s.y];
    final lowest = widget.yRange?.$1 ?? ys.reduce(min);
    final highest = widget.yRange?.$2 ?? ys.reduce(max);

    // The axis describes what is on screen rather than the window. After a
    // pinch the two differ, and labels that continue to describe the window
    // describe a chart that is no longer displayed. Seven labels are drawn at
    // any zoom level, which is what allows zooming in to report position rather
    // than removing the dates.
    final axis = window == null
        ? null
        : TimeAxis.of(window, earliest: widget.earliest, zoom: _scale);

    // One session is a chart with one dot on it, and a dot is worth drawing —
    // it establishes the current position, on the axis the next point is read
    // against. Its
    // span is zero days, though, and an axis from a day to itself has no width
    // to divide, so a fortnight of air is put either side of it.
    var minX = axis?.minX ?? xs.reduce(min);
    var maxX = axis?.maxX ?? xs.reduce(max);
    if (maxX - minX < 1) {
      minX -= 7;
      maxX += 7;
    }

    // Bounds snapped to a round step, so every gridline lands on a number a
    // person would say. Left to itself the axis labels `1126.5` at the
    // extremes, which wraps onto two lines and collides with the gridline
    // above. The band is the data plus air — never anchored at zero, which
    // draws a year of bodyweight as a flat line an inch off the bottom.
    final step = _niceStep((highest - lowest) / 4);
    var maxY = ((highest + step * 0.5) / step).ceilToDouble() * step;
    var minY = ((lowest - step * 0.5) / step).floorToDouble() * step;
    // Nothing this app charts is negative, so the air under the lowest point
    // stops at zero rather than drawing an axis into numbers that cannot exist.
    if (lowest >= 0 && minY < 0) minY = 0;

    // The bounds at this instant, part way between the previous range and the
    // selected one. `fl_chart` interpolates its own data changes but cannot
    // interpolate between two spot lists of different lengths, which is what a
    // change of resolution produces, so the transition is driven here.
    final t = Motion.emphasized.transform(_zoomTo.value);
    final was = _from;
    if (was != null && t < 1) {
      minX = _lerp(was.minX, minX, t);
      maxX = _lerp(was.maxX, maxX, t);
      minY = _lerp(was.minY, minY, t);
      maxY = _lerp(was.maxY, maxY, t);
    }
    _drawn = (minX: minX, maxX: maxX, minY: minY, maxY: maxY);

    final spanDays = maxX - minX;
    final xInterval = axis?.interval ?? _niceDayStep(spanDays / 4);
    final dense = all.length > 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            // Changing the range or averaging rescales the chart rather than
            // reloading it. The box retains its size and `fl_chart`
            // interpolates its contents: the axis bounds rescale and the line
            // travels to its new shape, so widening from three months to a year
            // reads as a change of scale rather than as a different chart.
            // `base` at the emphasized curve, which THEME § 6 gives anything
            // covering a distance.
            duration: Motion.base,
            curve: Motion.emphasized,
            // Pinch to zoom the time axis, drag to pan. The vertical axis stays
            // fixed: scaling the value axis freely would render identical
            // progress differently depending on the last pinch.
            transformationConfig: FlTransformationConfig(
              scaleAxis: FlScaleAxis.horizontal,
              minScale: 1,
              maxScale: 12,
              transformationController: _zoom,
            ),
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              // The tick ladder hangs off this. `fl_chart` phases its labels
              // against the baseline, so anchoring it on the last day is what
              // puts a label on today and counts the rest back from it.
              baselineX: axis?.baseline ?? minX,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: c.border, strokeWidth: 1, dashArray: gridlineDash),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                // Right-hand Y labels (THEME → Components): the left gutter is where the
                // eye starts a row, and spending it on an axis pushes the plot
                // off centre on a phone.
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: step,
                    reservedSize: axisGutter(
                      context,
                      _yTicks(minY, maxY, step).map(formatValue),
                    ),
                    getTitlesWidget: (value, meta) => _edgeSafe(
                      value,
                      meta,
                      Text(
                        formatValue(value),
                        style: context.t.bodySmall,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: xInterval,
                    // The padded edges are half a step outside the window and
                    // are not dates anybody asked about.
                    minIncluded: false,
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) => _edgeSafe(
                      value,
                      meta,
                      Text(
                        axis?.label(value) ??
                            DateFormat(axisDateFormat(spanDays)).format(
                              DateTime.fromMillisecondsSinceEpoch(
                                (value * 86400000).round(),
                              ),
                            ),
                        style: context.t.bodySmall,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: tooltip == null
                  ? const LineTouchData(enabled: false)
                  : LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => c.surfaceHigh,
                        getTooltipItems: (spots) => [
                          for (final s in spots)
                            LineTooltipItem(
                              tooltip(s.y),
                              context.t.labelMedium!
                                  .copyWith(color: c.textPrimary),
                            ),
                        ],
                      ),
                    ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: s.spots,
                    isCurved: false,
                    color: s.color,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: !dense,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 3,
                        color: c.bg,
                        strokeWidth: 2,
                        strokeColor: s.color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Markers only while they mark something. Past about forty points the
        // circles touch and the shape being examined is obscured by the points
        // composing it, so the markers are dropped and the gesture is labelled
        // instead.
        if (dense) ...[
          const SizedBox(height: Space.sm),
          Text(
            'Pinch to zoom and drag to pan.',
            style: context.t.bodySmall?.copyWith(color: c.textTertiary),
          ),
        ],
        if (series.length > 1) ...[
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.sm,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: s.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(s.name, style: context.t.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

}

/// The same plot with no data: the gridlines, the right-hand gutter and the
/// time axis of the selected range, with no series rendered.
///
/// A captioned box would be the wrong shape in two respects. An empty range is
/// not a failure to render a chart; it is a chart of a period in which no
/// training occurred. A box half the height of the plot also causes the page to
/// shift when ranges are changed. The axis remains accurate by remaining empty:
/// no value labels, because there is no data to scale them against, and no
/// series at zero, because a point the metric cannot score is not a zero
/// (THEME → Charts).
class EmptyTrendChart extends StatelessWidget {
  const EmptyTrendChart({
    super.key,
    required this.window,
    this.earliest,
    this.message,
    this.scale,
    this.formatValue,
    this.height = 220,
  });

  final TrendWindow window;

  /// The first day the chart has anything for, which only `All` reads.
  final DateTime? earliest;

  /// The explanation for the empty state, rendered beneath the plot in the same
  /// style as the zoom hint rather than across it.
  ///
  /// A sentence within the chart area reads as a dialog inside a chart frame,
  /// whereas a line beneath it reads as a caption and leaves the element above
  /// it a graph. Null while the underlying query is still in flight: "nothing
  /// logged" is an assertion, and a frame that has not yet read the log cannot
  /// make it.
  final String? message;

  /// The band the value axis should cover: the movement's complete history,
  /// where the selected range contains no data.
  ///
  /// This is what preserves an empty range as a range. The values remain in
  /// position, so moving from a trained year to an untrained month reads as an
  /// empty section of the same chart rather than as a different widget. Null
  /// only when nothing has ever been logged, in which case the axis is drawn
  /// without values, there being no accurate value to display.
  final (double, double)? scale;

  /// A y value as it should be read, exactly as [TrendChart.formatValue].
  final String Function(double value)? formatValue;

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final axis = TimeAxis.of(window, earliest: earliest);

    // The same treatment [TrendChart] gives a real band: data plus air, snapped
    // to a round step. With no data at all it is a bare 0–1, unlabelled, which
    // draws four gridlines and claims nothing.
    final (lowest, highest) = scale ?? (0.0, 1.0);
    final step = _niceStep((highest - lowest) / 4);
    final maxY = ((highest + step * 0.5) / step).ceilToDouble() * step;
    var minY = ((lowest - step * 0.5) / step).floorToDouble() * step;
    if (lowest >= 0 && minY < 0) minY = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            // The empty chart rescales with the same motion as a populated
            // one, so ranging across an untrained period is a single continuous
            // transition rather than a chart, a discontinuity, and a chart.
            duration: Motion.base,
            curve: Motion.emphasized,
            LineChartData(
              minX: axis.minX,
              maxX: axis.maxX,
              minY: minY,
              maxY: maxY,
              baselineX: axis.baseline,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: c.border, strokeWidth: 1, dashArray: gridlineDash),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: step,
                    // Held open even when there is nothing to write in it, so
                    // the plot does not widen the moment data lands.
                    reservedSize: axisGutter(context, [
                      if (formatValue case final f?)
                        ..._yTicks(minY, maxY, step).map(f),
                    ]),
                    getTitlesWidget: (value, meta) {
                      final format = formatValue;
                      if (scale == null || format == null) {
                        return const SizedBox.shrink();
                      }
                      return _edgeSafe(
                        value,
                        meta,
                        Text(
                          format(value),
                          style: context.t.bodySmall,
                          maxLines: 1,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: axis.interval,
                    minIncluded: false,
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) => _edgeSafe(
                      value,
                      meta,
                      Text(
                        axis.label(value),
                        style: context.t.bodySmall,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: const [],
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            message!,
            style: context.t.bodySmall?.copyWith(color: c.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// The width of the right-hand gutter containing the value labels, measured
/// rather than assumed.
///
/// A constant sized for the widest value a chart might print, such as 52 or 36,
/// causes every chart printing `70` and `102` to surrender a third of that
/// gutter, and the time axis beneath it loses the corresponding width. Laying
/// out the labels costs one text measurement each per build and returns the
/// unused width to the plot.
///
/// Stable rather than intrinsic: it is derived from the axis bounds, so it
/// changes when the chart rescales and not when a value within it moves. The
/// plot therefore cannot shift horizontally while a line is being updated.
///
/// **Measured over every tick, not the two bounds.** Inter's figures are
/// proportional — `1` is 833 units where `0` is 1292 — so a label is not as
/// wide as its digit count. An axis running 185 to 215 measures its gutter on
/// bounds that both contain a `1`, then prints `200` and `205`, which do not,
/// into a box a quarter of an em too small. A side title is clipped rather than
/// reported as overflowing, so the axis quietly reads `20` and nothing raises a
/// word about it. See [_yTicks].
///
/// Public because the bar chart measures its gutter the same way. [gap] is the
/// room a chart puts between the plot and its labels: `fl_chart`'s side title
/// spends `Space.xs` of the reserved size on it, and the bar chart lays the
/// same gap out beside the gutter rather than inside it, so passes none.
double axisGutter(
  BuildContext context,
  Iterable<String> labels, {
  double gap = Space.xs,
}) {
  final style = context.t.bodySmall;
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
    )..layout();
    if (painter.width > widest) widest = painter.width;
  }
  // The label, the gap before it, and a point of air so a rounded glyph does
  // not touch the card's padding.
  return widest + gap + 2;
}

/// Every value the y axis will label, so the gutter can be measured against
/// what is actually printed in it.
///
/// `fl_chart` walks the ticks from the lower bound in steps of `interval`, and
/// [_edgeSafe] then drops the two sitting on the bounds; the labels that survive
/// are the interior ones — precisely the set a gutter measured on the bounds
/// does not account for. The bounds are included anyway: they cost one
/// measurement each, and a gutter a glyph too wide is invisible where one a
/// glyph too narrow is the defect this exists to prevent.
///
/// A step that cannot divide the band — zero, negative, or so fine the axis
/// would carry hundreds of ticks — falls back to the bounds rather than
/// looping. Nothing in the app produces one, and an axis is not the place to
/// discover otherwise.
List<double> _yTicks(double minY, double maxY, double step) {
  if (!step.isFinite || step <= 0 || maxY < minY) return [minY, maxY];
  final count = (maxY - minY) / step;
  if (!count.isFinite || count > 64) return [minY, maxY];
  return [
    for (var i = 0; i <= count.ceil(); i++)
      if (minY + step * i <= maxY) minY + step * i,
    maxY,
  ];
}

/// A tick at the very edge has half a line of room and ends up printed over
/// its neighbour — `Dec 19Jul 26`, `330 Jul`. Both axes drop theirs.
Widget _edgeSafe(double value, TitleMeta meta, Widget child) {
  if (value <= meta.min || value >= meta.max) return const SizedBox.shrink();
  return SideTitleWidget(meta: meta, space: Space.xs, child: child);
}

/// Label resolution follows the span, or four ticks a day apart all render as
/// the same month and overlap into mush.
///
/// A week is labelled by its days, as `Fri Sat Sun … Thu`, because at that
/// range the day of the week is the relevant distinction.
///
/// Public because the bar charts read their labels by the same rule. Two kinds
/// of chart may draw different marks; they may not name the same fortnight two
/// different ways (THEME → Charts).
String axisDateFormat(double spanDays) {
  if (spanDays <= 8) return 'EEE';
  if (spanDays <= 45) return 'd MMM';
  if (spanDays <= 400) return 'MMM';
  if (spanDays <= 365 * 8) return "MMM ''yy";
  return 'yyyy';
}

/// The nearest round number at or above [raw], from the 1 / 2.5 / 5 / 10
/// family, so gridlines land on numbers a person would say.
double _niceStep(double raw) {
  if (raw <= 0) return 1;
  final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
  for (final multiple in const [1, 2, 2.5, 5, 10]) {
    final step = magnitude * multiple;
    if (step >= raw) return step;
  }
  return magnitude * 10;
}

/// The same idea on the time axis, in units a calendar has: a week, a
/// fortnight, a month, a quarter, a year. Ticks every 97 days label three
/// different months and read as noise.
double _lerp(double a, double b, double t) => a + (b - a) * t;

double _niceDayStep(double raw) {
  for (final step in const [7.0, 14.0, 30.0, 61.0, 91.0, 182.0, 365.0]) {
    if (step >= raw) return step;
  }
  return (raw / 365).ceilToDouble() * 365;
}
