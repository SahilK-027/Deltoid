/// The value axis of every chart: the band it covers, the gridlines drawn
/// across it, and the label each gridline carries.
///
/// One function for every chart, because the charts used to compute this four
/// times and each copy failed in its own way. The cycle axis capped its step at
/// 100 and drew a regime at +259% over its own readout. The trend chart chose
/// a step of 0.25 and printed it at one decimal, so a narrow band read
/// `80.1 80.1 80.1`, and a single value gave it one gridline. The volume chart
/// never stepped past 10 and stacked eleven labels into 150 points. And
/// `fl_chart` draws no gridline on either bound, so the cycle axis labelled
/// three values and drew one line.
///
/// Three shapes of axis, each following THEME → Charts:
///
/// - [ValueAxis.trend], for a line over time. The data plus air, never
///   anchored at zero unless zero is in the data, with gridlines on a round
///   step strictly inside the band. The bounds themselves carry no line and no
///   label, because the time axis keeps its edges clear.
/// - [ValueAxis.cycle], for the cycle axis. Two steps from a rounded floor, or
///   three where two would leave more than 40% of the band empty, and a
///   gridline with a label on every step, the bounds included.
/// - [ValueAxis.bars], for a bar chart. Anchored at zero, topped by a round
///   step at or above the tallest bar, and never off-scale.
///
/// A line chart takes one isolated wild value off the scale rather than
/// letting it set the band: see [OffScale].
///
/// Pure, and tested without a database (RULES § 7).
library;

import 'dart:math' as math;

/// The edge of the plot an off-scale point left by.
enum OffScaleEdge { top, bottom }

/// One point a line chart draws as a caret on the edge of the plot, rather
/// than letting it stretch the band.
///
/// A typo of 260 kg in a year of 100s drew the year as a flat line along the
/// floor with one spike: honest, and a chart that looks broken about data that
/// is almost all fine. So a point goes off-scale when it is a single bucket
/// with a neighbour either side, its neighbours lie inside the band of the
/// rest, and including it would more than double that band's height. A run of two such points is a trend and is
/// never clipped: each one is inside the band the other sets.
class OffScale {
  const OffScale({
    required this.series,
    required this.index,
    required this.value,
    required this.edge,
  });

  /// Which series the point is in, and where in it.
  final int series;
  final int index;

  /// Its real value, which the caption names when the point is read.
  final double value;

  final OffScaleEdge edge;

  @override
  String toString() => 'OffScale($series, $index, $value, ${edge.name})';
}

class ValueAxis {
  const ValueAxis._({
    required this.min,
    required this.max,
    required this.step,
    required this.gridlines,
    required this.labels,
    this.offScale = const [],
  });

  /// The trend chart's band: the data plus between half a step and a step of
  /// air on each side, with three or four gridlines inside it where the
  /// ladder allows, and two or five where it jumps over both.
  ///
  /// [series] is each line's values in the order they are drawn, which the
  /// off-scale rule reads to know a point's neighbours.
  ///
  /// [format] is the label as the chart prints it. A step is refused when two
  /// of its labels print the same, so whatever precision the format rounds to,
  /// no label repeats.
  ///
  /// [minStep] is the precision the labels are printed at: 0.1 for a
  /// bodyweight, 1 for seconds. Every step is a whole multiple of it, so a
  /// gridline at 82.25 is never labelled `82.3`.
  ///
  /// [minSpan] and [minSpanFraction] are the least height the band shows,
  /// absolute and as a share of the value. A single weigh-in, or a year flat
  /// to within 0.1 kg, is centred in a band that tall rather than drawn as a
  /// line with one gridline or as a cliff out of noise.
  factory ValueAxis.trend(
    List<List<double>> series, {
    required String Function(double value) format,
    double minStep = 0,
    double minSpan = 0,
    double minSpanFraction = 0,
  }) {
    final values = [for (final s in series) ...s];
    if (values.isEmpty) {
      return ValueAxis.trend(const [
        [0, 1],
      ], format: format);
    }

    double floorSpan(double lo, double hi) {
      final span = [
        minSpan,
        minSpanFraction * math.max(lo.abs(), hi.abs()),
        minStep * 2,
      ].reduce(math.max);
      if (span > 0) return span;
      // Nothing set by the caller, and one value: a tenth of it, or 1.
      return hi.abs() > 0 ? hi.abs() / 10 : 1;
    }

    final off = _offScale(series, floorSpan);
    final kept = _without(series, off);
    var lo = kept.reduce(math.min);
    var hi = kept.reduce(math.max);
    // Nothing this app charts is negative, so the air under the lowest point
    // stops at zero rather than reaching into numbers that cannot exist.
    final nonNegative = lo >= 0;

    final least = floorSpan(lo, hi);
    if (hi - lo < least) {
      final middle = (lo + hi) / 2;
      lo = middle - least / 2;
      hi = middle + least / 2;
      if (nonNegative && lo < 0) {
        hi -= lo;
        lo = 0;
      }
    }

    ValueAxis? fallback;
    ValueAxis? previous;
    for (final step in _ladder(
      from: (hi - lo) / 10,
      multiples: const [1, 2, 2.5, 5],
      minStep: minStep,
    )) {
      // Air of half a step at least and a whole step at most, snapped to the
      // half step. Snapping to the whole step put up to a step and a half
      // over the data, and the top fifth of every plot was empty.
      final half = step / 2;
      var min = _floorTo(lo - half, half);
      final max = _ceilTo(hi + half, half);
      if (nonNegative && min < 0) min = 0;
      final gridlines = [
        for (var k = _ceilDiv(min, step); k * step <= max + step * 1e-9; k++)
          if (_inside(_round(k * step), min, max, step)) _round(k * step),
      ];
      final axis = ValueAxis._(
        min: min,
        max: max,
        step: step,
        gridlines: gridlines,
        labels: [for (final g in gridlines) format(g)],
        offScale: off,
      );
      fallback ??= axis;
      if (gridlines.length <= 4 && axis._distinct) {
        // The ladder can jump from five gridlines to two, as 77 to 94 does
        // at steps of 5 and 10. Two leave a band of air and a scale with
        // one interval to read, so the five are kept instead.
        if (gridlines.length < 3 && previous?.gridlines.length == 5) {
          return previous!;
        }
        return axis;
      }
      previous = axis._distinct ? axis : null;
    }
    return fallback!;
  }

