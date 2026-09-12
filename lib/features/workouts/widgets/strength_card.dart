import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ids.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../core/widgets/trend_chart.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/cycle_progress.dart';

/// How much stronger a regime has made you, as one card.
///
/// Shared by Workouts and the regime screen rather than written twice: the two
/// differ only in whether the row at the foot opens anything, and a second copy
/// is how the figure and the chart above it come to disagree about which cycle
/// is selected.
///
/// It replaces the Last session card, which repeated what the masthead and
/// History already said. This answers a question nothing else on the screen
/// does: whether the programme is working.
class StrengthCard extends StatefulWidget {
  const StrengthCard({
    super.key,
    required this.regime,
    this.plannedLifts,
    this.showName = true,
    this.onOpen,
  });

  final RegimeProgress regime;

  /// How many lifts the programme holds, for the card's first cycle — `8 of
  /// 15 lifts recorded` is a sentence about a cycle still being filled in.
  /// Null where the caller does not know, and the denominator is then dropped
  /// rather than invented.
  final int? plannedLifts;

  /// The regime's name as the card's caption. Off on the regime screen, whose
  /// app bar already carries it.
  final bool showName;

  /// Opening the regime screen. Null draws no row at the foot — the regime
  /// screen is already there.
  final VoidCallback? onOpen;

  @override
  State<StrengthCard> createState() => _StrengthCardState();
}

class _StrengthCardState extends State<StrengthCard> {
  CycleRange _range = CycleRange.last12;

  /// The cycle the readout is describing, by cycle id. Null means the latest
  /// scored one, which is what the card opens on.
  String? _selected;

