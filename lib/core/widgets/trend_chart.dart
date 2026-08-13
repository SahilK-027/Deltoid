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
/// Both were written twice — once for an exercise's e1RM, once for bodyweight —
/// and the second copy came out with a different range control (`3m 6m 1y All`
/// in a segmented pill against `1W 1M 3M 1Y` in chips), no edge suppression on
/// the axes, and no calendar-aware tick spacing, so it printed `Dec 19Jul 26`
/// and `330 Jul` on top of themselves. A chart is a language, not a widget you
/// write per screen.

// ─── Range ──────────────────────────────────────────────────────────────────

/// The rolling windows, shortest first. Whole calendar years and *everything*
/// are the other two questions, and they are the chips at the end of the row.
///
/// [days] is how far back the window opens **from today, inclusive of today** —
/// so a week is six days back and seven days on the axis, and `1W` labels the
/// seven days ending with the one you are standing in rather than eight days
/// with a stump on each end.
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

  /// The window as x-axis bounds, which is what lets a chart with nothing in it
  /// still draw the time axis you asked for.
  ///
  /// [earliest] is the first day the chart has data for, and only `All` reads
  /// it. [toDayKey] is deliberately open at the top for a rolling window — every
  /// one of them ends today — and an axis cannot be drawn to the year 9999.
  (DateTime, DateTime) xBoundsSince([DateTime? earliest]) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (year != null) {
      return (DateTime(year!, 1, 1), DateTime(year!, 12, 31));
    }
    if (isAll) {
      final first = earliest == null
          ? today.subtract(const Duration(days: 365))
          : DateTime(earliest.year, earliest.month, earliest.day);
      // Never inverted and never a single day: "All" on a log with one entry in
      // it is still a chart, and a span of zero has no width to divide.
      return first.isBefore(today) ? (first, today) : (today.subtract(const Duration(days: 6)), today);
    }
    return (today.subtract(Duration(days: range!.days)), today);
  }

  /// The window as day-key bounds, so a query can ask for it rather than a
  /// screen filtering everything it has ever stored.
  int get fromDayKey => switch (this) {
        _ when isAll => 0,
        _ when year != null => year! * 10000,
        _ => dayKeyOf(DateTime.now().subtract(Duration(days: range!.days))),
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

/// How many date labels a chart draws, whatever it is showing.
///
/// Seven, always. It is enough to read a year by its months and few enough that
/// a phone can print them without collision, and holding it constant is what
/// makes changing range read as a zoom rather than as a different chart: the
/// labels stay where they are and only their words change.
const _axisTicks = 7;

/// The x axis of a window: where it starts, where it ends, and where the labels
/// go.
///
/// **Anchored on the right.** Every rolling range ends today, so the last label
/// is today and the rest are counted back from it — not laid out from the left
/// edge, which is what made `1W` print whichever day the data happened to start
/// on and never print today at all.
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
  /// [zoom] is the pinch scale: `1` is the whole window, `4` is a quarter of it
  /// on screen. The label ladder is built against **the visible span**, so
  /// zooming into a decade turns years into months rather than emptying the
  /// axis — the count stays at seven and only the resolution changes.
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
    final step = visible <= 0 ? 1.0 : visible / (_axisTicks - 1);
    return TimeAxis(
      minX: from - step / 2,
      maxX: to + step / 2,
      interval: step,
      // The ladder hangs off the last day rather than the first — see the class
      // doc. `fl_chart` phases its ticks against `baselineX`, so this is the
      // one number that decides whether today gets a label.
      baseline: to,
      format: _axisFormat(visible),
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
/// **The averaging chip is a chart control, not a preference.** It sits in the
/// same row as the range because it answers the same question — how much time
/// one mark is — and putting it in a menu somewhere else would leave the chart
/// silently smoothed with nothing on screen saying so.
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

  /// The averaging **in force** — what the chip says, and what the chart is
  /// actually drawing. Null on a chart that does not average, and the chip is
  /// absent then rather than present and inert.
  final Granularity? granularity;

  /// Whether [granularity] was chosen for you. The chip reads the same either
  /// way — what the chart is doing is the fact, not how it came to be doing it
  /// — but the picker has to know which row to tick.
  final bool granularityIsAuto;

  /// Called with null when `Auto` is picked — the caller stores "no choice"
  /// rather than the granularity auto happened to resolve to today, or a window
  /// change would find the chart pinned to a level nobody asked for.
  final ValueChanged<Granularity?>? onGranularity;

  /// The averaging levels this *screen* can draw at all. Weekly volume has no
  /// daily reading, so that screen leaves it out for good.
  ///
  /// What the picker actually offers is this list narrowed to the levels the
  /// **selected range** can show — see [granularitiesFor]. Yearly over one month
  /// is a chart of a single dot, and a picker that offers it is a picker that
  /// lies about what it will do.
  final List<Granularity> granularities;

  /// The most marks this screen's chart can draw at all — see
  /// [granularitiesFor]. A line carries thousands; a bar needs width.
  final int granularityCeiling;

  /// The levels on offer right now: what this screen supports, kept to what the
  /// window can show.
  List<Granularity> get _offered {
    final (from, to) = window.xBoundsSince(earliest);
    final fits = granularitiesFor(
      to.difference(from).inDays,
      ceiling: granularityCeiling,
    );
    final out = [
      for (final g in granularities)
        if (fits.contains(g)) g,
    ];
    // Never empty, and never without the one in force — a picker that cannot
    // show you what you are looking at is worse than one with a short list.
    if (out.isEmpty) return [?granularity, ...fits.take(1)];
    return out;
  }

  /// The rolling windows offered, shortest first. All of them unless a screen
  /// has one it cannot honestly draw — weekly volume bars over `1W` is a chart
  /// of one bar, so that screen passes the three that are charts.
  ///
  /// A subset rather than a per-screen control: the chips, the year picker and
  /// the sheet stay one component, so a screen cannot quietly grow a second
  /// range control with different spacing (THEME → Charts).
  final List<ChartRange> ranges;

  /// Years there is something to look at, newest first. A picker offering 2019
  /// to a log that starts in 2024 is a list of empty charts.
  final List<int> years;

  final ValueChanged<TrendWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    // **A track, not a scrolling strip.** Eight chips in a row is wider than a
    // phone, and a control that has to be dragged sideways before it can be read
    // hides half its own options — you cannot pick `All` if you do not know it
    // is there. The ranges are a segmented track that fits by construction:
    // equal segments, whatever the width, no scroll at any size.
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
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: false,
      builder: (sheet) => AppSheet(
        title: 'Average by',
        contentPadding: const EdgeInsets.fromLTRB(
            Space.gutter, 0, Space.gutter, Space.lg),
        children: [
          AppRow(
            title: 'Auto',
            // Named, because "auto" with nothing after it is a setting whose
            // effect you cannot check. It also *changes* with the range, which
            // is the whole point of it and invisible without this line.
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
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      // The sheet keeps itself inside the system's insets rather than relying
      // on the one inside it: `isScrollControlled` lets a long list grow to the
      // full height of the *window*, which on an edge-to-edge Android is taller
      // than the screen you can see.
      useSafeArea: true,
      // And it never takes the whole of it. Twenty years of training is a list
      // longer than a phone, and a sheet that fills the screen is a screen
      // wearing a sheet's clothes — the barrier above it is what says this is a
      // question you can dismiss.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (sheet) => AppSheet(
        title: 'Which year?',
        // The default padding, minus the top the header already provides. It
        // used to pass `only(bottom:)`, which drops the sheet's side gutter as
        // well — the rows then ran edge to edge while every other sheet's did
        // not.
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

/// Where a bucket sits on the time axis: **its middle, not its first day**.
///
/// A month plotted on the 1st is drawn half a month early, and at yearly
/// granularity a mark for 2019 would land on New Year's Day and read as the
/// wrong year entirely. Daily buckets are a single day, so the middle is the
/// day and nothing moves.
double bucketX(Bucket bucket) =>
    (bucket.start.millisecondsSinceEpoch + bucket.end.millisecondsSinceEpoch) /
    2 /
    86400000;

/// The chart from THEME → Components: dashed horizontal gridlines only,
/// labels on the
/// right, no border, markers while they still mark something, horizontal zoom.
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
  /// A chart that plots its **whole** history and uses the window only to
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
  /// **Changing range must feel like moving the walls, not redrawing the room.**
  ///
  /// The two things that change when you pick a new range fight each other: the
  /// bounds want to travel, and the data wants to re-fold at a resolution that
  /// suits the new span — a year of weeks is not the same list of points as
  /// three months of days, and no interpolation exists between two lists of
  /// different lengths. Swapping both at once is what read as a rebuild.
  ///
  /// So they are separated in time. The bounds animate while **the line you
  /// were already looking at** is held and scaled with them, which is the zoom;
  /// the new resolution arrives at the end of it, under the motion, where a
  /// change of detail in the same shape is nearly invisible. THEME → Charts
  /// says axis furniture cross-fades rather than travelling, and this is the
  /// same rule one level up.
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

    // The axis of **what is on screen**, not of the window: after a pinch those
    // are different, and labels that keep describing the window are labels for a
    // chart you are no longer looking at. Seven of them, always, whatever the
    // zoom — that is what makes zooming in tell you where you are rather than
    // taking the dates away.
    final axis = window == null
        ? null
        : TimeAxis.of(window, earliest: widget.earliest, zoom: _scale);

    // One session is a chart with one dot on it, and a dot is worth drawing —
    // it is where you are, on the axis you will read the next one against. Its
    // span is zero days, though, and an axis from a day to itself has no width
    // to divide, so a fortnight of air is put either side of it.
    var minX = axis?.minX ?? xs.reduce(min);
    var maxX = axis?.maxX ?? xs.reduce(max);
    if (maxX - minX < 1) {
      minX -= 7;
      maxX += 7;
    }

    // Bounds snapped to a round step, so every gridline lands on a number a
    // person would say. Left to itself the axis labelled `1126.5` at the
    // extremes, which wrapped onto two lines and collided with the gridline
    // above. The band is the data plus air — never anchored at zero, which
    // draws a year of bodyweight as a flat line an inch off the bottom.
    final step = _niceStep((highest - lowest) / 4);
    var maxY = ((highest + step * 0.5) / step).ceilToDouble() * step;
    var minY = ((lowest - step * 0.5) / step).floorToDouble() * step;
    // Nothing this app charts is negative, so the air under the lowest point
    // stops at zero rather than drawing an axis into numbers that cannot exist.
    if (lowest >= 0 && minY < 0) minY = 0;

    // Where the bounds are *now*, part way between the range you left and the
    // one you picked. `fl_chart` lerps its own data changes, but it cannot lerp
    // between two spot lists of different lengths, which is exactly what a
    // change of resolution is — so the travel is driven here instead.
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
            // **Changing range or averaging zooms; it does not reload.** The
            // box keeps its size and `fl_chart` interpolates what is inside it
            // — the axis bounds rescale, the line travels to its new shape —
            // so widening from three months to a year reads as stepping back
            // from the same chart rather than as a different chart arriving.
            // `base` at the emphasized curve, which THEME § 6 gives anything
            // covering a distance.
            duration: Motion.base,
            curve: Motion.emphasized,
            // Pinch to zoom the time axis, drag to pan. The vertical axis stays
            // fixed: scaling weight against nothing would make the same
            // progress look like whatever you last pinched.
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
                    FlLine(color: c.border, strokeWidth: 1, dashArray: [4, 4]),
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
                    reservedSize: _yGutter,
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
                            DateFormat(_axisFormat(spanDays)).format(
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
        // circles touch and the shape you came to read is hidden by the points
        // it is made of — so they go, and the gesture is named instead.
        if (dense) ...[
          const SizedBox(height: Space.sm),
          Text(
            'Pinch to zoom, drag to pan',
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

/// The same plot with nothing to plot: the gridlines, the right-hand gutter and
/// the real time axis of the range you asked for, with no line in it.
///
/// It replaced a captioned box, which was the wrong shape twice over. An empty
/// range is not a failure to draw a chart — it is a chart of a range you did not
/// train in — and a box half the height of the plot made switching ranges jump
/// the page under your thumb. The axis stays honest by staying empty: no y
/// labels, because there is no data to scale them against, and no series at
/// zero, because a point the metric cannot score is not a zero
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

  /// Why it is empty, said **under** the plot in the voice the zoom hint uses —
  /// never across it. A sentence in the middle of the chart is a dialog box
  /// wearing a chart's frame; a line beneath it is a caption, and the thing
  /// above stays a graph. Null while the answer is still being read off disk:
  /// "nothing logged" is a claim, and a frame that has not read the log yet is
  /// not entitled to make it.
  final String? message;

  /// The band the y axis should cover — the movement's whole history, when the
  /// range you are looking at happens to be empty.
  ///
  /// This is what keeps an empty range a *range*: the numbers stay where they
  /// were, so switching from a year you trained to a month you did not reads as
  /// an empty stretch of the same chart rather than as a different widget. Null
  /// only when nothing has ever been logged, and then the axis is drawn without
  /// numbers, because there is no honest number to put on it.
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
    var maxY = ((highest + step * 0.5) / step).ceilToDouble() * step;
    var minY = ((lowest - step * 0.5) / step).floorToDouble() * step;
    if (lowest >= 0 && minY < 0) minY = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            // The empty chart rescales with the same motion as a full one, so
            // ranging across a stretch you did not train is one continuous zoom
            // rather than a chart, a jump, and a chart again.
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
                    FlLine(color: c.border, strokeWidth: 1, dashArray: [4, 4]),
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
                    reservedSize: _yGutter,
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

/// The gutter the value labels sit in, on the right.
///
/// Wide enough for `1250` at `label` size and no wider: it was 52, which left a
/// finger's width of nothing between the plot and the card's own padding, and
/// made every chart look as though it had been laid out against the wrong edge.
const _yGutter = 36.0;

/// A tick at the very edge has half a line of room and ends up printed over
/// its neighbour — `Dec 19Jul 26`, `330 Jul`. Both axes drop theirs.
Widget _edgeSafe(double value, TitleMeta meta, Widget child) {
  if (value <= meta.min || value >= meta.max) return const SizedBox.shrink();
  return SideTitleWidget(meta: meta, space: Space.xs, child: child);
}

/// Label resolution follows the span, or four ticks a day apart all render as
/// the same month and overlap into mush.
///
/// A week is named by its days — `Fri Sat Sun … Thu` — because at that range
/// the day of the week *is* the question you are asking.
String _axisFormat(double spanDays) {
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