  /// The cycle axis's band: two steps from a rounded floor, or three where two
  /// would leave more than 40% of it empty, every step a labelled gridline.
  ///
  /// [values] are the scored cycles in the order the axis draws them. With
  /// none, the band is the 0 to 2% a programme not yet trained honestly has.
  ///
  /// The ladder is 1, 2, 4, 5, 10, 20, 25, 50 and on up the same way, with no
  /// top. It stopped at 100, so a band of two steps reached at most 200 points
  /// over its floor and a regime at +259% drew over the readout.
  factory ValueAxis.cycle(
    List<double> values, {
    required String Function(double value) format,
  }) {
    final off = _offScale([values], (_, _) => 1);
    final kept = _without([values], off);
    final lo = kept.isEmpty ? 0.0 : kept.reduce(math.min);
    // A flat band has no height to divide, so it is given one point.
    final hi = math.max(kept.isEmpty ? 0.0 : kept.reduce(math.max), lo + 1);

    double stepFor(int steps) => _cycleLadder().firstWhere(
      (s) => _floorTo(lo, s) + steps * s >= hi - s * 1e-9,
    );

    var steps = 2;
    var step = stepFor(2);
    final fill = (hi - lo) / (2 * step);
    if (fill < 0.6) {
      final three = stepFor(3);
      if ((hi - lo) / (3 * three) > fill) {
        steps = 3;
        step = three;
      }
    }

    final min = _floorTo(lo, step);
    final gridlines = [for (var k = 0; k <= steps; k++) _round(min + k * step)];
    return ValueAxis._(
      min: min,
      max: gridlines.last,
      step: step,
      gridlines: gridlines,
      labels: [for (final g in gridlines) format(g)],
      offScale: off,
    );
  }

  /// A bar chart's axis: zero to a round step at or above [peak], in two to
  /// four steps, with a labelled gridline on each step between them.
  ///
  /// Anchored at zero, the opposite of the trend chart, for the opposite
  /// reason: a week you skipped is zero and sits on the baseline. The bounds
  /// carry no line and no label, because a label on either edge has half a
  /// line of room and prints over the bar it describes. Bars are counts, and a
  /// heavy week is not a typo, so nothing here goes off-scale.
  factory ValueAxis.bars(
    double peak, {
    String Function(double value) format = _whole,
  }) {
    // Rounded up first: a peak of 6.4 sets a week has to fit under the axis,
    // not sit on its top gridline.
    final top = math.max(peak, 0).ceilToDouble();
    final step = _ladder(
      from: 1,
      multiples: const [1, 2, 2.5, 5],
      minStep: 1,
    ).firstWhere((s) => (top / s).ceil() <= 4);
    // Two steps at least, so the gutter keeps its labels, and the plot its
    // width, on a range with one set in it or none.
    final steps = math.max((top / step).ceil(), 2);
    final gridlines = [for (var k = 1; k < steps; k++) k * step];
    return ValueAxis._(
      min: 0,
      max: steps * step,
      step: step,
      gridlines: gridlines,
      labels: [for (final g in gridlines) format(g)],
    );
  }

  final double min;
  final double max;

  /// The distance between two gridlines.
  final double step;

  /// Every gridline the chart draws, lowest first. Each one is labelled.
  final List<double> gridlines;

  /// The label of each gridline, in the same order.
  final List<String> labels;

  /// The points drawn as a caret on an edge, at most one per edge.
  final List<OffScale> offScale;

  /// The label of the gridline at [value], or null when no gridline is there.
  ///
  /// `fl_chart` asks for a label at every multiple of the step it walks,
  /// including the bounds, and this is how a chart prints exactly the labels
  /// this axis chose.
  String? labelAt(double value) {
    for (var i = 0; i < gridlines.length; i++) {
      if ((gridlines[i] - value).abs() <= step * 1e-6) return labels[i];
    }
    return null;
  }

