import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/cycle_progress.dart';
import '../../domain/enums.dart';
import '../../domain/metrics.dart';
import '../../domain/set_format.dart';
import '../../domain/units.dart';
import 'cycle_progress_providers.dart';
import 'widgets/strength_card.dart';

/// One regime, lift by lift: the same card as Workouts, how the number is
/// arrived at, and what every lift in the programme did.
///
/// The card answers "is this working". This answers "on what", which is the
/// question a single averaged percentage cannot: a regime at +9.8 % with twelve
/// lifts climbing and three going backwards is a different month's training
/// from one where every lift moved a little.
class RegimeProgressScreen extends ConsumerWidget {
  const RegimeProgressScreen({super.key, required this.regimeId});

  final String regimeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regime = ref.watch(regimeProgressProvider(regimeId)).valueOrNull;
    final planned = ref.watch(regimeLiftsProvider(regimeId)).valueOrNull;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    return Scaffold(
      appBar: AppBar(title: Text(regime?.regimeName ?? '')),
      // Local disk, so a spinner would show for two frames (THEME → Empty
      // states).
      body: regime == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                Space.huge,
              ),
              children: regime.progress.isFirstCycle
                  ? _firstCycle(context, regime, planned, unit)
                  : _measured(context, regime, planned, unit),
            ),
    );
  }

  /// The screen once there is a comparison to draw.
  List<Widget> _measured(
    BuildContext context,
    RegimeProgress regime,
    List<({LiftId lift, LiftLabel label})>? planned,
    WeightUnit unit,
  ) {
    final progress = regime.progress;
    final lifts = progress.latest?.lifts ?? const <LiftChange>[];
    final last = progress.cycles.isEmpty ? null : progress.cycles.last.index;

    return [
      const SectionHeader('Strength'),
      StrengthCard(
        regime: regime,
        plannedLifts: planned?.length,
        showName: false,
      ),
      const SizedBox(height: Space.section),
      const _HowIsThisMeasured(),
      const SizedBox(height: Space.section),
      SectionHeader(
        'Lifts',
        trailing: last == null
            ? null
            : Text('Cycle 1 to $last', style: context.t.bodyMedium),
      ),
      for (final group in _groups(lifts))
        ..._group(context, regime, group, unit),
      if (lifts.isEmpty)
        Text(
          'Nothing in this cycle has a cycle to be measured against yet.',
          style: context.t.bodyMedium,
        ),
    ];
  }

  /// The three groups, in the order a person reads them, empty ones dropped.
  ///
  /// Weaker last rather than hidden: a lift going backwards is the single most
  /// useful thing on this screen, and a screen that only lists wins is a screen
  /// nobody can act on.
  List<({String name, List<LiftChange> lifts})> _groups(
    List<LiftChange> lifts,
  ) {
    final groups = [
      (name: 'Stronger', lifts: [for (final l in lifts) if (l.isStronger) l]),
      (name: 'No change', lifts: [for (final l in lifts) if (l.isUnchanged) l]),
      (name: 'Weaker', lifts: [for (final l in lifts) if (l.isWeaker) l]),
    ];
    return [
      for (final g in groups)
        if (g.lifts.isNotEmpty) g,
    ];
  }

  List<Widget> _group(
    BuildContext context,
    RegimeProgress regime,
    ({String name, List<LiftChange> lifts}) group,
    WeightUnit unit,
  ) {
    return [
      _GroupHeading(name: group.name, count: group.lifts.length),
      ListCard(
        children: [
          for (final lift in group.lifts)
            AppRow(
              title: regime.labelOf(lift.lift).exerciseName,
              subtitle: [
                regime.labelOf(lift.lift).sessionName,
                ?_sets(lift, unit),
              ].join('  ·  '),
              trailing: _Change(lift: lift, unit: unit),
            ),
        ],
      ),
      const SizedBox(height: Space.lg),
    ];
  }

  /// `160 kg × 10 to 180 kg × 10`, or one set where both ends are the same.
  ///
  /// Through [loadWithCount], so a pair of dumbbells reads `22.5 kg each × 8`
  /// here exactly as it does in the log — the comparison behind it was made on
  /// the 45 kg actually moved, and printing that number instead would
  /// contradict every other screen.
  String? _sets(LiftChange lift, WeightUnit unit) {
    String? format(ScoredSet? set) => set == null
        ? null
        : loadWithCount(
            loadMode: lift.load,
            measureMode: lift.measure,
            weight: set.weight,
            addedWeight: set.addedWeight,
            reps: set.reps,
            unit: unit,
          );

    final from = format(lift.baselineSet);
    final to = format(lift.latestSet);
    if (from == null || to == null) return from ?? to;
    return from == to ? from : '$from to $to';
  }

  /// The screen on a regime still in its first cycle.
  ///
  /// A different page rather than the same one with dashes, because there is
  /// genuinely nothing to compare: every lift is its own baseline, and a list
  /// of fifteen `0 %` rows would report a fact about arithmetic as though it
  /// were a fact about training.
  List<Widget> _firstCycle(
    BuildContext context,
    RegimeProgress regime,
    List<({LiftId lift, LiftLabel label})>? planned,
    WeightUnit unit,
  ) {
    final recorded = {
      for (final l in regime.progress.latest?.lifts ?? const <LiftChange>[])
        l.lift: l,
    };
    final all = planned ??
        [
          for (final l in recorded.keys)
            (lift: l, label: regime.labelOf(l)),
        ];
    final done = [
      for (final p in all)
        if (recorded.containsKey(p.lift)) p,
    ];
    final todo = [
      for (final p in all)
        if (!recorded.containsKey(p.lift)) p,
    ];
    final started = regime.progress.cycles.firstOrNull?.startDayKey;

    return [
      if (started != null) ...[
        Text(
          [
            'Started ${DateFormat('d MMM yyyy').format(dateFromDayKey(started))}',
            'Cycle ${regime.progress.cycles.first.index} under way',
          ].join('  ·  '),
          style: context.t.bodyMedium,
        ),
        const SizedBox(height: Space.lg),
      ],
      SectionHeader(
        'Starting point',
        trailing: Text(
          '${done.length} of ${all.length}',
          style: context.t.bodyMedium,
        ),
      ),
      AppCard(
        child: Text(
          'Your best set in cycle 1 is what every later cycle is measured '
          'against. The chart starts moving when you train each lift again in '
          'cycle 2.',
          style: context.t.bodyMedium,
        ),
      ),
      const SizedBox(height: Space.section),
      if (done.isNotEmpty) ...[
        _GroupHeading(name: 'Recorded', count: done.length),
        ListCard(
          children: [
            for (final p in done)
              AppRow(
                title: p.label.exerciseName,
                subtitle: [
                  p.label.sessionName,
                  ?_sets(recorded[p.lift]!, unit),
                ].join('  ·  '),
                trailing: Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: context.c.positive,
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
      ],
      if (todo.isNotEmpty) ...[
        _GroupHeading(name: 'Still to train', count: todo.length),
        ListCard(
          children: [
            for (final p in todo)
              AppRow(
                title: p.label.exerciseName,
                subtitle: p.label.sessionName,
                trailing: Text('Not yet', style: context.t.bodyMedium),
              ),
          ],
        ),
      ],
    ];
  }
}

/// What a lift gained, in the unit it was trained in.
///
/// Kilograms rather than a percentage: the row already names the two sets it
/// is between, and the number a person acts on is the weight. An estimated
/// one-rep max is what moved, so that is what is differenced — a hold has no
/// one-rep max and reports the seconds it gained instead.
class _Change extends StatelessWidget {
  const _Change({required this.lift, required this.unit});

  final LiftChange lift;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final colour = lift.isStronger
        ? c.positive
        : (lift.isWeaker ? c.textPrimary : c.textSecondary);
    final gain = lift.latest - lift.baseline;
    final sign = lift.isStronger ? '+' : (lift.isWeaker ? '−' : '');
    final magnitude = lift.measure.isHold
        ? '${gain.abs().round()}'
        : formatInUnit(gain.abs(), unit);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          lift.isUnchanged ? '0' : '$sign$magnitude',
          style: context.t.labelLarge?.copyWith(color: colour),
        ),
        const SizedBox(width: Space.xs),
        Text(
          lift.measure.isHold ? 's' : unit.label,
          style: context.t.labelSmall?.copyWith(color: colour),
        ),
      ],
    );
  }
}

