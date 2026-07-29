import 'package:drift/drift.dart' hide Column, Table;
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

final bodyweightLogProvider = StreamProvider<List<BodyweightLog>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.bodyweightLogs)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([
      (t) => OrderingTerm(expression: t.dayKey, mode: OrderingMode.desc)
    ])
    ..limit(30);
  return query.watch();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(bodyweightLogProvider).valueOrNull ?? const [];
    final c = context.c;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.sm, Space.lg, Space.huge),
        children: [
          const SectionLabel('Bodyweight'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.isEmpty
                                ? 'Not logged'
                                : '${_fmt(log.first.weightKg)} kg',
                            style: context.t.displaySmall,
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            log.isEmpty
                                ? 'Needed to score bodyweight and BW+ lifts'
                                : 'Last entry '
                                    '${DateFormat('d MMM yyyy').format(dateFromDayKey(log.first.dayKey))}',
                            style: context.t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding:
                            const EdgeInsets.symmetric(horizontal: Space.lg),
                      ),
                      onPressed: () => _logBodyweight(context, ref),
                      child: const Text('Log'),
                    ),
                  ],
                ),
                if (log.length > 1) ...[
                  const SizedBox(height: Space.lg),
                  Divider(color: c.border, height: 1),
                  const SizedBox(height: Space.md),
                  for (final entry in log.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('d MMM yyyy')
                                  .format(dateFromDayKey(entry.dayKey)),
                              style: context.t.bodySmall,
                            ),
                          ),
                          Text('${_fmt(entry.weightKg)} kg',
                              style: context.t.labelMedium),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.xxl),
          const SectionLabel('Data'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  titleAlignment: ListTileTitleAlignment.top,
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Export backup'),
                  subtitle: Text(
                    'One file with every workout, ready for Drive or iCloud. '
                    'This is what makes a new phone a copy, not a migration.',
                    style: context.t.labelSmall,
                  ),
                  onTap: () => _export(context, ref),
                ),
                Divider(color: c.border, height: 1),
                ListTile(
                  titleAlignment: ListTileTitleAlignment.top,
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Restore from backup'),
                  subtitle: Text(
                    'Replaces everything currently on this device.',
                    style: context.t.labelSmall,
                  ),
                  onTap: () => _restore(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xxl),
          const SectionLabel('Appearance'),
          const _ThemePicker(),
          const SizedBox(height: Space.xxl),
          const SectionLabel('About'),
          AppCard(
            child: Text(
              'Deltoid keeps everything on this device. Sessions carry their '
              'own history, so the same exercise progresses independently in '
              'each one.',
              style: context.t.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logBodyweight(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log bodyweight'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'kg'),
          onSubmitted: (v) => Navigator.of(ctx).pop(double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || value <= 0) return;
    await ref
        .read(trainingRepositoryProvider)
        .logBodyweight(DateTime.now(), value);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final file = await BackupService(ref.read(databaseProvider)).exportToFile();
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

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Deltoid backup', extensions: ['json']),
      ],
    );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Text(
          'This backup is from '
          '${DateFormat('d MMM yyyy, HH:mm').format(summary.exportedAt)} and '
          'holds ${summary.counts['workouts'] ?? 0} workouts.\n\n'
          'Restoring deletes everything currently on this device and replaces '
          'it with the file. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await service.restore(contents);
      messenger.showSnackBar(
        SnackBar(content: Text('Restored ${result.rowsWritten} rows')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final current = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.dark;

    return AppCard(
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          for (final mode in ThemeMode.values)
            Expanded(
              child: GestureDetector(
                onTap: () => setThemeMode(ref.read(databaseProvider), mode),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  decoration: BoxDecoration(
                    color: mode == current ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    switch (mode) {
                      ThemeMode.system => 'System',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    },
                    textAlign: TextAlign.center,
                    style: context.t.titleSmall?.copyWith(
                      color: mode == current ? c.onAccent : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
