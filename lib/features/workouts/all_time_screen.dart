import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/trend_chart.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/cycle_progress.dart';
import 'cycle_progress_providers.dart';
import 'regime_progress_screen.dart';

/// Every regime ever trained: which one, in which week, and what each did.
///
/// Reached from the Cycle progress heading on Workouts, exactly as the year
/// heatmap is reached from Consistency. The card on Workouts is about the
/// programme being trained now; this is the record behind it.
class AllTimeScreen extends ConsumerWidget {
  const AllTimeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regimes = ref.watch(liveRegimesProvider).valueOrNull;
    final years = ref.watch(trainedYearsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Regimes')),
      body: regimes == null || years == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                Space.huge,
              ),
              children: [
                if (years.isNotEmpty) ...[
                  const SectionHeader('Timeline'),
                  _TimelineCard(years: years, regimes: regimes),
                  const SizedBox(height: Space.section),
                ],
                const SectionHeader('Strength by regime'),
                if (regimes.isEmpty)
                  Text(
                    'No programmes yet.',
                    style: context.t.bodyMedium,
                  ),
                for (final regime in regimes) ...[
                  _RegimeCard(regime: regime),
                  const SizedBox(height: Space.md),
                ],
              ],
            ),
    );
  }
}

/// One year of weeks, with the year chosen rather than scrolled to.
///
/// A stepper, because the alternative is every year ever on one screen: thirty
/// strips a reader has to find their way down, drawn from thirty queries, to
/// answer a question about one of them.
class _TimelineCard extends ConsumerStatefulWidget {
  const _TimelineCard({required this.years, required this.regimes});

  final List<int> years;
  final List<RegimeMark> regimes;

  @override
  ConsumerState<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends ConsumerState<_TimelineCard> {
  int? _year;
  bool _runsOpen = false;

  /// The most recent year, until one is chosen. Read rather than stored on
  /// first build, so a session logged into a new year moves the card on its own.
  int get _shown {
    final chosen = _year;
    if (chosen != null && widget.years.contains(chosen)) return chosen;
    return widget.years.last;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final year = _shown;
    final index = widget.years.indexOf(year);
    final weeks = ref.watch(timelineYearProvider(year)).valueOrNull;
    final byId = {for (final r in widget.regimes) r.id: r};

    final trained = weeks == null
        ? const <TimelineWeek>[]
        : [
            for (final w in weeks)
              if (!w.isOff) w,
          ];
    // The regimes trained *this year*, in the order they first appear. The
    // legend names what is on the strip rather than every programme ever
    // created, which on a long history is six swatches explaining two colours.
    final used = <String>[];
    for (final w in trained) {
      if (!used.contains(w.regimeId)) used.add(w.regimeId!);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepButton(
                icon: Icons.chevron_left_rounded,
                onTap: index > 0
                    ? () => setState(() => _year = widget.years[index - 1])
                    : null,
              ),
              Expanded(
                child: Text(
                  '$year',
                  textAlign: TextAlign.center,
                  style: context.t.titleMedium,
                ),
              ),
              _StepButton(
                icon: Icons.chevron_right_rounded,
                onTap: index < widget.years.length - 1
                    ? () => setState(() => _year = widget.years[index + 1])
                    : null,
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          const _MonthRow(),
          const SizedBox(height: Space.xs),
          _WeekStrip(weeks: weeks ?? const [], regimes: byId),
          const SizedBox(height: Space.lg),
          // Two legends, not one. A regime's colour, a deload and a week off
          // are three different kinds of fact, and a single row of swatches
          // invites the reader to take the orange one for a seventh programme.
          _LegendGroup(
            title: 'Regimes',
            children: [
              for (final id in used)
                _LegendSwatch(
                  colour: byId[id] == null
                      ? c.surfaceHighest
                      : c.identityAt(byId[id]!.identityIndex),
                  label: byId[id]?.name ?? 'Deleted programme',
                ),
            ],
          ),
          if (trained.any((w) => w.isDeload) ||
              (weeks ?? const []).any((w) => w.isOff)) ...[
            const SizedBox(height: Space.md),
            _LegendGroup(
              title: 'Weeks',
              children: [
                if (trained.any((w) => w.isDeload))
                  _LegendSwatch(colour: c.deload, label: 'Deload'),
                if ((weeks ?? const []).any((w) => w.isOff))
                  _LegendSwatch(colour: c.heatEmpty, label: 'Week off'),
              ],
            ),
          ],
          const SizedBox(height: Space.md),
          const Divider(),
          _RunsFold(
            year: year,
            open: _runsOpen,
            onToggle: () => setState(() => _runsOpen = !_runsOpen),
            runs: timelineRuns(weeks ?? const []),
            regimes: byId,
          ),
        ],
      ),
    );
  }
}

/// One arrow of the year stepper. Disabled rather than absent at each end, so
/// the control keeps its shape and the year label stays where it is.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.xs),
        child: Icon(
          icon,
          size: 24,
          color: onTap == null ? c.textTertiary : c.textPrimary,
        ),
      ),
    );
  }
}

/// The twelve initials over the strip, spaced by the weeks each month covers.
class _MonthRow extends StatelessWidget {
  const _MonthRow();

