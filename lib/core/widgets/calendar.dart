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
/// [marks] rings the days you trained, keyed by `dayKey` — `heatOn` blue for a
/// session, `deload` orange for a light week. A calendar of identical white
/// numbers cannot answer the question it is opened with, which is *which day
/// did I miss*.
///
/// A dialog, not a sheet: this is a grid you read before you tap, the one
/// picker in the app that is looked at rather than scrolled, and a sheet put it
/// under your thumb at the bottom of the screen with the month you are reading
/// furthest from your eyes.
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

class _CalendarCardState extends State<_CalendarCard> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  /// The year grid, opened by tapping the month's name. Six years back through
  /// a chevron is eighteen taps; a programme edited in 2019 is two.
  bool _pickingYear = false;

  bool get _canGoBack =>
      _month.isAfter(DateTime(widget.first.year, widget.first.month));

  bool get _canGoForward =>
      _month.isBefore(DateTime(widget.last.year, widget.last.month));

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

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
          _MonthBar(
            label: _pickingYear
                ? '${_month.year}'
                : DateFormat('MMMM yyyy').format(_month),
            onTapLabel: () => setState(() => _pickingYear = !_pickingYear),
            onBack: _pickingYear || !_canGoBack ? null : () => _shift(-1),
            onForward: _pickingYear || !_canGoForward ? null : () => _shift(1),
            expanded: _pickingYear,
          ),
          const SizedBox(height: Space.md),
          // One height for every month and for the year grid alike. It used to
          // take the height of whatever it was showing, so a 5-week month and a
          // 6-week one were different dialogs and paging between them resized
          // the card under your thumb.
          SizedBox(
            height: _MonthGrid.height,
            child: _pickingYear
                ? _YearGrid(
                    first: widget.first.year,
                    last: widget.last.year,
                    selected: _month.year,
                    onPick: (year) => setState(() {
                      _month = DateTime(year, _month.month);
                      _pickingYear = false;
                    }),
                  )
                : _MonthGrid(
                    month: _month,
                    selected: widget.initial,
                    first: widget.first,
                    last: widget.last,
                    marks: widget.marks,
                    onPick: (day) => Navigator.of(context).pop(day),
                  ),
          ),
        ],
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

/// `‹  March 2026  ›`. The name is the control that opens the year grid, which
/// is why it is `title` type and centred rather than a heading on the left.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.label,
    required this.onTapLabel,
    required this.onBack,
    required this.onForward,
    required this.expanded,
  });

  final String label;
  final VoidCallback onTapLabel;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        _Arrow(
          icon: Icons.chevron_left_rounded,
          onTap: onBack,
          tooltip: 'Previous month',
        ),
        Expanded(
          child: Pressable(
            onTap: onTapLabel,
            scale: 0.96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: context.t.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.xs),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
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

/// A month step. Disabled at the ends of the range rather than hidden: a
/// control that disappears makes the row re-centre as you page through it.
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
      fill: onTap == null ? Colors.transparent : c.surfaceHigh,
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
  });

  final DateTime month;
  final DateTime selected;
  final DateTime first;
  final DateTime last;
  final Map<int, Color> marks;
  final ValueChanged<DateTime> onPick;

  /// Weeks start on Monday, and the labels come out of `intl` rather than a
  /// hardcoded list so they follow the same locale the dates do.
  static const _weekStart = DateTime.monday;

  /// Six rows, always. A month needs four, five or six depending on where its
  /// first day falls, and sizing to the month made every page turn a resize.
  static const _rows = 6;
  static const _rowHeight = 44.0;

  /// The weekday strip plus its gap plus the rows — what the card reserves.
  static const height = 16 + Space.sm + _rows * _rowHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = _midnight(DateTime.now());
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = (DateTime(month.year, month.month).weekday - _weekStart) % 7;

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    // Any known Monday, walked forward — the narrow name is the
                    // formatter's, not ours.
                    DateFormat('EEEEE')
                        .format(DateTime(2024, 1, 1).add(Duration(days: i))),
                    style: context.t.bodySmall?.copyWith(color: c.textTertiary),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
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
                      final usable =
                          !day.isBefore(first) && !day.isAfter(last);
                      return _DayCell(
                        day: day,
                        selected: day.sameDay(selected),
                        isToday: day.sameDay(today),
                        mark: marks[dayKeyOf(day)],
                        onTap: usable ? () => onPick(day) : null,
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
/// Three states stack on one circle, and they are ranked so none of them hides
/// another: a **ring in the day's own colour** for a day you trained (`heatOn`
/// blue, `deload` orange), the **`accent` fill** for the day currently chosen,
/// and the `textTertiary` ring for today. A trained day that is also selected
/// keeps its coloured ring around the white fill — the whole point of the ring
/// is that it survives being looked at.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.mark,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;

  /// Non-null when something was logged that day.
  final Color? mark;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = selected
        ? c.onAccent
        : onTap == null
            ? c.textTertiary
            : c.textPrimary;

    final ring = mark ?? (isToday ? c.textTertiary : null);

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
            child: Text(
              '${day.day}',
              style: context.t.labelLarge?.copyWith(color: fg),
            ),
          ),
        ),
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
    // and the card's height is fixed. It was a plain `Column`, which overflowed
    // the moment the log outgrew a decade.
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
