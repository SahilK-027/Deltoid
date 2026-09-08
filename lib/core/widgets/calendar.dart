import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ids.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// The app's day picker: a month grid in a dialog, in this app's own language.
///
/// It replaces `showDatePicker`, which is the one surface the theme could never
/// reach — Material's dialog arrives centred, with its own type scale, its own
/// ink ripples, a 3:2 landscape header, and an accent colour derived from the
/// `ColorScheme` rather than from [DeltoidColors]. Three screens asked the same
/// question ("which past day?") and all three answered it in a different app.
///
/// Returns the picked day at midnight, or null if dismissed. Days outside
/// [first]..[last] are shown but not tappable: a month with holes in it says
/// *why* the day cannot be picked, where a month that simply stops does not.
///
/// [marks] rings the logged days, keyed by `dayKey`: `heatOn` blue for a
/// session, `deload` orange for a light week, and whatever colour a caller
/// gives a weigh-in. Every other day inside the range wears the `heatEmpty`
/// ring instead, so the grid answers *which day did I miss* by shape rather
/// than by absence — a ring that is there and a ring that is not are read
/// against each other, where a ring and a bare number are read one at a time.
/// Today carries a dot under its number whichever ring it has, and a day that
/// has not happened yet has no ring at all and says so when it is tapped.
///
/// A dialog rather than a sheet. This is a grid that is read before it is
/// tapped, the one picker in the application that is examined rather than
/// scrolled. A sheet would place it at the bottom of the screen, positioning
/// the month being read furthest from the reader.
Future<DateTime?> pickDay(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
  Map<int, Color> marks = const {},
  String title = 'Pick a day',
  String? subtitle,
}) {
  final lastDay = _midnight(last ?? DateTime.now());
  final firstDay = _midnight(first ?? _floorFor(marks));
  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.66),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.xxl,
      ),
      child: _CalendarCard(
        initial: _midnight(initial).clamp(firstDay, lastDay),
        first: firstDay,
        last: lastDay,
        marks: marks,
        title: title,
        subtitle: subtitle,
      ),
    ),
  );
}

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// How far back a picker reaches when its caller names no floor.
///
/// 2015 unless something is marked before it, and then back to that mark. Both
/// halves matter and each one was a bug on its own. A flat 2015 silently
/// refuses every day of a history that starts before it. A floor taken from the
/// earliest mark instead — which is what the session picker used to pass —
/// refuses every day *before* the log begins, so a session done the week before
/// the app was installed cannot be backfilled, which is the one thing that
/// picker exists to do. The floor is therefore the earlier of the two, never
/// the later.
DateTime _floorFor(Map<int, Color> marks) {
  final base = DateTime(2015);
  if (marks.isEmpty) return base;
  final earliest = dateFromDayKey(marks.keys.reduce((a, b) => a < b ? a : b));
  return earliest.isBefore(base) ? earliest : base;
}

extension on DateTime {
  DateTime clamp(DateTime low, DateTime high) =>
      isBefore(low) ? low : (isAfter(high) ? high : this);

  bool sameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;
}

class _CalendarCard extends StatefulWidget {
  const _CalendarCard({
    required this.initial,
    required this.first,
    required this.last,
    required this.marks,
    required this.title,
    required this.subtitle,
  });

  final DateTime initial;
  final DateTime first;
  final DateTime last;
  final Map<int, Color> marks;
  final String title;
  final String? subtitle;

  @override
  State<_CalendarCard> createState() => _CalendarCardState();
}

/// Which of the three grids the card is showing.
///
/// One pane at a time inside a box of one height, rather than three cards that
/// each size to their contents: the month, the month list and the year list are
/// the same question asked at three scales, and a card that resized between
/// them would move the control that switches them out from under the thumb.
enum _Pane { days, months, years }

