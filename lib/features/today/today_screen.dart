import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/ticking.dart';
import '../../data/db/database.dart';
import '../../domain/consistency.dart';
import '../../domain/cycle_engine.dart';
import '../history/workout_detail_screen.dart';
import '../log/log_screen.dart';
import '../regime/regime_screen.dart';
import '../regime/regime_setup.dart';
import '../regime/session_editor.dart';
import '../settings/settings_screen.dart';
import 'heatmap_data.dart';
import 'history_heatmap_screen.dart';
import 'today_providers.dart';
import 'widgets/heatmap.dart';

/// True between tapping Start and the log screen appearing.
///
/// Starting a workout writes a row per set before it returns; a second tap in
/// that window used to open a parallel session that could never be finished.
final _startingProvider = StateProvider<bool>((ref) => false);

/// Creates the workout and opens the log, once.
///
/// Everything after the first `await` goes through the [ProviderContainer]
/// rather than the caller's `ref`: creating the workout swaps this card for the
/// resume card, disposing the widget that started it. Clearing the flag through
/// a dead `ref` throws, and the button stays disabled for the rest of the
/// session — which is how this was found.
Future<void> _startSession(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required String sessionId,
}) async {
  if (ref.read(_startingProvider)) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  container.read(_startingProvider.notifier).state = true;
  try {
    final id = await container
        .read(trainingRepositoryProvider)
        .startWorkout(regimeId: regimeId, sessionId: sessionId);
    await navigator.push(
      MaterialPageRoute(builder: (_) => LogScreen(workoutId: id)),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not start the session: $e')),
    );
  } finally {
    container.read(_startingProvider.notifier).state = false;
  }
}

/// Writes down a session that was trained but never logged.
///
/// `dayKey` used to be stamped once from `DateTime.now()` and never again, so
/// forgetting to log Monday left Wednesday's entry permanently wrong, and
/// delete-and-redo didn't help because the redo was stamped today too.
Future<void> _logPastSession(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required List<Session> sessions,
  required bool hasOpenWorkout,
}) async {
  if (hasOpenWorkout) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Finish the session you are in first'),
      ),
    );
    return;
  }

  final sessionId = await showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: SectionLabel('Which session did you train?'),
          ),
          for (final s in sessions)
            ListTile(
              title: Text(s.name),
              onTap: () => Navigator.of(sheet).pop(s.id),
            ),
          const SizedBox(height: Space.md),
        ],
      ),
    ),
  );
  if (sessionId == null || !context.mounted) return;

  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now.subtract(const Duration(days: 1)),
    firstDate: DateTime(2015),
    lastDate: now,
    helpText: 'When did you train it?',
  );
  if (date == null || !context.mounted) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(trainingRepositoryProvider);
  try {
    // Which cycle a backfill lands in is decided by its date, not by today, so
    // say which one. Otherwise it is invisible until a deload arrives early and
    // nobody knows why.
    final cycle = await repo.cycleCovering(regimeId, date);
    final id = await repo.startWorkout(
      regimeId: regimeId,
      sessionId: sessionId,
      at: date,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          cycle == null
              ? 'Older than this regime — counts towards no cycle'
              : 'Counts towards cycle ${cycle.cycleIndex}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
    await navigator.push(
      MaterialPageRoute(builder: (_) => LogScreen(workoutId: id)),
    );
  } on StateError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open that session: $e')),
    );
  }
}

