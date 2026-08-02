import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/enums.dart';
import '../log/widgets/exercise_sheets.dart';
import 'exercise_screen.dart';

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
/// Separate from the day it is used in on purpose: adding a movement you own is
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

  /// Null is `All`. One muscle at a time: this is a filter for finding a
  /// movement, not a report — two selected muscles answer no question a single
  /// search box doesn't answer faster.
  MuscleGroup? _muscle;

  @override
  Widget build(BuildContext context) {
    final archived =
        ref.watch(_archivedExercisesProvider).valueOrNull ?? const [];
    final all = _showArchived
        ? archived
        : ref.watch(exerciseCatalogProvider).valueOrNull;
    final c = context.c;
    final q = _query.trim().toLowerCase();

    final filtered = all == null
        ? const <Exercise>[]
        : all.where((e) {
            if (_muscle != null && e.muscle != _muscle) return false;
            if (q.isEmpty) return true;
            return e.name.toLowerCase().contains(q) ||
                e.muscle.label.toLowerCase().contains(q) ||
                e.equipment.label.toLowerCase().contains(q);
          }).toList();

    // Only the muscles something is actually filed under, in `MuscleGroup`
    // order so a chip keeps its position as the catalog grows (§5, muscle bars).
    final present = all == null
        ? const <MuscleGroup>[]
        : [
            for (final m in MuscleGroup.values)
              if (all.any((e) => e.muscle == m)) m,
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived' : 'Exercises'),
        actions: [
          if (archived.isNotEmpty || _showArchived)
            IconButton(
              tooltip: _showArchived ? 'Active exercises' : 'Archived',
              icon: Icon(
                _showArchived
                    ? Icons.inventory_2_outlined
                    : Icons.archive_outlined,
              ),
              onPressed: () => setState(() {
                _showArchived = !_showArchived;
                _muscle = null;
              }),
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: searchFieldPadding,
            child: SearchField(
              hint: 'Search exercises',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // The row bleeds off the right edge — the clipped chip is the scroll
          // affordance (§5).
          if (present.length > 1)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.md,
                ),
                children: [
                  AppChip(
                    label: 'All',
                    selected: _muscle == null,
                    onTap: () => setState(() => _muscle = null),
                  ),
                  for (final m in present) ...[
                    const SizedBox(width: Space.sm),
                    AppChip(
                      label: m.label,
                      selected: _muscle == m,
                      onTap: () =>
                          setState(() => _muscle = _muscle == m ? null : m),
                    ),
                  ],
                ],
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
                action: PrimaryButton(
                  label: q.isEmpty ? 'Add exercise' : 'Create "$q"',
                  onPressed: () =>
                      createExerciseFlow(context, initialName: _query.trim()),
                ),
              ),
            )
          else
            Expanded(
              // Full-bleed rows under the search, the way the exercise index in
              // History is built: a card per movement made a list of eighty
              // into eighty boxes.
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: Space.lg),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                itemBuilder: (context, i) {
                  final e = filtered[i];
                  return AppRow(
                    title: e.name,
                    subtitle:
                        '${e.muscle.label} · ${e.equipment.label} · '
                        '${loadModeLabel(e.loadMode)}',
                    chevron: true,
                    onTap: () => openExercise(context, exerciseId: e.id),
                  );
                },
              ),
            ),
          if (!_showArchived)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Space.md,
              ),
              child: SafeArea(
                top: false,
                child: PrimaryButton(
                  label: 'New exercise',
                  icon: Icons.add_rounded,
                  onPressed: () =>
                      createExerciseFlow(context, initialName: _query.trim()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The short form, for a row that has already said the muscle and the kit.
String loadModeLabel(LoadMode mode) => switch (mode) {
  LoadMode.total => 'total load',
  LoadMode.perSide => 'per side',
  LoadMode.bodyweight => 'bodyweight',
  LoadMode.bodyweightPlus => 'bodyweight +',
};
