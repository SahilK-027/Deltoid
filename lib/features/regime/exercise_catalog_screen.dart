import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/enums.dart';
import '../log/widgets/exercise_sheets.dart';
import 'regime_screen.dart';

/// Exercises taken out of circulation. Archiving is reversible, so there has to
/// be somewhere to reverse it from — without this the row is simply gone.
final _archivedExercisesProvider = StreamProvider<List<Exercise>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.exercises)
    ..where((t) => t.archived.equals(true) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.name)]);
  return query.watch();
});

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
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final archived = ref.watch(_archivedExercisesProvider).valueOrNull ?? const [];
    final all = _showArchived
        ? archived
        : ref.watch(exerciseCatalogProvider).valueOrNull;
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
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived' : 'Exercises'),
        actions: [
          if (archived.isNotEmpty || _showArchived)
            TextButton(
              onPressed: () => setState(() => _showArchived = !_showArchived),
              child: Text(
                _showArchived ? 'Active' : 'Archived (${archived.length})',
                style: context.t.titleSmall?.copyWith(color: c.accent),
              ),
            ),
          const SizedBox(width: Space.sm),
        ],
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton.extended(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              onPressed: () =>
                  showExerciseEditor(context, initialName: _query.trim()),
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
          else if (filtered.isEmpty && _showArchived)
            const Expanded(
              child: EmptyState(
                icon: Icons.archive_outlined,
                title: 'Nothing archived',
                message: 'Exercises you retire land here, and can come back.',
              ),
            )
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
                          tooltip: _showArchived ? 'Restore' : 'Archive',
                          icon: Icon(
                            _showArchived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                            size: 18,
                          ),
                          onPressed: () => _setArchived(e, !_showArchived),
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
  ///
  /// Reversible in both directions and from both lists — an undo that only
  /// lives as long as a snackbar is not an undo.
  Future<void> _setArchived(Exercise e, bool archived) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(regimeRepositoryProvider);
    await repo.updateExercise(e.id, archived: Value(archived));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${e.name} ${archived ? 'archived' : 'restored'}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              repo.updateExercise(e.id, archived: Value(!archived)),
        ),
      ),
    );
  }
}
