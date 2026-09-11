import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/toast.dart';
import '../../data/repositories/regime_repository.dart';
import '../../data/seed/seed_data.dart';
import '../../data/seed/seeder.dart';
import '../../domain/enums.dart';
import 'regime_screen.dart';

/// Creates a regime: either empty, or pre-filled from one of the templates.
///
/// The templates are starting points, not the app's opinion — every session and
/// slot they write is an ordinary row the user can rename, reorder or delete.
/// Returns the new regime's id, or null if the user backed out.
///
/// [activate] is what makes a shelf of programmes possible. Creating one and
/// always switching to it means building next month's split abandons the one
/// you are mid-cycle on, with no way to have three and choose. From the Regimes
/// screen this creates and stays put, and switching is its own tap; from an
/// empty app it activates, because there is nothing to leave.
Future<String?> createRegimeFlow(
  BuildContext context,
  WidgetRef ref, {
  bool activate = true,
}) async {
  // Asked before the sheet opens, not after a template and a name have been
  // chosen. A limit you meet at the end of a flow is a flow that wasted your
  // time — but the sheet still opens, saying so, with every option off. Being
  // refused by a control that isn't there teaches nothing.
  final repo = RegimeRepository(ref.read(databaseProvider));
  final full = await repo.nextIdentitySlot() == null;
  if (!context.mounted) return null;

  final template = await showAppSheet<RegimeTemplate>(
    context,
    builder: (_) => _TemplateSheet(full: full),
  );
  if (template == null) return null;

  // The live names, read once for the prompt's validator. Applying the same
  // template twice proposes the same name twice, which is how a shelf of
  // identical `Upper / Lower` rows gets built — the field says so before the
  // sheet will close.
  final taken = await repo.liveNames();
  bool isTaken(String value) => taken.contains(value.trim().toLowerCase());
  if (!context.mounted) return null;

  final proposed = template.isBlank ? '' : template.name;
  final name = await promptForText(
    context,
    title: 'Name this regime',
    hint: template.isBlank ? 'Upper / Lower' : template.name,
    // A template whose own name is already on a regime opens the field empty
    // rather than pre-filled with something that cannot be saved.
    initial: isTaken(proposed) ? '' : proposed,
    validate: (value) => isTaken(value)
        ? 'A regime called ${value.trim()} already exists'
        : null,
  );
  if (name == null || !context.mounted) return null;

  final db = ref.read(databaseProvider);
  // Held rather than reached for after the write: this flow is called from a
  // row that the new regime's own arrival can take off the screen (RULES § 4).
  final messenger = ScaffoldMessenger.of(context);
  final trimmed = name.trim();

  // Both paths below throw by design — a name already taken, the last identity
  // slot gone — and both were called bare. The checks above make that unlikely
  // rather than impossible: `full` and the name validator are read *before the
  // sheet opens*, so the throw is the fallback for exactly the window they
  // cannot cover. Uncaught it takes the whole flow down from inside a gesture
  // handler, which shows as a Create button that does nothing at all.
  try {
    if (template.isBlank) {
      return await repo.createRegime(
        trimmed.isEmpty ? 'My regime' : trimmed,
        activate: activate,
      );
    }
    return await createRegimeFromTemplate(
      db,
      template,
      name: trimmed,
      activate: activate,
    );
  } on RegimeNameTakenException catch (e) {
    showToastOn(messenger, '${e.name} is already taken', destructive: true);
    return null;
  } on RegimeSlotsFullException {
    showToastOn(
      messenger,
      'Delete a regime before creating another',
      destructive: true,
    );
    return null;
  } on BlankNameException {
    showToastOn(messenger, 'A regime needs a name', destructive: true);
    return null;
  }
}

/// One offer: blank, or one of the two templates.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, this.enabled = true});

  final RegimeTemplate template;

  /// Off when the six identity slots are full: the card still says what it
  /// would make, in `textTertiary`, and does nothing.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = template;
    final title = enabled ? null : c.textTertiary;
    final body = enabled ? null : c.textTertiary;

    return AppCard(
      radius: Radii.panel,
      outline: BorderSide(color: c.border),
      onTap: enabled ? () => Navigator.of(context).pop(t) : null,
      child: Row(
        children: [
          Icon(
            t.isBlank
                ? Icons.add_circle_outline_rounded
                : Icons.dashboard_outlined,
            size: 28,
            color: enabled ? c.textPrimary : c.textTertiary,
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    style: context.t.titleMedium?.copyWith(color: title)),
                const SizedBox(height: Space.xxs),
                Text(t.summary,
                    style: context.t.bodyMedium?.copyWith(color: body)),
                if (!t.isBlank) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    t.sessions.map((s) => s.name).join('  ·  '),
                    style:
                        context.t.bodySmall?.copyWith(color: c.textTertiary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Choice cards (THEME → Composing a screen): the one genuinely branching decision this app has
/// — start from a template, or from nothing — as a stack of outlined cards in a
/// sheet rather than the first screen of a wizard. There is no radio and no
/// confirm: picking one *is* the answer, and the next sheet asks the one other
/// question there is.
class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({required this.full});

  /// Every identity slot is taken. The sheet opens anyway and says so, with
  /// nothing in it to pick.
  final bool full;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          SheetHeader(
            title: 'New regime',
            // The sheet says what it will make, before it asks anything (THEME → Composing a screen).
            subtitle: full
                ? 'No template can be created while the regime limit is '
                      'reached'
                : 'A split you can edit freely afterwards',
          ),
          // Scratch first and alone, then the templates under a heading of
          // their own. They are two different offers — "I know what I want" and
          // "show me one" — and run together as an undifferentiated stack of
          // three cards the empty one read as a template of nothing.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.gutter, Space.lg, Space.gutter, Space.xl),
              children: [
                // A notice, not another grey box: with every card below it off,
                // a grey message is one more disabled thing rather than the
                // reason the rest are disabled.
                //
                // The copy states the rule, not its cause. Why the ceiling is
                // six is an implementation detail — an identity colour per
                // regime — and reading it here would tell you nothing you could
                // act on.
                if (full) ...[
                  const NoticeBox(
                    title: 'Regime limit reached',
                    message: 'You can keep up to $identitySlots regimes at a '
                        'time. Delete one to create another.',
                  ),
                  const SizedBox(height: Space.section),
                ],
                for (final t in regimeTemplates)
                  if (t.isBlank) _TemplateCard(template: t, enabled: !full),
                const SizedBox(height: Space.section),
                const SectionHeader('Regime templates'),
                for (final t in regimeTemplates)
                  if (!t.isBlank) ...[
                    _TemplateCard(template: t, enabled: !full),
                    const SizedBox(height: Space.md),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
