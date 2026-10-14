import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cycle_order.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/cycle_order.dart';
import 'regime_screen.dart';

/// The regime's cycle as a whole: the order it runs in, and its days.
///
/// The first tab of the regime editor, ahead of the days. A day tab is where a
/// day is filled; this is where the days are read together, and the one place
/// two of them are made to alternate, since that is a fact about the cycle and
/// about neither day alone.
class CycleBody extends ConsumerWidget {
  const CycleBody({
    super.key,
    required this.regimeId,
    required this.sessions,
    required this.onAddDay,
  });

  final String regimeId;

  /// The regime's live days in programme order.
  final List<Session> sessions;
  final VoidCallback onAddDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(cyclePositionsProvider(regimeId)).valueOrNull;
    if (loaded == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final byId = {for (final s in sessions) s.id: s};
    // The positions and the days arrive on two streams, and for a frame after
    // a day is added or deleted one can name a day the other does not hold
    // yet. A position is drawn from the days both agree on.
    final positions = [
      for (final p in loaded)
        if (p.sessionIds.every(byId.containsKey)) p,
    ];
    String nameOf(String id) => byId[id]!.name;

    final shown = cyclesBeforeRepeat(positions);
    final ahead = cyclesAhead(positions, shown);
    final captions = [
      for (var i = 0; i < positions.length; i++)
        if (positions[i].alternates)
          rotationCaption(
            [for (final id in positions[i].sessionIds) nameOf(id)],
            i + 1,
          ),
    ];

    return ListView(
      // The same inset the day pages take: this screen has no nav bar to hold
      // the bottom, so the gesture bar is cleared here.
      padding: EdgeInsets.only(
        top: Space.lg,
        bottom: Space.huge + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Space.gutter),
          child: SectionHeader('Cycle order'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: CycleOrderCard(
            rows: [
              for (var n = 0; n < ahead.length; n++)
                CycleOrderRow(
                  label: shown > 1 ? cycleAheadLabel(n) : null,
                  days: [
                    for (var i = 0; i < positions.length; i++)
                      CycleOrderDay(
                        name: nameOf(ahead[n][i]),
                        alternates: positions[i].alternates,
                      ),
                  ],
                ),
            ],
            // One clause takes no full stop; two rotations are two sentences
            // and take both (THEME → The words).
            caption: switch (captions.length) {
              0 => null,
              1 => captions.single,
              _ => '${captions.join('. ')}.',
            },
          ),
        ),
        const SizedBox(height: Space.section),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: SectionHeader(
            dayCount(sessions.length),
            actionLabel: 'Add day',
            onAction: onAddDay,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: ListCard(
            children: [
              for (var i = 0; i < positions.length; i++)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (turn, id) in positions[i].turnOrder.indexed)
                      _DayRow(
                        session: byId[id]!,
                        number: turn == 0 ? i + 1 : null,
                        turn: positions[i].alternates ? turn : null,
                        isLast: turn == positions[i].sessionIds.length - 1,
                        onTap: () => _showPositionSheet(
                          context,
                          ref,
                          position: positions[i],
                          others: [
                            for (final p in positions)
                              if (!identical(p, positions[i])) p,
                          ],
                          nameOf: nameOf,
                          regimeId: regimeId,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.section),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Space.gutter),
          child: EmptyBox(
            icon: Icons.self_improvement_rounded,
            message: 'Rest days are not scheduled. A cycle is one pass '
                'through these days rather than a calendar week, and it '
                'advances only when a day is trained. You can rest whenever '
                'you choose.',
          ),
        ),
      ],
    );
  }
}

/// One day in the list of a cycle's positions.
class _DayRow extends ConsumerWidget {
  const _DayRow({
    required this.session,
    required this.number,
    required this.turn,
    required this.isLast,
    required this.onTap,
  });

  final Session session;

  /// The position's number, on the day due in it and on no other.
  final int? number;

  /// How many cycles until this day's turn, or null for a day trained every
  /// cycle, which has no turn to wait for.
  final int? turn;

  /// Whether this is the last day of its position, where the line between the
  /// days that alternate ends.
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final slots = ref.watch(sessionSlotsProvider(session.id)).valueOrNull;
    final turn = this.turn;

