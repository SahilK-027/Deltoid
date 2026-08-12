import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/muscle_volume.dart';
import '../../domain/volume_history.dart';
import 'volume_history_screen.dart';
import 'volume_providers.dart';
import 'widgets/volume_chart.dart';
import 'widgets/volume_tile.dart';

/// One region: the chart at full size, what it adds up to, which movements
/// produced it, and the muscles under it.
///
/// The screen the fold on Today's bar list becomes when it has room. `Legs 18`
/// is a number you can read at a glance and cannot act on; `Quads 12 ·
/// Hamstrings 2` is the same training saying something you would change your
/// next session over — and over a year rather than a week, that split is the
/// whole reason this feature exists.
///
/// A region with one muscle has no split to show. It gets the other three
/// sections, because "which movements produced this" is the question it has
/// instead: Back cannot ask quads-versus-hamstrings, but it can ask why eleven
/// of its sets were pulldowns.
class RegionVolumeScreen extends ConsumerWidget {
  const RegionVolumeScreen({super.key, required this.region});

  final MuscleRegion region;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final history = ref.watch(volumeHistoryProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(region.label)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The same control as the grid, on the same notifier: opening a
          // region from a 1Y grid and finding it reset to 3M is the range
          // forgetting what you just asked it.
          const VolumeRangeBar(),
          Expanded(
            child: switch (history) {
              null => const SizedBox.shrink(),
              final h => _Body(
                  region: region,
                  history: h,
                  hue: c.forRegion(region),
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    required this.region,
    required this.history,
    required this.hue,
  });

  final MuscleRegion region;
  final VolumeHistory history;
  final Color hue;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// The week under the finger on the big chart, if any.
  VolumeWeek? _week;

  @override
  Widget build(BuildContext context) {
    final series = widget.history.byRegion[widget.region]!;
    final parts = widget.region.parts;
    final week = _week;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The figure the chart is of, and what it covers — replaced by
              // the week under your finger while the chart is being scrubbed,
              // exactly as a tile's caption is.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    week == null
                        ? series.averagePerWeek.toStringAsFixed(1)
                        : '${week.sets}',
                    style: context.t.displaySmall,
                  ),
                  const SizedBox(width: Space.xs),
                  Flexible(
                    child: Text(
                      week == null
                          ? 'sets per week · ${weekSpanLabel(series).toLowerCase()}'
                          : 'sets · ${weekReadout(week).split(' · ').first}',
                      style: context.t.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              VolumeChart(
                series: series,
                hue: widget.hue,
                onSelected: (w) => setState(() => _week = w),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xxl),
        _Figures(series: series),
        if (widget.region.isCompound) ...[
          const SizedBox(height: Space.xxl),
          const SectionHeader('By muscle'),
          // Every muscle in the region, zeros included — the zero is the point.
          // A `Legs 18` that opens onto `Hamstrings 0.0` is the one thing this
          // screen can say that a regional total cannot.
          for (var i = 0; i < parts.length; i += 2) ...[
            if (i > 0) const SizedBox(height: Space.md),
            Row(
              // See the note in `volume_history_screen.dart`: identical tiles
              // match without being measured.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + 2 && j < parts.length; j++) ...[
                  if (j > i) const SizedBox(width: Space.md),
                  Expanded(
                    child: VolumeTile(
                      series: widget.history.byMuscle[parts[j]]!,
                      // A muscle carries its region's hue, because that is the
                      // bar it is read against (`forMuscle`).
                      hue: widget.hue,
                    ),
                  ),
                ],
                // An odd count leaves the last row half full rather than
                // stretching one card to the width of two.
                if (i + 1 >= parts.length) ...[
                  const SizedBox(width: Space.md),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ],
        ],
        const SizedBox(height: Space.xxl),
        _Movements(region: widget.region, total: series.totalSets),
      ],
    );
  }
}

/// What the average leaves out.
///
/// Three figures rather than one: `4.0 per week` over thirteen weeks is a
/// different block depending on whether it was every week or three heavy ones
/// and ten of nothing, and the rate alone cannot say which.
class _Figures extends StatelessWidget {
  const _Figures({required this.series});

  final VolumeSeries series;

  @override
  Widget build(BuildContext context) {
    final weeks = series.weeks.length;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: StatTile(
              value: '${series.totalSets}',
              label: 'hard sets',
            ),
          ),
          Expanded(
            child: StatTile(
              value: '${series.peakSets}',
              label: 'best week',
            ),
          ),
          Expanded(
            child: StatTile(
              value: '${series.weeksTrained}',
              // The denominator is printed rather than implied: `9` alone
              // reads as a score, and `9 of 13 weeks` is a fact.
              label: 'of $weeks weeks trained',
            ),
          ),
        ],
      ),
    );
  }
}

/// Which movements the sets came from, most first.
class _Movements extends ConsumerWidget {
  const _Movements({required this.region, required this.total});

  final MuscleRegion region;

  /// The region's own total, so a row can say what share of it a movement is.
  /// Read from the same history the chart draws, so the parts add up to the
  /// whole on screen rather than approximately.
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(regionExercisesProvider(region)).valueOrNull;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Where the sets came from'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(color: context.c.border, height: 1),
                AppRow(
                  title: rows[i].name,
                  subtitle: total == 0
                      ? null
                      : '${(rows[i].sets / total * 100).round()}% of '
                          '${region.label.toLowerCase()}',
                  trailing: Text(
                    '${rows[i].sets}',
                    style: context.t.labelLarge,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
