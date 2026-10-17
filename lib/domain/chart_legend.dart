/// What a chart's legend keys, and how much of it fits (THEME → Charts).
///
/// Pure: the widget measures its entries and asks here which of them to print,
/// so the rule that a legend never grows past two rows is tested without a
/// screen.
library;

/// The gap between two entries on one row of a legend.
const legendSpacing = 12.0;

/// The most rows a legend takes. Past this the last entry that fits reads
/// `and 3 more`, so the header does not change height when a range brings
/// another session into view.
const legendMaxRows = 2;

/// How many of the entries [widths] wide a legend [maxWidth] wide prints, in
/// order, within [maxRows] rows of entries [spacing] apart.
///
/// All of them where all of them fit. Otherwise the most that still leave room
/// for the entry naming the rest, which is [moreWidth] of the number left out
/// wide. An entry wider than the legend takes a row of its own and is cut
/// short there rather than pushing the legend wider.
int legendFit(
  List<double> widths,
  double maxWidth, {
  required double Function(int hidden) moreWidth,
  double spacing = legendSpacing,
  int maxRows = legendMaxRows,
}) {
  if (widths.isEmpty || !maxWidth.isFinite) return widths.length;
  if (_rows(widths, maxWidth, spacing) <= maxRows) return widths.length;
  for (var shown = widths.length - 1; shown >= 0; shown--) {
    final packed = [
      ...widths.take(shown),
      moreWidth(widths.length - shown),
    ];
    if (_rows(packed, maxWidth, spacing) <= maxRows) return shown;
  }
  return 0;
}

/// The rows [widths] wrap into, greedily, as a `Wrap` lays them out.
int _rows(List<double> widths, double maxWidth, double spacing) {
  var rows = 0;
  var used = 0.0;
  for (final w in widths) {
    if (rows == 0 || used + spacing + w > maxWidth) {
      rows++;
      used = w;
    } else {
      used += spacing + w;
    }
  }
  return rows;
}

/// The entry that stands for every entry a legend left out.
String legendMore(int hidden) => 'and $hidden more';

/// The lines a legend keys, as groups of series indices: each group one line
/// on screen, ordered by its first member, ending with the series drawn on
/// top.
///
/// [series] is each line's points as `(x, y)` in drawing order, with a null
/// `y` for a break; a later series is drawn over an earlier one. A series is
/// hidden when every reading of it falls, to within [tolerance] in y, on a
/// drawn segment or lone point of a series drawn after it. Push 1 and Push 2
/// held at 100 kg for a year are one line, and a legend keying both named a
/// line nobody could see. A stretch where only the earlier one is drawn keeps
/// it a line of its own, because there it is visible.
///
/// A legend keys a group once, in the colour of its last member, which is the
/// one on top, under every name in it.
List<List<int>> identicalSeries(
  List<List<(double, double?)>> series, {
  double tolerance = 1e-9,
}) {
  // The series each one is hidden under, if any: the first drawn after it
  // that covers it, followed up to the one on top.
  final cover = [
    for (var i = 0; i < series.length; i++)
      [
        for (var j = i + 1; j < series.length; j++)
          if (_liesOn(series[i], series[j], tolerance)) j,
      ].firstOrNull,
  ];
  int top(int i) => cover[i] == null ? i : top(cover[i]!);

  final groups = <int, List<int>>{};
  for (var i = 0; i < series.length; i++) {
    groups.putIfAbsent(top(i), () => []).add(i);
  }
  return groups.values.toList()..sort((a, b) => a.first.compareTo(b.first));
}

/// Whether every reading of [a] falls on the line [b] draws.
bool _liesOn(
  List<(double, double?)> a,
  List<(double, double?)> b,
  double tolerance,
) {
  var any = false;
  for (final (x, y) in a) {
    if (y == null) continue;
    any = true;
    final at = _drawnAt(b, x);
    if (at == null || (at - y).abs() > tolerance) return false;
  }
  // A series with nothing drawn is not a line, so it is the same as nothing.
  return any;
}

/// The y the line [b] is drawn at, at [x], or null where it draws nothing:
/// outside it, across a break, or beside a lone reading.
double? _drawnAt(List<(double, double?)> b, double x) {
  for (var j = 0; j < b.length; j++) {
    final (x0, y0) = b[j];
    if (y0 == null) continue;
    if (x0 == x) return y0;
    if (j + 1 >= b.length) continue;
    final (x1, y1) = b[j + 1];
    if (y1 == null) continue;
    if (x > x0 && x < x1) return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
  }
  return null;
}

/// Names joined as a sentence lists them: `Push 1 and Push 2`,
/// `Push 1, Push 2 and Push 3`.
String joinNames(List<String> names) => switch (names.length) {
      0 => '',
      1 => names.first,
      _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
    };
