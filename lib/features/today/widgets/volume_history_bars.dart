import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/volume_history.dart';

/// One bar per week, scrubbable, and it zooms when the range changes.
///
/// Not a [TrendChart]: that draws a line between points, and a line says the
/// value between two weeks means something. Weekly sets are buckets — you did
/// eleven that week and nine the next, and nothing in between happened. Bars
/// are the honest mark, and they are the mark THEME's bar list already uses for
/// the same number on Today.
///
/// No axis and no gridlines, exactly as a sparkline drops them (THEME →
/// Components → Charts). The figures live in the row above and below.
///
/// **One painter rather than a row of boxes.** A year is 52 bars, six tiles is
/// six of those, and as widgets that was three hundred render objects laid out
/// and composited to draw what is a single path — before anything moved.
class WeeklyBars extends StatefulWidget {
  const WeeklyBars({
    super.key,
    required this.series,
    required this.hue,
    required this.height,
    this.scaleTo,
    this.onSelected,
  });

  final VolumeSeries series;
  final Color hue;
  final double height;

  /// The count a full-height bar means. Defaults to the series' own peak, which
  /// is what a tile wants: no axis, so the tallest bar filling the card is the
  /// clearest reading of "this was the most". A chart with a y axis passes its
  /// rounded maximum instead, or the tallest bar covers the top gridline.
  final int? scaleTo;

  /// Fired with the week under the finger, and with null when it is lifted
  /// clear. The caller prints the readout, because on a card this narrow a
  /// tooltip covers the chart it is describing.
  final ValueChanged<VolumeWeek?>? onSelected;

  @override
  State<WeeklyBars> createState() => _WeeklyBarsState();
}

