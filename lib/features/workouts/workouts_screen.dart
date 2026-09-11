import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../account/recovery_note.dart';
import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/calendar.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/ticking.dart';
import '../../data/db/database.dart';
import '../../domain/consistency.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/muscle_volume.dart';
import '../history/workout_detail_screen.dart';
import '../log/log_screen.dart';
import '../log/widgets/exercise_sheets.dart';
import '../regime/regime_screen.dart';
import '../regime/regime_setup.dart';
import 'heatmap_data.dart';
import 'history_heatmap_screen.dart';
import 'workouts_providers.dart';
import 'volume_history_screen.dart';
import 'widgets/heatmap.dart';
import 'widgets/volume_bars.dart';
import '../../core/widgets/toast.dart';
import '../../core/failure.dart';

/// True between tapping Start and the log screen appearing.
///
/// Starting a workout writes a row per set before it returns; a second tap in
/// that window would otherwise open a parallel session that could never be
/// finished.
final _startingProvider = StateProvider<bool>((ref) => false);

/// Creates the workout and opens the log, once.
///
/// Everything after the first `await` goes through the [ProviderContainer]
/// rather than the caller's `ref`: creating the workout swaps this card for the
/// resume card, disposing the widget that started it. Clearing the flag through
/// a dead `ref` throws, leaving the button disabled for the rest of the
/// session.
Future<void> _startSession(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required String sessionId,
}) async {
  if (ref.read(_startingProvider)) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context);

  container.read(_startingProvider.notifier).state = true;
  try {
    final id = await container
        .read(trainingRepositoryProvider)
        .startWorkout(regimeId: regimeId, sessionId: sessionId);
    await navigator.push(
      MaterialPageRoute(builder: (_) => LogScreen(workoutId: id)),
    );
  } catch (e, st) {
    reportFailure(e, st, what: 'That session could not be started.');
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
        child: InsetPanel(
          outline: isNext ? BorderSide(color: c.accent, width: 2) : null,
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
                Text('Done this cycle', style: context.t.labelSmall),
              ] else if (isNext)
                // Sentence case, like `Done this cycle` two lines up. An
                // uppercase micro-label is what makes a screen look like a
                // template (THEME → Type) — uppercase belongs to the masthead.
                Text('Next up', style: context.t.labelSmall)
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
/// is what an always-on session list under the hero would cost in vertical
/// space.
Future<void> _trainAnotherSession(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required List<Session> sessions,
  required CycleStatus status,
}) async {
  final chosen = await showAppSheet<Session>(
    context,
    builder: (sheet) => AppSheet(
      title: 'Start a session',
      subtitle: 'Cycle ${status.cycleIndex}',
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
/// `dayKey` is stamped from the chosen day and carried through every write
/// that follows. Stamping it from `DateTime.now()` instead would leave
/// Wednesday's entry for a forgotten Monday permanently wrong, with
/// delete-and-redo no help because the redo would be stamped today too.
Future<void> _logPastSession(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required List<Session> sessions,
  required bool hasOpenWorkout,
}) async {
  if (hasOpenWorkout) {
    showToast(context, 'Finish the session you are in first');
    return;
  }

  final picked = await showAppSheet<_BackfillResult>(
    context,
    builder: (sheet) => _BackfillSheet(sessions: sessions),
  );
  if (picked == null || !context.mounted) return;

  // Tapping a day that is already logged and asking to see it: this flow ends
  // there, on the record rather than on a second copy of it.
  final existing = picked.workoutId;
  if (existing != null) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutDetailScreen(workoutId: existing),
      ),
    );
    return;
  }

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(trainingRepositoryProvider);
  try {
    // Which cycle a backfill lands in is decided by its date, not by today, so
    // say which one. Otherwise it is invisible until a deload arrives early and
    // nobody knows why.
    final date = picked.date!;
    final cycle = await repo.cycleCovering(regimeId, date);
    final id = await repo.startWorkout(
      regimeId: regimeId,
      sessionId: picked.sessionId!,
      at: date,
    );
    showToastOn(
      messenger,
      cycle == null
          ? 'Older than this regime, so it counts towards no cycle'
          : 'Counts towards cycle ${cycle.cycleIndex}',
    );
    await navigator.push(
      MaterialPageRoute(builder: (_) => LogScreen(workoutId: id)),
    );
  } on StateError catch (e) {
    showToastOn(messenger, e.message, destructive: true);
  } catch (e, st) {
    reportFailure(e, st, what: 'That session could not be opened.');
  }
}

