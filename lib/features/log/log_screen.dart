import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/backup/backup_service.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import '../../domain/prefill.dart';
import 'log_providers.dart';
import 'widgets/exercise_rail.dart';
import 'widgets/exercise_sheets.dart';
import 'widgets/rest_timer.dart';
import 'widgets/set_row.dart';

/// Which value the keypad is currently editing.
class EditTarget {
  const EditTarget(this.setId, this.field);

  final String setId;
  final SetField field;

  @override
  bool operator ==(Object other) =>
      other is EditTarget && other.setId == setId && other.field == field;

  @override
  int get hashCode => Object.hash(setId, field);
}

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key, required this.workoutId});

  final String workoutId;

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  EditTarget? _editing;
  String _buffer = '';
  Timer? _clock;
  DateTime? _restStartedAt;
  int _restTargetSeconds = 120;

  // Latest build's data, so callbacks can resolve a set's ghost values without
  // threading them through every widget.
  Map<String, PrefillResult> _prefill = const {};
  WorkoutDetail? _detail;

  /// One exercise per page. Scrolling a long vertical stack mid-set was the
  /// thing this replaces: you only ever care about the movement in front of
  /// you, and the rail above keeps the rest of the session in view.
  final _pages = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // One second tick drives both the session elapsed time and the rest timer.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref
        .watch(workoutDetailProvider(widget.workoutId))
        .valueOrNull;
    final prefill =
        ref.watch(workoutPrefillProvider(widget.workoutId)).valueOrNull ??
        const {};
    _prefill = prefill;
    _detail = detail;
    final c = context.c;

    if (detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cells = _buildCells(detail);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back dismisses the keypad first: it covers half the screen, and
        // losing the whole session to one stray swipe would be unforgivable.
        if (_editing != null) {
          setState(() => _editing = null);
          return;
        }
        // Leaving without finishing is fine — the session keeps running and
        // survives a force-stop — but it has to be said out loud, or the sets
        // logged so far look lost.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session still running — resume it from Today'),
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      detail.session?.name ?? 'Workout',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (detail.workout.isDeload) ...[
                    const SizedBox(width: Space.sm),
                    Pill('Deload', color: c.deload),
                  ],
                ],
              ),
              Text(
                '${_elapsed(detail.workout.startedAt)}  ·  '
                '${_doneSets(detail)} of ${_totalSets(detail)} sets',
                style: context.t.labelMedium,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _finish(detail),
              child: Text(
                'Finish',
                style: context.t.titleSmall?.copyWith(color: c.accent),
              ),
            ),
            const SizedBox(width: Space.sm),
          ],
        ),
        body: Column(
          children: [
            ExerciseRail(
              entries: detail.entries,
              current: _page.clamp(0, math.max(0, detail.entries.length - 1)),
              onSelect: _goToPage,
              onAdd: () => _addExercise(detail),
            ),
            Expanded(
              child: detail.entries.isEmpty
                  ? EmptyState(
                      icon: Icons.fitness_center,
                      title: 'No exercises',
                      message: 'Add one to start logging.',
                      action: FilledButton(
                        onPressed: () => _addExercise(detail),
                        child: const Text('Add exercise'),
                      ),
                    )
                  : PageView.builder(
                      controller: _pages,
                      itemCount: detail.entries.length,
                      onPageChanged: (i) => _onPageChanged(detail, i),
                      itemBuilder: (context, index) {
                        final entry = detail.entries[index];
                        return _ExercisePage(
                          key: ValueKey(entry.workoutExercise.id),
                          index: index,
                          total: detail.entries.length,
                          entry: entry,
                          nextName: index + 1 < detail.entries.length
                              ? detail.entries[index + 1].exercise.name
                              : null,
                          prefill: prefill[entry.exercise.id],
                          editing: _editing,
                          buffer: _buffer,
                          onEdit: _focus,
                          onToggleDone: _toggleDone,
                          onNextExercise: () => _goToPage(index + 1),
                          onMove: (delta) => _move(detail, index, delta),
                        );
                      },
                    ),
            ),
            if (_restStartedAt != null && _editing == null)
              RestTimerBar(
                startedAt: _restStartedAt!,
                targetSeconds: _restTargetSeconds,
                onAdjust: (delta) => setState(
                  () => _restTargetSeconds = (_restTargetSeconds + delta).clamp(
                    15,
                    900,
                  ),
                ),
                onDismiss: () => setState(() => _restStartedAt = null),
              ),
            if (_editing != null) _keypad(detail, prefill, cells),
          ],
        ),
      ),
    );
  }

  // ── Keypad plumbing ───────────────────────────────────────────────────

  /// Every editable value in the workout, in the order a person fills them in.
  /// Drives the keypad's "Next" so the whole session can be logged without
  /// lifting a thumb.
  List<EditTarget> _buildCells(WorkoutDetail detail) {
    final cells = <EditTarget>[];
    for (final entry in detail.entries) {
      if (entry.workoutExercise.skipReason != SkipReason.none) continue;
      for (final set in entry.sets) {
        switch (entry.exercise.loadMode) {
          case LoadMode.bodyweight:
            break;
          case LoadMode.bodyweightPlus:
            cells.add(EditTarget(set.id, SetField.added));
          case LoadMode.total:
          case LoadMode.perSide:
            cells.add(EditTarget(set.id, SetField.weight));
        }
        cells.add(EditTarget(set.id, SetField.reps));
      }
    }
    return cells;
  }

  void _focus(SetLog set, SetField field) {
    setState(() {
      _editing = EditTarget(set.id, field);
      _buffer = switch (field) {
        SetField.weight => _fmt(set.weight),
        SetField.added => _fmt(set.addedWeight),
        SetField.reps => set.reps?.toString() ?? '',
      };
    });
  }

  Widget _keypad(
    WorkoutDetail detail,
    Map<String, PrefillResult> prefill,
    List<EditTarget> cells,
  ) {
    final target = _editing!;
    final located = _locate(detail, target.setId);
    if (located == null) return const SizedBox.shrink();

    final (entry, set, setPosition) = located;
    final ghost = _ghostSet(prefill[entry.exercise.id], setPosition);
    final hint = switch (target.field) {
      SetField.weight => _fmt(ghost?.weight),
      SetField.added => _fmt(ghost?.addedWeight),
      SetField.reps => ghost?.reps?.toString() ?? '',
    };

    final isLast = cells.isNotEmpty && cells.last == target;

    return SetKeypad(
      title:
          '${entry.exercise.name}  ·  Set ${setPosition + 1}  ·  '
          '${target.field.label}',
      field: target.field,
      value: _buffer,
      hint: hint.isEmpty ? null : hint,
      onUseHint: hint.isEmpty ? null : () => _commit(hint, target),
      nextLabel: isLast ? 'Done' : 'Next',
      onKey: (key) {
        final next = applyKey(_buffer, key, field: target.field);
        _commit(next, target);
      },
      onNext: () => _advance(detail, cells, target),
      onDismiss: () => setState(() => _editing = null),
    );
  }

  void _commit(String next, EditTarget target) {
    setState(() => _buffer = next);
    final repo = ref.read(trainingRepositoryProvider);
    final parsed = double.tryParse(next);

    switch (target.field) {
      case SetField.weight:
        repo.updateSet(target.setId, weight: Value(parsed));
      case SetField.added:
        repo.updateSet(target.setId, addedWeight: Value(parsed));
      case SetField.reps:
        repo.updateSet(target.setId, reps: Value(parsed?.round()));
    }
  }

  /// Moves to the next value. Leaving a reps field marks that set complete and
  /// starts the rest clock — the two things you'd otherwise forget to do.
  void _advance(WorkoutDetail detail, List<EditTarget> cells, EditTarget from) {
    if (from.field == SetField.reps) {
      // Read the buffer, not the row: the write for this keystroke may still be
      // in flight, and a stale row would silently skip marking the set done.
      final typedReps = int.tryParse(_buffer) ?? 0;
      if (typedReps > 0) {
        _adoptGhost(from.setId);
        ref
            .read(trainingRepositoryProvider)
            .updateSet(from.setId, isDone: const Value(true));
        HapticFeedback.mediumImpact();
        setState(() => _restStartedAt = DateTime.now());
      }
    }

    final index = cells.indexOf(from);
    if (index < 0 || index + 1 >= cells.length) {
      setState(() => _editing = null);
      return;
    }

    final next = cells[index + 1];
    final located = _locate(detail, next.setId);
    if (located == null) {
      setState(() => _editing = null);
      return;
    }

    // Walking off the end of an exercise turns the page with you.
    final page = _pageOf(detail, next.setId);
    if (page >= 0 && page != _page) {
      _goToPage(page);
    }

    _focus(located.$2, next.field);
  }

  (ExerciseEntry, SetLog, int)? _locate(WorkoutDetail detail, String setId) {
    for (final entry in detail.entries) {
      for (var i = 0; i < entry.sets.length; i++) {
        if (entry.sets[i].id == setId) return (entry, entry.sets[i], i);
      }
    }
    return null;
  }

  // ── Mutations ─────────────────────────────────────────────────────────

  void _toggleDone(SetLog set, bool done) {
    if (done) _adoptGhost(set.id);
    ref.read(trainingRepositoryProvider).updateSet(set.id, isDone: Value(done));
    if (done) {
      HapticFeedback.mediumImpact();
      setState(() => _restStartedAt = DateTime.now());
    }
  }

  /// Completes a set's blanks from last time's numbers.
  ///
  /// Typing only the reps is the normal case — same weight as last week, one
  /// more rep. Without this the set would be stored as reps against a null
  /// load: invisible to the progress chart, and unable to register as a PR.
  void _adoptGhost(String setId) {
    final detail = _detail;
    if (detail == null) return;
    final located = _locate(detail, setId);
    if (located == null) return;

    final (entry, set, position) = located;
    final ghost = _ghostSet(_prefill[entry.exercise.id], position);
    if (ghost == null) return;

    final repo = ref.read(trainingRepositoryProvider);
    switch (entry.exercise.loadMode) {
      case LoadMode.bodyweightPlus:
        if (set.addedWeight == null && ghost.addedWeight != null) {
          repo.updateSet(setId, addedWeight: Value(ghost.addedWeight));
        }
      case LoadMode.total:
      case LoadMode.perSide:
        if (set.weight == null && ghost.weight != null) {
          repo.updateSet(setId, weight: Value(ghost.weight));
        }
      case LoadMode.bodyweight:
        break;
    }
    if (set.reps == null && ghost.reps != null) {
      repo.updateSet(setId, reps: Value(ghost.reps));
    }
  }

  // ── Paging ────────────────────────────────────────────────────────────

  void _goToPage(int index) {
    final detail = _detail;
    if (detail == null) return;
    final target = index.clamp(0, detail.entries.length - 1);
    if (!_pages.hasClients) {
      setState(() => _page = target);
      return;
    }
    _pages.animateToPage(target, duration: Motion.base, curve: Motion.curve);
  }

  /// Which page an exercise sits on, or -1 if the set is not in the workout.
  int _pageOf(WorkoutDetail detail, String setId) {
    for (var i = 0; i < detail.entries.length; i++) {
      if (detail.entries[i].sets.any((s) => s.id == setId)) return i;
    }
    return -1;
  }

  void _onPageChanged(WorkoutDetail detail, int index) {
    setState(() {
      _page = index;
      // Turning the page by hand away from the value being typed dismisses the
      // keypad; the keypad's own "Next" lands on this page and keeps it open.
      final editing = _editing;
      if (editing != null && _pageOf(detail, editing.setId) != index) {
        _editing = null;
      }
    });
  }

  /// Moves an exercise one place earlier or later, following it with the page
  /// so the movement you were looking at stays in front of you.
  void _move(WorkoutDetail detail, int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= detail.entries.length) return;

    final ids = detail.entries.map((e) => e.workoutExercise.id).toList();
    ids.insert(target, ids.removeAt(index));
    ref.read(trainingRepositoryProvider).reorderWorkoutExercises(ids);
    _goToPage(target);
  }

  Future<void> _addExercise(WorkoutDetail detail) async {
    final exercise = await pickExercise(context, ref);
    if (exercise == null) return;
    await ref
        .read(trainingRepositoryProvider)
        .addExerciseToWorkout(detail.workout.id, exercise.id);
    // Land on the exercise that was just added rather than leaving it
    // somewhere off the end of the rail.
    _goToPage(detail.entries.length);
  }

  Future<void> _finish(WorkoutDetail detail) async {
    final done = _doneSets(detail);
    final navigator = Navigator.of(context);
    final repo = ref.read(trainingRepositoryProvider);

    if (done == 0) {
      final discard = await confirmAction(
        context,
        title: 'Nothing logged',
        message: 'No sets were completed. Discard this session?',
        confirmLabel: 'Discard',
        cancelLabel: 'Keep logging',
      );
      if (!discard) return;
      await repo.abandonWorkout(detail.workout.id);
      navigator.pop();
      return;
    }

    // Finishing early is allowed — life gets in the way, and an app that
    // refuses to close a session is an app you stop logging in. It does have to
    // be deliberate, though: unfinished sets are dropped on the way out, and
    // whatever is left blank never happened as far as next week is concerned.
    final unfinished = _unfinished(detail);
    if (unfinished.isNotEmpty) {
      final total = _totalSets(detail);
      final ok = await confirmAction(
        context,
        title: 'Finish with sets left?',
        message: '$done of $total sets logged.\n\n'
            '${unfinished.map((e) => '· $e').join('\n')}\n\n'
            'The empty sets are discarded — the session is saved with exactly '
            'what you did.',
        confirmLabel: 'Finish anyway',
        cancelLabel: 'Keep logging',
        destructive: false,
      );
      if (!ok) return;
    }

    await repo.completeWorkout(detail.workout.id);

    // Silent rolling snapshot. Finishing a session is the only moment the app
    // reliably has new data and idle time, so it is where the safety net gets
    // refreshed — failures here must never block leaving the screen.
    unawaited(
      BackupService(ref.read(databaseProvider)).autoExport().catchError((_) {}),
    );

    navigator.pop();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static int _doneSets(WorkoutDetail d) =>
      d.entries.expand((e) => e.sets).where((s) => s.isDone).length;

  /// Exercises with sets still open, named and counted. Skipped ones are
  /// deliberately absent: a skip is a decision already recorded, not an
  /// omission to be nagged about.
  static List<String> _unfinished(WorkoutDetail d) {
    final out = <String>[];
    for (final entry in d.entries) {
      if (entry.workoutExercise.skipReason != SkipReason.none) continue;
      final total = entry.sets.length;
      final done = entry.sets.where((s) => s.isDone).length;
      if (total == 0 || done == total) continue;
      out.add('${entry.exercise.name} — $done of $total sets');
    }
    return out;
  }

  static int _totalSets(WorkoutDetail d) =>
      d.entries.expand((e) => e.sets).length;

  static String _elapsed(int startedAtMs) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      startedAtMs,
      isUtc: true,
    ).toLocal();
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }
}

