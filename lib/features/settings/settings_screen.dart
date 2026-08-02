import 'dart:async';
import 'dart:io' show File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/backup/backup_service.dart';
import '../../data/backup/downloads.dart';
import '../../data/db/database.dart';
import 'bodyweight_screen.dart';
import '../../domain/units.dart';

/// When the last automatic export ran. One fires after every finished
/// session, but Settings never said so, which made the whole mechanism
/// invisible and therefore untrusted.
final lastBackupProvider = FutureProvider<DateTime?>((ref) {
  return BackupService(ref.watch(databaseProvider)).lastAutoExportAt();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(bodyweightHistoryProvider).valueOrNull ?? const [];
    final lastBackup = ref.watch(lastBackupProvider).valueOrNull;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final c = context.c;

    return Scaffold(
      body: Column(
        children: [
          // A tab now, not a screen pushed from a cog, so it wears the masthead
          // every other destination wears — eyebrow included. A title alone on
          // the band made this the only tab whose header was one line, which is
          // what made it read as a screen from a different app.
          const HeaderBand(
            child: PageHeader(
              title: 'Settings',
              eyebrow: 'On this device',
            ),
          ),
          Expanded(child: _body(context, ref, log, lastBackup, unit, c)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    List<BodyweightLog> log,
    DateTime? lastBackup,
    WeightUnit unit,
    DeltoidColors c,
  ) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.gutter, Space.lg, Space.gutter, Space.huge),
        children: [
          SectionHeader(
            'Bodyweight',
            actionLabel: log.isEmpty ? null : 'History',
            onAction: log.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BodyweightScreen()),
                    ),
          ),
          // The figure logs one, it does not open a screen that offers to.
          // Bodyweight was behind a cog, then behind a card that pushed a
          // screen with a `+` in its bar — three taps to type a number you are
          // asked for daily, which is why it had never once been logged
          // through the UI. Tapping the figure is the log; the past is a link.
          _BodyweightCard(log: log, unit: unit),
          const SizedBox(height: Space.section),
          const SectionHeader('Data'),
          ListCard(
            inset: Space.lg,
            children: [
              AppRow(
                icon: Icons.ios_share,
                title: 'Export backup',
                subtitle: 'One file with every workout, ready for Drive or '
                    'iCloud.',
                onTap: () => _export(context, ref),
                chevron: true,
              ),
              AppRow(
                icon: Icons.settings_backup_restore,
                title: 'Restore from backup',
                subtitle: 'Replaces everything currently on this device.',
                onTap: () => _restore(context, ref),
                chevron: true,
              ),
              AppRow(
                icon: Icons.schedule,
                title: lastBackup == null
                    ? 'No automatic backup yet'
                    : 'Last backup '
                        '${DateFormat('d MMM yyyy, HH:mm').format(lastBackup)}',
                subtitle: 'Written automatically after each finished session.',
              ),
            ],
          ),
          const SizedBox(height: Space.section),
          const SectionHeader('Units'),
          const _UnitPicker(),
          const SizedBox(height: Space.section),
          const SectionHeader('Appearance'),
          const _ThemePicker(),
          const SizedBox(height: Space.section),
          const SectionHeader('About'),
          AppCard(
            child: Text(
              // Not "everything stays on this device" — the masthead's eyebrow
              // says that, and a fact stated twice on one screen is the rule
              // this app breaks most often (THEME rule 6).
              'Sessions carry their own history, so the same exercise '
              'progresses independently in each one.',
              style: context.t.bodySmall,
            ),
          ),
        ],
    );
  }

  /// Ask where it goes, then write it with the progress on screen.
  ///
  /// The share sheet used to be the only way out, and sharing a backup to
  /// yourself is a strange thing to have to do — every other app that makes a
  /// file puts it in Downloads.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;

    final destination = await showModalBottomSheet<_ExportTo>(
      context: context,
      isScrollControlled: true,
      // `SheetHeader` draws its own grab handle, tighter than the framework's.
      showDragHandle: false,
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
              subtitle: 'Into $downloadsFolder, where a file manager can '
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
      final result = await _withProgress<File>(
        context,
        title: 'Exporting',
        task: (report) =>
            BackupService(ref.read(databaseProvider)).exportToFile(
          onProgress: report,
        ),
      );
      if (result == null) return;
      file = result;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
      return;
    }

    if (destination == _ExportTo.downloads) {
      try {
        final location = await saveToDownloads(file);
        messenger.showSnackBar(SnackBar(content: Text('Saved to $location')));
      } on BackupSaveException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }

    // The file is kept whether or not the share sheet is used, so say where
    // it went — a backup you cannot find later is one you have to trust.
    messenger.showSnackBar(
      SnackBar(content: Text('Saved to ${file.parent.path}')),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Deltoid backup',
        // iPad needs an anchor for the share popover or it throws.
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
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
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Finish or delete the session in progress first'),
        ),
      );
      return;
    }

    // No type filter. Android resolves `extensions: ['json']` to a MIME type,
    // and a .json file arriving from Downloads, a share sheet or a cloud
    // provider is as often `application/octet-stream` or `text/plain` — so the
    // filter greys out the very file the user came to pick, with no way to say
    // why. Anything that is not a backup is caught by `inspect` below and
    // named as such.
    final file = await openFile();
    if (file == null) return;

    // Parsed once, off the UI isolate, and the parsed map is what the restore
    // is handed. It used to be read three times over — the prompt, then
    // `restore`'s own check, then the real decode — two of them on the thread
    // drawing the dialog, which is most of why a long history froze here.
    final BackupSummary summary;
    final Map<String, dynamic> decoded;
    final String contents;
    try {
      contents = await file.readAsString();
      decoded = await service.decode(contents);
      summary = service.summarise(decoded);
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    if (!context.mounted) return;
    // The app's own confirmation, where the dangerous option is the loud one
    // and the safe option is the quiet one (§5) — this was two equal-weight
    // text buttons, with the one that wipes the device on the right.
    final confirmed = await confirmAction(
      context,
      title: 'Replace everything?',
      message: 'This backup is from '
          '${DateFormat('d MMM yyyy, HH:mm').format(summary.exportedAt)} and '
          'holds ${summary.counts['workouts'] ?? 0} workouts. Restoring '
          'deletes everything currently on this device and replaces it with '
          'the file. This cannot be undone.',
      confirmLabel: 'Replace everything',
    );
    if (!confirmed) return;

    if (!context.mounted) return;
    try {
      final result = await _withProgress<ImportResult>(
        context,
        title: 'Restoring',
        task: (report) =>
            service.restore(contents, onProgress: report, decoded: decoded),
      );
      if (result == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Restored ${result.rowsWritten} rows')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }
}

enum _ExportTo { downloads, share }

/// Runs a long backup job behind a sheet that says what it is doing.
///
/// A decade of training is a hundred thousand rows. Without something on
/// screen the app looks hung, and a hung restore gets killed halfway — which
/// is the one failure mode that costs data. Both jobs report through
/// [BackupStep], so this is the same sheet either way.
///
/// The sheet cannot be dismissed and the barrier does not close it: the
/// database is mid-transaction, and the way out is for the job to finish.
/// Errors are rethrown to the caller, which owns the wording.
Future<T?> _withProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(BackupProgress report) task,
}) async {
  final step = ValueNotifier<BackupStep?>(null);
  final navigator = Navigator.of(context);

  unawaited(showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressSheet(title: title, step: step),
    ),
  ));

  try {
    // The notifier is written from a callback that fires between database
    // batches, so the bar moves on the frames the work leaves free.
    return await task((s) => step.value = s);
  } finally {
    navigator.pop();
    step.dispose();
  }
}