/// The day picker and the session list in one sheet. Defaults to yesterday —
/// the overwhelmingly common case is remembering one day late.
/// What the backfill sheet came back with: a session to write on a day, or a
/// workout that day already holds and you asked to see.
class _BackfillResult {
  const _BackfillResult.log({required this.sessionId, required this.date})
    : workoutId = null;
  const _BackfillResult.open(this.workoutId) : sessionId = null, date = null;

  final String? sessionId;
  final DateTime? date;
  final String? workoutId;
}

class _BackfillSheet extends ConsumerStatefulWidget {
  const _BackfillSheet({required this.sessions});

  final List<Session> sessions;

  @override
  ConsumerState<_BackfillSheet> createState() => _BackfillSheetState();
}

class _BackfillSheetState extends ConsumerState<_BackfillSheet> {
  /// **This one becomes a row.** Every other date on this screen moves a label;
  /// accepting the sheet writes this into `startedAt` and `dayKey`, so a day
  /// that contains a clock change must not shift it. [daysBefore] names the
  /// calendar date rather than going back 86 400 seconds.
  DateTime _date = daysBefore(DateTime.now(), 1);

  /// Every day ever logged, so the calendar can ring them.
  ///
  /// Read in `build`, not in the handler that opens the picker: `fullHeatmapProvider`
  /// is `autoDispose`, so watching it from a callback subscribes at the moment
  /// of the tap and hands back the loading value, leaving the rings and the
  /// already-logged prompt with nothing to work from.
  Map<int, HeatDay> _logged = const {};

  Future<void> _pickDate() async {
    final c = context.c;
    final logged = _logged;

    final picked = await pickDay(
      context,
      initial: _date,
      // No floor of its own. The picker reaches back to 2015, or further if
      // something is marked before it — which is the rule every picker in the
      // app wants. Passing the first day ever logged, as this once did, made
      // the log its own floor: a session done the week before the app was
      // installed could not be backfilled, and backfill is what this is for.
      last: DateTime.now(),
      title: 'When did you train it?',
      // Blue for a day you trained, orange for a light week — the same two
      // colours the heatmap and the history rows use, so a calendar of
      // identical white numbers stops being the one place in the app that
      // cannot show you the gap you are trying to fill.
      marks: {
        for (final entry in logged.entries)
          entry.key: entry.value.isDeload ? c.deload : c.heatOn,
      },
    );
    if (picked == null || !mounted) return;

    final already = logged[dayKeyOf(picked)];
    if (already?.workoutId == null) {
      setState(() => _date = picked);
      return;
    }

    // A day that is already logged is ambiguous — you either came to read it or
    // to add the session you also did that day — so it asks rather than
    // guessing. Guessing "log another" is how a tap meant to check Tuesday
    // ends with a second Tuesday in history.
    final open = await _confirmTrainedDay(picked, already!);
    if (open == null || !mounted) return;
    if (open) {
      Navigator.of(context).pop(_BackfillResult.open(already.workoutId!));
    } else {
      setState(() => _date = picked);
    }
  }

  /// True to open what is there, false to log another, null to back out.
  Future<bool?> _confirmTrainedDay(DateTime day, HeatDay logged) {
    final count = logged.workouts;
    return showAppSheet<bool>(
      context,
      builder: (sheet) => AppSheet(
        title: DateFormat('EEEE d MMMM').format(day),
        subtitle: count == 1
            ? 'Already logged'
            : '$count sessions already logged',
        contentPadding: const EdgeInsets.only(bottom: Space.md),
        children: [
          AppRow(
            icon: Icons.visibility_outlined,
            title: 'See that workout',
            subtitle: 'What you actually did',
            onTap: () => Navigator.of(sheet).pop(true),
          ),
          AppRow(
            icon: Icons.add_circle_outline,
            title: 'Log another session',
            subtitle: 'A second session on the same day',
            onTap: () => Navigator.of(sheet).pop(false),
          ),
        ],
      ),
    );
  }