/// Prefill set aligned to a position in the current exercise, or null when
/// today has more sets than last time.
PastSet? _ghostSet(PrefillResult? prefill, int index) {
  if (prefill == null || index >= prefill.sets.length) return null;
  return prefill.sets[index];
}

/// A single exercise, filling the screen.
///
/// The session used to be one long vertical stack, which meant scrolling past
/// finished work to reach the set in front of you. One exercise per page keeps
/// the thing you are actually doing at a fixed place on screen.
class _ExercisePage extends ConsumerWidget {
  const _ExercisePage({
    super.key,
    required this.index,
    required this.total,
    required this.entry,
    required this.nextName,
    required this.prefill,
    required this.editing,
    required this.buffer,
    required this.onEdit,
    required this.onToggleDone,
    required this.onNextExercise,
    required this.onMove,
  });

  final int index;
  final int total;
  final ExerciseEntry entry;
  final String? nextName;
  final PrefillResult? prefill;
  final EditTarget? editing;
  final String buffer;
  final void Function(SetLog, SetField) onEdit;
  final void Function(SetLog, bool) onToggleDone;
  final VoidCallback onNextExercise;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final skipped = entry.workoutExercise.skipReason != SkipReason.none;
    final done = entry.sets.where((s) => s.isDone).length;
    final allDone = entry.sets.isNotEmpty && done == entry.sets.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.huge,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EXERCISE ${index + 1} OF $total',
                    style: context.t.labelSmall,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    entry.exercise.name,
                    style: context.t.titleLarge?.copyWith(
                      color: skipped ? c.textTertiary : c.textPrimary,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  _PrefillCaption(prefill: prefill),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () => showExerciseMenu(
                context,
                ref,
                entry,
                index: index,
                total: total,
                onMove: onMove,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        if (skipped)
          AppCard(
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline, size: 18, color: c.negative),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'Skipped — ${entry.workoutExercise.skipReason.label.toLowerCase()}',
                    style: context.t.bodySmall?.copyWith(color: c.negative),
                  ),
                ),
              ],
            ),
          )
        else ...[
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Column(
              children: [
                for (var i = 0; i < entry.sets.length; i++)
                  SetRow(
                    set: entry.sets[i],
                    position: i,
                    loadMode: entry.exercise.loadMode,
                    ghost: _ghostSet(prefill, i),
                    editing: editing,
                    buffer: buffer,
                    onEdit: onEdit,
                    onToggleDone: onToggleDone,
                    onOpenActions: () =>
                        showSetActions(context, ref, entry.sets[i], i),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    0,
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                          ),
                          minimumSize: const Size(0, 36),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add set'),
                        onPressed: () => ref
                            .read(trainingRepositoryProvider)
                            .addSet(entry.workoutExercise.id),
                      ),
                      const Spacer(),
                      Text(
                        '$done of ${entry.sets.length} done',
                        style: context.t.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (entry.exercise.notes != null) ...[
            const SizedBox(height: Space.lg),
            Text(entry.exercise.notes!, style: context.t.bodySmall),
          ],
        ],
        if (nextName != null) ...[
          const SizedBox(height: Space.xxl),
          // Moving on early is allowed — supersets and busy racks are normal —
          // but it should never be silent. The rail keeps the count; this says
          // it in words at the moment you are about to leave.
          if (!allDone && !skipped && entry.sets.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: c.textTertiary),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    '${entry.sets.length - done} set'
                    '${entry.sets.length - done == 1 ? '' : 's'} still open '
                    'here — you can come back to them.',
                    style: context.t.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
          ],
          // Turning the page works too; this is the discoverable version, and
          // it lights up once the exercise is actually finished.
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: allDone || skipped ? c.accent : c.textSecondary,
              side: BorderSide(color: allDone || skipped ? c.accent : c.border),
            ),
            onPressed: onNextExercise,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Next: $nextName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.sm),
                const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PrefillCaption extends StatelessWidget {
  const _PrefillCaption({required this.prefill});

  final PrefillResult? prefill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = prefill;
    if (p == null || !p.hasSuggestion) {
      return Text('First time — no previous log', style: context.t.labelSmall);
    }

    final ref = p.reference!;
    final date = DateFormat('d MMM').format(dateFromDayKey(ref.dayKey));

    final (text, color) = switch (p.source) {
      PrefillSource.sameSession => ('Last time · $date', c.textTertiary),
      PrefillSource.sameSessionDeload => (
        'Last time · $date · deload week',
        c.deload,
      ),
      PrefillSource.otherSession => (
        'From ${ref.sessionName} · $date',
        c.deload,
      ),
      PrefillSource.none => ('', c.textTertiary),
    };

    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: context.t.labelSmall?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (p.deloadApplied) ...[
          const SizedBox(width: Space.sm),
          Text(
            '· scaled',
            style: context.t.labelSmall?.copyWith(color: c.deload),
          ),
        ],
      ],
    );
  }
}
