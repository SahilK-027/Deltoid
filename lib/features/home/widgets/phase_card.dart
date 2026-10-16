import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ids.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/phase_sparkline.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/enums.dart';
import '../../../domain/phases.dart';
import '../../../domain/units.dart';
import '../home_providers.dart';
import '../phase_sheet.dart';

/// The `Phase` section on Home: its heading and the Phase card
/// (THEME → Phase card).
///
/// It answers one question, what the person is eating for and whether the
/// scale agrees, and the heading's `Change` is its one control. With no phase
/// set it says what a phase is for and offers `Set a phase` instead, and the
/// heading drops `Change`, because the button says it.
class PhaseSection extends ConsumerWidget {
  const PhaseSection({super.key, required this.data});

  final PhaseCardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayKey = dayKeyOf(DateTime.now());
    final current = currentPhase(data.spans, todayKey: todayKey);
    void open() => showPhaseSheet(context, data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (current == null)
          const SectionHeader('Phase')
        else
          SectionHeader('Phase', actionLabel: 'Change', onAction: open),
        if (current == null)
          _NoPhaseCard(onSet: open)
        else
          _PhaseCard(
            current: current,
            data: data,
            todayKey: todayKey,
            unit: ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg,
            onChange: open,
          ),
      ],
    );
  }
}

/// No phase set, or the last one cleared: what the card is for, and the way
/// to set one.
class _NoPhaseCard extends StatelessWidget {
  const _NoPhaseCard({required this.onSet});

  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('——', style: context.t.displaySmall),
          const SizedBox(height: Space.xs),
          Text(
            'Set a bulk, a cut or maintenance, and Cycle progress shows '
            'which one each cycle ran in.',
            style: context.t.bodyMedium,
          ),
          const SizedBox(height: Space.lg),
          SecondaryButton(label: 'Set a phase', onPressed: onSet),
        ],
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.current,
    required this.data,
    required this.todayKey,
    required this.unit,
    required this.onChange,
  });

  final PhaseSpan current;
  final PhaseCardData data;
  final int todayKey;
  final WeightUnit unit;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final week = phaseWeek(current, todayKey: todayKey);
    final planned = current.phase.plannedWeeks;
    final since = DateFormat('d MMM y').format(dateFromDayKey(current.startKey));

    final log = [
      for (final e in data.log)
        if (e.dayKey <= todayKey) e,
    ];
    final latest = log.isEmpty ? null : log.last;
    final change = phaseBodyweightChange(current, log, todayKey: todayKey);
    final sparkline =
        phaseSparkline(current, data.spans, log, todayKey: todayKey);
    final pastPlan = plannedLengthPassed(current, todayKey: todayKey);
    final against = weighInsAgainstPhase(current, log, todayKey: todayKey);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Grey, because a phase is not an identity; the glyph says the
              // direction before the name is read.
              IconTile(
                switch (current.kind) {
                  PhaseKind.bulk => Icons.trending_up_rounded,
                  PhaseKind.cut => Icons.trending_down_rounded,
                  PhaseKind.maintenance => Icons.trending_flat_rounded,
                },
                color: c.surfaceHigh,
                glyph: c.textPrimary,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.kind.label,
                      style: context.t.displaySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Since $since',
                      style: context.t.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              // Opens nothing: the heading's link is the card's one control.
              CompactPill(
                planned == null ? 'Week $week' : 'Week $week of $planned',
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          PhaseSparkline(
            data: sparkline,
            semanticLabel: 'Bodyweight by week, with the '
                '${current.kind.label.toLowerCase()} since $since',
          ),
          const SizedBox(height: Space.sm),
          PhaseLegend(kinds: sparkline.kinds),
          const SizedBox(height: Space.lg),
          const Divider(),
          const SizedBox(height: Space.md),
          // Stated, never judged: no figure turns green or yellow for moving
          // the way the phase intends or against it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  label: 'Bodyweight',
                  value: latest == null
                      ? null
                      : formatBodyweight(latest.weightKg, unit),
                  unit: unit.label,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: _Figure(
                  label: 'Since start',
                  value: change == null
                      ? null
                      : formatBodyweightChange(change.sinceStart, unit),
                  unit: unit.label,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: _Figure(
                  label: 'Each week',
                  value: change?.perWeek == null
                      ? null
                      : formatBodyweightChange(change!.perWeek!, unit),
                  unit: unit.label,
                ),
              ),
            ],
          ),
          if (pastPlan || against != null) ...[
            const SizedBox(height: Space.lg),
            _NextPhasePrompt(
              current: current,
              pastPlan: pastPlan,
              against: against,
              todayKey: todayKey,
              onChange: onChange,
            ),
          ],
        ],
      ),
    );
  }
}

/// The card asking what comes next, and the one place anything does
/// (THEME → Phase card, RULES § 6): no notification, badge or toast.
///
/// One panel even when both questions stand. The planned length speaks
/// first, and `Keep going` then answers both, because the person has said
/// the phase holds; the weigh-in question straight after would ask the same
/// thing twice.
///
/// `Keep going` is remembered on the phase row rather than in a device
/// preference: the schema already carries it, it syncs, so a second phone
/// does not ask what the first was told, and it goes with the phase it
/// answered. Past the plan it makes the phase open-ended, so that question is
/// asked once. Against the weigh-ins it records the day, and
/// [weighInsAgainstPhase] reads only the readings from that day on, so the
/// question returns only once three more weeks of weigh-ins have run against
/// the phase.
class _NextPhasePrompt extends ConsumerWidget {
  const _NextPhasePrompt({
    required this.current,
    required this.pastPlan,
    required this.against,
    required this.todayKey,
    required this.onChange,
  });

  final PhaseSpan current;
  final bool pastPlan;
  final WeightDirection? against;
  final int todayKey;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final against = this.against;
    final during = switch (current.kind) {
      PhaseKind.bulk => 'this bulk',
      PhaseKind.cut => 'this cut',
      PhaseKind.maintenance => 'maintenance',
    };
    final moved = against == WeightDirection.rising ? 'risen' : 'fallen';
    final sentence = pastPlan
        ? '${current.phase.plannedWeeks} weeks are up. Start the next phase, '
            'or keep this one going.'
        : 'Your weight has $moved for three weeks during $during.';

    Future<void> keep() async {
      final repo = ref.read(phaseRepositoryProvider);
      final id = current.phase.id;
      if (pastPlan) await repo.keepGoingPastPlan(id);
      if (against != null) {
        await repo.keepGoingAgainstWeighIns(id, on: dateFromDayKey(todayKey));
      }
    }

    return InsetPanel(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(sentence, style: context.t.bodyMedium),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Change phase',
                  onPressed: onChange,
                  fill: c.surfaceHighest,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: SecondaryButton(
                  label: 'Keep going',
                  onPressed: keep,
                  fill: c.surfaceHighest,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A `label` over a dense value, or `——` where the weigh-ins cannot support
/// one (THEME rule 4).
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.unit});

  final String label;
  final String? value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.t.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.xs),
        ValueUnit(
          value: value ?? '——',
          unit: value == null ? null : unit,
          dense: true,
        ),
      ],
    );
  }
}