  @override
  void didUpdateWidget(StrengthCard old) {
    super.didUpdateWidget(old);
    // A cycle that has left the chart cannot stay under the readout. This
    // happens when the regime is reset or the selected cycle is deleted;
    // falling back to null puts the readout on the latest cycle, where the card
    // opens.
    final selected = _selected;
    if (selected == null) return;
    if (!widget.regime.progress.cycles.any((c) => c.cycleId == selected)) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final progress = widget.regime.progress;
    final latest = progress.latest;

    // Three states, and all three are this card. THEME → Empty states: a thing
    // with no data still has the page it will have once there is some, with the
    // figures printed as dashes.
    if (latest == null) return _dashes(context, recorded: false);
    if (progress.isFirstCycle) return _dashes(context, recorded: true);

    final window = cycleWindow(progress, _range);
    final baseline =
        progress.cycles.where((p) => p.isScored).firstOrNull;
    final selected = window.points.firstWhere(
      (p) => p.cycleId == _selected,
      orElse: () => latest,
    );

    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showName) ...[
            Text(
              widget.regime.regimeName,
              style: context.t.titleMedium?.copyWith(color: c.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Space.sm),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ValueUnit(
                value: formatCycleValue(progress.percent!),
                unit: '%',
              ),
              if (progress.trend != null) ...[
                const SizedBox(width: Space.sm),
                Pill(
                  progress.trend!.label,
                  color: switch (progress.trend!) {
                    // Green for gaining only, which is the colour the app
                    // already uses for beating last time. Holding steady is a
                    // reading rather than a verdict, and dropping is not a
                    // failure the app is entitled to paint red.
                    ProgressTrend.progressing => c.positive,
                    ProgressTrend.holdingSteady => c.textSecondary,
                    ProgressTrend.dropping => c.textPrimary,
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.md),
          SegmentedPill<CycleRange>(
            segments: [
              for (final r in CycleRange.values)
                (value: r, label: r.label),
            ],
            value: _range,
            // Every range stays selectable on a short history. A chip that
            // would draw a perfectly good four-cycle chart and is greyed out
            // instead is a worse answer than the short chart.
            onChanged: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: Space.md),
          Text(
            cycleReadout(
              selected,
              isBaseline: selected.cycleId == baseline?.cycleId,
            ),
            style: context.t.bodyMedium,
            maxLines: 2,
          ),
          const SizedBox(height: Space.sm),
          CycleAxisChart(
            points: window.points,
            plotted: window.plotted,
            isBlocks: window.isBlocks,
            formatValue: formatCycleTick,
            selected: selected.cycleId,
            onSelected: (p) => setState(() => _selected = p.cycleId),
          ),
          const SizedBox(height: Space.sm),
          _Legend(window: window),
          if (widget.onOpen != null) ...[
            const SizedBox(height: Space.md),
            const Divider(),
            const SizedBox(height: Space.md),
            Pressable(
              onTap: widget.onOpen,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ValueUnit(
                    value: '${progress.liftsImproved} of '
                        '${progress.liftsCompared}',
                    dense: true,
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      'lifts improved',
                      style: context.t.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The card before there is anything to compare.
  ///
  /// [recorded] separates the two: a regime one cycle in has lifts on the board
  /// and nothing to measure them against yet, where a regime with nothing
  /// logged has neither. Both keep the card's shape, so the page does not
  /// change form on the day of the first session.
  Widget _dashes(BuildContext context, {required bool recorded}) {
    final progress = widget.regime.progress;
    final planned = widget.plannedLifts;
    final counted = recorded ? '${progress.liftsCompared}' : '—';

    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      onTap: recorded ? widget.onOpen : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showName) ...[
            Text(
              widget.regime.regimeName,
              style: context.t.titleMedium?.copyWith(
                color: context.c.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Space.md),
          ],
          // The chart's room, held open and left empty. A cycle axis with no
          // cycles has no numbers to label and no band to scale, so drawing one
          // would be a scale the data does not have — THEME → Charts refuses a
          // point the metric cannot score, and this is the same refusal one
          // level up.
          const SizedBox(height: _emptyChartHeight),
          const SizedBox(height: Space.md),
          const Divider(),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '——',
                  unit: '%',
                  label: 'Stronger overall',
                ),
              ),
              Expanded(
                child: StatTile(
                  value: planned == null ? counted : '$counted of $planned',
                  label: recorded ? 'Lifts recorded' : 'Lifts improved',
                ),
              ),
              if (recorded && widget.onOpen != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.c.textSecondary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The height the chart keeps while there is nothing to draw in it, so the card
/// is the same card before and after the first cycle.
const _emptyChartHeight = 150.0;

/// What the chart is saying, in words: which cycle, when it ran, and how it
/// scored.
///
/// A line of prose rather than a tooltip. A full date and a percentage want
/// room to be printed properly, and a tooltip that appears under a finger is
/// covered by the finger that summoned it.
///
/// [isBaseline] is the regime's first scored cycle, which prints no
/// percentage. It is the cycle everything else is measured against, and
/// `+0.0%` beside it reads as a fact about the training rather than as the
/// definition it actually is.
String cycleReadout(CyclePoint point, {bool isBaseline = false}) {
  final parts = <String>['Cycle ${point.index}'];
  final span = cycleSpan(point);
  if (span != null) parts.add(span);
  if (point.isDeload) {
    parts.add('Deload');
  } else if (point.value != null && !isBaseline) {
    parts.add(formatCyclePercent(point.value!));
  }
  return parts.join('  ·  ');
}

/// The days a cycle covers: `24 Aug to 30 Aug 2026`, `7 Sep 2026 to now`.
///
/// The year is always printed. A cycle is read months after the fact, and
/// "24 Aug to 30 Aug" in a log spanning years names four different weeks.
String? cycleSpan(CyclePoint point) {
  final from = point.startDayKey;
  if (from == null) return null;
  final start = dateFromDayKey(from);
  final day = DateFormat('d MMM');
  final withYear = DateFormat('d MMM yyyy');

  if (point.isOpen) return '${withYear.format(start)} to now';

  final to = point.endDayKey;
  if (to == null || to == from) return withYear.format(start);
  final end = dateFromDayKey(to);
  // Both years on a cycle that crosses one. `29 Dec to 4 Jan 2026` reads as a
  // week in December 2026 that ended the previous January.
  final opening = start.year == end.year ? day : withYear;
  return '${opening.format(start)} to ${withYear.format(end)}';
}

/// What the marks mean, under the chart.
///
/// Two legends would be one too many: the x axis is named on the left, and the
/// only marks that need explaining are the ones that are not a plain cycle —
/// the deload band and the cycle still being trained.
class _Legend extends StatelessWidget {
  const _Legend({required this.window});

  final CycleWindow window;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = context.t.labelSmall?.copyWith(color: c.textSecondary);
    final hasDeload = window.points.any((p) => p.isDeload);
    final open = window.points.where((p) => p.isOpen && p.isScored).firstOrNull;

    return Row(
      children: [
        Text('Cycle', style: style),
        const Spacer(),
        if (hasDeload) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c.deload.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Space.xs),
          Text('Deload', style: style),
        ],
        if (open != null) ...[
          if (hasDeload) const SizedBox(width: Space.md),
          SizedBox(
            width: 14,
            child: Divider(color: c.textTertiary, thickness: 2, height: 2),
          ),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(
              'Cycle ${open.index} so far',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