/// The screen reads top to bottom as one thought: where you stand, the one
/// thing to do about it, the alternatives, then the record.
///
/// It used to draw the cycle twice — a row of labelled bars inside the hero
/// card, then the same sessions again as a tappable list — which is what pushed
/// the consistency grid off the bottom of the screen and needed a
/// scroll-to-anchor to paper over. The list won: it says everything the bars
/// did and can be tapped.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One value, one frame. `valueOrNull` keeps the last snapshot on screen
    // while a reload runs, so a write on another tab never blanks this one.
    final today = ref.watch(todayProvider).valueOrNull;
    final regime = today?.regime;
    final sessions = today?.sessions ?? const <Session>[];
    final status = today?.snapshot.status;
    final open = today?.openWorkout;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deltoid'),
        actions: [
          if (regime != null && sessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.post_add_outlined),
              tooltip: 'Log a past session',
              onPressed: () => _logPastSession(
                context,
                ref,
                regimeId: regime.id,
                sessions: sessions,
                hasOpenWorkout: open != null,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: switch ((today, regime, sessions.isEmpty)) {
        // Nothing has loaded yet. Blank, not a spinner: the answers are on
        // local disk, and a spinner that shows for two frames is worse than
        // nothing. Any empty state here would be a guess — the frame before
        // the snapshot arrives looks exactly like a fresh install.
        (null, _, _) => const SizedBox.shrink(),
        (_, null, _) => const _NoRegimeState(),
        (_, final r?, true) => _NoSessionsState(regime: r),
        (_, final r?, false) => ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.sm, Space.lg, Space.huge),
            children: [
              // The rest gap answers the question the app is opened with — "am
              // I due?" — so it sits above the thing that acts on the answer.
              // Quiet on purpose: one 13pt line, because the card under it is
              // the only thing on this screen allowed to be loud.
              _RestGap(last: today!.lastCompleted),
              const SizedBox(height: Space.lg),
              if (open != null)
                _ResumeHero(
                  workout: open,
                  owner: today.snapshot.openWorkoutOwner,
                  activeRegimeId: r.id,
                  sessions: sessions,
                )
              else if (status != null)
                _NextUpHero(
                  regimeId: r.id,
                  status: status,
                  sessions: sessions,
                  preview:
                      today.snapshot.exerciseNamesBySession[status.nextSessionId],
                ),
              const SizedBox(height: Space.xl),
              // Every session, right under the hero: the hero names the first
              // one not yet done, which is a description and not an obligation.
              // Training Pull before Push has to be one tap and visible without
              // scrolling, or the app reads as though it forbids it.
              if (status != null)
                _CycleList(
                  regimeId: r.id,
                  status: status,
                  sessions: sessions,
                  slotCounts: today.snapshot.exerciseNamesBySession,
                  disabled: open != null,
                ),
              const SizedBox(height: Space.lg),
              _ConsistencyCard(
                data: today.heatmap,
                hasHistory: today.hasHistory,
              ),
              if (today.lastCompleted != null) ...[
                const SizedBox(height: Space.xxl),
                _LastSessionCard(last: today.lastCompleted!),
              ],
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

/// How long since the last session. Deliberately no session name — the card at
/// the bottom of the screen already names it, and saying it twice on one screen
/// reads as a template that lost track of itself.
class _RestGap extends StatelessWidget {
  const _RestGap({required this.last});

  final ({Workout workout, String? sessionName})? last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, text) = switch (last) {
      null => (Icons.flag_outlined, 'No sessions logged yet'),
      final l => switch (_daysSince(l.workout.dayKey)) {
          0 => (Icons.check_circle_outline, 'Trained today'),
          1 => (Icons.bedtime_outlined, 'Last trained yesterday'),
          final n => (Icons.bedtime_outlined, 'Last trained $n days ago'),
        },
    };

    return Row(
      children: [
        Icon(icon, size: 15, color: c.textTertiary),
        const SizedBox(width: Space.sm),
        // Today's date belongs on the screen called Today, and it was the one
        // piece of context the page never gave. Cheap to add here: this row was
        // already the page's quiet meta line.
        Text(
          DateFormat('EEE d MMM').format(DateTime.now()),
          style: context.t.bodySmall?.copyWith(color: c.textPrimary),
        ),
        Text('  ·  ', style: context.t.bodySmall),
        Flexible(
          child: Text(
            text,
            style: context.t.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Whole calendar days, not elapsed hours: a Monday evening session followed
  /// by a Tuesday morning one is "yesterday", not "0 days ago".
  static int _daysSince(int dayKey) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(dateFromDayKey(dayKey))
        .inDays;
  }
}

/// Shown when a session was started and not finished. Losing an in-progress
/// log to a locked phone screen would be unforgivable, so resuming is the
/// loudest thing on the screen.
///
/// The clock inside it used to read `DateTime.now()` once during `build` with
/// nothing to rebuild it, so a session started an hour ago still said "0m" — and
/// the first minute of every session said "0m" regardless, whole minutes being
/// the finest thing it could show. [Ticking] wraps the clock alone: the card
/// around it has no reason to repaint every second.
class _ResumeHero extends ConsumerWidget {
  const _ResumeHero({
    required this.workout,
    required this.owner,
    required this.activeRegimeId,
    required this.sessions,
  });

  final Workout workout;

  /// The running workout's own session and regime, which are not looked up
  /// among the active regime's sessions: switching regimes with a workout open
  /// left that filter empty, and the card fell back to "Workout".
  final ({String? sessionName, String regimeId, String? regimeName})? owner;

  final String activeRegimeId;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final owner = this.owner;
    final name = owner?.sessionName ??
        sessions
            .where((s) => s.id == workout.sessionId)
            .map((s) => s.name)
            .firstOrNull ??
        'Workout';
    // Finishing this advances the cycle of the regime it was started under,
    // which is worth saying when you are looking at a different one.
    final foreignRegime =
        owner != null && owner.regimeId != activeRegimeId ? owner.regimeName : null;
    // Carry the deload identity through the resume path too, or a light week
    // silently looks like a normal one the moment you come back to it.
    final accent = workout.isDeload ? c.deload : c.accent;
    final started =
        DateTime.fromMillisecondsSinceEpoch(workout.startedAt, isUtc: true)
            .toLocal();

    // Same tinted-card language as the next-up hero, one step louder: this one
    // is a solid accent outline rather than a faded one, because an unfinished
    // session outranks a suggested one.
    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      fill: Color.alphaBlend(accent.withValues(alpha: 0.07), c.surface),
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
            ],
          ),
          const SizedBox(height: Space.md),
          Text(name, style: context.t.displaySmall),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              // The only thing on this card that changes on its own.
              Ticking(
                builder: (context) => Text(
                  _elapsed(started),
                  style: context.t.titleMedium?.copyWith(
                    color: accent,
                    fontFeatures: tabular,
                  ),
                ),
              ),
              Text('  ·  ', style: context.t.bodySmall),
              Text(
                'started ${DateFormat.jm().format(started)}',
                style: context.t.bodySmall,
              ),
            ],
          ),
          if (foreignRegime != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              'in $foreignRegime — finishing it advances that regime',
              style: context.t.labelMedium?.copyWith(color: c.textSecondary),
            ),
          ],
          const SizedBox(height: Space.lg),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: c.onAccent,
              minimumSize: const Size.fromHeight(48),
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

  /// Stopwatch, because that is what the number is. Past a day it stops being a
  /// stopwatch and becomes a date — a workout left open since Tuesday should
  /// say Tuesday, not `51:20:07`.
  static String _elapsed(DateTime started) {
    final d = DateTime.now().difference(started);
    if (d.isNegative) return '0:00';
    if (d.inHours >= 24) return 'open since ${DateFormat('EEE d MMM').format(started)}';

    String two(int n) => n.toString().padLeft(2, '0');
    final mmss = '${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return d.inHours > 0 ? '${d.inHours}:$mmss' : mmss;
  }
}