    return TurnLine(
      numbered: number != null,
      above: turn != null && turn > 0,
      below: turn != null && !isLast,
      child: AppRow(
        leading: PositionMark(number: number),
        title: session.name,
        // An empty line while the day's movements load, so the row does not
        // change height when they arrive. `No exercises` is a claim, and it is
        // made only once it is known.
        subtitle: slots == null
            ? ''
            : exerciseLine([for (final s in slots) s.exercise.name]),
        subtitleMaxLines: 1,
        subtitleLeading: turn == null
            ? null
            : Pill(
                cycleAheadLabel(turn),
                color: turn == 0 ? c.textPrimary : null,
                solid: turn == 0,
              ),
        trailing: Icon(Icons.more_horiz_rounded, size: 20, color: c.textPrimary),
        onTap: onTap,
      ),
    );
  }
}

enum _PositionAction { addAlternate, alternateWithExisting, stop }

/// What can be done to one position of the cycle.
///
/// Reads both repositories before the first sheet opens and acts on what the
/// sheet returns, so nothing reaches for a [WidgetRef] after a sheet has
/// closed over it ([RULES.md § 4](RULES.md#4-code)).
Future<void> _showPositionSheet(
  BuildContext context,
  WidgetRef ref, {
  required CyclePosition position,
  required List<CyclePosition> others,
  required String Function(String id) nameOf,
  required String regimeId,
}) async {
  final regimes = ref.read(regimeRepositoryProvider);
  final training = ref.read(trainingRepositoryProvider);
  final names = [for (final id in position.sessionIds) nameOf(id)];
  final first = position.sessionIds.first;

  final action = await showAppSheet<_PositionAction>(
    context,
    builder: (sheet) => AppSheet(
      title: joinDayNames(names),
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        AppRow(
          icon: Icons.add_rounded,
          title: position.alternates
              ? 'Add another alternating day'
              : 'Add an alternating day',
          subtitle: position.alternates
              ? 'The new day joins this rotation. One day is trained in '
                  'each cycle.'
              : 'The new day shares this position. One of the two is '
                  'trained in each cycle.',
          onTap: () => Navigator.of(sheet).pop(_PositionAction.addAlternate),
        ),
        // Offered for a day with a position of its own. A rotation asked to
        // alternate with another day has no single day to move.
        if (!position.alternates && others.isNotEmpty)
          AppRow(
            icon: Icons.swap_horiz_rounded,
            title: 'Alternate with an existing day',
            subtitle: 'The two share one position, and their logged '
                'workouts are unchanged',
            onTap: () =>
                Navigator.of(sheet).pop(_PositionAction.alternateWithExisting),
          ),
        if (position.alternates)
          AppRow(
            icon: Icons.call_split_rounded,
            title: 'Stop alternating',
            subtitle:
                '${joinDayNames(names)} each take a position of their own',
            onTap: () => Navigator.of(sheet).pop(_PositionAction.stop),
          ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _PositionAction.addAlternate:
      final taken = await regimes.liveSessionNames(regimeId);
      if (!context.mounted) return;
      final name = await promptForText(
        context,
        title: 'New alternating day',
        hint: 'Leg 2, Upper B',
        help: 'Alternates with ${joinDayNames(names)}',
        validate: (value) => taken.contains(value.trim().toLowerCase())
            ? 'This regime already has a day called ${value.trim()}'
            : null,
      );
      if (name == null || name.isEmpty) return;
      await regimes.addAlternatingSession(first, name);

    case _PositionAction.alternateWithExisting:
      final partner = await showAppSheet<String>(
        context,
        builder: (sheet) => AppSheet(
          title: 'Alternates with',
          subtitle: names.single,
          contentPadding: const EdgeInsets.only(bottom: Space.md),
          children: [
            for (final other in others)
              AppRow(
                title: joinDayNames(
                  [for (final id in other.sessionIds) nameOf(id)],
                ),
                trailing: const AppRadio(selected: false),
                onTap: () => Navigator.of(sheet).pop(other.sessionIds.first),
              ),
          ],
        ),
      );
      if (partner == null) return;
      await regimes.alternateSessions(first, partner);

    case _PositionAction.stop:
      await regimes.stopAlternating(first);
  }

  // Two days folded into one position can leave the open cycle owing nothing:
  // one of them trained, the other no longer asked for. Closed here for the
  // reason deleting a day closes it, so Workouts never reads "up next" over a
  // cycle that is already full.
  await training.closeCycleIfSatisfied(regimeId);
}