class _ProgressSheet extends StatelessWidget {
  const _ProgressSheet({required this.title, required this.step});

  final String title;
  final ValueListenable<BackupStep?> step;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.xl, Space.xl, Space.xl, Space.xxl),
        child: ValueListenableBuilder<BackupStep?>(
          valueListenable: step,
          builder: (context, current, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: context.t.headlineSmall),
                const SizedBox(height: Space.xs),
                Text(
                  switch (current?.phase) {
                    null => 'Starting…',
                    BackupPhase.reading => 'Reading ${current!.detail}',
                    // Named rather than left as a stalled bar: this is the
                    // phase that takes the longest and reports nothing, and
                    // silence here is what made the whole thing look hung.
                    BackupPhase.encoding =>
                      'Packing ${current!.detail} into one file',
                    BackupPhase.decoding => 'Reading the file · ${current!.detail}',
                    BackupPhase.clearing => 'Clearing this device',
                    BackupPhase.writing =>
                      '${current!.rows} rows · ${current.detail}',
                  },
                  style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: Space.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    // Null while a phase genuinely cannot say how far it is,
                    // where the bar runs indeterminate rather than inventing a
                    // number and then jumping.
                    value: current?.fraction,
                    minHeight: 6,
                    backgroundColor: c.surfaceHigh,
                    color: c.accent,
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  'Keep the app open until this finishes.',
                  style: context.t.labelSmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The latest weight, and one tap to log today's.
///
/// One row, not a card with a 30sp figure in it: this is a number you glance
/// at on the way to logging the next one, and at display size it took the same
/// vertical room as the whole Data section under it.
///
/// Tapping opens the log sheet on today — prefilled when today already has an
/// entry, so a second weighing corrects rather than duplicates (the table is
/// keyed by day, so it would have overwritten either way; this says so).
class _BodyweightCard extends ConsumerWidget {
  const _BodyweightCard({required this.log, required this.unit});

  final List<BodyweightLog> log;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final today = dayKeyOf(DateTime.now());
    final latest = log.isEmpty ? null : log.first;
    final loggedToday = latest != null && latest.dayKey == today;

    return ListCard(
      inset: Space.lg,
      children: [
        AppRow(
          icon: Icons.monitor_weight_outlined,
          title: latest == null
              ? 'Not logged'
              : '${formatInUnit(latest.weightKg, unit)} ${unit.label}',
          subtitle: latest == null
              ? 'Needed to score bodyweight and BW+ lifts'
              : loggedToday
                  ? 'Logged today  ·  ${log.length} entries'
                  : 'Last entry '
                      '${DateFormat('d MMM').format(dateFromDayKey(latest.dayKey))}'
                      '  ·  ${log.length} entries',
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
/// Rows with radios, not a segmented pill: a pill fits the labels and nothing
/// else, and the unit is the one setting here that changes what every number
/// in the app means. A row has the width to say so.
class _UnitPicker extends ConsumerWidget {
  const _UnitPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    return ListCard(
      inset: Space.lg,
      children: [
        for (final unit in WeightUnit.values)
          AppRow(
            title: switch (unit) {
              WeightUnit.kg => 'Kilograms',
              WeightUnit.lb => 'Pounds',
            },
            trailing: AppRadio(selected: unit == current),
            onTap: () => setWeightUnit(ref.read(databaseProvider), unit),
          ),
      ],
    );
  }
}

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
            // choice-card state from THEME §7.
            padding: EdgeInsets.all(selected ? 3 : 4),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.md + 3),
              border: Border.all(
                color: selected ? c.accent : c.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
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
              // The identity hues, spaced across the six rather than the first
              // four of `series[]` — which put cyan next to blue and made two
              // of the four dots read as one colour at 5pt. Big enough to be a
              // colour: at 5 they were punctuation.
              for (final colour in const [
                DeltoidColors.orange,
                DeltoidColors.blue,
                DeltoidColors.lavender,
                DeltoidColors.green,
              ]) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: colour),
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