/// The one action, and the cycle it belongs to. No card: this is the page, not
/// a panel on it.
class _NextUpHero extends ConsumerWidget {
  const _NextUpHero({
    required this.regimeId,
    required this.status,
    required this.sessions,
    required this.preview,
  });

  final String regimeId;
  final CycleStatus status;
  final List<Session> sessions;

  /// Exercise names in the next session, in slot order. Empty means the session
  /// has none; null only when there is no next session to preview.
  final List<String>? preview;

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
    final accent = status.isDeload ? c.deload : c.accent;
    final preview = this.preview ?? const <String>[];
    // An empty session can be started, but only produces an empty log. Send the
    // user to fill it in instead of into a blank page.
    final isEmptySession = preview.isEmpty;

    // The one tinted surface on the page. Everything else is a plain card, so
    // the eye lands here first without the hero having to shout in type size.
    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      fill: Color.alphaBlend(accent.withValues(alpha: 0.07), c.surface),
      highlightColor: accent.withValues(alpha: 0.30),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Says where you are, not what to do. Every "up next" wording tried
            // here read as an instruction, and the queue head is a suggestion:
            // the list below it starts any session in one tap.
            // One line, two voices: the cycle number in the accent, the count
            // after it quiet. Expanded rather than a fixed pair — "deload in 3
            // cycles" on the right is long enough to overflow a narrow phone,
            // which is exactly how this row first shipped.
            // No "0 of 6 done" here. The track directly underneath says it, and
            // the section header below says it again in figures — three copies
            // of one number on one screen was worse than the gap it filled.
            Expanded(
              child: Text(
                'CYCLE ${status.cycleIndex}',
                style: context.t.labelSmall?.copyWith(
                  color: accent,
                  letterSpacing: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Space.sm),
            _DeloadSignal(status: status),
          ],
        ),
        const SizedBox(height: Space.sm),
        // The cycle's shape in one line. Dense enough to read without counting,
        // quiet enough not to become a second chart.
        _CycleTrack(status: status, accent: accent),
        const SizedBox(height: Space.md),
        Text(
          session?.name ?? 'Session',
          style: context.t.displayMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          // One line, not two. This is a glance — "yes, that's the session I
          // meant" — and the second line it used to wrap onto was the last 18px
          // between the consistency grid and the bottom of a 844pt phone.
          Text(
            preview.take(3).join('  ·  ') +
                (preview.length > 3 ? '  ·  +${preview.length - 3} more' : ''),
            style: context.t.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (isEmptySession) ...[
          const SizedBox(height: Space.sm),
          Text(
            'This session has no exercises yet.',
            style: context.t.bodySmall,
          ),
        ],
        const SizedBox(height: Space.lg),
        if (isEmptySession)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
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
              minimumSize: const Size.fromHeight(52),
              textStyle: context.t.titleMedium,
            ),
            onPressed: ref.watch(_startingProvider)
                ? null
                : () => _startSession(
                      context,
                      ref,
                      regimeId: regimeId,
                      sessionId: nextId,
                    ),
            child: Text('Start ${session?.name ?? 'session'}'),
          ),
      ],
      ),
    );
  }
}

