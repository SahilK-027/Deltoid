import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/cycle_engine.dart';
import '../log/log_screen.dart';
import '../regime/regime_screen.dart';
import '../regime/regime_setup.dart';
import '../regime/session_editor.dart';
import '../settings/settings_screen.dart';
import 'heatmap_providers.dart';
import 'widgets/heatmap.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regimeAsync = ref.watch(activeRegimeProvider);
    final regime = regimeAsync.valueOrNull;
    final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];
    final status = ref.watch(cycleStatusProvider).valueOrNull;
    final open = ref.watch(openWorkoutProvider).valueOrNull;
    final hasHistory = ref.watch(hasCompletedWorkoutProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deltoid'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: switch ((regimeAsync.isLoading, regime, sessions.isEmpty)) {
        // Still opening the database: no empty state, or a fresh install
        // flashes "no regime" at someone who has one.
        (true, null, _) => const Center(child: CircularProgressIndicator()),
        (_, null, _) => const _NoRegimeState(),
        (_, final r?, true) => _NoSessionsState(regime: r),
        (_, final r?, false) => ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.sm, Space.lg, Space.huge),
            children: [
              if (open != null)
                _ResumeCard(workout: open, sessions: sessions)
              else if (status != null)
                _NextSessionCard(
                  regimeId: r.id,
                  status: status,
                  sessions: sessions,
                ),
              const SizedBox(height: Space.xxl),
              _ConsistencyCard(hasHistory: hasHistory),
              const SizedBox(height: Space.xxl),
              if (status != null)
                _AllSessions(
                  regimeId: r.id,
                  status: status,
                  sessions: sessions,
                  disabled: open != null,
                ),
            ],
          ),
      },
    );
  }
}

/// First launch. The app ships with no programme at all, so this is the one
/// screen a brand-new install has — it has to offer the way forward, not just
/// point at another tab.
class _NoRegimeState extends ConsumerWidget {
  const _NoRegimeState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyState(
      icon: Icons.tune,
      title: 'Nothing set up yet',
      message: 'Build your training split — any number of sessions, in any '
          'order. One pass through all of them is a cycle.',
      action: FilledButton(
        onPressed: () => createRegimeFlow(context, ref),
        child: const Text('Create a regime'),
      ),
    );
  }
}

/// A regime exists but has no training days in it, which happens after
/// "start from scratch". Starting a workout is impossible until this is fixed,
/// so the fix is the only thing offered.
class _NoSessionsState extends ConsumerWidget {
  const _NoSessionsState({required this.regime});

  final Regime regime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyState(
      icon: Icons.playlist_add,
      title: 'No sessions in ${regime.name}',
      message: 'Add the training days that make up one cycle, then fill each '
          'one with exercises in the Regime tab.',
      action: FilledButton(
        onPressed: () => addSessionPrompt(context, ref, regime.id),
        child: const Text('Add a session'),
      ),
    );
  }
}

/// Shown when a session was started and not finished. Losing an in-progress
/// log to a locked phone screen would be unforgivable, so resuming is the
/// loudest thing on the screen.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.workout, required this.sessions});

  final Workout workout;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final name = sessions
            .where((s) => s.id == workout.sessionId)
            .map((s) => s.name)
            .firstOrNull ??
        'Workout';
    // Carry the deload identity through the resume path too, or a light week
    // silently looks like a normal one the moment you come back to it.
    final accent = workout.isDeload ? c.deload : c.accent;

    return AppCard(
      highlightColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill('In progress', color: accent, icon: Icons.circle),
              if (workout.isDeload) ...[
                const SizedBox(width: Space.sm),
                Pill('Deload', color: c.deload),
              ],
              const Spacer(),
              Text(
                _elapsed(workout.startedAt),
                style: context.t.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(name, style: context.t.displaySmall),
          const SizedBox(height: Space.lg),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: c.onAccent,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LogScreen(workoutId: workout.id),
              ),
            ),
            child: const Text('Resume session'),
          ),
        ],
      ),
    );
  }

  static String _elapsed(int startedAtMs) {
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(startedAtMs, isUtc: true).toLocal(),
    );
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

class _NextSessionCard extends ConsumerWidget {
  const _NextSessionCard({
    required this.regimeId,
    required this.status,
    required this.sessions,
  });

  final String regimeId;
  final CycleStatus status;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final nextId = status.nextSessionId;
    if (nextId == null) {
      return const EmptyState(
        icon: Icons.playlist_add,
        title: 'No sessions yet',
        message: 'Add sessions to this regime and they will show up here.',
      );
    }

    final session = sessions.where((s) => s.id == nextId).firstOrNull;
    final preview = ref.watch(sessionPreviewProvider(nextId)).valueOrNull;
    final accent = status.isDeload ? c.deload : c.accent;
    // An empty session can be started, but only produces an empty log. Send the
    // user to fill it in instead of into a blank page.
    final isEmptySession = preview != null && preview.isEmpty;

