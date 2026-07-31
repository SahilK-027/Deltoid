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

/// One row in either session sheet. The two sheets ask different questions of
/// the same list, so the row is shared and only the trailing mark differs.
class _SessionPickRow extends StatelessWidget {
  const _SessionPickRow({
    required this.session,
    required this.onTap,
    this.done = false,
    this.isNext = false,
  });

  final Session session;
  final VoidCallback onTap;
  final bool done;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: c.surfaceHigh,
            borderRadius: BorderRadius.circular(Radii.md),
            border: isNext ? Border.all(color: c.accent, width: 2) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session.name,
                  style: context.t.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (done) ...[
                Icon(Icons.check_rounded, size: 16, color: c.positive),
                const SizedBox(width: Space.xs),
                Text('done this cycle', style: context.t.labelSmall),
              ] else if (isNext)
                Text('NEXT UP', style: context.t.labelSmall)
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: c.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starts a session other than the queue head.
///
/// The cycle is an order, not a rota: the hero names the first session not yet
/// trained, and this is how you say "not that one, this one". Two taps, which
/// is what the always-on session list under the hero used to cost.
Future<void> _trainAnotherSession(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required List<Session> sessions,
  required CycleStatus status,
}) async {
  final chosen = await showModalBottomSheet<Session>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => AppSheet(
      title: 'Start a session',
      subtitle: 'Cycle ${status.cycleIndex} — train them in any order',
      children: [
        for (final s in sessions)
          _SessionPickRow(
            session: s,
            done: status.completedSessionIds.contains(s.id),
            isNext: status.nextSessionId == s.id,
            onTap: () => Navigator.of(sheet).pop(s),
          ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;

  // Training the same day twice in a cycle is legitimate, but it is far more
  // often a mis-tap on a row that already carries a tick.
  if (status.completedSessionIds.contains(chosen.id)) {
    final again = await confirmAction(
      context,
      title: '${chosen.name} is already done',
      message: 'You logged it in this cycle. Train it again?',
      confirmLabel: 'Train again',
      destructive: false,
    );
    if (!again || !context.mounted) return;
  }

  await _startSession(context, ref, regimeId: regimeId, sessionId: chosen.id);
}

/// Writes down a session that was trained but never logged.
///
/// One sheet, not two: picking the session and then being handed a bare
/// calendar dialog gave no sign that the two questions belonged to the same
/// answer. The day is chosen first and stays on screen while you pick, because
/// the day is the part that makes this different from starting a session now.
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
      const SnackBar(content: Text('Finish the session you are in first')),
    );
    return;
  }

  final picked =
      await showModalBottomSheet<({String sessionId, DateTime date})>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => _BackfillSheet(sessions: sessions),
  );
  if (picked == null || !context.mounted) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(trainingRepositoryProvider);
  try {
    // Which cycle a backfill lands in is decided by its date, not by today, so
    // say which one. Otherwise it is invisible until a deload arrives early and
    // nobody knows why.
    final cycle = await repo.cycleCovering(regimeId, picked.date);
    final id = await repo.startWorkout(
      regimeId: regimeId,
      sessionId: picked.sessionId,
      at: picked.date,
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

/// The day picker and the session list in one sheet. Defaults to yesterday —
/// the overwhelmingly common case is remembering one day late.
class _BackfillSheet extends StatefulWidget {
  const _BackfillSheet({required this.sessions});

  final List<Session> sessions;

  @override
  State<_BackfillSheet> createState() => _BackfillSheetState();
}

class _BackfillSheetState extends State<_BackfillSheet> {
  DateTime _date = DateTime.now().subtract(const Duration(days: 1));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: now,
      helpText: 'When did you train it?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  String get _label {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(_date.year, _date.month, _date.day))
        .inDays;
    final stamp = DateFormat('EEE d MMM').format(_date);
    return switch (days) {
      0 => 'Today  ·  $stamp',
      1 => 'Yesterday  ·  $stamp',
      _ => '$days days ago  ·  $stamp',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppSheet(
      title: 'Log a past session',
      subtitle: 'Set the day, then pick what you did',
      children: [
        Pressable(
          onTap: _pickDate,
          scale: 0.98,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            decoration: BoxDecoration(
              color: c.surfaceHigh,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: 18, color: c.textPrimary),
                const SizedBox(width: Space.md),
                Expanded(child: Text(_label, style: context.t.titleMedium)),
                const LinkAction('Change'),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Text('Which session', style: context.t.bodySmall),
        ),
        for (final s in widget.sessions)
          _SessionPickRow(
            session: s,
            onTap: () =>
                Navigator.of(context).pop((sessionId: s.id, date: _date)),
          ),
      ],
    );
  }
}

/// The screen reads top to bottom as one thought: where you stand, the one
/// thing to do about it, then the record.
///
/// It used to draw the cycle twice — a row of labelled bars inside the hero
/// card, then the same sessions again as a tappable list — which is what pushed
/// the consistency grid off the bottom of the screen. The hero's track is the
/// only rendering of cycle progress now; the sessions live in a sheet.
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
      body: switch ((today, regime, sessions.isEmpty)) {
        // Nothing has loaded yet. Blank, not a spinner: the answers are on
        // local disk, and a spinner that shows for two frames is worse than
        // nothing. Any empty state here would be a guess — the frame before
        // the snapshot arrives looks exactly like a fresh install.
        (null, _, _) => const SizedBox.shrink(),
        (_, null, _) => const SafeArea(child: _NoRegimeState()),
        (_, final r?, true) => SafeArea(child: _NoSessionsState(regime: r)),
        (_, final r?, false) => Column(
            children: [
              HeaderBand(
                child: PageHeader(
                  title: 'Today',
                  eyebrow: DateFormat('EEEE d MMMM').format(DateTime.now()),
                  actions: [
                    CircleIconButton(
                      icon: Icons.edit_calendar_outlined,
                      tooltip: 'Log a past session',
                      onTap: () => _logPastSession(
                        context,
                        ref,
                        regimeId: r.id,
                        sessions: sessions,
                        hasOpenWorkout: open != null,
                      ),
                    ),
                    CircleIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                  // The question the app is opened with — "am I due?" — sits in
                  // the header, above the card that acts on the answer.
                  below: _RestGap(last: today!.lastCompleted),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.lg,
                    Space.gutter,
                    Space.huge,
                  ),
                  children: [
                    if (open != null)
                      _ResumeHero(
                        workout: open,
                        owner: today.snapshot.openWorkoutOwner,
                        doneSets: today.snapshot.openWorkoutDoneSets,
                        activeRegimeId: r.id,
                        sessions: sessions,
                      )
                    else if (status != null)
                      _NextUpHero(
                        regimeId: r.id,
                        regimeName: r.name,
                        status: status,
                        sessions: sessions,
                        preview: today.snapshot
                            .exerciseNamesBySession[status.nextSessionId],
                      ),
                    const SizedBox(height: Space.section),
                    _ConsistencyCard(
                      data: today.heatmap,
                      hasHistory: today.hasHistory,
                    ),
                    if (today.lastCompleted != null) ...[
                      const SizedBox(height: Space.section),
                      _LastSessionCard(last: today.lastCompleted!),
                    ],
                  ],
                ),
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
      icon: Icons.tune_rounded,
      title: 'Nothing set up yet',
      message: 'Build your training split — any number of sessions, in any '
          'order. One pass through all of them is a cycle.',
      action: PrimaryButton(
        label: 'Create a regime',
        onPressed: () => createRegimeFlow(context, ref),
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
      icon: Icons.playlist_add_rounded,
      title: 'No sessions in ${regime.name}',
      message: 'Add the training days that make up one cycle, then fill each '
          'one with exercises in the Regime tab.',
      action: PrimaryButton(
        label: 'Add a session',
        onPressed: () => addSessionPrompt(context, ref, regime.id),
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
    final (icon, text, tint) = switch (last) {
      null => (Icons.flag_outlined, 'No sessions logged yet', c.textSecondary),
      final l => switch (_daysSince(l.workout.dayKey)) {
          0 => (Icons.check_circle_rounded, 'Trained today', c.positive),
          1 => (
              Icons.bedtime_outlined,
              'Last trained yesterday',
              c.textSecondary
            ),
          final n => (
              Icons.bedtime_outlined,
              'Last trained $n days ago',
              n >= 4 ? c.deload : c.textSecondary,
            ),
        },
    };

    return Row(
      children: [
        Icon(icon, size: 15, color: tint),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Text(
            text,
            style: context.t.bodyMedium?.copyWith(color: tint),
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
/// nothing to rebuild it, so a session started an hour ago still said "0m".
/// [Ticking] wraps the clock alone: the card around it has no reason to repaint
/// every second.
class _ResumeHero extends ConsumerWidget {
  const _ResumeHero({
    required this.workout,
    required this.owner,
    required this.doneSets,
    required this.activeRegimeId,
    required this.sessions,
  });

  final Workout workout;

  /// The running workout's own session and regime, which are not looked up
  /// among the active regime's sessions: switching regimes with a workout open
  /// left that filter empty, and the card fell back to "Workout".
  final ({String? sessionName, String regimeId, String? regimeName})? owner;

  /// Sets ticked off so far. Zero-set sessions older than a day never reach
  /// this card — they are swept at launch — so a stale card here always has
  /// work in it worth deciding about.
  final int doneSets;

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
    final foreignRegime = owner != null && owner.regimeId != activeRegimeId
        ? owner.regimeName
        : null;
    final started =
        DateTime.fromMillisecondsSinceEpoch(workout.startedAt, isUtc: true)
            .toLocal();
    // Past a day this stops being a session in progress and becomes a decision:
    // a stopwatch reading 51 hours is not a useful thing to put on a screen.
    final stale = DateTime.now().difference(started).inHours >= 24;
    final mark = workout.isDeload ? c.deload : c.positive;

    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      fill: c.accentSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (stale)
                Icon(Icons.pause_circle_outline_rounded, size: 14, color: mark)
              else
                _LivePulse(color: mark),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  stale ? 'LEFT OPEN' : 'IN PROGRESS',
                  style: context.t.labelSmall?.copyWith(color: mark),
                ),
              ),
              if (workout.isDeload) Pill('Deload', color: c.deload),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(name, style: context.t.headlineSmall, maxLines: 2),
          const SizedBox(height: Space.xs),
          // A date does not belong in the value slot the stopwatch uses:
          // "open since Tue 28 Jul" set at display size overflowed the card on
          // every phone. Stale sessions say it once, quietly.
          if (stale)
            Text(
              'Started ${DateFormat('EEE d MMM').format(started)}  ·  '
              '$doneSets set${doneSets == 1 ? '' : 's'} logged',
              style: context.t.bodyMedium,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // The only thing on this card that changes on its own.
                Ticking(
                  builder: (context) => Text(
                    _elapsed(started),
                    style: context.t.displaySmall,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  'since ${DateFormat.jm().format(started)}',
                  style: context.t.bodyMedium,
                ),
              ],
            ),
          if (foreignRegime != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              'in $foreignRegime — finishing it advances that regime',
              style: context.t.bodyMedium,
            ),
          ],
          const SizedBox(height: Space.lg),
          PrimaryButton(
            label: stale ? 'Carry on with it' : 'Resume session',
            icon: Icons.play_arrow_rounded,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LogScreen(workoutId: workout.id),
              ),
            ),
          ),
          // Two ways out, offered only once the session has gone stale. A
          // running session needs neither: they are one tap deep in the log
          // screen, and putting them on Today would make quitting as prominent
          // as training.
          if (stale) ...[
            const SizedBox(height: Space.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                LinkAction(
                  'Finish it',
                  onTap: () => _finishStale(context, name, started),
                ),
                LinkAction(
                  'Discard',
                  onTap: () => _discardStale(context, name),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Saves it to the day it was started on, not to today. The workout's
  /// `dayKey` was stamped at Start and never moves, so the history it writes is
  /// the day it was actually trained.
  Future<void> _finishStale(
    BuildContext context,
    String name,
    DateTime started,
  ) async {
    final stamp = DateFormat('EEE d MMM').format(started);
    final ok = await confirmAction(
      context,
      title: 'Finish $name?',
      message: doneSets == 0
          ? 'It will be saved to $stamp with nothing in it.'
          : 'It will be saved to $stamp with the $doneSets '
              'set${doneSets == 1 ? '' : 's'} you logged. Sets you never '
              'ticked off are dropped.',
      confirmLabel: 'Finish',
      destructive: false,
    );
    if (!ok || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repo = ProviderScope.containerOf(context, listen: false)
        .read(trainingRepositoryProvider);
    try {
      await repo.completeWorkout(workout.id);
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Could not finish it: $e')));
    }
  }

  Future<void> _discardStale(BuildContext context, String name) async {
    final ok = await confirmAction(
      context,
      title: 'Discard $name?',
      message: doneSets == 0
          ? 'Nothing was logged in it, so nothing is lost.'
          : 'The $doneSets set${doneSets == 1 ? '' : 's'} logged in it go with '
              'it. This cannot be undone.',
      confirmLabel: 'Discard',
    );
    if (!ok || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repo = ProviderScope.containerOf(context, listen: false)
        .read(trainingRepositoryProvider);
    try {
      await repo.abandonWorkout(workout.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not discard it: $e')),
      );
    }
  }

  /// Stopwatch, because that is what the number is. Only drawn while the
  /// session is live — past a day the card stops showing a clock at all.
  static String _elapsed(DateTime started) {
    final d = DateTime.now().difference(started);
    if (d.isNegative) return '0:00';

    String two(int n) => n.toString().padLeft(2, '0');
    final mmss = '${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return d.inHours > 0 ? '${d.inHours}:$mmss' : mmss;
  }
}

/// A breathing dot. The only looping animation in the app, and it earns its
/// place: it is the difference between "a session is running right now" and "a
/// session was left open at some point".
class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.color});

  final Color color;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.55 + 0.45 * t),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// The one action, and the cycle it belongs to.
class _NextUpHero extends ConsumerWidget {
  const _NextUpHero({
    required this.regimeId,
    required this.regimeName,
    required this.status,
    required this.sessions,
    required this.preview,
  });

  final String regimeId;
  final String regimeName;
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
        icon: Icons.playlist_add_rounded,
        title: 'No sessions yet',
        message: 'Add sessions to this regime and they will show up here.',
      );
    }

    final session = sessions.where((s) => s.id == nextId).firstOrNull;
    final preview = this.preview ?? const <String>[];
    // An empty session can be started, but only produces an empty log. Send the
    // user to fill it in instead of into a blank page.
    final isEmptySession = preview.isEmpty;
    // One colour on this card, and it is the regime's own identity mark — not
    // an accent. A deload overrides it, because a light week outranks whose
    // programme it belongs to.
    final mark = status.isDeload ? c.deload : c.identityFor(regimeId);

    return AppCard(
      padding: const EdgeInsets.all(Space.lg),
      fill: c.accentSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(
                status.isDeload
                    ? Icons.trending_down_rounded
                    : Icons.bolt_rounded,
                color: mark,
                size: 40,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      regimeName,
                      style: context.t.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.xxs),
                    // The fraction used to live beside a "This cycle" header
                    // over the session list. That section is gone; this is the
                    // only place the cycle is summarised in figures, and the
                    // track below draws the same thing.
                    Text(
                      'Cycle ${status.cycleIndex}  ·  ${status.done} of '
                      '${status.total} done',
                      style: context.t.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              _DeloadSignal(status: status),
            ],
          ),
          const SizedBox(height: Space.md),
          // The cycle's shape in one line. Dense enough to read without
          // counting, quiet enough not to become a second chart.
          _CycleTrack(status: status, mark: mark),
          const SizedBox(height: Space.lg),
          Text(
            session?.name ?? 'Session',
            style: context.t.displayMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            // One line, not two. This is a glance — "yes, that's the session I
            // meant" — and the second line it used to wrap onto was the last
            // 18px above the bottom of a 844pt phone.
            Text(
              preview.take(3).join('  ·  ') +
                  (preview.length > 3
                      ? '  ·  +${preview.length - 3} more'
                      : ''),
              style: context.t.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (isEmptySession) ...[
            const SizedBox(height: Space.sm),
            Text(
              'This session has no exercises yet.',
              style: context.t.bodyMedium,
            ),
          ],
          const SizedBox(height: Space.lg),
          if (isEmptySession)
            SecondaryButton(
              label: 'Add exercises',
              icon: Icons.add_rounded,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionEditorScreen(sessionId: nextId),
                ),
              ),
            )
          else
            PrimaryButton(
              label: 'Start ${session?.name ?? 'session'}',
              icon: Icons.play_arrow_rounded,
              onPressed: ref.watch(_startingProvider)
                  ? null
                  : () => _startSession(
                        context,
                        ref,
                        regimeId: regimeId,
                        sessionId: nextId,
                      ),
            ),
          // The hero names the first session not yet trained, which is a
          // description and not an instruction — training Legs before Pull is
          // normal. One tap to open the picker, one to start: the same two taps
          // the old always-on session list cost, without a six-row block
          // claiming to be a plan for the day.
          if (sessions.length > 1) ...[
            const SizedBox(height: Space.sm),
            Center(
              child: LinkAction(
                'Train another session',
                onTap: ref.watch(_startingProvider)
                    ? null
                    : () => _trainAnotherSession(
                          context,
                          ref,
                          regimeId: regimeId,
                          sessions: sessions,
                          status: status,
                        ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Progress through the cycle as one hairline track, segment per session.
///
/// Not a return of the labelled bars this hero used to carry: those repeated
/// the session list underneath it, name for name. This is unlabelled and 5pt
/// tall — it says "two of five" faster than the words next to it can.
class _CycleTrack extends StatelessWidget {
  const _CycleTrack({required this.status, required this.mark});

  final CycleStatus status;
  final Color mark;

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
              duration: Motion.slow,
              curve: Motion.emphasized,
              height: 5,
              decoration: BoxDecoration(
                color: i < status.done ? mark : c.surfaceHighest,
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
      return Pill('Deload', color: c.deload, icon: Icons.trending_down);
    }
    if (status.deloadAfterThisCycle) {
      return Pill('Deload next', color: c.deload, icon: Icons.trending_down);
    }
    // -1 when deloads are switched off for this regime; nothing to promise.
    final remaining = status.cyclesUntilDeload;
    if (remaining <= 0) return const SizedBox.shrink();
    // With the unit, always. A bare "deload in 5" invites the two readings the
    // app can least afford to be vague about — days and weeks — and a cycle is
    // neither: it advances when the work is done.
    // `flex: 0` is the whole point. A bare [Flexible] defaults to flex 1, which
    // made this a flex child competing with the [Expanded] column beside it —
    // the row split its free space in half, this label used a fraction of its
    // half and left the rest as dead card, and the regime name was ellipsized
    // to pay for it. At flex 0 it sizes to its words and the column keeps the
    // remainder; it still shrinks rather than overflows if the words alone
    // outgrow the row.
    return Flexible(
      flex: 0,
      child: Text(
        'Deload in $remaining cycle${remaining == 1 ? '' : 's'}',
        style: context.t.labelSmall,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Consistency',
          // The three figures used to be a row of stat tiles inside the card,
          // above the grid. They are one short sentence, and 70pt of card was
          // what pushed the grid — the section's whole point — under the fold.
          subtitle: hasHistory ? _summary(data.consistency) : null,
          actionLabel: hasHistory ? 'All time' : null,
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HistoryHeatmapScreen()),
          ),
        ),
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
              ConsistencyHeatmap(days: data.days),
              // No legend here. It is reference material rather than something
              // you read at a glance, and the screen this card opens carries it
              // in full.
              if (!hasHistory) ...[
                const SizedBox(height: Space.md),
                Text(
                  'Nothing logged yet. Finish a session and it lands here, '
                  'and in History.',
                  style: context.t.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// One line where three stat tiles used to be. An em dash rather than a
  /// fabricated rate — under a fortnight of history there is no honest number
  /// (see [computeConsistency]).
  static String _summary(Consistency c) {
    final perWeek = c.perWeek;
    final days = c.windowDays;
    return [
      '${c.thisWeek} this week',
      perWeek == null ? '— per week' : '${perWeek.toStringAsFixed(1)} per week',
      '${c.sessions} in $days day${days == 1 ? '' : 's'}',
    ].join('  ·  ');
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
        const SectionHeader('Last session'),
        ListCard(
          children: [
            AppRow(
              title: last.sessionName ?? 'Workout',
              subtitle: [
                DateFormat('EEE d MMM').format(date),
                ?duration,
              ].join('  ·  '),
              leading: IconTile(
                w.isDeload ? Icons.trending_down_rounded : Icons.check_rounded,
                color: w.isDeload ? c.deload : c.positive,
                size: 40,
              ),
              chevron: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WorkoutDetailScreen(workoutId: w.id),
                ),
              ),
            ),
          ],
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