/// Progress through the cycle as one hairline track, segment per session.
///
/// Not a return of the labelled bars this hero used to carry: those repeated
/// the session list underneath it, name for name, and were the reason the
/// consistency grid fell off the bottom of the screen. This is unlabelled and
/// 4pt tall — it says "two of five" faster than the words next to it can, and
/// says nothing the list would have to say again.
class _CycleTrack extends StatelessWidget {
  const _CycleTrack({required this.status, required this.accent});

  final CycleStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A regime with no sessions never reaches here, but a zero would divide the
    // row into nothing and render as a stray gap.
    final total = status.total;
    if (total <= 0) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: Space.xs),
          Expanded(
            child: AnimatedContainer(
              duration: Motion.base,
              curve: Motion.curve,
              height: 4,
              decoration: BoxDecoration(
                // `surfaceHigh` for the unfilled segments vanished completely
                // against the hero's tinted card — the track was on screen and
                // invisible. `borderStrong` is the quietest colour that still
                // reads as a segment in both themes.
                color: i < status.done ? accent : c.borderStrong,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Where the deload is, stated once and in the hero rather than as a footnote
/// under the button. A light week that arrives unannounced looks like a bug in
/// the app; one that is two cycles away is worth planning around.
class _DeloadSignal extends StatelessWidget {
  const _DeloadSignal({required this.status});

  final CycleStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (status.isDeload) {
      return Pill('Deload cycle', color: c.deload, icon: Icons.trending_down);
    }
    if (status.deloadAfterThisCycle) {
      return Pill('Deload next', color: c.deload, icon: Icons.trending_down);
    }
    // -1 when deloads are switched off for this regime; nothing to promise.
    final remaining = status.cyclesUntilDeload;
    if (remaining <= 0) return const SizedBox.shrink();
    return Text(
      'deload in $remaining cycle${remaining == 1 ? '' : 's'}',
      style: context.t.labelSmall,
    );
  }
}

/// Every session in the regime, so training out of order is one tap rather
/// than a fight with the app.
class _CycleList extends ConsumerWidget {
  const _CycleList({
    required this.regimeId,
    required this.status,
    required this.sessions,
    required this.slotCounts,
    required this.disabled,
  });

  final String regimeId;
  final CycleStatus status;
  final List<Session> sessions;

  /// Exercise names per session id — the row only needs whether the list is
  /// empty, but it comes free with the preview.
  final Map<String, List<String>> slotCounts;

  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'This cycle',
          // The progress the labelled bars in the hero used to draw. The list
          // below is the same information with somewhere to tap.
          trailing: Text(
            '${status.done} / ${status.total}',
            style: context.t.labelMedium?.copyWith(
              color: status.isDeload ? c.deload : c.accent,
              fontFeatures: tabular,
            ),
          ),
        ),
        // A tap that does nothing reads as a broken app — but a sentence of
        // explanation under the header read as an error message, and it was the
        // only thing in the section anyone noticed. Dimming the whole group says
        // "not now" before a finger is lifted, and [IgnorePointer] means the
        // rows cannot be pressed at all rather than pressed to no effect.
        AnimatedOpacity(
          duration: Motion.base,
          curve: Motion.curve,
          opacity: disabled ? 0.38 : 1,
          child: IgnorePointer(
            ignoring: disabled,
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < sessions.length; i++) ...[
                    if (i > 0) Divider(color: c.border, height: 1),
                    _SessionRow(
                      regimeId: regimeId,
                      session: sessions[i],
                      ordinal: i + 1,
                      exercises: slotCounts[sessions[i].id] ?? const [],
                      done: status.completedSessionIds.contains(sessions[i].id),
                      isNext: status.nextSessionId == sessions[i].id,
                      disabled: disabled,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.regimeId,
    required this.session,
    required this.ordinal,
    required this.exercises,
    required this.done,
    required this.isNext,
    required this.disabled,
  });

  final String regimeId;
  final Session session;

  /// Position in the cycle, from one. The list is an order, and a column of
  /// identical circle outlines never said so.
  final int ordinal;

  /// What the session holds, in slot order. Empty means starting it would only
  /// produce an empty log, so the row offers the editor instead.
  ///
  /// Only the length is drawn. Listing the names filled the row but read as
  /// clutter, and repeated the hero's preview verbatim on whichever row is next.
  final List<String> exercises;

  bool get isEmpty => exercises.isEmpty;

  final bool done;
  final bool isNext;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final muted = disabled || done;

    return InkWell(
      onTap: disabled ? null : () => _tap(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            _Ordinal(ordinal: ordinal, done: done, isNext: isNext && !disabled),
            const SizedBox(width: Space.md),
            // One line. The count sits after the name rather than under it:
            // stacked, it made every row two lines tall for a number, and six
            // of those pushed the consistency grid towards the fold.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      session.name,
                      style: context.t.titleSmall?.copyWith(
                        color: muted ? c.textSecondary : c.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  // An empty session can be started, but only produces an empty
                  // log — offer the fix instead of the dead end.
                  // With the unit, not bare. A lone "6" after "Push 1" read as
                  // a typo rather than a count.
                  Text(
                    isEmpty
                        ? 'No exercises yet'
                        : '·  ${exercises.length} exercises',
                    style: context.t.labelMedium?.copyWith(
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // One trailing mark, never two. A "Next" pill beside a chevron
            // beside a tick was three competing affordances on a row whose whole
            // job is "tap me".
            if (isNext && !disabled)
              Pill('Next', color: c.accent)
            else if (done)
              Icon(Icons.check, size: 16, color: c.accent)
            else
              Icon(
                isEmpty ? Icons.edit_outlined : Icons.chevron_right,
                size: 18,
                color: c.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _tap(BuildContext context, WidgetRef ref) async {
    if (isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionEditorScreen(sessionId: session.id),
        ),
      );
      return;
    }

    // Training the same day twice in a cycle is legitimate, but it is far more
    // often a mis-tap on a row that already has a tick against it.
    if (done) {
      final again = await confirmAction(
        context,
        title: '${session.name} is already done',
        message: 'You logged it in this cycle. Train it again?',
        confirmLabel: 'Train again',
        destructive: false,
      );
      if (!again || !context.mounted) return;
    }

    await _startSession(
      context,
      ref,
      regimeId: regimeId,
      sessionId: session.id,
    );
  }
}

/// The session's place in the cycle, as a numeral in a chip.
///
/// Three states, one shape: done is filled, next is outlined in the accent, the
/// rest are quiet. Replaced a column of identical circle icons that said only
/// "done or not" and cost the row its sense of order.
class _Ordinal extends StatelessWidget {
  const _Ordinal({
    required this.ordinal,
    required this.done,
    required this.isNext,
  });

  final int ordinal;
  final bool done;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg, border) = switch ((done, isNext)) {
      (true, _) => (c.accentMuted, c.accent, c.accentMuted),
      (_, true) => (Colors.transparent, c.accent, c.accent),
      _ => (c.surfaceHigh, c.textTertiary, c.surfaceHigh),
    };

    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: border),
      ),
      child: Text(
        '$ordinal',
        style: context.t.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.data, required this.hasHistory});

  final HeatmapData data;

  /// An empty grid reads as a bug on a fresh install; with nothing logged the
  /// card says so in words instead.
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Consistency'),
        AppCard(
          padding: const EdgeInsets.all(Space.md),
          onTap: !hasHistory
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HistoryHeatmapScreen(),
                    ),
                  ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The rate used to be a 13pt trailing label on the section header,
              // the same size as the eyebrow next to it and easy to miss. It is
              // the point of the card, so it leads it — with the two numbers
              // that give it context, all three already in this snapshot.
              if (hasHistory) ...[
                _ConsistencyStats(consistency: data.consistency),
                const SizedBox(height: Space.md),
                Divider(color: c.border, height: 1),
                const SizedBox(height: Space.md),
              ],
              ConsistencyHeatmap(days: data.days),
              // No legend here. It is reference material rather than something
              // you read at a glance, it cost the grid its place above the fold,
              // and the screen this row opens carries it in full.
              if (hasHistory) ...[
                const SizedBox(height: Space.lg),
                Divider(color: c.border, height: 1),
                const SizedBox(height: Space.md),
                // "All time ›" used to be a lone right-aligned pair floating in
                // its own row with the whole card width empty beside it. Naming
                // the window the grid actually shows fills that line with the
                // one caption it was missing, and turns a stray affordance into
                // a footer that reads left to right.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Last $heatmapWeeks weeks',
                        style: context.t.bodySmall,
                      ),
                    ),
                    Text(
                      'All time',
                      style: context.t.labelMedium?.copyWith(color: c.accent),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: c.accent),
                  ],
                ),
              ] else ...[
                const SizedBox(height: Space.md),
                Text(
                  'Nothing logged yet. Finish a session and it lands here, '
                  'and in History.',
                  style: context.t.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

}

/// Three numbers across the top of the consistency card: the week you are in,
/// the rate, and the window the rate came from.
///
/// They are one fact each and deliberately not a chart — the grid underneath is
/// the chart. Everything here is already in the Today snapshot, so the row costs
/// no extra query.
class _ConsistencyStats extends StatelessWidget {
  const _ConsistencyStats({required this.consistency});

  final Consistency consistency;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final perWeek = consistency.perWeek;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StatTile(
            value: '${consistency.thisWeek}',
            label: 'this week',
            emphasis: c.accent,
          ),
        ),
        Expanded(
          // An em dash rather than a fabricated rate: under a fortnight of
          // history there is no honest number to print here. See
          // [computeConsistency].
          child: StatTile(
            value: perWeek == null ? '—' : perWeek.toStringAsFixed(1),
            label: perWeek == null ? 'need 2 weeks' : 'per week',
          ),
        ),
        Expanded(
          child: StatTile(
            value: '${consistency.sessions}',
            label: 'in ${consistency.windowDays} days',
          ),
        ),
      ],
    );
  }
}

