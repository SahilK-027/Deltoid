import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/enums.dart';
import '../log/widgets/exercise_sheets.dart';
import 'regime_screen.dart';

/// The exercise catalog, shared by every regime.
///
/// Separate from the session editor on purpose: adding a movement you own is
/// not the same act as putting it in a training day, and a gym that has a
/// machine no app has heard of shouldn't force you into a session first.
class ExerciseCatalogScreen extends ConsumerStatefulWidget {
  const ExerciseCatalogScreen({super.key});

  @override
  ConsumerState<ExerciseCatalogScreen> createState() =>
      _ExerciseCatalogScreenState();
}

class _ExerciseCatalogScreenState extends ConsumerState<ExerciseCatalogScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exerciseCatalogProvider).valueOrNull;
    final c = context.c;
    final q = _query.trim().toLowerCase();
    final filtered = all == null
        ? const <Exercise>[]
        : q.isEmpty
            ? all
            : all
                .where((e) =>
                    e.name.toLowerCase().contains(q) ||
                    e.muscle.label.toLowerCase().contains(q) ||
                    e.equipment.label.toLowerCase().contains(q))
                .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        onPressed: () => showExerciseEditor(context, initialName: _query.trim()),
        icon: const Icon(Icons.add),
        label: const Text('New exercise'),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search exercises',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: c.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (all == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            Expanded(
              child: EmptyState(
                icon: Icons.fitness_center,
                title: q.isEmpty ? 'No exercises yet' : 'Nothing matches',
                message: q.isEmpty
                    ? 'Add the movements you train.'
                    : 'Create it and it is available everywhere.',
                action: FilledButton(
                  onPressed: () =>
                      showExerciseEditor(context, initialName: _query.trim()),
                  child: Text(q.isEmpty ? 'Add exercise' : 'Create "$q"'),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, 0, Space.lg, Space.huge),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                itemBuilder: (context, i) {
                  final e = filtered[i];
                  return AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.md,
                    ),
                    onTap: () => showExerciseEditor(context, existing: e),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.name, style: context.t.titleSmall),
                              const SizedBox(height: Space.xs),
                              Text(
                                '${e.muscle.label} · ${e.equipment.label} · '
                                '${_loadModeLabel(e)}',
                                style: context.t.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Archive',
                          icon: const Icon(Icons.archive_outlined, size: 18),
                          onPressed: () => _archive(e),
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

  static String _loadModeLabel(Exercise e) => switch (e.loadMode) {
        LoadMode.total => 'total load',
        LoadMode.perSide => 'per side',
        LoadMode.bodyweight => 'bodyweight',
        LoadMode.bodyweightPlus => 'bodyweight +',
      };

  /// Archive rather than delete: past workouts point at this row, and history
  /// with a hole in it is worse than a catalog with one extra entry.
  Future<void> _archive(Exercise e) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(regimeRepositoryProvider)
        .updateExercise(e.id, archived: const Value(true));
    messenger.showSnackBar(
      SnackBar(
        content: Text('${e.name} archived'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => ref
              .read(regimeRepositoryProvider)
              .updateExercise(e.id, archived: const Value(false)),
        ),
      ),
    );
  }
}