  bool isGridline(double value) => labelAt(value) != null;

  /// The point at [index] of [series], if it is off the scale.
  OffScale? offScaleAt(int series, int index) {
    for (final o in offScale) {
      if (o.series == series && o.index == index) return o;
    }
    return null;
  }

  /// Where to draw a value: on the edge it left by when it is off the scale,
  /// so the line runs to the edge and back, and where it is otherwise.
  double place(int series, int index, double value) =>
      switch (offScaleAt(series, index)?.edge) {
        OffScaleEdge.top => max,
        OffScaleEdge.bottom => min,
        null => value,
      };

  bool get _distinct => labels.toSet().length == labels.length;

  @override
  String toString() =>
      'ValueAxis($min to $max by $step: $labels'
      '${offScale.isEmpty ? '' : ', off $offScale'})';
}

String _whole(double value) => value.round().toString();

/// The one isolated wild value at each edge, if there is one — see
/// [OffScale]. [floorSpan] is the least height a band is read as having, so a
/// flat line does not send a point off-scale for being a little different.
List<OffScale> _offScale(
  List<List<double>> series,
  double Function(double lo, double hi) floorSpan,
) {
  final count = series.fold<int>(0, (n, s) => n + s.length);
  // Two points are a line, not a line and a typo.
  if (count <= 2) return const [];

  final out = <OffScale>[];
  for (final edge in OffScaleEdge.values) {
    final top = edge == OffScaleEdge.top;
    (int, int)? at;
    var extreme = 0.0;
    for (var s = 0; s < series.length; s++) {
      for (var i = 0; i < series[s].length; i++) {
        // Only a point with a neighbour either side: the line runs to the
        // edge and back, and the newest or oldest point of a line is where
        // it is going or where it came from, never a typo between two others.
        if (i == 0 || i == series[s].length - 1) continue;
        if (out.any((o) => o.series == s && o.index == i)) continue;
        final v = series[s][i];
        if (at == null || (top ? v > extreme : v < extreme)) {
          at = (s, i);
          extreme = v;
        }
      }
    }
    if (at == null) continue;

    // The band of the rest: everything but this point and any point already
    // off the other edge. A second point at the same height is in it, which
    // is what keeps a run of two inside the scale.
    final rest = [
      for (var s = 0; s < series.length; s++)
        for (var i = 0; i < series[s].length; i++)
          if ((s, i) != at && !out.any((o) => o.series == s && o.index == i))
            series[s][i],
    ];
    if (rest.length < 2) continue;
    final lo = rest.reduce(math.min);
    final hi = rest.reduce(math.max);
    final band = math.max(hi - lo, floorSpan(lo, hi));
    final widened = top ? extreme - lo : hi - extreme;
    if (widened > band * 2) {
      out.add(
        OffScale(series: at.$1, index: at.$2, value: extreme, edge: edge),
      );
    }
  }
  return out;
}

List<double> _without(List<List<double>> series, List<OffScale> off) => [
  for (var s = 0; s < series.length; s++)
    for (var i = 0; i < series[s].length; i++)
      if (!off.any((o) => o.series == s && o.index == i)) series[s][i],
];

/// Round steps from [from] upward: [multiples] of each power of ten, and only
/// whole multiples of [minStep], so no step is finer than the labels print.
Iterable<double> _ladder({
  required double from,
  required List<double> multiples,
  double minStep = 0,
}) sync* {
  final start = from > 0 ? from : 1e-9;
  var magnitude = math
      .pow(10, (math.log(start) / math.ln10).floor())
      .toDouble();
  // Ninety rungs reach well past any value a chart draws, and a finite list
  // cannot leave a caller looping on a step nothing accepts.
  for (var rung = 0; rung < 30; rung++) {
    for (final m in multiples) {
      final step = _round(magnitude * m);
      if (step < minStep - 1e-12) continue;
      if (minStep > 0) {
        final ratio = step / minStep;
        if ((ratio - ratio.round()).abs() > 1e-6) continue;
      }
      yield step;
    }
    magnitude *= 10;
  }
}

/// The cycle axis's ladder: 1, 2, 4 and 5, then 10, 20, 25 and 50 at every
/// power of ten from there up.
Iterable<double> _cycleLadder() sync* {
  yield* const [1.0, 2.0, 4.0, 5.0];
  for (var magnitude = 10.0; magnitude < 1e12; magnitude *= 10) {
    for (final m in const [1, 2, 2.5, 5]) {
      yield magnitude * m;
    }
  }
}

/// Floating point through the snapping: `0.1 * 3` is `0.30000000000000004`,
/// and a gridline there is not the one at 0.3 when a label is looked up.
double _round(double v) => (v * 1e9).round() / 1e9;

double _floorTo(double v, double unit) =>
    _round((v / unit + 1e-9).floorToDouble() * unit);

double _ceilTo(double v, double unit) =>
    _round((v / unit - 1e-9).ceilToDouble() * unit);

int _ceilDiv(double v, double unit) => (v / unit - 1e-9).ceil();

bool _inside(double v, double min, double max, double step) =>
    v > min + step * 1e-6 && v < max - step * 1e-6;
