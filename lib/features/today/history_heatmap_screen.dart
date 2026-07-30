import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'heatmap_data.dart';
import 'today_providers.dart';
import 'widgets/heatmap.dart';

/// Everything ever logged, a year at a time.
///
/// Today's grid is thirteen weeks because that is what fits and what you act on.
/// This is the other question — "how has this year gone" — and it gets a screen
/// rather than a taller card.
class HistoryHeatmapScreen extends ConsumerWidget {
  const HistoryHeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(fullHeatmapProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Consistency')),
      body: switch (data) {
        // Local disk again: a spinner here would show for two frames.
        null => const SizedBox.shrink(),
        final d when d.days.isEmpty => const EmptyState(
            icon: Icons.grid_view_outlined,
            title: 'Nothing logged yet',
            message: 'Finish a session and every year you train lands here.',
          ),
        final d => _Years(days: d.days),
      },
    );
  }
}

class _Years extends StatelessWidget {
  const _Years({required this.days});

  final Map<int, HeatDay> days;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstKey = days.keys.reduce((a, b) => a < b ? a : b);
    final firstDate = dateFromDayKey(firstKey);
    final total = days.values.fold(0, (sum, d) => sum + d.workouts);

    // Newest first: scrolling down goes back in time, which is the direction
    // history reads everywhere else in the app.
    final years = [
      for (var y = now.year; y >= firstDate.year; y--) y,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.sm, Space.lg, Space.huge),
      children: [
        Text(
          '$total session${total == 1 ? '' : 's'} since '
          '${DateFormat('d MMM y').format(firstDate)}',
          style: context.t.bodyMedium,
        ),
        const SizedBox(height: Space.md),
        const HeatmapLegend(),
        const SizedBox(height: Space.xl),
        for (final year in years) ...[
          _YearBlock(
            year: year,
            days: days,
            isCurrent: year == now.year,
          ),
          const SizedBox(height: Space.xl),
        ],
      ],
    );
  }
}

/// One calendar year as week columns.
///
/// Stateful only to park the horizontal scroll at today on the current year —
/// opening this on a December evening should not show you January.
class _YearBlock extends StatefulWidget {
  const _YearBlock({
    required this.year,
    required this.days,
    required this.isCurrent,
  });

  final int year;
  final Map<int, HeatDay> days;
  final bool isCurrent;

  @override
  State<_YearBlock> createState() => _YearBlockState();
}

class _YearBlockState extends State<_YearBlock> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    if (!widget.isCurrent) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cell = 13.0;
    const gap = 3.0;
    const labelWidth = 22.0;

    // UTC for the same reason the compact grid uses it: `add(Duration(days: 1))`
    // across a DST boundary lands on 23:00 the day before, which would double a
    // column twice a year. `dayKeyOf` only reads y/m/d.
    final now = DateTime.now();
    final todayKey = dayKeyOf(now);
    final jan1 = DateTime.utc(widget.year, 1, 1);
    final start = jan1.subtract(Duration(days: jan1.weekday - 1));
    // The current year stops at this week rather than drawing ten months of
    // empty cells; past years run to the end.
    final lastDay = widget.isCurrent
        ? DateTime.utc(now.year, now.month, now.day)
        : DateTime.utc(widget.year, 12, 31);
    final end = lastDay.add(Duration(days: 7 - lastDay.weekday));
    final weeks = (end.difference(start).inDays + 1) ~/ 7;

    var sessions = 0;
    for (final entry in widget.days.entries) {
      if (dateFromDayKey(entry.key).year == widget.year) {
        sessions += entry.value.workouts;
      }
    }

    final columns = <Widget>[];
    var lastMonth = -1;

    for (var w = 0; w < weeks; w++) {
      final cells = <Widget>[];
      var monthLabel = '';

      for (var d = 0; d < 7; d++) {
        final date = start.add(Duration(days: w * 7 + d));
        final key = dayKeyOf(date);
        // Days either side of the year boundary belong to a neighbouring year's
        // block, so this one leaves a hole rather than drawing them twice.
        final outside = date.year != widget.year;

        if (d == 0 && date.month != lastMonth && !outside) {
          lastMonth = date.month;
          monthLabel = DateFormat('MMM').format(date);
        }

        cells.add(Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: outside
              ? const SizedBox(width: cell, height: cell)
              : HeatCell(
                  date: date,
                  day: widget.days[key],
                  size: cell,
                  isFuture: key > todayKey,
                ),
        ));
      }

      columns.add(Padding(
        padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 14,
              width: cell,
              child: monthLabel.isEmpty
                  ? null
                  : OverflowBox(
                      maxWidth: 40,
                      alignment: Alignment.centerLeft,
                      child: Text(monthLabel, style: context.t.labelSmall),
                    ),
            ),
            ...cells,
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          '${widget.year}',
          trailing: Text(
            '$sessions session${sessions == 1 ? '' : 's'}',
            style: context.t.labelMedium?.copyWith(color: context.c.accent),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    for (final label in ['M', '', 'W', '', 'F', '', 'S'])
                      SizedBox(
                        height: cell + gap,
                        child: Text(label, style: context.t.labelSmall),
                      ),
                  ],
                ),
              ),
              // The weekday labels stay put while the year scrolls under them.
              Expanded(
                child: SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  child: Row(children: columns),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
