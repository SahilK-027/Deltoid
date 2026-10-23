part of '../home_screen.dart';

/// The masthead, shared by every state this screen can be in.
///
/// The empty states carry it too. Centring a lone card on a blank page instead
/// reads as a different screen than the one the tab bar says you are on, and on
/// a fresh install leaves no way to reach More, which is where restoring a
/// backup lives. More is always here for that reason, and nothing in the band
/// needs sessions to exist.
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
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.last});

  final ({Workout workout, String? sessionName})? last;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return HeaderBand(
      child: PageHeader(
        // The screen names itself, like every other destination. The nav label
        // is 11sp at the bottom of the screen, so titling this with the date
        // instead would leave the one screen you land on the only one you have
        // to identify by inference. The date sits over the title.
        title: 'Home',
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
        // No cog: More is a destination on the nav bar, and a screen
        // reachable two ways is a screen you have to decide about twice.
        actions: const [BackupMark()],
      ),
    );
  }
}

/// The way into a session logged after the fact.
///
/// A row rather than the calendar glyph that once sat in the masthead: a row
/// says what it does, where a glyph in the band could say it only through a
/// tooltip, which needs a long press. It sits under the Workouts tile because
/// that is where the gap it fills is seen.
class _PastSessionsCard extends StatelessWidget {
  const _PastSessionsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Past sessions'),
        ListCard(
          children: [
            AppRow(
              icon: Icons.event_outlined,
              title: 'Log a past session',
              subtitle: 'For a day you trained without the app',
              chevron: true,
              onTap: onTap,
            ),
          ],
        ),
      ],
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
    //
    // Every rest length is the same grey. Four days and more used to turn
    // orange, but orange is a deload and nothing else, and the number of days
    // already says how long it has been without the app judging it.
    final (icon, text, tint) = switch (last) {
      null => (Icons.flag_outlined, 'Nothing logged', c.textSecondary),
      final l => switch (_daysSince(l.workout.dayKey)) {
        0 => (Icons.check_circle_rounded, 'Trained today', c.positive),
        1 => (Icons.bedtime_outlined, 'Rested 1 day', c.textSecondary),
        final n => (Icons.bedtime_outlined, 'Rested $n days', c.textSecondary),
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
    required this.weighIns,
    required this.phase,
    required this.hasHistory,
  });

  final ({Workout workout, String? sessionName})? last;
  final HeatmapData heatmap;
  final Set<int> weighIns;
  final PhaseCardData phase;
  final bool hasHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same shape the populated screen has — masthead, a band carrying the
    // one action, then the record underneath — rather than a centred card on a
    // blank page. What the screen is *made of* is visible before there is
    // anything in it, so the first regime lands in a page you have already
    // seen rather than replacing one.
    return Column(
      children: [
        _HomeHeader(last: last),
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
                    // No play button: there is no session to start.
                    _HabitsSection(heatmap: heatmap, weighIns: weighIns),
                    // Not about the regime either: a phase is what the person
                    // is eating for, with or without a split to train.
                    const SizedBox(height: Space.section),
                    PhaseSection(data: phase),
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
    required this.weighIns,
    required this.phase,
    required this.hasHistory,
  });

  final Regime regime;
  final ({Workout workout, String? sessionName})? last;
  final HeatmapData heatmap;
  final Set<int> weighIns;
  final PhaseCardData phase;
  final bool hasHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **The same page it will be once the regime has days in it**, which is the
    // rule the sibling state above follows too. Habits is not about the
    // regime — the habit grids are read off logged work, and a regime with no
    // sessions yet says nothing about whether there is any. Dropping them for a
    // lone centred card would make adding the first session look like it built
    // a section, when all it does is fill one.
    //
    // Titled `Your split` rather than `Today's session` to match
    // [_NoRegimeState]: both are the same sentence at different depths — there
    // is no split yet, and there is a split with no days in it — and the action
    // in each builds the split rather than starting a workout.
    return Column(
      children: [
        // No Past sessions card: there is nothing to log a past session
        // against.
        _HomeHeader(last: last),
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
                    // Training today does not wait for the split to be built:
                    // a custom session needs a regime and nothing else.
                    const SizedBox(height: Space.sm),
                    Center(
                      child: LinkAction(
                        'Start a custom session',
                        onTap: ref.watch(_startingProvider)
                            ? null
                            : () => _startSession(
                                context,
                                ref,
                                regimeId: regime.id,
                                sessionId: null,
                              ),
                      ),
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
                    // No play button: there is no session to start.
                    _HabitsSection(heatmap: heatmap, weighIns: weighIns),
                    // Not about the regime either: a phase is what the person
                    // is eating for, with or without a split to train.
                    const SizedBox(height: Space.section),
                    PhaseSection(data: phase),
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
    final dayName =
        owner?.sessionName ??
        sessions
            .where((s) => s.id == workout.sessionId)
            .map((s) => s.name)
            .firstOrNull;
    final isCustom = workout.sessionId == null;
    final name = dayName ?? (isCustom ? customSessionName : 'Workout');
    // What the finish and discard dialogs call it, mid-sentence.
    final inSentence = isCustom ? sessionInSentence(null) : name;
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
    final mark = workout.isDeload ? c.deload : c.progress;

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
              Text(setsOfTotal(done, total), style: context.t.labelSmall),
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
                onTap: () => _finishStale(context, inSentence, started, done),
              ),
              LinkAction(
                'Discard',
                onTap: () => _discardStale(context, inSentence, done),
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
    final mark = status.isDeload ? c.deload : c.progress;

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
        // claiming to be a plan for the day. Shown for a regime of one day
        // too, since the sheet always offers a custom session beside it.
        if (sessions.isNotEmpty) ...[
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

/// The two habit tiles, Weigh-ins on the left and Workouts on the right
/// (THEME → Components → Habit tile). The Workouts tile takes the place the
/// Consistency card had, and opens the same Consistency screen.
class _HabitsSection extends ConsumerWidget {
  const _HabitsSection({
    required this.heatmap,
    required this.weighIns,
    this.play,
  });

  final HeatmapData heatmap;

  /// Every day with a weigh-in, as day keys.
  final Set<int> weighIns;

  /// The Workouts tile's button. Null on the states with no session to start.
  final Widget? play;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final consistency = heatmap.consistency;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Habits'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: HabitTile(
                title: 'Weigh-ins',
                fill: (key) => weighIns.contains(key) ? c.weighIn : null,
                thisWeek: weighIns.isEmpty
                    ? null
                    : daysKeptThisWeek(weighIns, today: DateTime.now()),
                action: HabitAction(
                  icon: Icons.add_rounded,
                  tooltip: 'Log weight',
                  onTap: () => logTodaysWeight(context, ref),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WeighInsScreen()),
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: HabitTile(
                title: 'Workouts',
                // The colours the Consistency calendar draws in: a trained
                // day in progress blue, a deload in orange.
                fill: (key) => switch (heatmap.days[key]) {
                  null => null,
                  final day => day.isDeload ? c.deload : c.progress,
                },
                // Counted as the Consistency card counted it, a dash included
                // while nothing has been trained in its window.
                thisWeek: consistency.isEmpty ? null : consistency.thisWeek,
                action: play,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HistoryHeatmapScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The Workouts tile's play button: the hero's own action, one tap from the
/// habit it keeps.
///
/// It starts the session that is due through the same path as `Start` on the
/// hero, so a second tap while the first is starting is refused in the same
/// way. While a session is open it resumes that one instead, which is what the
/// hero above it offers then: starting a second would leave two open, and only
/// one of them could ever be finished. It is absent when there is nothing to
/// start, which includes a due session with no exercises in it, where the hero
/// offers to add exercises rather than to start an empty log.
class _PlayAction extends ConsumerWidget {
  const _PlayAction({
    required this.regimeId,
    required this.open,
    required this.status,
    required this.sessions,
    required this.preview,
  });

  final String regimeId;
  final Workout? open;
  final CycleStatus? status;
  final List<Session> sessions;

  /// Exercise names by session, to tell an empty session from a startable one.
  final Map<String, List<String>> preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = this.open;
    if (open != null) {
      return HabitAction(
        icon: Icons.play_arrow_rounded,
        tooltip: 'Resume session',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LogScreen(workoutId: open.id)),
        ),
      );
    }

    final nextId = status?.nextSessionId;
    if (nextId == null || (preview[nextId] ?? const []).isEmpty) {
      return const SizedBox.shrink();
    }
    final name = sessions.where((s) => s.id == nextId).firstOrNull?.name;
    return HabitAction(
      icon: Icons.play_arrow_rounded,
      tooltip: 'Start ${name ?? 'session'}',
      onTap: ref.watch(_startingProvider)
          ? null
          : () => _startSession(
              context,
              ref,
              regimeId: regimeId,
              sessionId: nextId,
            ),
    );
  }
}
