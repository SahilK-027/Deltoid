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
Future<String?> createRegimeFlow(BuildContext context, WidgetRef ref) async {
  final template = await showModalBottomSheet<RegimeTemplate>(
    context: context,
    isScrollControlled: true,
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
    );
  }
  return createRegimeFromTemplate(db, template, name: trimmed);
}

class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text('New regime', style: context.t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
              child: Text(
                'Start empty, or from a split you can edit freely afterwards. '
                'Each session keeps its own progression.',
                style: context.t.bodySmall,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, 0, Space.lg, Space.xl),
                itemCount: regimeTemplates.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                itemBuilder: (context, i) {
                  final t = regimeTemplates[i];
                  return AppCard(
                    padding: const EdgeInsets.all(Space.lg),
                    onTap: () => Navigator.of(context).pop(t),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: context.t.titleSmall),
                              const SizedBox(height: Space.xs),
                              Text(t.summary, style: context.t.bodySmall),
                              if (!t.isBlank) ...[
                                const SizedBox(height: Space.sm),
                                Text(
                                  t.sessions.map((s) => s.name).join('  ·  '),
                                  style: context.t.labelSmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
