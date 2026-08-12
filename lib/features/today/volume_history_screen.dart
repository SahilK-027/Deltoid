import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/trend_chart.dart';
import '../../domain/muscle_volume.dart';
import '../../domain/volume_history.dart';
import 'region_volume_screen.dart';
import 'volume_providers.dart';
import 'widgets/volume_tile.dart';

/// Sets per muscle per week, over months and years.
///
/// Today's bar list answers "have I trained this muscle enough lately" over
/// seven days. This is the other question — "have I ever" — and it is the one
/// the app could not answer at all: a rolling window recomputed on every open
/// and forgotten, with no way to ask what a year looked like.
///
/// Reached from the volume card on Today, exactly as the year heatmap is
/// reached from the consistency card above it.
class VolumeHistoryScreen extends ConsumerWidget {
  const VolumeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(volumeHistoryProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Volume')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned: a control that governs the page stays reachable while the
          // page scrolls under it (THEME → Mastheads).
          const VolumeRangeBar(),
          Expanded(
            child: switch (history) {
              // Local disk: a spinner here would show for two frames.
              null => const SizedBox.shrink(),
              final h when h.isEmpty => const EmptyState(
                  icon: Icons.bar_chart_rounded,
                  title: 'Nothing counted yet',
                  message: 'Tick some sets and the weeks land here, '
                      'one bar each.',
                ),
              final h => _Grid(history: h),
            },
          ),
        ],
      ),
    );
  }
}

/// The range chips and the year picker, shared with every other chart in the
/// app (THEME → Charts: one chart and one range control, both shared).
class VolumeRangeBar extends ConsumerWidget {
  const VolumeRangeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(volumeWindowProvider);
    final years = ref.watch(volumeYearsProvider).valueOrNull ?? const <int>[];

    return Padding(
      // A real gap under the app bar. At zero the chips sat against the bar's
      // hairline and read as part of it rather than as the page's control.
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      child: TrendRangeBar(
        window: window,
        years: years,
        // A week of weekly bars is one bar. The shortest range this screen can
        // honestly draw is a month, and the chips it does not offer are the
        // chips it does not show.
        ranges: const [
          ChartRange.month,
          ChartRange.threeMonths,
          ChartRange.year,
        ],
        onChanged: (w) =>
            ref.read(volumeWindowProvider.notifier).state = w,
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.history});

  final VolumeHistory history;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          _summary(history),
          style: context.t.bodyMedium,
        ),
        const SizedBox(height: Space.md),
        // Two columns of rows rather than a `GridView`: a grid wants a
        // `childAspectRatio`, which is a guess about how tall a card is, and
        // the guess is what clips the figure off the bottom on a small phone.
        //
        // `start`, not `stretch` or `IntrinsicHeight`. Every tile is the same
        // shape — one line of title, one of caption, a fixed chart, a figure —
        // so a row's cards already match without being measured. `stretch`
        // inside a `ListView` asks for an infinite height and throws;
        // `IntrinsicHeight` works but lays the subtree out twice to discover
        // what these tiles already agree on.
        for (var i = 0; i < MuscleRegion.values.length; i += 2) ...[
          if (i > 0) const SizedBox(height: Space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = i;
                  j < i + 2 && j < MuscleRegion.values.length;
                  j++) ...[
                if (j > i) const SizedBox(width: Space.md),
                Expanded(
                  child: _RegionTile(
                    region: MuscleRegion.values[j],
                    series: history.byRegion[MuscleRegion.values[j]]!,
                    hue: c.forRegion(MuscleRegion.values[j]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// The line under the range control.
  ///
  /// Weeks first, because it is what every average on the screen is divided by
  /// and a rate whose denominator is unstated is a number you cannot check.
  static String _summary(VolumeHistory history) {
    final weeks = history.weekCount;
    final span = '$weeks ${weeks == 1 ? 'week' : 'weeks'}';
    if (history.isEmpty) return '$span · nothing logged';
    return '$span · ${history.averagePerWeek.toStringAsFixed(1)} '
        'hard sets per week';
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.region,
    required this.series,
    required this.hue,
  });

  final MuscleRegion region;
  final VolumeSeries series;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    return VolumeTile(
      series: series,
      hue: hue,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegionVolumeScreen(region: region),
        ),
      ),
    );
  }
}