class _WeeklyBarsState extends State<WeeklyBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    // A layout change, and one that travels: `base` at the emphasized curve,
    // which is what THEME § 6 gives anything covering a distance.
    duration: Motion.base,
    value: 1,
  );

  int? _touched;

  /// The shape of the chart before the range changed. Only the two numbers the
  /// zoom interpolates — keeping the old week list would pin a year of data in
  /// memory to draw a fifth of a second of motion.
  int _fromWeeks = 0;
  double _fromMax = 0;

  int get _max => widget.scaleTo ?? widget.series.peakSets;

  @override
  void didUpdateWidget(WeeklyBars old) {
    super.didUpdateWidget(old);

    // Only a change of *range* zooms. Ticking a set rewrites the weeks list and
    // moves one bar's height, and animating a zoom at that would make logging a
    // set look like navigating somewhere.
    final spanChanged =
        old.series.weeks.length != widget.series.weeks.length ||
            (old.series.weeks.isNotEmpty &&
                widget.series.weeks.isNotEmpty &&
                old.series.weeks.first.start !=
                    widget.series.weeks.first.start);
    if (!spanChanged) return;

    _fromWeeks = old.series.weeks.length;
    _fromMax = (old.scaleTo ?? old.series.peakSets).toDouble();
    // Scrubbing a chart that is no longer the chart you were scrubbing.
    //
    // The parent is told **after** the frame, never here: `onSelected` sets
    // state on the widget that owns the caption, and this runs inside its
    // build. Calling it synchronously marks an ancestor dirty mid-build, which
    // is an assertion in debug and a dropped update in release.
    if (_touched != null) {
      _touched = null;
      final notify = widget.onSelected;
      if (notify != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notify(null);
        });
      }
    }
    _zoom.forward(from: 0);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// The week under [dx], measured against this widget's own box.
  ///
  /// Deliberately not a `LayoutBuilder`: these bars sit inside cards laid out
  /// two to a row, and a `LayoutBuilder` cannot report an intrinsic height, so
  /// any parent that asks for one throws. Gestures only arrive after layout, so
  /// the render box is always there to ask.
  void _selectAt(double dx) {
    final weeks = widget.series.weeks;
    final width = context.size?.width ?? 0;
    if (weeks.isEmpty || width <= 0) return;
    final i = (dx / width * weeks.length).floor().clamp(0, weeks.length - 1);
    if (i == _touched) return;
    setState(() => _touched = i);
    widget.onSelected?.call(weeks[i]);
  }

  void _clear() {
    if (_touched == null) return;
    setState(() => _touched = null);
    widget.onSelected?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Press and scrub. A drag rather than a tap per bar because a year is 52
      // bars across a phone — four points each, which no finger can land on.
      // The log screen's ban on horizontal gestures is about its `PageView`
      // (RULES § 4) and does not reach here; this widget is inside a vertical
      // scroll, which the drag recogniser wins against only on a horizontal
      // movement.
      onTapDown: (d) => _selectAt(d.localPosition.dx),
      onTapUp: (_) => _clear(),
      onTapCancel: _clear,
      onHorizontalDragStart: (d) => _selectAt(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _selectAt(d.localPosition.dx),
      onHorizontalDragEnd: (_) => _clear(),
      onHorizontalDragCancel: _clear,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarsPainter(
            weeks: widget.series.weeks,
            max: _max,
            fromWeeks: _fromWeeks,
            fromMax: _fromMax,
            zoom: CurvedAnimation(parent: _zoom, curve: Motion.emphasized),
            hue: widget.hue,
            // The same grey as a rest day on the heatmap: a week you skipped
            // and a day you skipped are one absence.
            track: c.heatEmpty,
            touched: _touched,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.weeks,
    required this.max,
    required this.fromWeeks,
    required this.fromMax,
    required this.zoom,
    required this.hue,
    required this.track,
    required this.touched,
  }) : super(repaint: zoom);

  final List<VolumeWeek> weeks;
  final int max;

  /// How many weeks were on screen before the range changed, and what they were
  /// scaled against. Zero means there is nothing to zoom from.
  final int fromWeeks;
  final double fromMax;

  final Animation<double> zoom;
  final Color hue;
  final Color track;
  final int? touched;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty || size.width <= 0) return;

    final t = zoom.value;
    final count = weeks.length;

    // **Anchored on the right, because every range ends today.** Widening from
    // three months to a year should feel like stepping back from the same wall
    // — the weeks you were looking at stay where they are and more of them
    // arrive on the left. Scaling about the centre instead would slide this
    // week sideways, which is the one bar the eye is holding on to.
    final slot = fromWeeks <= 0 || t >= 1
        ? size.width / count
        : _lerp(size.width / fromWeeks, size.width / count, t);

    final scale = fromWeeks <= 0 || t >= 1
        ? max.toDouble()
        : _lerp(fromMax <= 0 ? max.toDouble() : fromMax, max.toDouble(), t);

    // Weeks that were off-screen a moment ago are drawn outside the box while
    // they travel in.
    canvas.clipRect(Offset.zero & size);

    final gap = slot >= 8
        ? 2.0
        : slot >= 4
            ? 1.0
            : 0.0;
    final barWidth = (slot - gap).clamp(1.0, slot);
    // A 2pt radius on a 2pt bar is a lozenge, not a bar (THEME → Bar list).
    final radius = barWidth >= 5 ? const Radius.circular(2) : Radius.zero;

    // Zooming out reveals weeks that were not on screen before. They fade in
    // rather than sliding in from nowhere fully drawn.
    final entering = count - fromWeeks;
    final trackPaint = Paint()..color = track;

    for (var i = 0; i < count; i++) {
      // Counted back from the right edge, so the last bar is always the last
      // bar whatever the slot width is doing.
      final left = size.width - (count - i) * slot;
      if (left + barWidth < 0) continue;

      final fade = fromWeeks > 0 && t < 1 && i < entering ? t : 1.0;
      final rect = Rect.fromLTWH(left, 0, barWidth, size.height);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: radius,
          topRight: radius,
          bottomLeft: radius,
          bottomRight: radius,
        ),
        fade >= 1
            ? trackPaint
            : (Paint()..color = track.withValues(alpha: fade)),
      );

      final sets = weeks[i].sets;
      if (sets <= 0 || scale <= 0) continue;

      // At least a point of ink for a week that was trained: rounded down, one
      // set against a peak of forty is nothing at all, and a week you trained
      // must never draw as a week you skipped.
      final filled =
          (size.height * sets / scale).clamp(1.0, size.height);
      final colour = touched == null || touched == i
          ? hue
          // Untouched bars step back rather than the touched one lighting up,
          // so the readout and the bar it belongs to stay the same brightness.
          : hue.withValues(alpha: 0.35);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - filled, barWidth, filled),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()
          ..color = fade >= 1 ? colour : colour.withValues(alpha: fade),
      );
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.touched != touched ||
      old.max != max ||
      old.hue != hue ||
      old.track != track ||
      !identical(old.weeks, weeks);
}
