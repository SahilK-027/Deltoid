import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/sync_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/sync/sync_state.dart';

/// The header's backup button: whether training is on the account, and how
/// much of it is still only on this phone.
///
/// The same `CircleIconButton` as the calendar beside it on Workouts, so the
/// header holds two buttons of one kind rather than a button and a stray glyph.
/// Drawn whenever an account is signed in, because *is my training backed up*
/// is asked at the gym and should be answered at a glance. Absent without an
/// account: there is nothing to back up to, and Settings offers the sign-in.
///
/// **Green when backed up, yellow when not.** Green is `positive`, which
/// already means done. Yellow is `warning`, a stated consequence, which is what
/// being offline is: nothing is lost, but the account is behind. Not orange —
/// orange means a deload and nothing else, and this button sits above the
/// heatmap — and never red, because red is where a person reads that something
/// has been lost.
///
/// The number is what the sheet lists, added up: sets for each session, and
/// entries for bodyweight and the programme. It appears only while the button
/// is yellow. Online, a set is owed for the few seconds the push waits, and a
/// count that blinked with every set would be noise.
///
/// On Settings as on the other three tabs. The account row there names the
/// account and says nothing about its state, so the state is still said once
/// on that screen.
class BackupMark extends ConsumerWidget {
  const BackupMark({super.key, this.size = 40});

  /// 40 in a masthead, beside the calendar; the log's bar takes the same.
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indicator = ref.watch(backupIndicatorProvider);
    if (indicator == null) return const SizedBox.shrink();
    final c = context.c;
    final backedUp = indicator.look == BackupLook.backedUp;