class _CalendarCardState extends State<_CalendarCard> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  _Pane _pane = _Pane.days;

  /// Why the last tap did nothing, shown over the grid until it lapses.
  ///
  /// A day with no ring is a day that cannot be picked, and the tap that
  /// discovers this has to be answered where it happened. Not [showToast]: a
  /// toast is drawn by the `ScaffoldMessenger` under this route, so it would
  /// arrive behind the dialog's own barrier. Not the header's subtitle either —
  /// that line is only built when there is one, so filling it would grow the
  /// card at the moment of the tap.
  String? _refusal;
  Timer? _refusalTimer;

  /// Long enough to read a sentence, and gone before the month is paged.
  static const _refusalDwell = Duration(milliseconds: 2400);

  bool get _canGoBack =>
      _month.isAfter(DateTime(widget.first.year, widget.first.month));

  bool get _canGoForward =>
      _month.isBefore(DateTime(widget.last.year, widget.last.month));

  void _shift(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
    _clearRefusal();
  });

  void _show(_Pane pane) => setState(() {
    _pane = _pane == pane ? _Pane.days : pane;
    _clearRefusal();
  });

  /// Called from inside a `setState`, so it only has to drop the message: a
  /// refusal names a day in the month it was tapped in, and paging away from
  /// that month leaves it sitting over a grid it is not about.
  void _clearRefusal() {
    _refusalTimer?.cancel();
    _refusal = null;
  }

  void _refuse(String why) {
    setState(() => _refusal = why);
    _refusalTimer?.cancel();
    _refusalTimer = Timer(_refusalDwell, () {
      if (mounted) setState(() => _refusal = null);
    });
  }

  @override
  void dispose() {
    _refusalTimer?.cancel();
    super.dispose();
  }

  void _swipe(DragEndDetails details) {
    // Velocity, not distance: a month is turned with a flick, and a slow drag
    // across the grid is a thumb resting on it rather than a gesture.
    final v = details.primaryVelocity ?? 0;
    if (v < -240 && _canGoForward) _shift(1);
    if (v > 240 && _canGoBack) _shift(-1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.sheet),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The header carries the card's own padding, and the hairline under
          // it runs the full width. A title with the grid straight underneath
          // reads as the first line of the grid rather than as the card's name,
          // which is the same reason every sheet in the app draws this rule.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.xl,
              Space.md,
              Space.lg,
            ),
            child: _CardHeader(
              title: widget.title,
              // The card never said which day it was sitting on: the filled
              // circle is the only sign, and it is one of forty-two. The day
              // chosen belongs in the header, in the `body` line that names
              // *which* thing is being edited everywhere else in the app.
              subtitle: widget.subtitle ??
                  DateFormat('EEE d MMM yyyy').format(widget.initial),
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.lg,
              Space.lg,
              Space.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Above the grid, not under it. The strip of weekday letters
                // labels the columns beneath it and the month names the days,
                // so both are read before the dates they describe rather than
                // after them — which is what made the old arrangement feel like
                // furniture stacked at the wrong end of the card.
                _ControlBar(
                  month: _month,
                  onBack: _pane == _Pane.days && _canGoBack
                      ? () => _shift(-1)
                      : null,
                  onForward: _pane == _Pane.days && _canGoForward
                      ? () => _shift(1)
                      : null,
                  onMonths: () => _show(_Pane.months),
                  onYears: () => _show(_Pane.years),
                ),
                const SizedBox(height: Space.lg),
                // One height for every month, and for the month and year lists
                // alike. Taking the height of whatever is showing makes a
                // 5-week month and a 6-week one different dialogs, and paging
                // between them resizes the card under the point of contact.
                SizedBox(
                  height: _MonthGrid.heightIn(context),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _pane == _Pane.days
                            ? GestureDetector(
                                // The grid is turned by dragging it, which is how
                                // a month is turned everywhere else on a phone.
                                // The arrows stay: a gesture nothing announces
                                // cannot be the only way to reach a month.
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragEnd: _swipe,
                                child: AnimatedSwitcher(
                                  duration: Motion.fast,
                                  // A fade, and nothing else. The month used to
                                  // slide in from the side it came from, which
                                  // read as a page being dragged over another
                                  // page — a stack, for what is one grid being
                                  // replaced by another in the same frame.
                                  //
                                  // The month being left drops out on the first
                                  // frame rather than fading through the one
                                  // arriving: two grids over each other put a 2
                                  // beside every 3 and a ring around every ring.
                                  // `Threshold(1)`, not `Threshold(0)` — the
                                  // curve is `t < threshold ? 0 : 1`, so at 0 it
                                  // returns 1 for every t there is, a no-op that
                                  // held the old month at full opacity for the
                                  // whole transition. That is the version that
                                  // shipped in 1.6.0.
                                  switchOutCurve: const Threshold(1),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                  child: _MonthGrid(
                                    key: ValueKey(_monthKey),
                                    month: _month,
                                    selected: widget.initial,
                                    first: widget.first,
                                    last: widget.last,
                                    marks: widget.marks,
                                    onPick: (day) =>
                                        Navigator.of(context).pop(day),
                                    onRefuse: _refuse,
                                  ),
                                ),
                              )
                            : _pane == _Pane.months
                            ? _MonthList(
                                year: _month.year,
                                selected: _month,
                                first: widget.first,
                                last: widget.last,
                                onPick: (month) => setState(() {
                                  _month = DateTime(_month.year, month);
                                  _pane = _Pane.days;
                                }),
                              )
                            : _YearGrid(
                                first: widget.first.year,
                                last: widget.last.year,
                                selected: _month.year,
                                onPick: (year) => setState(() {
                                  _month = DateTime(year, _month.month).clamp(
                                    DateTime(
                                      widget.first.year,
                                      widget.first.month,
                                    ),
                                    DateTime(
                                      widget.last.year,
                                      widget.last.month,
                                    ),
                                  );
                                  _pane = _Pane.days;
                                }),
                              ),
                      ),
                      // Over the grid rather than under it, so the card is the
                      // same height whether or not a dead day has been tapped.
                      if (_refusal != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _Refusal(message: _refusal!),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get _monthKey => _month.year * 100 + _month.month;
}

/// Why a day refused the tap, drawn over the foot of the grid.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHighest,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.t.bodySmall?.copyWith(color: c.textSecondary),
      ),
    );
  }
}

