import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/regime_repository.dart';
import '../../domain/enums.dart';
import '../log/widgets/exercise_sheets.dart';
import 'regime_screen.dart';
import 'regime_setup.dart';
import '../../core/widgets/toast.dart';

/// The Regimes tab: every programme, and the catalog they are all built from.
///
/// The tab used to open straight into the active regime's editor, which made
/// the other regimes look deleted — they were two sheets deep behind a sliders
/// button, next to the catalog. This is the index of the section instead:
/// what exists, which one is being trained, and the shared list of movements.
/// One tap in and you are on the same editor as before, now scoped to the
/// regime you tapped rather than to whichever one is active.
class RegimesScreen extends ConsumerWidget {
  const RegimesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(regimeSummariesProvider).valueOrNull;

    // No status line under the title: the `Active regime` heading below says
    // which one is being trained, and the band saying it too is the same fact
    // twice, 40pt apart.
    //
    // The eyebrow states the inventory instead — the one fact about this page
    // that no row on it carries — so the band is the two-line masthead every
    // other tab wears rather than a lone 30sp word on a strip of surface. It
    // waits for the count the same way History's does: no honest eyebrow yet,
    // so the title takes the wider top gap until there is one (THEME → Space).
    final header = HeaderBand(
      child: PageHeader(
        title: 'Regimes',
        eyebrow: _inventory(summaries),
        topGap: summaries == null ? Space.xxl : Space.md,
      ),
    );

