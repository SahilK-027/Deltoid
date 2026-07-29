import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/regime_repository.dart';
import '../log/widgets/exercise_sheets.dart';
import 'regime_screen.dart';

/// Edits one session template: which exercises, in what order, how many sets.
///
/// Changes here affect future workouts only. Past logs hold their own snapshot,
/// so reordering Push 1 today cannot rewrite what Push 1 looked like in March.
class SessionEditorScreen extends ConsumerWidget {
  const SessionEditorScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(sessionSlotsProvider(sessionId)).valueOrNull;
    final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];
    final session = sessions.where((s) => s.id == sessionId).firstOrNull;
    final repo = ref.read(regimeRepositoryProvider);
    final c = context.c;

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.name ?? 'Session'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) async {
              if (value == 'rename') {
                final name = await promptForText(
                  context,
                  title: 'Rename session',
                  initial: session?.name ?? '',
                );
                if (name == null || name.isEmpty) return;
                await repo.renameSession(sessionId, name);
              } else if (value == 'delete') {
                final navigator = Navigator.of(context);
                final ok = await confirmAction(
                  context,
                  title: 'Delete ${session?.name ?? 'this session'}?',
                  message: 'It leaves the cycle, and its exercise slots go '
                      'with it.\n\nWorkouts already logged under this session '
                      'stay in History — they hold their own record of what '
                      'you did.',
                  confirmLabel: 'Delete',
                );
                if (!ok) return;
                await repo.deleteSession(sessionId);
                navigator.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete session')),
            ],
          ),
        ],
      ),
      body: slots == null
          ? const Center(child: CircularProgressIndicator())
          : slots.isEmpty
              ? EmptyState(
                  icon: Icons.fitness_center,
                  title: 'No exercises yet',
                  message: 'Add the movements you do on this day.',
                  action: FilledButton(
                    onPressed: () => _add(context, ref),
                    child: const Text('Add exercise'),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Space.lg, Space.md, Space.lg, Space.huge),
                  buildDefaultDragHandles: false,
                  itemCount: slots.length,
                  onReorder: (oldIndex, newIndex) {
                    var target = newIndex;
                    if (target > oldIndex) target -= 1;
                    final ids = slots.map((s) => s.slot.id).toList();
                    ids.insert(target, ids.removeAt(oldIndex));
                    repo.reorderSessionExercises(ids);
                  },
                  itemBuilder: (context, i) {
                    final entry = slots[i];
                    final reps = entry.slot.targetRepLow == null
                        ? null
                        : entry.slot.targetRepLow == entry.slot.targetRepHigh
                            ? '${entry.slot.targetRepLow}'
                            : '${entry.slot.targetRepLow}–${entry.slot.targetRepHigh}';

                    return Padding(
                      key: ValueKey(entry.slot.id),
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: Space.sm,
                        ),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.only(right: Space.md),
                                child: Icon(Icons.drag_indicator,
                                    color: c.textTertiary, size: 20),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.exercise.name,
                                      style: context.t.titleSmall),
                                  Text(
                                    '${entry.slot.targetSets} sets'
                                    '${reps == null ? '' : ' · $reps reps'}',
                                    style: context.t.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: entry.slot.targetSets > 1
                                  ? () => repo.updateSessionExercise(
                                        entry.slot.id,
                                        targetSets:
                                            Value(entry.slot.targetSets - 1),
                                      )
                                  : null,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: () => repo.updateSessionExercise(
                                entry.slot.id,
                                targetSets: Value(entry.slot.targetSets + 1),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: 'Remove from session',
                              onPressed: () => _remove(
                                context,
                                repo,
                                slotId: entry.slot.id,
                                name: entry.exercise.name,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: slots == null || slots.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
    );
  }

  /// Removing a slot is one tap, so it gets an undo rather than a dialog — the
  /// row is only tombstoned, and putting it back keeps its sets and rep range.
  Future<void> _remove(
    BuildContext context,
    RegimeRepository repo, {
    required String slotId,
    required String name,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await repo.removeSessionExercise(slotId);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$name removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.restoreSessionExercise(slotId),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final exercise = await pickExercise(context, ref);
    if (exercise == null) return;
    await ref
        .read(regimeRepositoryProvider)
        .addExerciseToSession(sessionId, exercise.id);
  }
}
