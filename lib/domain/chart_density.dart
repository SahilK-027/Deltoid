import 'dart:math' as math;

/// How close a chart's marks may stand before they stop reading as marks.
///
/// Every threshold here is a distance on screen, in logical pixels, and never
/// a count of points. A count says nothing about the room the points have:
/// twenty-six readings squeezed into the newest quarter of a year touch, while
/// fifty-two spread across six months have room to spare (THEME → Charts).

/// The least distance between neighbouring readings at which a line keeps
/// its circle markers. Closer than this the circles touch and the line is
/// lost inside them.
const markerSpacing = 10.0;

/// The widest a bar is drawn. One week across a whole plot is a slab that
/// reads as a filled panel rather than as a bar, so past this the slot keeps
/// its width and the bar stands in the middle of it.
const barMaxWidth = 24.0;

/// The narrowest slot a bar chart is drawn at. Below this the bars meet and
/// the chart becomes a texture, so a chart that can fold its bars coarser
/// does so.
const barMinSlot = 4.0;

/// Whether a series plotted at [xs] keeps its markers, when one unit of x is
/// [pixelsPerX] logical pixels on screen.
///
/// Decided on the closest pair of neighbours, because that is where the
/// circles touch first. One reading, or none, has no neighbour to touch.
/// [xs] need not be sorted.
bool markersFit(Iterable<double> xs, double pixelsPerX) {
  final sorted = xs.toList()..sort();
  for (var i = 1; i < sorted.length; i++) {
    if ((sorted[i] - sorted[i - 1]) * pixelsPerX < markerSpacing) return false;
  }
  return true;
}

/// The gap between two bars in a slot [slot] wide: a share of the slot, never
/// a constant. A fixed gap is a quarter of a wide slot and three quarters of a
/// narrow one, and below [barMinSlot] the bars meet.
double barGap(double slot) => slot >= 8
    ? 2.0
    : slot >= barMinSlot
    ? 1.0
    : 0.0;

/// The width of one bar's slot when [count] bars share [width]. The slots
/// always fill the width, however few bars there are, so a short range is
/// spread across the plot rather than packed against one edge of it.
double barSlot(double width, int count) =>
    count <= 0 || width <= 0 ? 0 : width / count;

/// The ink of one bar in a slot [slot] wide, never wider than [barMaxWidth].
///
/// Never `clamp(1.0, slot)`: a slot narrower than a point makes the lower
/// bound exceed the upper one, and `clamp` throws rather than picking a side.
/// A bar is a point of ink or the whole slot, whichever is smaller.
double barWidth(double slot) => math.min(
      barMaxWidth,
      math.max(slot - barGap(slot), math.min(slot, 1.0)),
    );