    final button = CircleIconButton(
      icon: backedUp ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
      tooltip: switch (indicator.look) {
        BackupLook.backedUp => 'Backed up',
        BackupLook.offline => 'Offline',
        BackupLook.refused => 'Not backed up',
      },
      tint: backedUp ? c.positive : c.warning,
      size: size,
      onTap: () => showAppSheet<void>(
        context,
        builder: (_) => const _BackupSheet(),
      ),
    );
    if (indicator.waiting == 0) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -4,
          right: -6,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: c.warning,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                indicator.waiting > 999 ? '999+' : '${indicator.waiting}',
                textAlign: TextAlign.center,
                style: context.t.labelSmall?.copyWith(
                  color: IconTile.glyphOn(c.warning),
                  fontFeatures: tabular,
                  height: 18 / 11,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Where the training is: what is only on this phone, and what the account
/// last received in full.
///
/// The first sentence is always the same, because it is the one the button
/// exists to say mid-session: everything is saved on this phone. The lines
/// under it are sessions by name and day, the way History names them, rather
/// than the tables a session is stored in.
class _BackupSheet extends ConsumerWidget {
  const _BackupSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final indicator = ref.watch(backupIndicatorProvider);
    final state = ref.watch(syncStateProvider).valueOrNull;
    final summary =
        ref.watch(owedSummaryProvider).valueOrNull ?? OwedSummary.empty;
    final look = indicator?.look ?? BackupLook.backedUp;
    final owed = summary.waiting.isNotEmpty;

    final (title, detail) = switch (look) {
      BackupLook.offline => (
        'Offline',
        'Everything is saved on this phone. It is backed up to your account '
            'when the phone is online again.',
      ),
      BackupLook.refused => (
        'Not backed up',
        'Everything is saved on this phone. Your account refused the last '
            'attempt, and the app keeps trying.',
      ),
      BackupLook.backedUp when owed => (
        'Backing up',
        'Everything is saved on this phone, and the newest changes are being '
            'sent to your account now.',
      ),
      // The title names the state and nothing else. With the time in it, the
      // title read as a second clock beside the file backup's on Settings,
      // and nothing said which of the two it was.
      BackupLook.backedUp => (
        'Backed up',
        'Everything is saved on this phone and on your account.',
      ),
    };
    // One more sentence, after the one that is always there: how much is
    // waiting and since when, or when the account last received anything.
    final further = look == BackupLook.backedUp && !owed
        ? lastBackedUpLine(state)
        : backupWaitingLine(state);
    final hue = look == BackupLook.backedUp ? c.positive : c.warning;

    return AppSheet(
      title: title,
      // No subtitle. A sheet's subtitle is one line that names the thing, and
      // this is a sentence: there it was cut to "Everything is saved on this
      // phone. It is…", which drops the half that says when (THEME → Sheets).
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      footer: look != BackupLook.backedUp && owed
          ? SecondaryButton(
              label: 'Try again now',
              icon: Icons.refresh_rounded,
              onPressed: () {
                ref.read(syncEngineProvider)?.resumed();
                Navigator.of(context).pop();
              },
            )
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            0,
          ),
          child: Text(
            further == null ? detail : '$detail $further',
            style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ),
        if (owed) ...[
          const _Heading('On this phone only'),
          for (final item in summary.waiting)
            AppRow(
              icon: switch (item.kind) {
                WaitingKind.session => Icons.fitness_center_rounded,
                WaitingKind.removed => Icons.delete_outline_rounded,
                WaitingKind.bodyweight => Icons.monitor_weight_outlined,
                WaitingKind.programme => Icons.view_list_rounded,
              },
              title: _title(item),
              subtitle: _subtitle(item),
              trailing: Icon(Icons.cloud_off_outlined, size: 18, color: hue),
              ink: false,
            ),
        ],
        if (summary.last case final last?) ...[
          // Not `Last backed up`. The paragraph above ends with the time the
          // account last received anything, in those words, and this is a
          // different fact: the newest finished session the account holds.
          // Under one phrase, `14:28` today sat over `yesterday`.
          const _Heading('Newest session on your account'),
          AppRow(
            icon: Icons.fitness_center_rounded,
            title: _sessionTitle(last.sessionName, last.dayKey),
            subtitle: 'On your account',
            trailing: Icon(
              Icons.cloud_done_outlined,
              size: 18,
              color: c.positive,
            ),
            ink: false,
          ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.lg,
      Space.gutter,
      Space.xs,
    ),
    // Sentence case: uppercase belongs to the page title and its eyebrow
    // and nowhere else (THEME → Type).
    child: Text(
      text,
      style: context.t.titleSmall?.copyWith(color: context.c.textSecondary),
    ),
  );
}

String _title(WaitingItem item) => switch (item.kind) {
  WaitingKind.session => _sessionTitle(item.sessionName, item.dayKey!),
  WaitingKind.removed => 'Discarded and deleted sessions',
  WaitingKind.bodyweight => 'Bodyweight',
  WaitingKind.programme => 'Programme and exercises',
};

String _subtitle(WaitingItem item) {
  final n = item.count;
  return switch (item.kind) {
    WaitingKind.session => [
      n == 1 ? '1 set' : '$n sets',
      if (item.inProgress) 'in progress',
    ].join(', '),
    WaitingKind.removed => n == 1 ? '1 session' : '$n sessions',
    WaitingKind.bodyweight => n == 1 ? '1 entry' : '$n entries',
    WaitingKind.programme => n == 1 ? '1 change' : '$n changes',
  };
}

/// `Push 1 · today`, `Pull 2 · Tue 22 Sep`.
String _sessionTitle(String? name, int dayKey) {
  final day = dateFromDayKey(dayKey);
  final today = dayKeyOf(DateTime.now());
  final when = dayKey == today
      ? 'today'
      : dayKey == dayKeyOf(DateTime.now().subtract(const Duration(days: 1)))
      ? 'yesterday'
      : DateFormat('EEE d MMM').format(day);
  return '${name ?? 'Workout'} · $when';
}

/// How much is waiting to reach the account, and since when:
/// `3 changes waiting since 09:14.`
///
/// [SYNC.md § 2](SYNC.md#2-the-three-states) asks for how long as well as how
/// many, and how long is the one that carries the meaning. Pending is normal,
/// since a session logged in a basement gym is pending for an hour, so the
/// count alone says nothing: since this morning is a gym with no signal, and
/// since Tuesday is something to look at.
///
/// Null when nothing is waiting, and null while the state has not resolved. A
/// loading value read as nothing owed would say `Backed up` over a phone that
/// is holding a session ([SYNC.md § 19](SYNC.md#19-traps)).
String? backupWaitingLine(SyncState? state) {
  if (state == null || state.status != SyncStatus.pending) return null;
  final count =
      state.owed == 1 ? '1 change waiting' : '${state.owed} changes waiting';
  return switch (state.owedSince) {
    final since? => '$count since ${_since(since)}.',
    _ => '$count.',
  };
}

/// When the account last received anything: `Last backed up at 14:02.` on the
/// day it happened, `Last backed up on 12 Aug at 14:02.` after it.
///
/// Null when nothing has ever been sent: signed in on a fresh install is not
/// backed up, and has no time to give.
String? lastBackedUpLine(SyncState? state) {
  final at = state?.lastPushAt?.toLocal();
  if (at == null) return null;
  final time = DateFormat('HH:mm').format(at);
  return dayKeyOf(at) == dayKeyOf(DateTime.now())
      ? 'Last backed up at $time.'
      : 'Last backed up on ${DateFormat('d MMM').format(at)} at $time.';
}

/// A time if it is today, a date if it is not.
///
/// `09:14` on the day it happened and `12 Aug` after that: the hour matters
/// while it is still this session, and stops meaning anything once the answer
/// is days.
String _since(DateTime at) {
  final local = at.toLocal();
  final sameDay = dayKeyOf(local) == dayKeyOf(DateTime.now());
  return DateFormat(sameDay ? 'HH:mm' : 'd MMM').format(local);
}
