part of '../home_screen.dart';

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
///
/// A null [sessionId] starts a custom session, which opens empty and carries
/// [isDeload] as its own flag.
Future<void> _startSession(
  BuildContext context,
  WidgetRef ref, {
  required String regimeId,
  required String? sessionId,
  bool isDeload = false,
}) async {
  if (ref.read(_startingProvider)) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context);

  container.read(_startingProvider.notifier).state = true;
  try {
    final repo = container.read(trainingRepositoryProvider);
    final id = sessionId == null
        ? await repo.startCustomWorkout(regimeId: regimeId, isDeload: isDeload)
        : await repo.startWorkout(regimeId: regimeId, sessionId: sessionId);
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
    this.notDue = false,
  });

  final Session session;
  final VoidCallback onTap;
  final bool done;
  final bool isNext;

  /// Whether the day alternates with another and this cycle is not its turn.
  /// It can still be started, and the row says what starting it means.
  final bool notDue;

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
              else if (notDue)
                Text('Not due this cycle', style: context.t.labelSmall)
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

/// What either session sheet came back with when the custom row was tapped.
class _CustomPick {
  const _CustomPick({required this.isDeload});

  final bool isDeload;
}

/// The custom-session choice at the foot of either session sheet.
///
/// The same inset panel as a day, so it reads as one more choice of the same
/// kind, with its deload switch under a hairline inside it. The switch lives in
/// the panel rather than in a question asked after the tap, which keeps
/// starting a custom session one tap, and it opens on [initialDeload]: the open
/// cycle's state when starting now, the covering cycle's when backfilling.
///
/// Under its own label, `Outside the programme`, so the days stay the list
/// and this reads as the exception.
class _CustomSessionPick extends StatefulWidget {
  const _CustomSessionPick({
    required this.subtitle,
    required this.initialDeload,
    required this.onStart,
  });

  final String subtitle;
  final bool initialDeload;
  final ValueChanged<bool> onStart;

  @override
  State<_CustomSessionPick> createState() => _CustomSessionPickState();
}

class _CustomSessionPickState extends State<_CustomSessionPick> {
  late bool _deload = widget.initialDeload;

  @override
  void didUpdateWidget(_CustomSessionPick old) {
    super.didUpdateWidget(old);
    // The backfill sheet's date can change under the panel, and with it the
    // cycle the session would have been in.
    if (old.initialDeload != widget.initialDeload) {
      _deload = widget.initialDeload;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
          child: Text('Outside the programme', style: context.t.bodySmall),
        ),
        InsetPanel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Pressable(
                onTap: () => widget.onStart(_deload),
                scale: 0.98,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customSessionName,
                              style: context.t.titleMedium,
                            ),
                            const SizedBox(height: Space.xxs),
                            Text(widget.subtitle, style: context.t.bodyMedium),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: c.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.surfaceHighest),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.md,
                  Space.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deload session', style: context.t.bodyLarge),
                          Text(
                            'A light day, marked orange',
                            style: context.t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _deload,
                      onChanged: (on) => setState(() => _deload = on),
                    ),
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

/// Starts a session other than the queue head, or a custom session.
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
  // The days that alternate with another and are waiting their turn.
  final notDue = {
    for (final p in status.positions)
      for (final id in p.sessionIds)
        if (id != p.dueSessionId) id,
  };
  final picked = await showAppSheet<Object>(
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
            notDue: notDue.contains(s.id),
            onTap: () => Navigator.of(sheet).pop(s),
          ),
        _CustomSessionPick(
          subtitle: 'Starts empty. Add exercises as you train.',
          initialDeload: status.isDeload,
          onStart: (deload) =>
              Navigator.of(sheet).pop(_CustomPick(isDeload: deload)),
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;

  if (picked is _CustomPick) {
    await _startSession(
      context,
      ref,
      regimeId: regimeId,
      sessionId: null,
      isDeload: picked.isDeload,
    );
    return;
  }
  final chosen = picked as Session;

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
    builder: (sheet) => _BackfillSheet(regimeId: regimeId, sessions: sessions),
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
    final sessionId = picked.sessionId;
    final id = sessionId == null
        // A custom session belongs to no cycle whatever its date, so the
        // toast below says so rather than naming the covering cycle.
        ? await repo.startCustomWorkout(
            regimeId: regimeId,
            isDeload: picked.isDeload,
            at: date,
          )
        : await repo.startWorkout(
            regimeId: regimeId,
            sessionId: sessionId,
            at: date,
          );
    showToastOn(
      messenger,
      sessionId == null
          ? 'Counts towards no cycle'
          : cycle == null
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
///
/// A log with a null [sessionId] is a custom session, carrying its own
/// [isDeload].
class _BackfillResult {
  const _BackfillResult.log({
    required this.sessionId,
    required this.date,
    this.isDeload = false,
  }) : workoutId = null;
  const _BackfillResult.open(this.workoutId)
    : sessionId = null,
      date = null,
      isDeload = false;

  final String? sessionId;
  final DateTime? date;
  final bool isDeload;
  final String? workoutId;
}

class _BackfillSheet extends ConsumerStatefulWidget {
  const _BackfillSheet({required this.regimeId, required this.sessions});

  final String regimeId;
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

  /// Whether the cycle covering [_date] was a deload, which is what the custom
  /// session's switch opens on. False before the regime existed.
  bool _coveringDeload = false;

  @override
  void initState() {
    super.initState();
    _readCoveringDeload();
  }

  /// Read on open and on every change of day. The repository is looked up
  /// while this state is mounted, and the answer is dropped if it no longer is.
  Future<void> _readCoveringDeload() async {
    final repo = ref.read(trainingRepositoryProvider);
    final day = _date;
    final cycle = await repo.cycleCovering(widget.regimeId, day);
    if (!mounted || day != _date) return;
    setState(() => _coveringDeload = cycle?.isDeload ?? false);
  }

  void _setDate(DateTime day) {
    setState(() => _date = day);
    _readCoveringDeload();
  }

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
          entry.key: entry.value.isDeload ? c.deload : c.progress,
      },
    );
    if (picked == null || !mounted) return;

    final already = logged[dayKeyOf(picked)];
    if (already?.workoutId == null) {
      _setDate(picked);
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
      _setDate(picked);
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
        _CustomSessionPick(
          subtitle: 'Not a day of your programme',
          initialDeload: _coveringDeload,
          onStart: (deload) => Navigator.of(context).pop(
            _BackfillResult.log(sessionId: null, date: _date, isDeload: deload),
          ),
        ),
      ],
    );
  }
}