  String get _label {
    final days = daysBetween(_date, DateTime.now());
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
    _logged = ref.watch(fullHeatmapProvider).valueOrNull?.days ?? const {};
    return AppSheet(
      title: 'Log a past session',
      children: [
        Pressable(
          onTap: _pickDate,
          scale: 0.98,
          child: InsetPanel(
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
            onTap: () => Navigator.of(
              context,
            ).pop(_BackfillResult.log(sessionId: s.id, date: _date)),
          ),
      ],
    );
  }
}

/// The screen reads top to bottom as one thought: where you stand, the one
/// thing to do about it, then the record.
///
/// The hero's track is the only rendering of cycle progress, and the sessions
/// live in a sheet. Drawing the cycle twice — labelled bars inside the hero
/// card and the same sessions again as a tappable list — pushes the consistency
/// grid off the bottom of the screen.
class WorkoutsScreen extends ConsumerWidget {
  const WorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One value, one frame. `valueOrNull` keeps the last snapshot on screen
    // while a reload runs, so a write on another tab never blanks this one.
    final today = ref.watch(workoutsProvider).valueOrNull;
    // Warmed here, drawn two screens away. `Consistency` and the backfill
    // calendar both read every day ever logged, and starting that query when
    // they open means both open empty and fill in. Workouts is where you are
    // before you go to either, and this costs one aggregated query per change
    // to `workouts`.
    ref.watch(fullHeatmapProvider);
    // **Warmed here for the same reason, and it is the stronger case.** This
    // one is drawn *on this screen*, and watching it only where it is drawn
    // made it strictly slower than everything around it: the card lives inside
    // the branch that renders once `today` has arrived, so the query did not
    // start until the snapshot had already landed. Two local reads that could
    // have run together ran one after the other, and the section visibly
    // dropped in afterwards — the staged reveal the rest of this screen exists
    // to avoid. Started here, both are in flight in the same frame.
    final volume = ref.watch(weeklyVolumeProvider).valueOrNull;
    final regime = today?.regime;
    final sessions = today?.sessions ?? const <Session>[];
    final status = today?.snapshot.status;
    final open = today?.openWorkout;