    if (summaries == null) {
      return Scaffold(
        body: Column(
          children: [
            header,
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    // Which one is being trained is said by the heading it sits under, not by
    // a badge on the row. A pill in the trailing slot is a chip one row wide
    // and no other, so the title beside it wraps where its neighbours don't and
    // the column bends around whichever regime happens to be active.
    final live = [for (final s in summaries) if (s.regime.isActive) s];
    final library = [for (final s in summaries) if (!s.regime.isActive) s];

    return Scaffold(
      body: Column(
        children: [
          header,
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Space.huge),
              children: [
                const SizedBox(height: Space.lg),
                if (live.isNotEmpty) ...[
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: SectionHeader('Active regime'),
                  ),
                  // In a card, like `Movements` below it and every list in
                  // Settings. Full-bleed rows put the first line of text 28
                  // under the heading with nothing in between, so this section
                  // opened at a visibly different distance than the one under
                  // it — a card's edge lands at 12 and the row reads from
                  // there.
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: ListCard(
                      inset: Space.lg,
                      children: [
                        for (final s in live)
                          _RegimeRow(summary: s, total: summaries.length),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.section),
                ],
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: Space.gutter),
                  // No second line. What the library is needs no explaining
                  // once the heading above it says `Active regime`, and the
                  // eyebrow already states how many slots are left.
                  child: SectionHeader(
                    'Regime library',
                    // `New` stays, full or not. A control that vanishes at the
                    // limit leaves you looking for the button rather than
                    // reading the reason — the sheet it opens is where the
                    // limit is explained, with nothing in it to pick.
                    actionLabel: summaries.isEmpty ? null : 'New',
                    onAction:
                        summaries.isEmpty ? null : () => _create(context, ref),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: library.isEmpty
                      ? Column(
                          children: [
                            EmptyBox(
                              icon: Icons.tune,
                              message: summaries.isEmpty
                                  ? 'Build your own split, or start from a '
                                      'template and edit it into shape.'
                                  : 'Nothing else yet. A second split can be '
                                      'built without losing the one you are '
                                      'mid-cycle on.',
                            ),
                            if (summaries.isEmpty) ...[
                              const SizedBox(height: Space.lg),
                              PrimaryButton(
                                label: 'Create regime',
                                onPressed: () => createRegimeFlow(context, ref),
                              ),
                            ],
                          ],
                        )
                      : ListCard(
                          inset: Space.lg,
                          children: [
                            for (final s in library)
                              _RegimeRow(summary: s, total: summaries.length),
                          ],
                        ),
                ),
                const SizedBox(height: Space.section),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: SectionHeader('Movements'),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: ListCard(
                    inset: Space.lg,
                    children: [_CatalogRow()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `3 regimes · 3 slots free` — what the page holds, which is the eyebrow's
  /// job on every tab that has one (Workouts prints the date, History the span
  /// it covers).
  ///
  /// Null until the query lands: a header that prints `0 regimes` for one frame
  /// is the same fabricated number rule 4 exists to stop.
  static String? _inventory(List<RegimeSummary>? summaries) {
    if (summaries == null) return null;
    final n = summaries.length;
    final free = identitySlots - n;
    return '$n regime${n == 1 ? '' : 's'} · '
        '${free == 0 ? 'no slots left' : '$free slot${free == 1 ? '' : 's'} free'}';
  }

  /// Builds a regime without switching to it, and says so in the one place a
  /// consequence like that belongs: an offer to switch, rather than a switch
  /// you have to undo.
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = await createRegimeFlow(context, ref, activate: false);
    if (id == null) return;
    messenger.hideCurrentSnackBar();
    showToastOn(
      messenger,
      'Added to the library — still training the old one',
      actionLabel: 'Activate',
      onAction: () => ref.read(regimeRepositoryProvider).setActiveRegime(id),
    );
  }
}

/// The catalog, which belongs to no single regime — which is exactly why it
/// sits out here rather than inside one.
class _CatalogRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(exerciseCatalogProvider).valueOrNull;

    return AppRow(
      icon: Icons.fitness_center_rounded,
      title: 'Exercise catalog',
      subtitle: all == null
          ? 'Every movement, shared by every regime'
          : '${all.length} movement${all.length == 1 ? '' : 's'}, shared by '
              'every regime',
      onTap: () => openExerciseCatalog(context),
    );
  }
}

class _RegimeRow extends ConsumerWidget {
  const _RegimeRow({required this.summary, required this.total});

  final RegimeSummary summary;

  /// The last regime standing can't be deleted — deleting it would drop the app
  /// back to its first-launch state with a full history behind it.
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final regime = summary.regime;

    final facts = [
      '${summary.sessionCount} day${summary.sessionCount == 1 ? '' : 's'}',
      '${summary.workoutCount} logged',
      // Every 6 *what*. The unit is the whole fact here: a cycle is one pass
      // through all the days, not a week, and the bare number read as days.
      if (!regime.deloadEnabled)
        'no deload'
      else if (regime.deloadAfterCycles == 1)
        'deload every cycle'
      else
        'deload every ${regime.deloadAfterCycles} cycles',
    ];

    return AppRow(
      // The identity mark History already scans by, on the row that owns it —
      // the same stack, solid, on every row. A regime is a stack of days
      // whether or not it is the one being trained, and both attempts at
      // marking the active one here (a bolt, then the 16% wash on the rest)
      // said what the `Active regime` heading already says. The wash was also
      // the only translucent fill in the app.
      leading: IconTile(
        Icons.layers_outlined,
        color: c.identityAt(regime.identityIndex),
      ),
      title: regime.name,
      subtitle: facts.join('  ·  '),
      // A tap opens the programme, active or not. Activating one is a decision,
      // not a side effect of looking at it — it lives in the ⋯ sheet.
      onTap: () => openRegimeEditor(context, regime.id),
      // One control, the same width on every row. `Active` is said by the
      // section heading above instead.
      trailing: CircleIconButton(
        icon: Icons.more_horiz_rounded,
        fill: Colors.transparent,
        onTap: () => _showActions(context, ref),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) {
    final active = summary.regime.isActive;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheet) => AppSheet(
        title: summary.regime.name,
        contentPadding: const EdgeInsets.only(bottom: Space.md),
        children: [
          if (!active)
            AppRow(
              icon: Icons.play_circle_outline,
              // Names the state it produces. "Train this one" described the
              // consequence and left you to work out what it did to the row.
              title: 'Activate regime',
              subtitle: 'Workouts run off this programme from now on',
              onTap: () {
                Navigator.of(sheet).pop();
                _activate(context, ref);
              },
            ),
          AppRow(
            icon: Icons.edit_outlined,
            title: 'Rename',
            onTap: () async {
              final navigator = Navigator.of(sheet);
              final taken = await ref
                  .read(regimeRepositoryProvider)
                  .liveNames(exceptId: summary.regime.id);
              if (!context.mounted) return;
              final name = await promptForText(
                context,
                title: 'Rename regime',
                initial: summary.regime.name,
                validate: (value) =>
                    taken.contains(value.trim().toLowerCase())
                        ? 'A regime called ${value.trim()} already exists'
                        : null,
              );
              if (name == null || name.isEmpty) return;
              await ref
                  .read(regimeRepositoryProvider)
                  .updateRegime(summary.regime.id, name: Value(name));
              navigator.pop();
            },
          ),
          AppRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete regime',
            subtitle: total > 1
                ? 'Its days and slots go with it'
                : 'Not the only one — there would be nothing to train',
            tint: total > 1 ? sheet.c.negative : sheet.c.textTertiary,
            onTap: total > 1
                ? () async {
                    final navigator = Navigator.of(sheet);
                    final done = await _delete(context, ref);
                    if (done) navigator.pop();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(regimeRepositoryProvider).setActiveRegime(summary.regime.id);
    showToastOn(messenger, 'Training ${summary.regime.name}');
  }

  Future<bool> _delete(BuildContext context, WidgetRef ref) async {
    final logged = summary.workoutCount;
    final ok = await confirmAction(
      context,
      title: 'Delete ${summary.regime.name}?',
      message: logged == 0
          ? 'Its days and exercise slots go with it. Nothing has been logged '
              'under this regime.'
          : 'Its days and exercise slots go with it.\n\n'
              'The $logged workout${logged == 1 ? '' : 's'} logged under it '
              'stay in History — each one holds its own record of what you '
              'actually did.',
      confirmLabel: 'Delete',
    );
    if (!ok) return false;
    await ref.read(regimeRepositoryProvider).deleteRegime(summary.regime.id);
    return true;
  }
}