/// The last thing you actually did, and a way back into it. Closes the loop the
/// rest of the screen opens: everything above is about what happens next.
class _LastSessionCard extends StatelessWidget {
  const _LastSessionCard({required this.last});

  final ({Workout workout, String? sessionName}) last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = last.workout;
    final date = dateFromDayKey(w.dayKey);
    final duration = _duration(w);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Last session'),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WorkoutDetailScreen(workoutId: w.id),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      last.sessionName ?? 'Workout',
                      style: context.t.titleSmall,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      [
                        DateFormat('EEE d MMM').format(date),
                        ?duration,
                      ].join('  ·  '),
                      style: context.t.bodySmall,
                    ),
                  ],
                ),
              ),
              if (w.isDeload) ...[
                Pill('Deload', color: c.deload),
                const SizedBox(width: Space.sm),
              ],
              Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
            ],
          ),
        ),
      ],
    );
  }

  /// Null when the workout has no end stamp, or when the two stamps disagree
  /// about the order of time — a backfilled session carries a made-up start and
  /// its "duration" would be fiction.
  static String? _duration(Workout w) {
    final ended = w.endedAt;
    if (ended == null || ended <= w.startedAt) return null;
    final d = Duration(milliseconds: ended - w.startedAt);
    if (d.inMinutes < 1) return null;
    if (d.inHours >= 6) return null;
    return d.inHours > 0
        ? '${d.inHours}h ${d.inMinutes % 60}m'
        : '${d.inMinutes} min';
  }
}
