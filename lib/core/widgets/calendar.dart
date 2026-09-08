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
  final firstDay = _midnight(first ?? DateTime(2015));
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

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.sheet),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(title: widget.title, subtitle: widget.subtitle),
          const SizedBox(height: Space.md),
          // One height for every month, and for the month and year lists alike.
          // Taking the height of whatever is showing makes a 5-week month and a
          // 6-week one different dialogs, and paging between them resizes the
          // card under the point of contact.
          SizedBox(
            height: _MonthGrid.heightIn(context),
            child: Stack(
              children: [
                Positioned.fill(child: _pane == _Pane.days
                    ? _MonthGrid(
                        month: _month,
                        selected: widget.initial,
                        first: widget.first,
                        last: widget.last,
                        marks: widget.marks,
                        onPick: (day) => Navigator.of(context).pop(day),
                        onRefuse: _refuse,
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
                              _month = DateTime(year, _month.month)
                                  .clamp(
                                    DateTime(
                                        widget.first.year, widget.first.month),
                                    DateTime(
                                        widget.last.year, widget.last.month),
                                  );
                              _pane = _Pane.days;
                            }),
                          )),
                // Over the grid rather than under it, so the card is the same
                // height whether or not a dead day has been tapped.
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
          const SizedBox(height: Space.md),
          _ControlBar(
            month: _month,
            pane: _pane,
            onBack: _pane == _Pane.days && _canGoBack ? () => _shift(-1) : null,
            onForward:
                _pane == _Pane.days && _canGoForward ? () => _shift(1) : null,
            onMonths: () => _show(_Pane.months),
            onYears: () => _show(_Pane.years),
          ),
        ],
      ),
    );
  }
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
    required this.pane,
    required this.onBack,
    required this.onForward,
    required this.onMonths,
    required this.onYears,
  });

  final DateTime month;
  final _Pane pane;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onMonths;
  final VoidCallback onYears;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        // The two steps read as one control, because they do one thing in two
        // directions. Disabled at the ends of the range rather than hidden: a
        // control that is removed makes the row re-flow while paging.
        Container(
          decoration: BoxDecoration(
            color: c.surfaceHigh,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Arrow(
                icon: Icons.chevron_left_rounded,
                onTap: onBack,
                tooltip: 'Previous month',
              ),
              _Arrow(
                icon: Icons.chevron_right_rounded,
                onTap: onForward,
                tooltip: 'Next month',
              ),

            ],
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: _Pill(
            label: DateFormat('MMMM').format(month),
            open: pane == _Pane.months,
            onTap: onMonths,
          ),
        ),
        const SizedBox(width: Space.sm),
        _Pill(
          label: '${month.year}',
          open: pane == _Pane.years,
          onTap: onYears,
        ),
      ],
    );
  }
}

/// One of the two list openers. `Deltoid` has no other dropdown, so this is a
/// pill with a chevron on it rather than a `DropdownButton` wearing the theme.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        height: Sizes.controlCompact,
        // `md` rather than `lg`: `September` and a four-digit year have to sit
        // beside the two steps on the narrowest phone this app runs on, and a
        // month name that ellipsises is the one thing this bar cannot do.
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                style: context.t.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Space.xs),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: Motion.fast,
              curve: Motion.curve,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A month step, inside the pair.
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
      fill: Colors.transparent,
      tint: onTap == null ? c.textTertiary : c.textPrimary,
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
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
      _rows * _rowHeight + Space.sm + MediaQuery.textScalerOf(context).scale(16);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = _midnight(DateTime.now());
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = (DateTime(month.year, month.month).weekday - _weekStart) % 7;

    return Column(
      children: [
        for (var row = 0; row < _rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final index = row * 7 + col - leading;
                      if (index < 0 || index >= daysInMonth) {
                        return const SizedBox(height: _rowHeight);
                      }
                      final day = DateTime(month.year, month.month, index + 1);
                      final ahead = day.isAfter(last);
                      final behind = day.isBefore(first);
                      return _DayCell(
                        day: day,
                        selected: day.sameDay(selected),
                        isToday: day.sameDay(today),
                        mark: marks[dayKeyOf(day)],
                        beyond: ahead || behind,
                        onTap: ahead
                            ? () => onRefuse(
                                'A day that has not happened cannot be logged.')
                            : behind
                                ? () => onRefuse(
                                    'There is nothing in the log this far back.')
                                : () => onPick(day),
                      );
                    },
                  ),
                ),
            ],
          ),
        const SizedBox(height: Space.sm),
        // Under the grid, with the controls. The column a day sits in is read
        // off the day beside it far more often than off a letter, and the strip
        // is a legend rather than a heading — it belongs where the rest of the
        // card's furniture is.
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
                    style: context.t.bodySmall?.copyWith(color: c.textTertiary),
                  ),
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
    required this.day,
    required this.selected,
    required this.isToday,
    required this.mark,
    required this.beyond,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;

  /// Non-null when something was logged that day.
  final Color? mark;

  /// Outside the range: shown, ringless, and answering the tap with a reason.
  final bool beyond;

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

    return SizedBox(
      height: 44,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? c.accent : Colors.transparent,
              border: ring == null ? null : Border.all(color: ring, width: 2),
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
                          final usable = !at.isBefore(firstMonth) &&
                              !at.isAfter(lastMonth);
                          final live =
                              month == selected.month && year == selected.year;
                          return Pressable(
                            onTap: usable ? () => onPick(month) : null,
                            scale: 0.94,
                            child: Container(
                              height: 44,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: Space.xs),
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
                                      horizontal: Space.xs),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color:
                                        live ? c.accent : c.surfaceHigh,
                                    borderRadius:
                                        BorderRadius.circular(Radii.pill),
                                  ),
                                  child: Text(
                                    '$year',
                                    style: context.t.labelLarge?.copyWith(
                                      color: live ? c.onAccent : c.textPrimary,
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
