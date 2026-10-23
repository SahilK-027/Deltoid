import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/habits.dart';

/// One habit, kept or not, this week (THEME → Components → Habit tile).
///
/// Shaped as a stat tile is: the name with `Last 30 days` under it, the habit's
/// one action at the top right, the grid, a hairline, then `3/7 this week` and
/// a chevron. Two sit side by side under `Habits` on Home, and every tile is
/// the same shape, so the row is `CrossAxisAlignment.start` and nothing else.
///
/// The figure is a count and says nothing else: no flame, no colour that moves
/// with the number, nothing at `7/7` that `6/7` lacks (RULES § 6).
class HabitTile extends StatelessWidget {
  const HabitTile({
    super.key,
    required this.title,
    required this.fill,
    required this.thisWeek,
    required this.onTap,
    this.action,
    this.today,
  });

  final String title;

  /// The colour of a day in the grid, or null for a day the habit was not kept,
  /// which draws in `heatEmpty`.
  final Color? Function(int dayKey) fill;

  /// Days kept this calendar week, or null with nothing ever logged, which
  /// prints a dash where the count goes: a zero is a measurement, and a dash
  /// is nothing here yet (THEME rule 4).
  final int? thisWeek;

  /// Opens the habit's full map. The [action] takes its own taps, so pressing
  /// it never also opens the tile.
  final VoidCallback onTap;

  /// The round button at the top right, a [HabitAction], or null when there is
  /// nothing for it to do. Absent rather than disabled.
  final Widget? action;

  /// The last day of the grid. Tests pin it; the app passes nothing.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final count = thisWeek;
    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Last $habitWindowDays days',
                      style: context.t.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: Space.sm),
                action!,
              ],
            ],
          ),
          const SizedBox(height: Space.lg),
          HabitGrid(fill: fill, today: today ?? DateTime.now()),
          const SizedBox(height: Space.lg),
          const Divider(),
          const SizedBox(height: Space.md),
          Row(
            children: [
              // Only the words give way. The figure is never longer than
              // `7/7`, and two `Flexible`s split the row in half, which cut
              // `this week` short in half a phone's width while the figure
              // left most of its half empty.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      count == null ? '—/7' : '$count/7',
                      style: context.t.labelLarge,
                      maxLines: 1,
                    ),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(
                        'this week',
                        style: context.t.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: c.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The habit's one action: a 36dp circular icon button.
///
/// 36 rather than the usual 40, because it shares a corner with two lines of
/// text rather than a row of buttons. The label is required, as on every
/// circular icon button.
class HabitAction extends StatelessWidget {
  const HabitAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CircleIconButton(
        icon: icon,
        tooltip: tooltip,
        onTap: onTap,
        size: 36,
        glyphScale: 0.5,
      );
}

/// The last thirty days in ten columns of three, oldest first and today last.
///
/// Filled down each column and then across, the order the year map is read
/// in. Filled along each row instead, the same days read in a different order
/// from the map the tile opens, and a run of recent days looked missing.
///
/// Thirty widgets rather than a painter: the year maps paint because they draw
/// a year at a time, many years deep, and this is one month in one card.
class HabitGrid extends StatelessWidget {
  const HabitGrid({super.key, required this.fill, required this.today});

  final Color? Function(int dayKey) fill;
  final DateTime today;

  static const _columns = 10;
  static const _perColumn = 3;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final empty = context.c.heatEmpty;
    final days = habitWindow(today);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell =
            (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        return Row(
          children: [
            for (var column = 0; column < _columns; column++) ...[
              if (column > 0) const SizedBox(width: _gap),
              Column(
                children: [
                  for (var i = 0; i < _perColumn; i++) ...[
                    if (i > 0) const SizedBox(height: _gap),
                    Container(
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        color: fill(days[column * _perColumn + i]) ?? empty,
                        borderRadius: BorderRadius.circular(Radii.heatCell),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
