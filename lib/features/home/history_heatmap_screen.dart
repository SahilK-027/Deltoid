import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'heatmap_data.dart';
import 'home_providers.dart';
import 'widgets/heatmap.dart';
import 'widgets/year_heatmap.dart';

/// Everything ever logged, a year at a time.
///
/// The Workouts grid is eighteen weeks because that is what fits above the fold and
/// what you act on. This is the other question — "how has this year gone" — and
/// a year here means a **whole** year on screen: no horizontal scrolling, cells
/// sized to fit. A year you have to drag through is not a year at a glance,
/// which is the only reason to open this screen.
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
    final years = [for (var y = now.year; y >= firstDate.year; y--) y];

    // Sessions per year, counted once here rather than by each year block
    // walking the whole map — that was O(years x days) and thirty years of it
    // ran on every build.
    final byYear = <int, int>{};
    for (final entry in days.entries) {
      final year = entry.key ~/ 10000;
      byYear[year] = (byYear[year] ?? 0) + entry.value.workouts;
    }

    // `.builder`, not a list of children: a `ListView` with children builds
    // every one of them before the first frame, which with thirty years meant
    // thirty grids painted to show two.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, Space.lg, Space.gutter, Space.huge),
      itemCount: years.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.section),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total session${total == 1 ? '' : 's'} since '
                  '${DateFormat('MMMM y').format(firstDate)}',
                  style: context.t.titleMedium,
                ),
                const SizedBox(height: Space.md),
                const HeatmapLegend(),
              ],
            ),
          );
        }

        final year = years[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The count as a figure on the heading's right, the way History
              // states a month's — not as a subtitle, which would make this
              // heading taller than every other one in the app.
              SectionHeader(
                '$year',
                trailing: Text(
                  '${byYear[year] ?? 0} session'
                  '${(byYear[year] ?? 0) == 1 ? '' : 's'}',
                  style: context.t.bodySmall,
                ),
              ),
              AppCard(
                // The 16 of every chart card, shy of even at the bottom: the
                // month strip is 18dp tall for a 14dp line, so it carries ~4dp
                // of its own slack under the labels. Padding the full 16
                // there put the grid visibly high in the card.
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, Space.lg, Space.lg, Space.md),
                child: YearHeatmap(
                  year: year,
                  days: TrainingYearDays(days),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
