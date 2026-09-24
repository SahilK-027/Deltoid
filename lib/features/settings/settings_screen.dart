import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/progress_sheet.dart';
import '../../data/backup/backup_service.dart';
import '../../data/backup/downloads.dart';
import '../../data/sync/forget.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_state.dart';
import '../../domain/rest.dart';
import '../account/sign_in_flow.dart';
import 'bodyweight_screen.dart';
import '../../domain/units.dart';
import '../../core/widgets/toast.dart';
import '../../core/failure.dart';

// `lastBackupProvider` lives in `core/providers.dart`: one fires after every
// finished session, and the screen that reports it is not the screen that
// writes it.

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyweight =
        ref.watch(bodyweightSummaryProvider).valueOrNull ??
        (latest: null, count: 0);
    final lastBackup = ref.watch(lastBackupProvider).valueOrNull;
    final c = context.c;

    return Scaffold(
      body: Column(
        children: [
          // A tab, not a screen pushed from a cog, so it wears the masthead
          // every other destination wears — eyebrow included. A title alone on
          // the band would make this the only tab whose header is one line,
          // which reads as a screen from a different app.
          const HeaderBand(
            child: PageHeader(title: 'Settings', eyebrow: 'On this device'),
          ),
          Expanded(child: _body(context, ref, bodyweight, lastBackup, c)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    BodyweightSummary bodyweight,
    DateTime? lastBackup,
    DeltoidColors c,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.huge,
      ),
      children: [
        SectionHeader(
          'Bodyweight',
          actionLabel: bodyweight.latest == null ? null : 'History',
          onAction: bodyweight.latest == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BodyweightScreen()),
                ),
        ),
        // The figure logs one, it does not open a screen that offers to.
        // Behind a cog, then behind a card that pushes a screen with a `+` in
        // its bar, bodyweight is three taps to type a number you are asked for
        // daily — which is how it goes unlogged. Tapping the figure is the log;
        // the past is a link.
        _BodyweightCard(bodyweight: bodyweight),
        const SizedBox(height: Space.section),
        const SectionHeader('Account & backup'),
        ListCard(
          inset: Space.lg,
          children: [
            // The account is the first row of the same card, not a card above
            // it: backing up to Google and backing up to a file are one
            // question asked two ways. It renders nothing at all in a build
            // with no sync configured, and a card cannot hold a nothing —
            // ListCard would rule a divider under it — so the condition is
            // here rather than inside the row.
            if (ref.watch(syncAuthProvider) != null) const _AccountSection(),
            AppRow(
              icon: Icons.ios_share,
              title: 'Export a backup file',
              // One clause each. What the file is and where it can go is the
              // sheet's to say, and the sheet has the width to say it.
              subtitle: 'Every workout, in one file',
              onTap: () => _export(context, ref),
              chevron: true,
            ),
            AppRow(
              icon: Icons.settings_backup_restore,
              title: 'Restore from a file',
              subtitle: 'Replaces everything on this phone',
              onTap: () => _restore(context, ref),
              chevron: true,
            ),
            AppRow(
              icon: Icons.schedule,
              title: 'Automatic backup',
              // "After each finished session" alone does not say whether it
              // has ever happened — it reads as a description or as a promise
              // depending on what you came to the row for, and the one thing a
              // backup row exists to answer is whether there is a backup.
              subtitle: lastBackup == null
                  ? 'Has not run yet. It writes a file after each finished '
                        'session.'
                  : 'Last ran '
                        '${DateFormat('d MMM yyyy, HH:mm').format(lastBackup)}',
              subtitleMaxLines: 3,
            ),
          ],
        ),
        const SizedBox(height: Space.section),
        const SectionHeader('Training'),
        ListCard(
          inset: Space.lg,
          children: const [
            _RestRow(),
            _UnitRow(),
            _SessionNotificationRow(),
            _KeepScreenOnRow(),
          ],
        ),
        const SizedBox(height: Space.section),
        const SectionHeader('Appearance'),
        const _ThemePicker(),
        const SizedBox(height: Space.section),
        const SectionHeader('About app'),
        const _AboutCard(),
      ],
    );
  }

  /// Ask where it goes, then write it with the progress on screen.
  ///
  /// A chosen destination rather than the share sheet alone: sharing a backup
  /// to yourself is a strange thing to have to do, and every other app that
  /// makes a file puts it in Downloads.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;

    final destination = await showAppSheet<_ExportTo>(
      context,
      builder: (sheet) => AppSheet(
        title: 'Export backup',
        subtitle: 'Every workout, in one file',
        // Full-bleed rows, as every other action sheet in the app: a card in
        // here is a panel inside a panel, and the gutter double-insets rows
        // that already carry their own padding.
        contentPadding: const EdgeInsets.only(bottom: Space.md),
        children: [
          if (canSaveToDownloads)
            AppRow(
              icon: Icons.download_outlined,
              title: 'Save to Downloads',
              subtitle:
                  'Into $downloadsFolder, where a file manager can '
                  'find it',
              onTap: () => Navigator.of(sheet).pop(_ExportTo.downloads),
            ),
          AppRow(
            icon: Icons.ios_share,
            title: 'Share',
            subtitle: 'Hand it to Drive, iCloud or anything else',
            onTap: () => Navigator.of(sheet).pop(_ExportTo.share),
          ),
        ],
      ),
    );
    if (destination == null || !context.mounted) return;

    final File file;
    try {
      final result = await withProgressSheet<File>(
        context,
        title: 'Exporting',
        task: (report) => BackupService(
          ref.read(databaseProvider),
        ).exportToFile(onProgress: report),
      );
      if (result == null) return;
      file = result;
    } on BackupSaveException catch (e) {
      showToastOn(messenger, e.message, destructive: true);
      return;
    } catch (e, st) {
      reportFailure(e, st, what: 'The backup could not be written.');
      return;
    }

    if (destination == _ExportTo.downloads) {
      try {
        final location = await saveToDownloads(file);
        showToastOn(messenger, 'Saved to $location');
      } on BackupSaveException catch (e) {
        showToastOn(messenger, e.message, destructive: true);
      }
      return;
    }

    // The file is kept whether or not the share sheet is used, so say where
    // it went — a backup you cannot find later is one you have to trust.
    showToastOn(messenger, 'Saved to ${file.parent.path}');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Deltoid backup',
        // iPad needs an anchor for the share popover or it throws.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = BackupService(ref.read(databaseProvider));

    // Restoring wipes the database. Doing that with a session open would take
    // the sets being logged right now with it, and the log screen would go on
    // writing into rows that no longer exist.
    final open = await ref.read(trainingRepositoryProvider).openWorkout();
    if (open != null) {
      showToastOn(messenger, 'Finish or delete the session in progress first');
      return;
    }

    // The platform picker, which copies the document into the cache and returns
    // a path — never the contents. `file_selector` sends the bytes through the
    // channel, and its codec built the whole file in one array on the main
    // thread: a long history died of `OutOfMemoryError` in the picker's reply,
    // before any of this ran. `file_selector` stays as the fallback for a build
    // without the host code, where small files still work.
    //
    // No type filter either way. Android resolves `extensions: ['json']` to a
    // MIME type, and a .json file arriving from Downloads, a share sheet or a
    // cloud provider is as often `application/octet-stream` or `text/plain` —
    // so the filter greys out the very file the user came to pick, with no way
    // to say why. Anything that is not a backup is named as such below.
    final File? file;
    try {
      file = await pickBackupFile(
        fallback: () async {
          final picked = await openFile();
          if (picked == null) return null;
          // The fallback's `XFile` has no file behind it, so its bytes are
          // written out once and read back the same way as the real path.
          final scratch = File(
            '${Directory.systemTemp.path}/deltoid-restore-'
            '${DateTime.now().millisecondsSinceEpoch}.json',
          );
          await scratch.writeAsBytes(await picked.readAsBytes());
          return scratch;
        },
      );
    } on BackupSaveException catch (e) {
      showToastOn(messenger, e.message, destructive: true);
      return;
    }
    if (file == null) return;

    // Parsed once, off the UI isolate, and the parsed map is what the restore
    // is handed. Reading it once for the prompt, again for `restore`'s own
    // check and a third time for the real decode puts two full parses on the
    // thread drawing the dialog, which is most of what freezes a long history
    // here.
    final BackupSummary summary;
    final Map<String, dynamic> decoded;
    try {
      // **Decoded as UTF-8 off the byte stream** — not `file.readAsString()`,
      // and not `utf8.decode(await file.readAsBytes())` either.
      //
      // The plugin's string read comes back Latin-1 on Android, which restores
      // every non-ASCII character in a backup double-encoded: the `·` in this
      // app's own template names arrives as `Â·`, and so does every accent in a
      // note or an exercise the user has renamed. The exported file is correct
      // — the corruption is on the way back in, and restore replaces the
      // database, so it would overwrite the good copy with the mangled one.
      //
      // Decoding the bytes by hand fixes the encoding but keeps the cost: the
      // whole file as a UTF-16 string is twice its size in one allocation, and
      // a long history threw `OutOfMemoryError` on that line — the app died
      // with the user's only copy in the file picker. [decodeStream] walks the
      // file off disk in chunks instead, so neither copy is ever made.
      decoded = await service.decodeStream(file.openRead());
      summary = service.summarise(decoded);
    } on FormatException catch (e) {
      showToastOn(messenger, e.message, destructive: true);
      return;
    } catch (e) {
      // A photo picked by mistake never gets as far as a `FormatException`:
      // reading it as UTF-8 throws first, and the only handler here was for
      // JSON that parsed but was not a backup. So the screen returned in
      // silence — indistinguishable from a restore that ran and did nothing,
      // on the one screen in the app where "did that work?" matters most.
      showToastOn(
        messenger,
        'That file could not be read. Pick a Deltoid backup (.json).',
        destructive: true,
      );
      return;
    }

    if (!context.mounted) return;
    // The app's own confirmation, where the dangerous option is the loud one
    // and the safe option is the quiet one (THEME → Components) — this was two equal-weight
    // text buttons, with the one that wipes the device on the right.
    final confirmed = await confirmAction(
      context,
      title: 'Replace everything?',
      message:
          'This backup is from '
          '${DateFormat('d MMM yyyy, HH:mm').format(summary.exportedAt)} and '
          'holds ${summary.counts['workouts'] ?? 0} workouts. Restoring '
          'deletes everything currently on this device and replaces it with '
          'the file. This cannot be undone.',
      confirmLabel: 'Replace everything',
    );
    if (!confirmed) return;

    if (!context.mounted) return;
    try {
      final result = await withProgressSheet<ImportResult>(
        context,
        title: 'Restoring',
        task: (report) =>
            service.restore(null, onProgress: report, decoded: decoded),
      );
      if (result == null) return;
      showToastOn(messenger, 'Restored ${result.rowsWritten} rows');
    } on FormatException catch (e) {
      // The messages these carry are already written for a reader — "this
      // backup is incomplete", "update the app before restoring it". Prefixing
      // them turned each one into `Restore failed: FormatException: …`.
      showToastOn(messenger, e.message, destructive: true);
    } catch (e, st) {
      reportFailure(e, st, what: 'Your history could not be restored.');
    }
  }
}

