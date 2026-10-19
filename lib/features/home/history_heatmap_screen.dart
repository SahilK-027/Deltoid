import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/consistency_year.dart';
import 'heatmap_data.dart';
import 'home_providers.dart';
import 'widgets/heatmap.dart';
import 'widgets/session_bars.dart';
import 'widgets/year_calendar.dart';

/// Everything ever logged, one year at a time.
///
/// The year map this screen drew put fifty-three weeks across a phone, at
/// cells of about 5dp: the year read as a texture, and no single week could be
/// picked out of it. The question this screen answers is how consistent each
/// week was, so the week is the unit it draws. One year is on screen, chosen
/// from the year sheet, and it is drawn twice: as sessions per week, a bar a
/// week, and as twelve month calendars of the days themselves. A week picked
/// on the chart is ringed in the calendar.
class HistoryHeatmapScreen extends ConsumerStatefulWidget {
  const HistoryHeatmapScreen({super.key});

  @override
  ConsumerState<HistoryHeatmapScreen> createState() =>
      _HistoryHeatmapScreenState();
}

class _HistoryHeatmapScreenState extends ConsumerState<HistoryHeatmapScreen> {
  /// The year on screen. Null until one is chosen, which is this year.
  int? _year;

  /// The week being read on the chart, as an index into the year's weeks.
  int? _picked;

  @override
  Widget build(BuildContext context) {
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
        final d => _body(d.days),
      },
    );
  }

  Widget _body(Map<int, HeatDay> days) {
    final today = DateTime.now();
    final years = consistencyYears(days.keys, today: today);
    final year = _year != null && years.contains(_year) ? _year! : years.first;
    final logged = <int, LoggedDayCount>{
      for (final MapEntry(:key, :value) in days.entries)
        key: (sessions: value.workouts, deload: value.isDeload),
    };
    final fold = foldConsistencyYear(logged, year: year, today: today);
    final picked =
        _picked != null && _picked! < fold.weeks.length ? _picked : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pinned over the page, as the range row is on Volume: it governs both
        // cards, so it stays in reach while they scroll.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.md, Space.lg, Space.md),
          child: AppChip(
            label: '$year',
            icon: Icons.calendar_today_rounded,
            selected: true,
            caret: true,
            onTap: () => _pickYear(years, days, year),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, 0, Space.gutter, Space.huge),
            children: [
              // Each count is stated once: sessions in this heading, days in
              // the calendar's, and the two rates in the card.
              SectionHeader(
                'Sessions per week',
                trailing: Text(
                  _count(fold.sessions, 'session'),
                  style: context.t.bodySmall,
                ),
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatRow(
                      children: [
                        StatTile(
                          value: fold.averagePerWeek?.toStringAsFixed(1) ??
                              '——',
                          label: 'Average a week',
                        ),
                        StatTile(
                          value: fold.weeksCounted == 0
                              ? '——'
                              : '${fold.weeksTrained}',
                          unit: fold.weeksCounted == 0
                              ? null
                              : 'of ${fold.weeksCounted}',
                          label: 'Weeks trained',
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xl),
                    SessionBars(
                      // A different year is a different chart: nothing picked
                      // on the last one carries over.
                      key: ValueKey(year),
                      weeks: fold.weeks,
                      picked: picked,
                      today: today,
                      onPicked: (i) => setState(() => _picked = i),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.section),
              SectionHeader(
                'Training calendar',
                trailing: Text(
                  _count(fold.trainingDays, 'day'),
                  style: context.t.bodySmall,
                ),
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YearCalendar(
                      year: year,
                      days: days,
                      today: today,
                      week: picked == null ? null : fold.weeks[picked].start,
                    ),
                    const SizedBox(height: Space.lg),
                    Divider(height: 1, thickness: 1, color: context.c.border),
                    const SizedBox(height: Space.md),
                    // One legend for both cards: the bars are drawn in the
                    // calendar's colours.
                    const HeatmapLegend(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  /// The year sheet: newest first, each year with its sessions, the one on
  /// screen checked. A list rather than a stepper, so a year a decade back is
  /// one tap and a scroll, not ten presses of an arrow.
  Future<void> _pickYear(
    List<int> years,
    Map<int, HeatDay> days,
    int current,
  ) async {
    final byYear = <int, int>{};
    for (final MapEntry(:key, :value) in days.entries) {
      final y = key ~/ 10000;
      byYear[y] = (byYear[y] ?? 0) + value.workouts;
    }

    final picked = await showAppSheet<int>(
      context,
      capped: true,
      builder: (sheet) => AppSheet(
        title: 'Which year?',
        contentPadding: const EdgeInsets.fromLTRB(
            Space.gutter, 0, Space.gutter, Space.lg),
        children: [
          for (final y in years)
            AppRow(
              title: '$y',
              subtitle: _count(byYear[y] ?? 0, 'session'),
              onTap: () => Navigator.of(sheet).pop(y),
              trailing: AppRadio(selected: y == current),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _year = picked;
      _picked = null;
    });
  }
}