    return AppCard(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('UP NEXT', style: context.t.labelSmall),
              const Spacer(),
              if (status.isDeload)
                Pill('Deload cycle', color: c.deload, icon: Icons.trending_down),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(session?.name ?? 'Session', style: context.t.displaySmall),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Text(
                'Cycle ${status.cycleIndex}',
                style: context.t.bodyMedium?.copyWith(color: accent),
              ),
              Text('  ·  ', style: context.t.bodyMedium),
              Text(
                '${status.done} of ${status.total} sessions done',
                style: context.t.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          _CycleDots(status: status, sessions: sessions),
          if (preview != null && preview.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Text(
              preview.take(4).join('  ·  ') +
                  (preview.length > 4 ? '  ·  +${preview.length - 4} more' : ''),
              style: context.t.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (isEmptySession) ...[
            const SizedBox(height: Space.lg),
            Text(
              'This session has no exercises yet.',
              style: context.t.bodySmall,
            ),
          ],
          const SizedBox(height: Space.xl),
          if (isEmptySession)
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionEditorScreen(sessionId: nextId),
                ),
              ),
              child: const Text('Add exercises'),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: c.onAccent,
              ),
              onPressed: () => _start(context, ref, nextId),
              child: Text('Start ${session?.name ?? 'session'}'),
            ),
          if (status.deloadAfterThisCycle && !status.isDeload) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: c.deload),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Deload starts after this cycle.',
                    style: context.t.bodySmall?.copyWith(color: c.deload),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref, String sessionId) async {
    final repo = ref.read(trainingRepositoryProvider);
    final navigator = Navigator.of(context);
    final id = await repo.startWorkout(regimeId: regimeId, sessionId: sessionId);
    if (!context.mounted) return;
    navigator.push(MaterialPageRoute(builder: (_) => LogScreen(workoutId: id)));
  }
}

/// One dot per session in the cycle. Filled = trained. Reads as progress
/// without needing a percentage.
class _CycleDots extends StatelessWidget {
  const _CycleDots({required this.status, required this.sessions});

  final CycleStatus status;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = status.isDeload ? c.deload : c.accent;

    return Row(
      children: [
        for (final id in status.sessionIds)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: Motion.base,
                    height: 4,
                    decoration: BoxDecoration(
                      color: status.completedSessionIds.contains(id)
                          ? accent
                          : c.surfaceHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    sessions
                            .where((s) => s.id == id)
                            .map((s) => s.name)
                            .firstOrNull ??
                        '',
                    style: context.t.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ConsistencyCard extends ConsumerWidget {
  const _ConsistencyCard({required this.hasHistory});

  /// An empty grid reads as a bug on a fresh install; with nothing logged the
  /// card says so in words instead.
  final bool hasHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(heatmapProvider(13)).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Consistency',
          trailing: data == null || !hasHistory
              ? null
              : Text(
                  '${data.perWeekLast4.toStringAsFixed(1)} / week',
                  style: context.t.labelMedium?.copyWith(color: context.c.accent),
                ),
        ),
        AppCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConsistencyHeatmap(days: data?.days ?? const {}),
              const SizedBox(height: Space.lg),
              if (hasHistory)
                const HeatmapLegend()
              else
                Text(
                  'Nothing logged yet. Finish a session and it lands here, '
                  'and in History.',
                  style: context.t.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Every session in the regime, so training out of order is one tap rather
/// than a fight with the app.
class _AllSessions extends ConsumerWidget {
  const _AllSessions({
    required this.regimeId,
    required this.status,
    required this.sessions,
    required this.disabled,
  });

  final String regimeId;
  final CycleStatus status;
  final List<Session> sessions;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('This cycle'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < sessions.length; i++) ...[
                if (i > 0) Divider(color: c.border, height: 1),
                _SessionRow(
                  session: sessions[i],
                  done: status.completedSessionIds.contains(sessions[i].id),
                  isNext: status.nextSessionId == sessions[i].id,
                  onTap: disabled
                      ? null
                      : () => _start(context, ref, sessions[i].id),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref, String sessionId) async {
    final repo = ref.read(trainingRepositoryProvider);
    final navigator = Navigator.of(context);
    final id = await repo.startWorkout(regimeId: regimeId, sessionId: sessionId);
    if (!context.mounted) return;
    navigator.push(MaterialPageRoute(builder: (_) => LogScreen(workoutId: id)));
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.done,
    required this.isNext,
    required this.onTap,
  });

  final Session session;
  final bool done;
  final bool isNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: done ? c.accent : c.textTertiary,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                session.name,
                style: context.t.titleSmall?.copyWith(
                  color: done ? c.textSecondary : c.textPrimary,
                ),
              ),
            ),
            if (isNext) Pill('Next', color: c.accent),
            const SizedBox(width: Space.sm),
            Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