/// A group's name and how many lifts are in it.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: context.t.bodyMedium?.copyWith(
                color: context.c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$count', style: context.t.bodyMedium),
        ],
      ),
    );
  }
}

/// The rules behind the number, folded away until they are asked for.
///
/// Closed by default: the card above is readable without any of this, and a
/// screen that opens on five paragraphs of method buries the answer under the
/// working. No worked example inside — a sum with invented weights in it is a
/// sixth thing to read, and the reader already has their own numbers on the
/// screen above.
class _HowIsThisMeasured extends StatefulWidget {
  const _HowIsThisMeasured();

  @override
  State<_HowIsThisMeasured> createState() => _HowIsThisMeasuredState();
}

class _HowIsThisMeasuredState extends State<_HowIsThisMeasured> {
  bool _open = false;

  static const _points = <({String title, String body})>[
    (
      title: 'Every cycle is compared with cycle 1',
      body: 'Cycle 1 is where this regime started. Each point is how much '
          'stronger you were in that cycle, averaged across its lifts. It '
          'never starts again.',
    ),
    (
      title: 'Each regime keeps its own count',
      body: 'Switching to another regime pauses this one. Coming back to it '
          'carries on from the next cycle number.',
    ),
    (
      title: 'Deload cycles are left out',
      body: 'The weights are lighter on purpose, so a deload is marked in '
          'orange and scores nothing.',
    ),
    (
      title: 'All shows one point per block on a long regime',
      body: 'Past 24 cycles, each point is the last cycle before a deload, and '
          'the orange lines are the deloads.',
    ),
    (
      title: 'Strength comes from your best set',
      body: 'Weight and reps become an estimated one-rep max. A lift is '
          'compared only with itself in the same session.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return AppCard(
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The size of the title beside it. An icon set larger than the
              // line it introduces reads as a warning rather than as a
              // question.
              Icon(Icons.help_outline_rounded, size: 24, color: c.textSecondary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text('How is this measured?', style: context.t.titleMedium),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: Motion.base,
                curve: Motion.curve,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          // The fold has a height, so it animates to it (THEME § 6).
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.emphasized,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _points.length; i++) ...[
                        const SizedBox(height: Space.lg),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // A numbered badge rather than a bare figure: the
                            // five points are a sequence to be read in order,
                            // and a grey digit beside a bold line reads as a
                            // footnote marker.
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.surfaceHighest,
                                borderRadius: BorderRadius.circular(Radii.mark),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: context.t.labelSmall
                                    ?.copyWith(color: c.textPrimary),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _points[i].title,
                                    style: context.t.titleSmall,
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    _points[i].body,
                                    style: context.t.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