/// The dialog's own header: the title on the left, ✕ on the right. Not
/// [SheetHeader] — there is no drag handle to hang under, and the ✕ sits on the
/// title's line for the same reason it does there.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      // Centred against the ✕ when the title is the only line, so a 26pt title
      // does not sit at the top of a 40pt button with the slack under it. With
      // a subtitle the ✕ goes back to the title's own line rather than floating
      // between the two, which is the rule every sheet header follows.
      crossAxisAlignment: subtitle == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.t.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Space.xxs),
                Text(
                  subtitle!,
                  style: context.t.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Space.sm),
        CircleIconButton(
          icon: Icons.close_rounded,
          fill: Colors.transparent,
          tooltip: 'Close',
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// The card's foot: the two month steps, then the month, then the year.
///
/// Under the grid rather than over it. The grid is what this dialog is opened
/// to read, so it takes the top of the card where reading starts, and the
/// controls sit where the thumb already is. Splitting `March 2026` into two
/// pills is the same move: a year six back was a month name tapped, a grid
/// read, and a month re-picked, where the two lists are now one tap each.
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.month,
    required this.onBack,
    required this.onForward,
    required this.onMonths,
    required this.onYears,
  });

  final DateTime month;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onMonths;
  final VoidCallback onYears;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // One step at each end, with the month's name between them: the two
        // directions sit either side of the thing they move, rather than
        // paired in a corner where the pair reads as one control and the name
        // reads as something else again.
        _Arrow(
          icon: Icons.chevron_left_rounded,
          onTap: onBack,
          tooltip: 'Previous month',
        ),
        Expanded(
          // Scaled as a pair when the room runs out, which keeps the chips' own
          // height and padding exactly as every other chip in the app wears
          // them. On a phone it never triggers — `September` and a four-digit
          // year fit at 384dp with room to spare — but a longer month name has
          // to make the bar smaller rather than wider than the card.
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `AppChip`, not a pill of this file's own: a chip with a
                  // caret is what the app calls a control that opens a picker,
                  // and these two are exactly that. The bespoke version had to
                  // be told its height and padding and got both wrong — 46 tall
                  // on 8 of side padding, a tall box pinched at the sides.
                  AppChip(
                    label: DateFormat('MMMM').format(month),
                    caret: true,
                    onTap: onMonths,
                  ),
                  const SizedBox(width: Space.sm),
                  AppChip(
                    label: '${month.year}',
                    caret: true,
                    onTap: onYears,
                  ),
                ],
              ),
            ),
          ),
        ),
        _Arrow(
          icon: Icons.chevron_right_rounded,
          onTap: onForward,
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

/// A month step, at either end of the bar.
class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CircleIconButton(
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      // Smaller than the app's default 40. These two are furniture beside the
      // month's name, and the name is what the row is for: every point they
      // take is a point `September` does not have.
      size: 36,
      fill: Colors.transparent,
      tint: onTap == null ? c.textTertiary : c.textPrimary,
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.first,
    required this.last,
    required this.marks,
    required this.onPick,
    required this.onRefuse,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime first;
  final DateTime last;
  final Map<int, Color> marks;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<String> onRefuse;

  /// Weeks start on Monday, and the labels come out of `intl` rather than a
  /// hardcoded list so they follow the same locale the dates do.
  static const _weekStart = DateTime.monday;

  /// Six rows, always. A month needs four, five or six depending on where its
  /// first day falls, so sizing to the month makes every page turn a resize.
  static const _rows = 6;
  static const _rowHeight = 44.0;

  /// The rows plus the gap plus the weekday strip — what the card reserves.
  ///
  /// The strip is the one part of this that scales: it is text, and a phone set
  /// to twice the type size draws it at twice the height. Reserving a flat 16
  /// for it overflowed the column by exactly the difference, so the figure is
  /// asked for rather than assumed.
  static double heightIn(BuildContext context) =>
      _rows * _rowHeight +
      _stripGap +
      MediaQuery.textScalerOf(context).scale(16);

  /// The gap between the last row of days and the weekday strip, named because
  /// the reserved height above and the `SizedBox` in the grid have to agree.
  /// They did not once, and the column overflowed by the two points of the
  /// difference.
  static const _stripGap = Space.md;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = _midnight(DateTime.now());
    final firstOfMonth = DateTime(month.year, month.month);
    final leading = (firstOfMonth.weekday - _weekStart) % 7;

    return Column(
      children: [
        // The letters label the columns under them, so they sit above those
        // columns. Below the grid they were a legend for something already
        // read.
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    // Any known Monday, walked forward — the narrow name is the
                    // formatter's, not ours. Named rather than added to, like
                    // every other date in the app: this one could not have gone
                    // wrong, and leaving it would make the rule look optional.
                    DateFormat('EEEEE').format(DateTime(2024, 1, 1 + i)),
                    style: context.t.labelSmall?.copyWith(
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: _stripGap),
        for (var row = 0; row < _rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      // Counted off the first of the month, so the days either
                      // side of it are the neighbouring months' own dates
                      // rather than blanks. Every month is then the same six
                      // full rows, and the grid stops changing shape under a
                      // page turn while the card's height stays put.
                      final day = DateTime(
                        month.year,
                        month.month,
                        row * 7 + col - leading + 1,
                      );
                      final ahead = day.isAfter(last);
                      final behind = day.isBefore(first);
                      return _DayCell(
                        key: ValueKey(dayKeyOf(day)),
                        day: day,
                        selected: day.sameDay(selected),
                        isToday: day.sameDay(today),
                        mark: marks[dayKeyOf(day)],
                        beyond: ahead || behind,
                        // A day belonging to the month either side of this one.
                        // Drawn, because six ragged rows and six full ones are
                        // two different cards; recessive, because the month on
                        // show is the one being read.
                        adjacent: day.month != month.month,
                        onTap: ahead
                            ? () => onRefuse(
                                'A day that has not happened cannot be logged.',
                              )
                            : behind
                            ? () => onRefuse(
                                'There is nothing in the log this far back.',
                              )
                            : () => onPick(day),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// One day.
///
/// Four facts stack on one circle, ranked so none of them hides another.
///
/// The ring says whether the day holds anything: the day's own colour when it
/// does (`heatOn` blue for a session, `deload` orange for a light week), and
/// `heatEmpty` — the grey an untrained day wears in the heatmap — when it does
/// not. Both rings are drawn, because *logged* and *not logged* are read
/// against each other; a ring against a bare number is two states one of which
/// looks like nothing rendered.
///
/// A day past the range has no ring at all, which is the shape of a day that
/// holds nothing and can hold nothing. Today carries a dot under its number
/// whichever ring it has, so the grid says where the present is without
/// spending the ring on it. The `accent` fill is the day currently picked, and
/// a marked day keeps its coloured ring around that fill — the whole point of
/// the ring is that it survives being looked at.
class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.selected,
    required this.isToday,
    required this.mark,
    required this.beyond,
    required this.adjacent,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;

  /// Non-null when something was logged that day.
  final Color? mark;

  /// Outside the range: shown, ringless, and answering the tap with a reason.
  final bool beyond;

  /// A date belonging to the month before or after the one on show.
  final bool adjacent;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = selected
        ? c.onAccent
        : beyond
        ? c.textTertiary
        : c.textPrimary;

    final ring = beyond ? null : mark ?? c.heatEmpty;

    // The neighbouring month is drawn back, ring and number together, so
    // the grid is six full rows without those rows competing with the month
    // being read — far enough back to be scenery, near enough to still be read
    // as a date. Opacity rather than a paler set of colours: the ring has to
    // stay the colour it is — a logged day either side of the seam is still
    // blue, only quieter — and two tones per state would be four to keep in
    // step for no gain.
    return Opacity(
      opacity: adjacent ? 0.42 : 1,
      child: SizedBox(
        height: 44,
        child: Pressable(
          onTap: onTap,
          scale: 0.92,
          child: Center(
            // Not an `AnimatedContainer`. Nothing about a day changes while the
            // card is open — the mark, the selection, today and the range are all
            // fixed for the life of the dialog — so the only time a tween ever
            // ran was across a month change, where the cell is reused for a
            // different day and the animation drags the old ring onto the new
            // one. Paging August onto September showed a grey ring fading off
            // days that have not happened yet.
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.accent : Colors.transparent,
                border: ring == null
                  ? null
                  // A logged day's ring is the heavier of the two. At one
                  // weight the grid is forty-two identical circles and the
                  // colour is the only difference between a day that holds
                  // something and a day that does not; at two, the shape says
                  // it before the colour is read.
                  : Border.all(color: ring, width: mark == null ? 1.5 : 2),
              ),
              // Stacked rather than stacked in a `Column`: the number keeps the
              // centre of the circle whether or not the dot is under it, and a
              // phone set to twice the type size overflows a vertical flex here
              // — 38dp is a circle sized for a two-digit number, not for a
              // number and a dot in a column that has to fit both.
              // Aligned rather than stacked in a `Column`: a vertical flex has
              // to fit both children inside 38dp, and a phone set to twice the
              // type size overflows it. Two alignments inside the circle instead
              // — the number lifted just off centre, the dot below it and clear
              // of the ring — which cannot overflow whatever the type size.
              child: Stack(
                children: [
                  Align(
                    alignment: const Alignment(0, -0.2),
                    child: Text(
                      '${day.day}',
                      style: context.t.labelLarge?.copyWith(color: fg),
                    ),
                  ),
                  if (isToday)
                    Align(
                      alignment: const Alignment(0, 0.78),
                      child: SizedBox(
                        width: 4,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: fg,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The twelve months of the year on show, for moving inside it.
///
/// Three across rather than four: a month's name is `September`, and four to a
/// row is either an abbreviation nobody asked for or twelve pills of ellipsis.
class _MonthList extends StatelessWidget {
  const _MonthList({
    required this.year,
    required this.selected,
    required this.first,
    required this.last,
    required this.onPick,
  });

  final int year;
  final DateTime selected;
  final DateTime first;
  final DateTime last;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final firstMonth = DateTime(first.year, first.month);
    final lastMonth = DateTime(last.year, last.month);
    return SingleChildScrollView(
      child: Column(
        children: [
          for (var row = 0; row < 4; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                children: [
                  for (var col = 0; col < 3; col++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final month = row * 3 + col + 1;
                          final at = DateTime(year, month);
                          final usable =
                              !at.isBefore(firstMonth) &&
                              !at.isAfter(lastMonth);
                          final live =
                              month == selected.month && year == selected.year;
                          return Pressable(
                            onTap: usable ? () => onPick(month) : null,
                            scale: 0.94,
                            child: Container(
                              height: 44,
                              margin: const EdgeInsets.symmetric(
                                horizontal: Space.xs,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: live ? c.accent : c.surfaceHigh,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                              child: Text(
                                DateFormat('MMM').format(at),
                                style: context.t.labelLarge?.copyWith(
                                  color: live
                                      ? c.onAccent
                                      : usable
                                      ? c.textPrimary
                                      : c.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Newest year first: the reason to open this is usually a day last month that
/// fell on the other side of January, not a session in 2016.
class _YearGrid extends StatelessWidget {
  const _YearGrid({
    required this.first,
    required this.last,
    required this.selected,
    required this.onPick,
  });

  final int first;
  final int last;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final years = [for (var y = last; y >= first; y--) y];
    // Scrolls, because a history that starts in 1976 is fifty years of pills
    // and the card's height is fixed. A plain `Column` overflows the moment the
    // log outgrows a decade.
    return SingleChildScrollView(
      child: Column(
        children: [
          for (var row = 0; row * 4 < years.length; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                children: [
                  for (var col = 0; col < 4; col++)
                    Expanded(
                      child: row * 4 + col >= years.length
                          ? const SizedBox(height: 44)
                          : Builder(
                              builder: (context) {
                                final year = years[row * 4 + col];
                                final live = year == selected;
                                return Pressable(
                                  onTap: () => onPick(year),
                                  scale: 0.94,
                                  child: Container(
                                    height: 44,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: Space.xs,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: live ? c.accent : c.surfaceHigh,
                                      borderRadius: BorderRadius.circular(
                                        Radii.pill,
                                      ),
                                    ),
                                    child: Text(
                                      '$year',
                                      style: context.t.labelLarge?.copyWith(
                                        color: live
                                            ? c.onAccent
                                            : c.textPrimary,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
