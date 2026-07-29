import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import 'exercise_history_screen.dart';
import 'history_providers.dart';
import 'history_screen.dart' show formatWeight;

/// One day, exactly as it was logged.
///
/// Reads from the workout's own snapshot rows, so a session that has since been
/// reordered, renamed or gutted still shows what actually happened.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(workoutDetailProvider(workoutId)).valueOrNull;
    final c = context.c;

    if (detail == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final workout = detail.workout;
    final date = dateFromDayKey(workout.dayKey);
    final accent = workout.isDeload ? c.deload : c.accent;

    return Scaffold(
      appBar: AppBar(title: Text(detail.session?.name ?? 'Ad-hoc session')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.sm, Space.lg, Space.huge),
        children: [
          AppCard(
            padding: const EdgeInsets.all(Space.xl),
            highlightColor: workout.isDeload ? c.deload : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(DateFormat('EEEE').format(date).toUpperCase(),
                        style: context.t.labelSmall),
                    const Spacer(),
                    if (workout.isDeload) Pill('Deload', color: c.deload),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(DateFormat('d MMMM yyyy').format(date),
                    style: context.t.displaySmall),
                const SizedBox(height: Space.md),
                Text(
                  _facts(detail).join('  ·  '),
                  style: context.t.bodyMedium?.copyWith(color: accent),
                ),
                if (workout.notes != null && workout.notes!.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  Text(workout.notes!, style: context.t.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.xxl),
          if (detail.entries.isEmpty)
            AppCard(
              child: Text(
                'This workout was finished without anything logged in it.',
                style: context.t.bodySmall,
              ),
            )
          else ...[
            const SectionLabel('What you did'),
            for (final entry in detail.entries) ...[
              _ExerciseBlock(entry: entry),
              const SizedBox(height: Space.sm),
            ],
          ],
        ],
      ),
    );
  }

  static List<String> _facts(WorkoutDetail detail) {
    final sets = detail.entries
        .expand((e) => e.sets)
        .where((s) => s.isDone)
        .length;
    final ended = detail.workout.endedAt;
    final minutes =
        ended == null ? null : (ended - detail.workout.startedAt) ~/ 60000;

    return [
      '${detail.entries.length} exercise'
          '${detail.entries.length == 1 ? '' : 's'}',
      '$sets set${sets == 1 ? '' : 's'}',
      if (minutes != null && minutes >= 0) '$minutes min',
    ];
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({required this.entry});

  final ExerciseEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = entry.sets.where((s) => s.isDone).toList();
    final skipped = entry.workoutExercise.skipReason != SkipReason.none;

    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExerciseHistoryScreen(exerciseId: entry.exercise.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(entry.exercise.name, style: context.t.titleSmall),
              ),
              if (skipped)
                Pill(entry.workoutExercise.skipReason.label, color: c.negative),
              const SizedBox(width: Space.sm),
              Icon(Icons.history, size: 16, color: c.textTertiary),
            ],
          ),
          if (!skipped) ...[
            const SizedBox(height: Space.sm),
            if (done.isEmpty)
              Text('Nothing logged', style: context.t.labelSmall)
            else
              for (final set in done) _SetLine(set: set, exercise: entry.exercise),
          ],
        ],
      ),
    );
  }
}

/// One logged set. Continuation sets (drop, rest-pause) are indented under the
/// set they extend, the same way the log screen shows them.
class _SetLine extends StatelessWidget {
  const _SetLine({required this.set, required this.exercise});

  final SetLog set;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final indent = set.setType.isContinuation;

    return Padding(
      padding: EdgeInsets.only(
        left: indent ? Space.lg : 0,
        top: Space.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              set.setType.shortLabel.isEmpty ? '·' : set.setType.shortLabel,
              style: context.t.labelSmall?.copyWith(
                color: set.setType == SetType.working
                    ? c.textTertiary
                    : c.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_load(set, exercise), style: context.t.labelLarge),
                if (set.note != null && set.note!.isNotEmpty)
                  Text(set.note!, style: context.t.labelSmall),
              ],
            ),
          ),
          Text(
            '${set.reps ?? 0} reps',
            style: context.t.labelMedium?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _load(SetLog set, Exercise exercise) {
    final added = set.addedWeight;
    if (exercise.loadMode == LoadMode.bodyweight) return 'Bodyweight';
    if (exercise.loadMode == LoadMode.bodyweightPlus) {
      return added == null || added == 0
          ? 'Bodyweight'
          : 'BW + ${formatWeight(added)} kg';
    }
    final weight = set.weight;
    if (weight == null) return '—';
    final perSide = exercise.loadMode == LoadMode.perSide ? ' × 2' : '';
    return '${formatWeight(weight)} kg$perSide';
  }
}