  @override
  Widget build(BuildContext context) {
    const initials = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    return Row(
      children: [
        for (final m in initials)
          Expanded(
            child: Text(
              m,
              textAlign: TextAlign.center,
              style: context.t.labelSmall?.copyWith(color: context.c.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// A year as one cell per week: the regime's colour, orange for a deload, the
/// empty grey for a week off.
///
/// Deload beats the regime's own colour, because a light week is the fact worth
/// seeing — the regime it belongs to is legible from the weeks either side of
/// it.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.weeks, required this.regimes});

  final List<TimelineWeek> weeks;
  final Map<String, RegimeMark> regimes;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = DateTime.now();
    final now = isoWeekOf(today);

    return SizedBox(
      height: 22,
      child: Row(
        children: [
          for (final w in weeks)
            Expanded(
              child: Builder(
                builder: (context) {
                  // A week that has not happened is drawn as an outline. Filled
                  // with the empty grey it would read as a week off, which is a
                  // claim about a week nobody has had the chance to train yet.
                  final future = w.start.year >= now.year &&
                      (w.start.year > now.year || w.week > now.week);
                  final mark = w.regimeId == null ? null : regimes[w.regimeId];
                  final fill = future
                      ? Colors.transparent
                      : w.isOff
                          ? c.heatEmpty
                          : w.isDeload
                              ? c.deload
                              : mark == null
                                  ? c.surfaceHighest
                                  : c.identityAt(mark.identityIndex);
                  // `SizedBox.expand`, because a `DecoratedBox` with no
                  // child takes the smallest height its constraints allow —
                  // which inside a row is none, and the whole strip drew as a
                  // band of empty space.
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: SizedBox.expand(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: BorderRadius.circular(2),
                          border: future
                              ? Border.all(color: c.border, width: 1)
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A titled group of swatches.
class _LegendGroup extends StatelessWidget {
  const _LegendGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.t.labelSmall?.copyWith(color: context.c.textTertiary),
        ),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.lg, runSpacing: Space.sm, children: children),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: Space.xs),
        Text(label, style: context.t.labelSmall),
      ],
    );
  }
}

/// The year's spells, folded away behind a row that counts them.
class _RunsFold extends StatelessWidget {
  const _RunsFold({
    required this.year,
    required this.open,
    required this.onToggle,
    required this.runs,
    required this.regimes,
  });

  final int year;
  final bool open;
  final VoidCallback onToggle;
  final List<TimelineRun> runs;
  final Map<String, RegimeMark> regimes;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pressable(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Row(
              children: [
                Expanded(
                  child: Text('Regimes in $year', style: context.t.titleMedium),
                ),
                Text('${runs.length}', style: context.t.bodyMedium),
                const SizedBox(width: Space.sm),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
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
          ),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final run in runs) ...[
                      _RunRow(run: run, regime: regimes[run.regimeId]),
                      const SizedBox(height: Space.md),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.regime});

  final TimelineRun run;
  final RegimeMark? regime;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final day = DateFormat('d MMM');
    final start = run.from.start;
    final end = run.to.start.add(const Duration(days: 6));
    final ongoing = !end.isBefore(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: regime == null
                  ? c.surfaceHighest
                  : c.identityAt(regime!.identityIndex),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      regime?.name ?? 'Deleted programme',
                      style: context.t.bodyMedium
                          ?.copyWith(color: c.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    '${day.format(start)} to '
                    '${ongoing ? 'now' : day.format(end)}',
                    style: context.t.bodyMedium,
                  ),
                ],
              ),
              if (run.firstCycle != null && run.lastCycle != null)
                Text(
                  run.firstCycle == run.lastCycle
                      ? 'Cycle ${run.firstCycle}'
                      : 'Cycles ${run.firstCycle} to ${run.lastCycle}',
                  style: context.t.labelSmall
                      ?.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One regime's whole life, as a card: its mark, its name, its sparkline and
/// the two figures the Workouts card carries.
class _RegimeCard extends ConsumerWidget {
  const _RegimeCard({required this.regime});

  final RegimeMark regime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final progress = ref.watch(regimeProgressProvider(regime.id)).valueOrNull;
    final cycles = progress?.progress.cycles ?? const <CyclePoint>[];
    final window = progress == null
        ? null
        : cycleWindow(progress.progress, CycleRange.all);

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegimeProgressScreen(regimeId: regime.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c.identityAt(regime.identityIndex),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  regime.name,
                  style: context.t.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // `Active`, not a date range: the range is under the card already,
              // and what the reader is looking for here is which one of these
              // is the programme they are on.
              if (regime.isActive) ...[
                const Pill('Active'),
                const SizedBox(width: Space.sm),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: c.textSecondary,
              ),
            ],
          ),
          Text(
            cycles.length == 1 ? '1 cycle' : '${cycles.length} cycles',
            style: context.t.bodyMedium,
          ),
          if (window != null && progress!.progress.latest != null) ...[
            const SizedBox(height: Space.md),
            CycleAxisChart(
              points: window.points,
              plotted: window.plotted,
              isBlocks: window.isBlocks,
              formatValue: formatCycleTick,
              small: true,
            ),
          ],
          const SizedBox(height: Space.md),
          const Divider(),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: progress?.progress.percent == null
                      ? '——'
                      : formatCycleValue(progress!.progress.percent!),
                  unit: '%',
                  label: 'Stronger overall',
                ),
              ),
              Expanded(
                child: StatTile(
                  value: progress == null || progress.progress.liftsCompared == 0
                      ? '—'
                      : '${progress.progress.liftsImproved} of '
                          '${progress.progress.liftsCompared}',
                  label: 'Lifts improved',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
