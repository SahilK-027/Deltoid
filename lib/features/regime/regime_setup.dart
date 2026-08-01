import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/regime_repository.dart';
import '../../data/seed/seed_data.dart';
import '../../data/seed/seeder.dart';
import 'regime_screen.dart';

/// Creates a regime: either empty, or pre-filled from one of the templates.
///
/// The templates are starting points, not the app's opinion — every session and
/// slot they write is an ordinary row the user can rename, reorder or delete.
/// Returns the new regime's id, or null if the user backed out.
///
/// [activate] is what makes a shelf of programmes possible. Creating one used
/// to switch to it, always, so building next month's split meant abandoning the
/// one you are mid-cycle on — there was no way to have three and choose. From
/// the Regimes screen it now creates and stays put, and switching is the tap it
/// always was; from an empty app it activates, because there is nothing to
/// leave.
Future<String?> createRegimeFlow(
  BuildContext context,
  WidgetRef ref, {
  bool activate = true,
}) async {
  final template = await showModalBottomSheet<RegimeTemplate>(
    context: context,
    isScrollControlled: true,
    // `SheetHeader` draws its own grab handle, tighter than the framework's.
    showDragHandle: false,
    builder: (_) => const _TemplateSheet(),
  );
  if (template == null || !context.mounted) return null;

  final name = await promptForText(
    context,
    title: 'Name this regime',
    hint: template.isBlank ? 'Upper / Lower' : template.name,
    initial: template.isBlank ? '' : template.name,
  );
  if (name == null) return null;

  final db = ref.read(databaseProvider);
  final trimmed = name.trim();

  if (template.isBlank) {
    return RegimeRepository(db).createRegime(
      trimmed.isEmpty ? 'My regime' : trimmed,
      activate: activate,
    );
  }
  return createRegimeFromTemplate(
    db,
    template,
    name: trimmed,
    activate: activate,
  );
}

/// Choice cards (THEME §7): the one genuinely branching decision this app has
/// — start from a template, or from nothing — as a stack of outlined cards in a
/// sheet rather than the first screen of a wizard. There is no radio and no
/// confirm: picking one *is* the answer, and the next sheet asks the one other
/// question there is.
class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          const SheetHeader(
            title: 'New regime',
            // The sheet says what it will make, before it asks anything (§7).
            subtitle: 'A split you can edit freely afterwards',
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                  Space.gutter, Space.lg, Space.gutter, Space.xl),
              itemCount: regimeTemplates.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.md),
              itemBuilder: (context, i) {
                final t = regimeTemplates[i];
                return AppCard(
                  radius: Radii.lg,
                  outline: BorderSide(color: c.border),
                  onTap: () => Navigator.of(context).pop(t),
                  child: Row(
                    children: [
                      Icon(
                        t.isBlank
                            ? Icons.add_circle_outline_rounded
                            : Icons.dashboard_outlined,
                        size: 28,
                        color: c.textPrimary,
                      ),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name, style: context.t.titleMedium),
                            const SizedBox(height: Space.xxs),
                            Text(t.summary, style: context.t.bodyMedium),
                            if (!t.isBlank) ...[
                              const SizedBox(height: Space.sm),
                              Text(
                                t.sessions.map((s) => s.name).join('  ·  '),
                                style: context.t.bodySmall
                                    ?.copyWith(color: c.textTertiary),
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