    return Scaffold(
      body: switch ((today, volume, regime, sessions.isEmpty)) {
        // Nothing has loaded yet. Blank, not a spinner: the answers are on
        // local disk, and a spinner that shows for two frames is worse than
        // nothing. Any empty state here would be a guess — the frame before
        // the snapshot arrives looks exactly like a fresh install.
        //
        // **Both reads, not just the snapshot.** The page arrives whole or not
        // at all; waiting on the slower of two queries that started together
        // costs a frame or two, and a section that appears after the page did
        // costs the user's attention every time they land here.
        (null, _, _, _) || (_, null, _, _) => const SizedBox.shrink(),
        (_, _, null, _) => _NoRegimeState(
          last: today!.lastCompleted,
          heatmap: today.heatmap,
          hasHistory: today.hasHistory,
          volume: volume!,
        ),
        (_, _, final r?, true) => _NoSessionsState(
          regime: r,
          last: today!.lastCompleted,
          heatmap: today.heatmap,
          hasHistory: today.hasHistory,
          volume: volume!,
        ),
        // The masthead and the one action are a single band, and the record
        // scrolls under it. See [_WorkoutsHeader] for why the hero is not a card:
        // `AppCard` and `HeaderBand` are the same grey, so a card here grouped
        // nothing — it drew a rounded seam between two identical surfaces,
        // 16pt below a band it matched exactly. The band is also the answer to
        // why this block, alone on the screen, had no section header over it:
        // it is not a section, it is the header.
        // The band is pinned and the record scrolls under it. As the first
        // item in the list it would slide off the top the moment you looked at
        // the heatmap, taking the one thing you came for with it — the session,
        // and the button that starts it.
        (_, _, final r?, false) => Column(
          children: [
            _WorkoutsHeader(
              last: today!.lastCompleted,
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
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: Space.huge),
                children: [
                  // The session is the page's first *section*, not part of the
                  // masthead. The band ends at the line about when you last
                  // trained; everything you can act on is content under it,
                  // with its own heading like every other block here.
                  // The band's own `surface`, full width — connected to the
                  // header by colour, separated from it by the gap. On the page
                  // background the screen's one primary action sat on the
                  // flattest surface the app has.
                  if (open != null)
                    _SurfaceBlock(
                      child: _ResumeHero(
                        workout: open,
                        owner: today.snapshot.openWorkoutOwner,
                        doneSets: today.snapshot.openWorkoutDoneSets,
                        totalSets: today.snapshot.openWorkoutTotalSets,
                        preview: today.snapshot.openWorkoutExerciseNames,
                        activeRegimeId: r.id,
                        activeRegimeName: r.name,
                        sessions: sessions,
                      ),
                    )
                  else if (status != null)
                    _SurfaceBlock(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader("Today's session"),
                          _NextUpHero(
                            regimeId: r.id,
                            regimeName: r.name,
                            status: status,
                            sessions: sessions,
                            preview: today
                                .snapshot
                                .exerciseNamesBySession[status.nextSessionId],
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.section,
                      Space.gutter,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ConsistencyCard(
                          data: today.heatmap,
                          hasHistory: today.hasHistory,
                        ),
                        // Under the grid, because they answer the same
                        // question one level down: the heatmap says whether you
                        // turned up, this says what you trained when you did.
                        //
                        // Not gated on history. Appearing only once something
                        // was logged would make the section arrive out of
                        // nowhere on the day of the first workout — the screen
                        // changing shape underneath you at the one moment you
                        // are reading it. The zero state carries it too, so the
                        // page is the same page before and after.
                        const SizedBox(height: Space.section),
                        _VolumeCard(volume: volume!),
                        if (today.lastCompleted != null) ...[
                          const SizedBox(height: Space.section),
                          _LastSessionCard(last: today.lastCompleted!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      },
    );
  }
}

/// The masthead, shared by every state this screen can be in.
///
/// The empty states carry it too. Centring a lone card on a blank page instead
/// reads as a different screen than the one the tab bar says you are on, and on
/// a fresh install leaves no way to reach Settings, which is where restoring a
/// backup lives. Settings is always here for that reason; anything that needs
/// sessions to exist is passed in by the caller.
///
/// The title is the screen's name, with the date as its eyebrow, rather than
/// the other way round: the nav label is 11sp at the far end of the screen, and
/// a masthead is not, so titling by date would leave the one screen you land on
/// the only one whose masthead never says where you are.
///
/// It is pinned, and the record below it scrolls: the session and the button
/// that starts it are the reason the screen exists, and they would otherwise
/// slide away the moment you looked at the heatmap.
///
/// The rest gap stays a quiet line under it. It answers the question the app is
/// opened with, but it is not the page's name and does not want title type:
/// `NO SESSIONS YET` at 27sp is the loudest thing on a screen whose whole
/// message is that nothing has happened yet.
class _WorkoutsHeader extends StatelessWidget {
  const _WorkoutsHeader({required this.last, this.actions = const []});

  final ({Workout workout, String? sessionName})? last;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return HeaderBand(
      child: PageHeader(
        // The screen names itself, like every other destination. The nav label
        // is 11sp at the bottom of the screen, so titling this with the date
        // instead would leave the one screen you land on the only one you have
        // to identify by inference. The date sits over the title.
        title: 'Workouts',
        eyebrow: DateFormat('EEEE d MMMM').format(now),
        // Tight to the date: the rest gap is a line about it, not the next
        // thing on the page.
        belowGap: Space.xs,
        // The band is the masthead and nothing else — name, date, and when you
        // last trained. Putting the session in here too, on the band's own
        // surface, would make the header half the screen tall and leave the
        // first real section starting somewhere down the page with no boundary
        // to mark it.
        below: _RestGap(last: last),
        // No cog: Settings is a destination on the nav bar, and a screen
        // reachable two ways is a screen you have to decide about twice.
        actions: actions,
      ),
    );
  }
}

/// A full-width block on the band's own `surface`.
///
/// Connected to the header by colour, separated from it by the gap — a card
/// would draw a rounded seam between two identical greys, which is the thing
/// the hero was taken out of a card to stop.
class _SurfaceBlock extends StatelessWidget {
  const _SurfaceBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: context.c.surface,
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xl,
      ),
      child: child,
    );
  }
}

/// How long since the last session, under the date it is counted from.
///
/// Deliberately no session name — the card at the bottom of the screen already
/// names it, and saying it twice on one screen reads as a template that lost
/// track of itself. At `body` size it can afford the full phrasing; the tint is
/// the only colour in the band, and it earns it (rule 1: this *is* data).
class _RestGap extends StatelessWidget {
  const _RestGap({required this.last});

  final ({Workout workout, String? sessionName})? last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Four states, one verb each, none longer than "Trained today".
    //
    // `Last trained 3 days ago` was three words of scaffolding around one
    // number, and the scaffolding is what the icon beside it is for: a bed
    // means rest, so the line only has to say how much of it. Counting rest
    // rather than dating the last session also answers the question actually
    // being asked — not "when did I train" but "am I due".
    //
    // Trained / Rested keeps the two live states parallel: same shape, same
    // length, one word apart, so the difference between them is the only thing
    // that has to be read.
    final (icon, text, tint) = switch (last) {
      null => (Icons.flag_outlined, 'Nothing logged', c.textSecondary),
      final l => switch (_daysSince(l.workout.dayKey)) {
        0 => (Icons.check_circle_rounded, 'Trained today', c.positive),
        1 => (Icons.bedtime_outlined, 'Rested 1 day', c.textSecondary),
        final n => (
          Icons.bedtime_outlined,
          'Rested $n days',
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
  static int _daysSince(int dayKey) =>
      daysBetweenKeys(dayKey, dayKeyOf(DateTime.now()));
}

/// First launch. The app ships with no programme at all, so this is the one
/// screen a brand-new install has — it has to offer the way forward, not just
/// point at another tab.
class _NoRegimeState extends ConsumerWidget {
  const _NoRegimeState({
    required this.last,
    required this.heatmap,
    required this.hasHistory,
    required this.volume,
  });

  final ({Workout workout, String? sessionName})? last;
  final HeatmapData heatmap;
  final bool hasHistory;
  final WeeklyVolume volume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same shape the populated screen has — masthead, a band carrying the
    // one action, then the record underneath — rather than a centred card on a
    // blank page. What the screen is *made of* is visible before there is
    // anything in it, so the first regime lands in a page you have already
    // seen rather than replacing one.
    return Column(
      children: [
        _WorkoutsHeader(last: last),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.huge),
            children: [
              _SurfaceBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader('Your split'),
                    Text(
                      'Any number of sessions, in any order. One pass through '
                      'all of them is a cycle.',
                      style: context.t.bodyMedium,
                    ),
                    const SizedBox(height: Space.lg),
                    PrimaryButton(
                      label: 'Create a regime',
                      onPressed: () => createRegimeFlow(context, ref),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.section,
                  Space.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nothing logged and signed out: the history may be on an
                    // account this phone has not reached yet, and saying so is
                    // the difference between waiting and reinstalling in a
                    // panic (SYNC.md § 2).
                    AccountRecoveryNote(hasHistory: hasHistory),
                    _ConsistencyCard(data: heatmap, hasHistory: hasHistory),
                    const SizedBox(height: Space.section),
                    _VolumeCard(volume: volume),
                    if (last != null) ...[
                      const SizedBox(height: Space.section),
                      _LastSessionCard(last: last!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A regime exists but has no training days in it, which happens after
/// "start from scratch". Starting a workout is impossible until this is fixed,
/// so the fix is the only thing offered.
class _NoSessionsState extends ConsumerWidget {
  const _NoSessionsState({
    required this.regime,
    required this.last,
    required this.heatmap,
    required this.hasHistory,
    required this.volume,
  });

  final Regime regime;
  final ({Workout workout, String? sessionName})? last;
  final HeatmapData heatmap;
  final bool hasHistory;
  final WeeklyVolume volume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **The same page it will be once the regime has days in it**, which is the
    // rule the sibling state above follows too. Consistency, This week and Last
    // session are not about the regime — a heatmap and a week's volume are read
    // off logged work, and a regime with no sessions yet says nothing about
    // whether there is any. Dropping them for a lone centred card would make
    // adding the first session look like it built three cards, when all it does
    // is fill one.
    //
    // Titled `Your split` rather than `Today's session` to match
    // [_NoRegimeState]: both are the same sentence at different depths — there
    // is no split yet, and there is a split with no days in it — and the action
    // in each builds the split rather than starting a workout.
    return Column(
      children: [
        // No backfill action: there is nothing to log a past session against.
        _WorkoutsHeader(last: last),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.huge),
            children: [
              _SurfaceBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader('Your split'),
                    Text(
                      'No sessions in ${regime.name} yet. Add the training '
                      'days that make up one cycle, then fill each one with '
                      'exercises in the Regimes tab.',
                      style: context.t.bodyMedium,
                    ),
                    const SizedBox(height: Space.lg),
                    PrimaryButton(
                      label: 'Add a session',
                      onPressed: () => addSessionPrompt(context, ref, regime.id),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.section,
                  Space.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AccountRecoveryNote(hasHistory: hasHistory),
                    _ConsistencyCard(data: heatmap, hasHistory: hasHistory),
                    const SizedBox(height: Space.section),
                    _VolumeCard(volume: volume),
                    if (last != null) ...[
                      const SizedBox(height: Space.section),
                      _LastSessionCard(last: last!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when a session was started and not finished. Losing an in-progress
/// log to a locked phone screen would be unforgivable, so resuming is the
/// loudest thing on the screen.
///
/// [Ticking] wraps the clock alone, so it keeps counting without the card
/// around it repainting every second. Reading `DateTime.now()` once during
/// `build` would leave a session started an hour ago still saying "0m".
class _ResumeHero extends ConsumerWidget {
  const _ResumeHero({
    required this.workout,
    required this.owner,
    required this.doneSets,
    required this.totalSets,
    required this.preview,
    required this.activeRegimeId,
    required this.activeRegimeName,
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

  /// Every set in the log, ticked or not. Zero for a session whose exercises
  /// carry no set rows yet, which is why the count is only drawn when it is
  /// positive — "0 of 0 sets" says nothing.
  final int totalSets;

  /// The running workout's own exercises, in order — off the log, not the
  /// template it was copied from.
  final List<String> preview;

  final String activeRegimeId;
  final String activeRegimeName;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final owner = this.owner;
    final name =
        owner?.sessionName ??
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
    // The snapshot's counts are frozen at Start — see [openWorkoutSetsProvider].
    // They stand in only until the live query lands.
    final live = ref.watch(openWorkoutSetsProvider(workout.id)).valueOrNull;
    final done = live?.done ?? doneSets;
    final total = live?.total ?? totalSets;
    final started = DateTime.fromMillisecondsSinceEpoch(
      workout.startedAt,
      isUtc: true,
    ).toLocal();
    // Past a day this stops being a session in progress and becomes a decision:
    // a stopwatch reading 51 hours is not a useful thing to put on a screen.
    final stale = DateTime.now().difference(started).inHours >= 24;
    // A session is the heatmap's blue, whatever programme it belongs to, and a
    // deload is orange. Taking the regime's identity hue instead would make the
    // one distinction worth seeing here — light week or not — invisible on an
    // orange regime and competing with the mark on every other one. Which
    // programme a workout came from is on the row in words; whether it was a
    // deload is only ever said by this tile.
    final mark = workout.isDeload ? c.deload : c.heatOn;

    // No accent fill: what makes this loud is the pulse, the label and a
    // stopwatch at display size, not a tinted rectangle. The `surface` under it
    // is the card the caller wraps it in.
    //
    // Same skeleton as [_NextUpHero], deliberately: identity row, a status
    // line, the session name at display size, the exercise preview, then the
    // one action. Only the middle band differs — the cycle track answers
    // "which session next", which is not a question a session in progress has.
    // Everything else — the regime's identity mark, the exercise list, the
    // section's own type scale — is as true here as it is there, and keeping it
    // is what stops starting a session from redrawing the screen out from under
    // you.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconTile(
              workout.isDeload
                  ? Icons.trending_down_rounded
                  : Icons.bolt_rounded,
              color: mark,
              size: 40,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                owner?.regimeName ?? activeRegimeName,
                style: context.t.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (workout.isDeload)
              Pill('Deload', color: c.deload, icon: Icons.trending_down),
          ],
        ),
        const SizedBox(height: Space.md),
        // The band that stands where the cycle track does: what state this is
        // in on the left, how far through it you are on the right.
        Row(
          children: [
            if (stale)
              Icon(Icons.pause_circle_outline_rounded, size: 14, color: mark)
            else
              _LivePulse(color: mark),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                stale ? 'Unfinished' : 'In progress',
                style: context.t.labelSmall?.copyWith(color: mark),
              ),
            ),
            if (total > 0)
              Text('$done of $total sets', style: context.t.labelSmall),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text(
          name,
          style: context.t.displayMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(
            preview.take(3).join('  ·  ') +
                (preview.length > 3 ? '  ·  +${preview.length - 3} more' : ''),
            style: context.t.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: Space.md),
        // A date does not belong in the value slot the stopwatch uses:
        // "open since Tue 28 Jul" set at display size overflowed the card on
        // every phone. Stale sessions say it once, quietly.
        if (stale)
          Text(
            'Started ${DateFormat('EEE d MMM').format(started)}',
            style: context.t.bodyMedium,
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // The only thing on this card that changes on its own.
              Ticking(
                builder: (context) =>
                    Text(_elapsed(started), style: context.t.displaySmall),
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
            'Finishing it counts towards $foreignRegime, not towards '
            '$activeRegimeName.',
            style: context.t.bodyMedium,
          ),
        ],
        const SizedBox(height: Space.lg),
        PrimaryButton(
          label: 'Resume session',
          icon: Icons.play_arrow_rounded,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LogScreen(workoutId: workout.id)),
          ),
        ),
        // Two ways out, offered only once the session has gone stale. A
        // running session needs neither: they are one tap deep in the log
        // screen, and putting them on Workouts would make quitting as prominent
        // as training.
        if (stale) ...[
          const SizedBox(height: Space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              LinkAction(
                'Finish it',
                onTap: () => _finishStale(context, name, started, done),
              ),
              LinkAction(
                'Discard',
                onTap: () => _discardStale(context, name, done),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Saves it to the day it was started on, not to today. The workout's
  /// `dayKey` was stamped at Start and never moves, so the history it writes is
  /// the day it was actually trained.
  Future<void> _finishStale(
    BuildContext context,
    String name,
    DateTime started,
    int doneSets,
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
    final repo = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(trainingRepositoryProvider);
    try {
      // False when it is already gone — finished or discarded from the log
      // itself while this card was still on screen.
      if (!await repo.completeWorkout(workout.id)) {
        showToastOn(messenger, 'That session is no longer there');
      }
    } catch (e, st) {
      reportFailure(e, st, what: 'That session could not be finished.');
    }
  }

  Future<void> _discardStale(
    BuildContext context,
    String name,
    int doneSets,
  ) async {
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

    final repo = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(trainingRepositoryProvider);
    try {
      await repo.abandonWorkout(workout.id);
    } catch (e, st) {
      reportFailure(e, st, what: 'That session could not be discarded.');
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
    // One colour on this card, and it is the blue a trained day gets on the
    // heatmap — not an accent, and not the regime's identity hue. A deload
    // overrides it: the light week is the fact this tile exists to state.
    final mark = status.isDeload ? c.deload : c.heatOn;

    // The caller wraps this in an `AppCard`: out of the header band, `surface`
    // has to be drawn rather than inherited.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Three bands, each with one job: who this is, where the cycle
        // stands, what to do. Four elements in four type roles — tile, regime
        // name in `body`, the cycle fraction in `titleSmall`, and a loose grey
        // deload label floating at the right — read as assembled rather than
        // composed.
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
              child: Text(
                regimeName,
                style: context.t.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Only the two loud cases keep a pill up here. "In five cycles"
            // is not news; it belongs on the meta line under the track.
            if (status.isDeload)
              Pill('Deload', color: c.deload, icon: Icons.trending_down)
            else if (status.deloadAfterThisCycle)
              Pill('Deload next', color: c.deload, icon: Icons.trending_down),
          ],
        ),
        const SizedBox(height: Space.md),
        // The cycle's shape in one line. Dense enough to read without
        // counting, quiet enough not to become a second chart.
        _CycleTrack(status: status, mark: mark),
        const SizedBox(height: Space.sm),
        // Everything the cycle needs in words, on one quiet line under the
        // thing it describes. `1 of 6 done` is gone: six segments above say
        // it faster than the words can, and rule 6 keeps the graphic when it
        // does.
        Text(
          _cycleNote(status),
          style: context.t.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
          // meant" — and a second line would wrap into the last 18px above the
          // bottom of a 844pt phone.
          Text(
            preview.take(3).join('  ·  ') +
                (preview.length > 3 ? '  ·  +${preview.length - 3} more' : ''),
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
            // The picker, not a trip to the Regime tab: the session is one
            // exercise away from being startable, and sending someone to
            // another tab to fix it is three taps and a way back.
            onPressed: () async {
              final exercise = await pickExercise(context, ref);
              if (exercise == null) return;
              await ref
                  .read(regimeRepositoryProvider)
                  .addExerciseToSession(nextId, exercise.id);
            },
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
        // an always-on session list would cost, without a six-row block
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
    );
  }

  /// The cycle in words, under the track that draws it.
  ///
  /// Where the deload is, stated once: a light week that arrives unannounced
  /// looks like a bug in the app, and one two cycles out is worth planning
  /// around. With the unit, always — a bare "deload in 5" invites the two
  /// readings this app can least afford to be vague about, days and weeks, and
  /// a cycle is neither: it advances when the work is done.
  ///
  /// Silent about a deload that is already on a pill in the row above, and
  /// silent when deloads are off for this regime (`cyclesUntilDeload` is -1
  /// then, and there is nothing to promise).
  static String _cycleNote(CycleStatus status) {
    final cycle = 'Cycle ${status.cycleIndex}';
    if (status.isDeload || status.deloadAfterThisCycle) return cycle;
    final remaining = status.cyclesUntilDeload;
    if (remaining <= 0) return cycle;
    return '$cycle  ·  Deload in $remaining '
        'cycle${remaining == 1 ? '' : 's'}';
  }
}

/// Progress through the cycle as one hairline track, segment per session.
///
/// Unlabelled and 5pt tall — it says "two of five" faster than the words next
/// to it can. Labelled bars would repeat the session list underneath it, name
/// for name.
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
          actionLabel: hasHistory ? 'All time' : null,
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HistoryHeatmapScreen()),
          ),
        ),
        // The volume tile (THEME → Components → Stat tile): caption, chart,
        // hairline, figure + unit + chevron. Same padding, same gaps, same
        // styles — see [VolumeTile], which is the widget this is deliberately
        // shaped after.
        //
        // Without that tile's title row: a volume tile carries its own because
        // six of them sit in a header-less grid, and here the section heading
        // above the card already names it. Two headings, one card.
        //
        // A grid over a three-fact sentence would be a shape no other card in
        // the app has.
        AppCard(
          padding: const EdgeInsets.all(Space.lg),
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
              // The caption slot, where a volume tile names the span its bars
              // cover — and this one names the span its cells cover, in days,
              // because the grid draws whole weeks either side of today.
              Text(
                'Last ${heatmapWeeks * 7} days',
                style: context.t.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Space.lg),
              ConsistencyHeatmap(days: data.days),
              const SizedBox(height: Space.lg),
              const Divider(),
              const SizedBox(height: Space.md),
              // No legend here. It is reference material rather than something
              // you read at a glance, and the screen this card opens carries it
              // in full.
              Row(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            _thisWeek(data.consistency),
                            style: context.t.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Space.xs),
                        Flexible(
                          child: Text(
                            'this week',
                            style: context.t.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Text('·', style: context.t.bodyMedium),
                        const SizedBox(width: Space.sm),
                        // Both figures are `valueSm` and both units are `body`:
                        // a number is a number, and the row is one column of
                        // them read left to right.
                        Flexible(
                          child: Text(
                            _average(data.consistency),
                            style: context.t.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Space.xs),
                        Flexible(
                          child: Text(
                            'avg/wk',
                            style: context.t.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasHistory)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: context.c.textSecondary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The figure the card is about, under the hairline, with `this week` beside
  /// it where a volume tile prints `sets/wk`.
  ///
  /// Out of seven, because that is what the row of cells above it shows — a
  /// bare `4` under a week of squares invites you to count them to find out
  /// what it is four of. It counts **days trained**, not sessions: two sessions
  /// on a Tuesday are one cell, and a figure the grid contradicts is worse than
  /// no figure.
  ///
  /// A dash rather than `0` with nothing logged — a zero is a measurement and a
  /// dash is "nothing here yet" (THEME rule 4) — and the row keeps its shape
  /// either way, which is the stat tile's zero state.
  static String _thisWeek(Consistency c) =>
      c.isEmpty ? '—/7' : '${c.thisWeek}/7';

  /// Sessions per week over [Consistency.windowDays], beside the week's count.
  ///
  /// Whole sessions and rounded **down** — the app never reports a session it
  /// cannot point at — and an em dash under a fortnight of history, where the
  /// rate would be a number divided by weeks that have not happened yet (see
  /// [computeConsistency]). The dash keeps the row's shape rather than dropping
  /// the fact, so the card does not change width the day it becomes true.
  static String _average(Consistency c) {
    final perWeek = c.perWeek;
    return perWeek == null ? '—' : '${perWeek.floor()}';
  }
}

/// This week's sets per muscle (THEME → Components → Bar list).
///
/// A section on the page you already open rather than a screen you navigate to
/// — a volume dashboard came off the non-goals list on exactly that condition,
/// and a hero pager carrying it fails the test that a landing screen you have
/// to swipe to use is a landing screen that failed.
///
/// **Handed its numbers rather than watching for them.** A provider starts when
/// something first watches it, so reading [weeklyVolumeProvider] here would
/// start it only once the card is being built — after the snapshot it should
/// have been racing, which is what makes a section arrive late. The screen
/// starts both reads in the same frame and does not draw until it has both, so
/// there is nothing here to be absent.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.volume});

  final WeeklyVolume volume;

  @override
  Widget build(BuildContext context) {
    void openHistory() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VolumeHistoryScreen()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `Weekly volume`, not `This week`: the window is a rolling seven days
        // ([volumeWindowDays]), and the heading sat directly under a
        // Consistency section whose `this week` is calendar-bound — two
        // different weeks on one screen, both called this one.
        SectionHeader(
          'Weekly volume',
          // Nothing to open on a fresh install, and a link to an empty screen
          // is a control that does nothing.
          actionLabel: volume.isEmpty ? null : 'All time',
          onAction: openHistory,
        ),
        AppCard(
          padding: const EdgeInsets.all(Space.md),
          onTap: volume.isEmpty ? null : openHistory,
          // Just the bars. A sentence under them would restate what every row
          // already prints — a total, a count of trained regions, and the
          // window named in the heading — and no other card in the app explains
          // its own chart in prose.
          child: VolumeBars(volume: volume),
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
