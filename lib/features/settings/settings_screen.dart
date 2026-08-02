import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/backup/backup_service.dart';
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
          // every other destination wears.
          const HeaderBand(child: PageHeader(title: 'Settings', topGap: Space.xxl)),
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
          const SizedBox(height: Space.xxl),
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
          const SizedBox(height: Space.xxl),
          const SectionHeader('Units'),
          const _UnitPicker(),
          const SizedBox(height: Space.xxl),
          const SectionHeader('Appearance'),
          const _ThemePicker(),
          const SizedBox(height: Space.xxl),
          const SectionHeader('About'),
          AppCard(
            child: Text(
              'Deltoid keeps everything on this device. Sessions carry their '
              'own history, so the same exercise progresses independently in '
              'each one.',
              style: context.t.bodySmall,
            ),
          ),
        ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final file = await BackupService(ref.read(databaseProvider)).exportToFile();
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
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
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

    final BackupSummary summary;
    final String contents;
    try {
      contents = await file.readAsString();
      summary = service.inspect(contents);
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

    // A decade of training is a hundred thousand rows. Without something on
    // screen the app looks hung, and a hung restore gets killed halfway.
    final progress = ValueNotifier<String>('Starting…');
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Restoring'),
          content: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (context, text, _) => Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: Space.lg),
                Expanded(child: Text(text)),
              ],
            ),
          ),
        ),
      ),
    ));

    try {
      final result = await service.restore(
        contents,
        onProgress: (table, rows) =>
            progress.value = '$rows rows · ${table.replaceAll('_', ' ')}',
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Restored ${result.rowsWritten} rows')),
      );
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      progress.dispose();
    }
  }

}

/// The latest weight, and one tap to log today's.
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

    return AppCard(
      onTap: () => logBodyweightPrompt(
        context,
        ref,
        date: loggedToday ? dateFromDayKey(latest.dayKey) : null,
        initial: loggedToday ? latest.weightKg : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latest == null
                      ? 'Not logged'
                      : '${formatInUnit(latest.weightKg, unit)} ${unit.label}',
                  style: context.t.displaySmall,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  latest == null
                      ? 'Needed to score bodyweight and BW+ lifts'
                      : loggedToday
                          ? 'Logged today  ·  ${log.length} entries'
                          : 'Last entry '
                              '${DateFormat('d MMM yyyy').format(dateFromDayKey(latest.dayKey))}'
                              '  ·  ${log.length} entries',
                  style: context.t.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Icon(
            loggedToday ? Icons.edit_outlined : Icons.add,
            size: 20,
            color: c.textTertiary,
          ),
        ],
      ),
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
/// The control is the app's own segmented pill, not a card of hand-rolled
/// `AnimatedContainer`s: this screen had drawn its own version of a primitive
/// that already existed, in an accent the rest of the app reserves for the
/// selected segment of exactly this control.
class _UnitPicker extends ConsumerWidget {
  const _UnitPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;

    return SegmentedPill<WeightUnit>(
      expand: true,
      value: current,
      onChanged: (unit) => setWeightUnit(ref.read(databaseProvider), unit),
      segments: const [
        (value: WeightUnit.kg, label: 'Kilograms'),
        (value: WeightUnit.lb, label: 'Pounds'),
      ],
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.dark;

    return SegmentedPill<ThemeMode>(
      expand: true,
      value: current,
      onChanged: (mode) => setThemeMode(ref.read(databaseProvider), mode),
      segments: const [
        (value: ThemeMode.system, label: 'System'),
        (value: ThemeMode.light, label: 'Light'),
        (value: ThemeMode.dark, label: 'Dark'),
      ],
    );
  }
}
