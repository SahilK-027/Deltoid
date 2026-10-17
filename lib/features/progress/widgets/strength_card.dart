import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ids.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chart_legend.dart';
import '../../../core/widgets/phase_sparkline.dart';
import '../../../core/widgets/primitives.dart';
import '../../../core/widgets/trend_chart.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/cycle_progress.dart';
import '../../../domain/enums.dart';
import '../../../domain/phases.dart';

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
          // The spacing every chart card shares (THEME → Charts): 16 to the
          // range control, 12 to the readout, 16 to the plot, 12 under it to
          // the legend and 16 to the row that follows.
          const SizedBox(height: Space.lg),
          SegmentedPill<CycleRange>(
            segments: [
              for (final r in CycleRange.values)
                (value: r, label: r.label),
            ],
            value: _range,
            // The full width of the card: the control governs everything under
            // it, and a track hugging three short words on the left of an
            // otherwise empty band reads as something left over.
            expand: true,
            // Every range stays selectable on a short history. A chip that
            // would draw a perfectly good four-cycle chart and is greyed out
            // instead is a worse answer than the short chart.
            onChanged: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: Space.md),
          _Readout(
            point: selected,
            isBaseline: selected.cycleId == baseline?.cycleId,
          ),
          const SizedBox(height: Space.lg),
          CycleAxisChart(
            points: window.points,
            plotted: window.plotted,
            isBlocks: window.isBlocks,
            formatValue: formatCycleTick,
            selected: selected.cycleId,
            onSelected: (p) => setState(() => _selected = p.cycleId),
          ),
          const SizedBox(height: Space.md),
          _Legend(window: window),
          if (widget.onOpen != null) ...[
            const SizedBox(height: Space.lg),
            const Divider(),
            const SizedBox(height: Space.md),
            Pressable(
              onTap: widget.onOpen,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ValueUnit(
                    // Out of every lift the regime has scored, which is the
                    // list the row opens onto. Counting against the lifts the
                    // open cycle happened to reach gave a denominator that
                    // moved with every session and did not match the list.
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
    final window = cycleWindow(progress, CycleRange.last12);

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
          // One cycle is a chart with one dot on it (THEME → Charts): the dot
          // is the starting point every later cycle is read against, and
          // refusing to draw until there are two makes a new regime's first
          // week look like a fault.
          //
          // With nothing logged there is no dot and no chart at all. A cycle
          // axis with no cycles has no numbers to label and no band to scale,
          // so drawing one invents a scale — and holding the height open for
          // it leaves a card with a hole in it.
          // The axis this regime will have, with what there is on it: one dot
          // for a first cycle, nothing at all before that. Four slots either
          // way, so the chart is a chart rather than a dot in the middle of
          // nothing (THEME → The cycle axis).
          CycleAxisChart(
            points: window.points,
            plotted: window.plotted,
            formatValue: formatCycleTick,
            selected: progress.latest?.cycleId,
            minSlots: _quietSlots,
          ),
          const SizedBox(height: Space.lg),
          const Divider(),
          const SizedBox(height: Space.md),
          StatRow(
            trailing: recorded && widget.onOpen != null
                ? Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: context.c.textSecondary,
                  )
                : null,
            children: [
              const StatTile(
                value: '——',
                unit: '%',
                label: 'Stronger overall',
              ),
              StatTile(
                value: planned == null ? counted : '$counted of $planned',
                label: recorded ? 'Lifts recorded' : 'Lifts improved',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How many positions the axis lays out before there is a cycle to fill them.
const _quietSlots = 4;

/// The readout: a filled strip under the range pill, naming the cycle in the
/// primary colour and the rest of the line beside it.
///
/// A strip rather than a bare line, because it is the one thing on the card
/// that changes when the chart is tapped, and a line of grey prose moving is
/// not visibly an answer to the tap.
class _Readout extends StatelessWidget {
  const _Readout({required this.point, required this.isBaseline});

  final CyclePoint point;
  final bool isBaseline;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rest = cycleReadout(point, isBaseline: isBaseline)
        .replaceFirst('Cycle ${point.index}', '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.cell),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Cycle ${point.index}',
              style: context.t.bodyMedium?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: rest,
              style: point.isDeload
                  ? context.t.bodyMedium?.copyWith(color: c.deload)
                  : context.t.bodyMedium,
            ),
          ],
        ),
        maxLines: 2,
      ),
    );
  }
}

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
///
/// A cycle that ran in a phase names it after the days. One with no phase
/// leaves the item out rather than printing `No phase`.
String cycleReadout(CyclePoint point, {bool isBaseline = false}) {
  final parts = <String>['Cycle ${point.index}'];
  final span = cycleSpan(point);
  if (span != null) parts.add(span);
  final phase = point.phase;
  if (phase != null) parts.add(phase.label);
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
/// The x axis is named by the title, and the only marks that need explaining
/// are the ones that are not a plain cycle — the deload band, the cycle still
/// being trained, and the phase tints.
class _Legend extends StatelessWidget {
  const _Legend({required this.window});

  final CycleWindow window;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hasDeload = window.points.any((p) => p.isDeload);
    final open = window.points.where((p) => p.isOpen && p.isScored).firstOrNull;
    // The phases the window shows, in the order they appear, each once. A
    // phase no cycle on screen ran in has no swatch, for the reason `Deload`
    // appears only where a deload does.
    final phases = <PhaseKind>[];
    for (final kind in cycleTints(window.points, isBlocks: window.isBlocks)) {
      if (kind != null && !phases.contains(kind)) phases.add(kind);
    }

    return ChartLegend(
      title: 'Cycle',
      entries: [
        if (hasDeload)
          LegendEntry('Deload', c.deload.withValues(alpha: 0.5)),
        // Dashed, because the line it stands for is: a solid rule in the
        // legend names a mark the chart never draws.
        if (open != null)
          LegendEntry(
            'Cycle ${open.index} so far',
            c.textTertiary,
            mark: LegendMark.dashedLine,
          ),
        for (final kind in phases) LegendEntry(kind.label, c.phase(kind)),
      ],
    );
  }
}
