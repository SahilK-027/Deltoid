import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/toast.dart';
import '../../data/db/database.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/deload_rest.dart';

/// The deload's rest actions, shared by Home and the cycle sheet on Regimes.
///
/// Each one writes through the repository and answers with a toast. The two
/// that add rest days carry `Undo`, because a rest is a choice about a day and
/// a mistaken tap should cost one more tap, not a trip to the cycle sheet.

/// Rests today in place of the session due next.
Future<void> restTodayAction(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
}) async {
  final repo = ref.read(trainingRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final ids = await repo.restToday(regimeId);
  if (ids.isEmpty) return;
  showToastOn(
    messenger,
    'Today is a rest day.',
    actionLabel: 'Undo',
    onAction: () => repo.removeRests(ids),
  );
}

/// Plans one rest day for each position the deload still owes, after showing
/// the days it would rest.
Future<void> restRemainingDaysAction(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required CycleStatus status,
  required List<Session> sessions,
}) async {
  final owed = status.remainingSessionIds;
  if (owed.isEmpty) return;
  final days = plannedRestDays(
    count: owed.length,
    todayKey: status.todayKey,
    todayTaken: status.restedTodaySessionId != null || status.trainedToday,
  );
  final names = {for (final s in sessions) s.id: s.name};
  final plan = [
    for (var i = 0; i < owed.length; i++)
      (name: names[owed[i]] ?? 'Session', dayKey: days[i]),
  ];

  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await _confirmRestPlan(
    context,
    plan: plan,
    nextCycle: status.cycleIndex + 1,
  );
  if (!confirmed) return;

  final repo = ref.read(trainingRepositoryProvider);
  final ids = await repo.restRemainingDays(regimeId);
  if (ids.isEmpty) return;
  showToastOn(
    messenger,
    ids.length == 1
        ? 'One rest day is planned.'
        : '${ids.length} rest days are planned.',
    actionLabel: 'Undo',
    onAction: () => repo.removeRests(ids),
  );
}

/// Gives back the rest days planned after today, so they are trained again.
Future<void> cancelPlannedRestAction(
  BuildContext context,
  WidgetRef ref, {
  required String cycleId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(trainingRepositoryProvider).cancelPlannedRests(cycleId);
  showToastOn(messenger, 'The planned rest is cancelled.');
}

/// A day key as the plan states it: `Thu 20 Nov`.
String restDayLabel(int dayKey) =>
    DateFormat('EEE d MMM').format(dateFromDayKey(dayKey));

Future<bool> _confirmRestPlan(
  BuildContext context, {
  required List<({String name, int dayKey})> plan,
  required int nextCycle,
}) async {
  final last = plan.last.dayKey;
  final answer = await showAppSheet<bool>(
    context,
    builder: (ctx) {
      final c = ctx.c;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.xl,
            Space.xl,
            Space.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Rest the remaining days',
                      style: ctx.t.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  CircleIconButton(
                    icon: Icons.close_rounded,
                    fill: Colors.transparent,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Each session the deload still holds becomes a rest day, '
                'one a day. Cycle $nextCycle starts on '
                '${restDayLabel(addDaysToKey(last, 1))}.',
                style: ctx.t.bodyMedium,
              ),
              const SizedBox(height: Space.lg),
              for (final day in plan)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bedtime_outlined,
                        size: Sizes.glyph,
                        color: c.deload,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          day.name,
                          style: ctx.t.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        restDayLabel(day.dayKey),
                        style: ctx.t.bodyMedium,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: plan.length == 1
                    ? 'Rest this day'
                    : 'Rest these ${plan.length} days',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: Space.xs),
              Pressable(
                onTap: () => Navigator.of(ctx).pop(false),
                scale: 0.97,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Text('Go back', style: ctx.t.titleMedium),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return answer ?? false;
}