enum _ExportTo { downloads, share }

class _BodyweightCard extends ConsumerWidget {
  const _BodyweightCard({required this.bodyweight});

  /// The newest entry and the number of them — the two figures this card shows,
  /// rather than every row in the table for it to work them out from.
  final BodyweightSummary bodyweight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // Watched *here*, not at the top of the screen. One line in
    // `SettingsScreen.build` would make switching kg to lb rebuild the whole
    // page — masthead, every section, the three painted theme miniatures — to
    // change the two words in this row and the tick in the units card. This is
    // the screen the switch is on, so it is the one that would hitch.
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final today = dayKeyOf(DateTime.now());
    final latest = bodyweight.latest;
    final loggedToday = latest != null && latest.dayKey == today;

    return ListCard(
      inset: Space.lg,
      children: [
        AppRow(
          icon: Icons.monitor_weight_outlined,
          title: latest == null
              ? 'Not logged'
              : '${formatBodyweight(latest.weightKg, unit)} ${unit.label}',
          subtitle: latest == null
              ? 'Used to score your bodyweight lifts'
              : loggedToday
              ? 'Logged today  ·  ${bodyweight.count} entries'
              : 'Last entry '
                    '${DateFormat('d MMM').format(dateFromDayKey(latest.dayKey))}'
                    '  ·  ${bodyweight.count} entries',
          onTap: () => logBodyweightPrompt(
            context,
            ref,
            date: loggedToday ? dateFromDayKey(latest.dayKey) : null,
            initial: loggedToday ? latest.weightKg : null,
          ),
          trailing: Icon(
            loggedToday ? Icons.edit_outlined : Icons.add,
            size: 20,
            color: c.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Kilograms or pounds.
///
/// Display only: every weight is stored in kilograms whatever this says, and
/// converted at the edges. Storing what was typed would mean a database whose
/// rows mean different things depending on when they were written, and no way
/// to tell which is which afterwards. The keypad's ± step follows this too —
/// 2.5 kg is a pair of plates, and so is 5 lb.
///
/// Where a `Local` install connects, and where a signed-in one sees which
/// account it is on.
///
/// The same connection the welcome screen offered, offered again — that is what
/// makes declining there a real answer rather than a decision the user is stuck
/// with ([SYNC.md § 3](SYNC.md#3-identity)). Nothing nags: there is no prompt
/// that comes back when the network does, and this row is the whole of the
/// second chance.
///
/// **Signed in, it says which of the three states this install is in**
/// ([SYNC.md § 2](SYNC.md#2-the-three-states)), read off the database rather
/// than off the engine — there is no second copy of the answer, and no state
/// for *syncing right now*. `Pending` is normal: a session logged in a basement
/// gym is pending for an hour and that is the design working. Phase 6 is where
/// it says for how long, and what a failure was.
///
/// Absent entirely from a build with no configuration, rather than present and
/// broken: a clone of this repo has no project to reach.
class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  /// True from the tap until Google's sheet closes and the account has been
  /// reconciled.
  ///
  /// The same wait the welcome screen has, and the same reason it is allowed to
  /// wait: nothing on screen depends on it, and the row that started it has to
  /// say it is working or it gets tapped again while Google is still opening.
  /// The adoption that may follow brings its own sheet.
  bool _signingIn = false;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(syncAuthProvider) == null) return const SizedBox.shrink();
    final account = ref.watch(accountProvider).valueOrNull;
    // Answered `account` and signed out anyway is § 13 row 2: a token that
    // could not be refreshed. The queue keeps filling and no data is lost, and
    // the only thing that fixes it is a sign-in.
    final dropped =
        account == null &&
        ref.watch(welcomeAnswerProvider).valueOrNull == WelcomeAnswer.account;

    return account == null
        ? AppRow(
                    icon: dropped
                        ? Icons.cloud_sync_outlined
                        : Icons.cloud_off_outlined,
                    title: _signingIn
                        ? 'Signing in'
                        : dropped
                        ? 'Sign in again to keep backing up'
                        : 'Back up to your Google account',
                    subtitle: _signingIn
                        ? 'Waiting for Google.'
                        : dropped
                        ? 'This phone was signed out. Everything logged since '
                              'is still here and still waiting.'
                        : 'Your history is on this phone and nowhere else.',
                    subtitleMaxLines: 3,
                    // The chevron is the affordance, so it goes while the
                    // spinner is there: two of them would say the row is both
                    // busy and ready.
                    trailing: _signingIn ? const RowSpinner() : null,
                    // A second tap would open a second sheet behind the first.
                    onTap: _signingIn ? null : () => _signIn(context, ref),
            chevron: !_signingIn,
          )
        // One row, opening the two ways out rather than listing
                  // them. Side by side on the page they read as the same
                  // action twice: both titles start "Sign out", and the
                  // difference between them — whether the history stays on
                  // this phone — was a subtitle each, in a column with room
                  // for neither to finish the thought.
        : AppRow(
            icon: Icons.account_circle_outlined,
            title: account.email ?? 'Signed in',
            subtitle: backupState(
              ref.watch(syncStateProvider).valueOrNull,
              ref.watch(syncTroubleProvider).valueOrNull,
            ),
            subtitleMaxLines: 3,
            onTap: () => _openAccountSheet(context, ref),
            chevron: true,
          );
  }

  /// The two ways out, where each has room to say what it does.
  ///
  /// They are not variations on one action. Signing out stops the backing up
  /// and changes nothing else; the second one empties this phone. The titles
  /// say which, the descriptions say what happens to the training, and the
  /// destructive one is last because red is where a list ends (THEME → Sheets).
  Future<void> _openAccountSheet(BuildContext context, WidgetRef ref) async {
    final c = context.c;
    final choice = await showAppSheet<String>(
      context,
      builder: (sheet) => AppSheet(
        title: 'Account',
        contentPadding: EdgeInsets.zero,
        children: [
          AppRow(
            icon: Icons.logout,
            title: 'Sign out',
            subtitle: 'Your training stays on this phone and you carry on '
                'logging. Backing up stops until you sign in again.',
            subtitleMaxLines: 4,
            onTap: () => Navigator.of(sheet).pop('out'),
          ),
          AppRow(
            icon: Icons.delete_sweep_outlined,
            title: 'Sign out and delete data',
            subtitle: 'Every session is deleted from this phone. Your '
                'account keeps its copy, so signing in again restores it. '
                'Use this when the phone is about to stop being yours.',
            subtitleMaxLines: 4,
            tint: c.negative,
            onTap: () => Navigator.of(sheet).pop('forget'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'out') {
      await _signOut(context, ref);
    } else if (choice == 'forget') {
      await _signOutAndForget(context, ref);
    }
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    setState(() => _signingIn = true);
    try {
      await signInAndAdopt(context, ref);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  /// Signing out leaves every row where it is.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(syncAuthProvider);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: 'Sign out?',
      message:
          'Your training stays on this phone. You can sign back in from '
          'here at any time.',
      confirmLabel: 'Sign out',
      destructive: false,
    );
    if (!confirmed || auth == null) return;
    await auth.signOut();
    showToastOn(messenger, 'Signed out.');
  }

  /// The second door, and it is forced open rather than found by accident.
  ///
  /// [SYNC.md § 11](SYNC.md#11-signing-out): *sign out and remove the history
  /// from this phone*, after a confirmation naming the number of sessions. The
  /// count is the whole point — a prompt that says *everything* is a prompt
  /// nobody can weigh, and this is the one control in Settings that cannot be
  /// undone from Settings.
  ///
  /// The rows are hard-deleted rather than tombstoned. This is not *the user
  /// deleted their training*, which every other phone would then hear about and
  /// apply; it is *this phone is no longer carrying it*.
  Future<void> _signOutAndForget(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(syncAuthProvider);
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final sessions = await localSessionCount(db);
    if (!context.mounted) return;

    final counted = sessions == 1 ? '1 session' : '$sessions sessions';
    final confirmed = await confirmAction(
      context,
      title: 'Remove your training from this phone?',
      message:
          '$counted will be deleted from this device. Your account keeps '
          'its copy, and signing in again brings it back.',
      confirmLabel: 'Sign out and remove',
      highlight: [counted],
    );
    if (!confirmed || auth == null) return;

    await auth.signOut();
    await forgetLocalHistory(db);
    showToastOn(messenger, 'Removed from this phone.');
  }
}

/// What the account row says under the address: which state, for how long, and
/// why.
///
/// [SYNC.md § 2](SYNC.md#2-the-three-states) asks for all three, and *for how
/// long* is the one that carries the meaning. **Pending is normal** — a session
/// logged in a basement gym is pending for an hour and that is the design
/// working — so the number of changes alone says nothing. Since this morning is
/// a gym with no signal; since Tuesday is something to look at.
///
/// The loading case is the other half: `valueOrNull` on an `AsyncValue` that has
/// not resolved is null, and reading null as *nothing owed* would show
/// `Backed up` over a phone that is holding a session
/// ([SYNC.md § 19](SYNC.md#19-traps)). Until the count arrives this says only
/// what is certain — that this device is signed in.
///
/// The header's backup sheet says the same line, so the two never disagree
/// about how much is waiting or why.
String backupState(SyncState? state, SyncTrouble? trouble) {
  if (state == null) return 'Signed in on this device.';

  return switch (state.status) {
    SyncStatus.pending => [
      state.owed == 1 ? '1 change waiting' : '${state.owed} changes waiting',
      if (state.owedSince case final since?) ' since ${_since(since)}',
      '.',
      // Only when the last attempt actually failed. Rows written a minute ago
      // are pending because the debounce has not elapsed, and explaining that
      // to a user would be inventing a problem to reassure them about.
      switch (trouble) {
        SyncTrouble.offline => " There's no connection right now.",
        SyncTrouble.refused =>
          ' The account refused the last attempt. It will keep trying.',
        null => '',
      },
    ].join(),
    SyncStatus.synced || SyncStatus.local => switch (state.lastPushAt) {
      final at? =>
        'Backed up ${DateFormat('d MMM, HH:mm').format(at.toLocal())}.',
      // Signed in, nothing owed, and nothing has ever left: a fresh install
      // that has not been trained on yet.
      _ => 'Signed in on this device.',
    },
  };
}

/// A time if it is today, a date if it is not.
///
/// `09:14` on the day it happened and `12 Aug` after that: the hour matters
/// while it is still this session, and stops meaning anything the moment the
/// answer is *days*.
String _since(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return DateFormat(sameDay ? 'HH:mm' : 'd MMM').format(local);
}

/// **The three numbers rest runs on.**
///
/// The first two are defaults, not the whole story: an exercise inside a
/// training day can carry its own rest, set on that exercise's own screen, and
/// it outranks the default here. This section is what an exercise falls back
/// to and what the walk to the next machine is worth.
/// The unit, as one row showing the answer.
///
/// Not two radio rows on the page. Radios are right where a choice needs room
/// to say what it means (THEME → Toggles), and this one does — switching
/// restates every number in the app — but the place with room is the sheet, not
/// a card that has to carry both options forever to be read once a year.
class _UnitRow extends ConsumerWidget {
  const _UnitRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    return AppRow(
      icon: Icons.straighten,
      title: 'Weight units',
      trailing: RowValue(_unitName(current)),
      onTap: () => _open(context, ref, current),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    WeightUnit current,
  ) async {
    final picked = await showAppSheet<WeightUnit>(
      context,
      builder: (sheet) => AppSheet(
        title: 'Weight units',
        contentPadding: EdgeInsets.zero,
        children: [
          for (final unit in WeightUnit.values)
            AppRow(
              title: _unitName(unit),
              // The sheet is where the option has room to say what it means,
              // which is the whole reason the choice moved into one.
              subtitle: switch (unit) {
                WeightUnit.kg => 'Weights, charts and plates in kilograms',
                WeightUnit.lb => 'Weights, charts and plates in pounds',
              },
              trailing: AppRadio(selected: unit == current),
              ink: false,
              onTap: () => Navigator.of(sheet).pop(unit),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await _switchTo(context, ref, from: current, to: picked);
  }

  /// Asks first, the way an exercise's own fields do.
  ///
  /// This one is reversible and stores nothing — the database is kilograms
  /// whichever row is ticked — but it is a radio, one tap, and it restates every
  /// number in the app at once: the logs, the charts, the keypad's step and the
  /// plates on the bar. A screen you came to for a backup should not be able to
  /// do that to you on the way past.
  Future<void> _switchTo(
    BuildContext context,
    WidgetRef ref, {
    required WeightUnit from,
    required WeightUnit to,
  }) async {
    if (from == to) return;
    // The database outlives the widget: a repository read after the sheet
    // closes must not go through a `ref` this screen may have disposed.
    final db = ref.read(databaseProvider);
    final ok = await confirmAction(
      context,
      title: 'Show weights in ${_unitName(to).toLowerCase()}?',
      message:
          'Every weight in the app changes from ${_unitName(from)} to '
          '${_unitName(to)}: your logs, the charts, the keypad and the plate '
          'view. Nothing logged changes, because weights are stored in kilograms '
          'either way and converted for the screen.',
      highlight: [_unitName(from), _unitName(to)],
      confirmLabel: 'Switch to ${_unitName(to).toLowerCase()}',
      destructive: false,
    );
    if (!ok) return;
    // Written *after* the sheet has finished leaving, not while it is.
    //
    // Nothing is converted here — storage is kilograms either way — so there is
    // no work to move off the UI isolate and nothing a progress bar could
    // honestly count. What there is is one rebuild of every widget holding a
    // weight, and the shell keeps all four tabs alive in an `IndexedStack`, so
    // that rebuild lands on more than the screen you are looking at. Running it
    // against the sheet's own exit animation is what makes it read as a stutter
    // rather than as a redraw.
    await Future<void>.delayed(Motion.base);
    await setWeightUnit(db, to);
  }
}

String _unitName(WeightUnit unit) => switch (unit) {
  WeightUnit.kg => 'Kilograms',
  WeightUnit.lb => 'Pounds',
};

/// Three miniatures of the app, side by side.
///
/// Named modes in a segmented track ask you to remember what "System" did last
/// time; the tiles show it. System is drawn as both halves at once, which is
/// the only honest picture of a setting that is neither.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.dark;

    return Row(
      children: [
        for (final mode in ThemeMode.values) ...[
          if (mode != ThemeMode.values.first) const SizedBox(width: Space.md),
          Expanded(
            child: _ThemeTile(
              mode: mode,
              selected: mode == current,
              onTap: () => setThemeMode(ref.read(databaseProvider), mode),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: Column(
        children: [
          AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            // A hairline when it is not chosen, not nothing.
            //
            // The miniature is painted in its *own* palette, so the dark tile
            // is `#131313` on a `#131313` page: with a transparent ring around
            // it, the tile you are not using has no edge at all and reads as a
            // hole in the section rather than as the other choice. The ring is
            // the card, and it is `surface` filled so the mount is visible on
            // both themes; selected takes it to 2px `accent`, which is the
            // choice-card state from THEME → Composing a screen.
            padding: EdgeInsets.all(selected ? 3 : 4),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.control + 3),
              border: Border.all(
                color: selected ? c.accent : c.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.control),
              child: AspectRatio(
                aspectRatio: 1.1,
                child: switch (mode) {
                  ThemeMode.light => const _ThemeMiniature(DeltoidColors.light),
                  ThemeMode.dark => const _ThemeMiniature(DeltoidColors.dark),
                  // Both halves, split on the diagonal the way the OS setting
                  // itself is neither one nor the other.
                  ThemeMode.system => const Stack(
                    fit: StackFit.expand,
                    children: [
                      _ThemeMiniature(DeltoidColors.dark),
                      ClipPath(
                        clipper: _DiagonalClipper(),
                        child: _ThemeMiniature(DeltoidColors.light),
                      ),
                    ],
                  ),
                },
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            switch (mode) {
              ThemeMode.system => 'System',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            },
            style: context.t.titleSmall?.copyWith(
              color: selected ? c.textPrimary : c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The top-left triangle, so the System tile shows light over dark without
/// either half being a rectangle you could mistake for the whole thing.
class _DiagonalClipper extends CustomClipper<Path> {
  const _DiagonalClipper();

  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// A page of the app at thumbnail size: a heading, the chart series as dots,
/// and cards. Not a screenshot — a screenshot at 90pt is grey mush, and this
/// has to survive being looked at for half a second.
class _ThemeMiniature extends StatelessWidget {
  const _ThemeMiniature(this.palette);

  final DeltoidColors palette;

  @override
  Widget build(BuildContext context) {
    Widget block({double width = double.infinity, double height = 10}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: BorderRadius.circular(3),
          ),
        );

    return Container(
      color: palette.bg,
      padding: const EdgeInsets.all(Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aa',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              // Four of the identity hues, spaced across the six so no two
              // neighbours read as one colour at this size — and none of the
              // reserved ones, since a dot of deload orange or progress blue
              // would be decoration wearing a meaning. Big enough to be a
              // colour: at 5 they were punctuation.
              for (final colour in const [
                DeltoidColors.pink,
                DeltoidColors.cyan,
                DeltoidColors.lavender,
                DeltoidColors.green,
              ]) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colour,
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
            ],
          ),
          const SizedBox(height: Space.sm),
          block(height: 12),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: block()),
              const SizedBox(width: 4),
              Expanded(child: block()),
            ],
          ),
        ],
      ),
    );
  }
}

/// The name of the app, the build actually installed, and the one sentence
/// that says what makes it different from every other training log.
///
/// A card holding one `bodySmall` paragraph and nothing else is wrong twice
/// over: the type sits a step below every other sentence on the page, so the
/// only section that reads as an explanation is the only one set smaller than
/// the rows above it, and a person looking for a version number — which is what
/// anybody opens About for — finds no number at all.
class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final version = ref.watch(appVersionProvider).valueOrNull;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and version are one phrase, not a row with the version
          // pushed to the far edge — "Deltoid" on the left and "1.3.1" hard
          // right read as a label and an unrelated figure, the shape a stat
          // row has. The version is absent rather than a placeholder while it
          // is being read: a dash would be rule 4's dash, which means a
          // measurement that should exist and does not, and this one is
          // simply late.
          Text(
            version == null ? 'Deltoid' : 'Deltoid v$version',
            style: context.t.titleMedium,
          ),
          const SizedBox(height: Space.sm),
          Text(
            // What the app is, then the one thing that makes it different
            // from every other training log. The second sentence earns its
            // place: session-scoped progression is the reason this exists
            // (CLAUDE.md rule 1), and without it the paragraph describes any
            // tracker on the store.
            //
            // Not "everything stays on this device" — the masthead's eyebrow
            // says that, and a fact stated twice on one screen is the rule
            // this app breaks most often (THEME rule 6).
            'An exercise tracker for building your own training regimes and '
            'logging your progress as you get stronger. Each session keeps '
            'its own history, so the same movement progresses independently '
            'in each one.',
            style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Rest, as one row that says what it is set to and opens the rest.
///
/// On the page, a stepper leaves 136pt for the words beside it, which cuts
/// every helper line under it off mid sentence: "For an exercise that has not
/// been given its own…". Neither shortening them nor letting them wrap fixes
/// that, because the room is taken by the control. In a sheet each one has the
/// full width, and the page keeps three rows for the three controls.
class _RestRow extends ConsumerWidget {
  const _RestRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(restPrefsProvider).valueOrNull ?? restPrefsDefaults;

    return AppRow(
      icon: Icons.timer_outlined,
      title: 'Rest time & alert',
      // The summary is the two numbers, because they are what a person opens
      // this row to check and what they would otherwise have to open it to see.
      subtitle:
          '${formatRestClock(prefs.defaultSeconds)} between sets and '
          '${formatRestClock(prefs.betweenExercises)} between exercises',
      onTap: () => showRestSheet(context),
      chevron: true,
    );
  }
}

/// The rest settings, with room for each one to say what it governs.
Future<void> showRestSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (sheet) => Consumer(
      builder: (context, ref, _) {
        final prefs =
            ref.watch(restPrefsProvider).valueOrNull ?? restPrefsDefaults;
        final db = ref.read(databaseProvider);

        return AppSheet(
          title: 'Rest time & alert',
          // Full-bleed rows carry their own padding, so the sheet adds none of
          // its own at the sides — the double-inset [AppSheet.contentPadding]
          // warns about. Bottom only, for the last row to breathe.
          contentPadding: const EdgeInsets.only(bottom: Space.md),
          children: [
            StepperRow(
              label: 'Between sets',
              helper: 'The default for an exercise that has not been given '
                  'a rest of its own',
              value: formatRestClock(prefs.defaultSeconds),
              onDecrement: prefs.defaultSeconds > kMinRestSeconds
                  ? () => setRestDefaultSeconds(
                        db,
                        prefs.defaultSeconds - kRestStepSeconds,
                      )
                  : null,
              onIncrement: prefs.defaultSeconds < kMaxRestSeconds
                  ? () => setRestDefaultSeconds(
                        db,
                        prefs.defaultSeconds + kRestStepSeconds,
                      )
                  : null,
            ),
            StepperRow(
              label: 'Between exercises',
              helper: 'The pause after the last set of one movement, before '
                  'the first set of the next',
              value: formatRestClock(prefs.betweenExercises),
              onDecrement: prefs.betweenExercises > kMinRestSeconds
                  ? () => setRestBetweenExercisesSeconds(
                        db,
                        prefs.betweenExercises - kRestStepSeconds,
                      )
                  : null,
              onIncrement: prefs.betweenExercises < kMaxRestSeconds
                  ? () => setRestBetweenExercisesSeconds(
                        db,
                        prefs.betweenExercises + kRestStepSeconds,
                      )
                  : null,
            ),
            AppRow(
              title: 'Alert sound',
              subtitle: 'Plays a tone when the rest reaches zero.',
              subtitleMaxLines: 3,
              trailing: Switch(
                value: prefs.sound,
                onChanged: (on) => setRestSound(db, on),
              ),
            ),
            AppRow(
              title: 'Vibration',
              // Its own switch rather than half of the one above, because the
              // two fail differently: the tone is what carries over a gym, and
              // the buzz is what a phone lying face down on a bench still
              // reports.
              subtitle: 'Buzzes when the rest reaches zero, whether or not '
                  'the tone is on.',
              subtitleMaxLines: 3,
              trailing: Switch(
                value: prefs.vibrate,
                onChanged: (on) => setRestVibrate(db, on),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Whether a session posts its ongoing line.
///
/// The line is a foreground service, and Android will not run one without a
/// notification — so this is not "hide it", it is "do not run it". The
/// subtitle says what that costs, because the cost is a feature: the rest bar
/// drains a second at a time only because a service is holding it. The alert
/// itself is a scheduled alarm and arrives either way, which is the half worth
/// promising.
class _SessionNotificationRow extends ConsumerWidget {
  const _SessionNotificationRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(sessionPrefsProvider).valueOrNull ?? sessionPrefsDefaults;

    return AppRow(
      icon: Icons.notifications_none_rounded,
      title: 'Session notification',
      subtitle: prefs.notification
          ? 'Shows what you are training and the rest clock while a session '
                'is open.'
          : 'Off. The rest alert still sounds, but the clock stops counting '
                'while the screen is off.',
      subtitleMaxLines: 3,
      trailing: Switch(
        value: prefs.notification,
        onChanged: (on) => setSessionNotification(ref.read(databaseProvider), on),
      ),
    );
  }
}

/// Whether the screen is held awake for the length of a session.
class _KeepScreenOnRow extends ConsumerWidget {
  const _KeepScreenOnRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(sessionPrefsProvider).valueOrNull ?? sessionPrefsDefaults;

    return AppRow(
      icon: Icons.stay_current_portrait_outlined,
      title: 'Keep screen on',
      subtitle: 'Stops the phone locking while a session is open.',
      subtitleMaxLines: 3,
      trailing: Switch(
        value: prefs.keepScreenOn,
        onChanged: (on) => setKeepScreenOn(ref.read(databaseProvider), on),
      ),
    );
  }
}
