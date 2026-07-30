import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/rest_alert.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/ticking.dart';
import '../../data/backup/backup_service.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import '../../domain/prefill.dart';
import '../../domain/units.dart';
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

  /// Set once the current rest has reached zero, so the buzz fires on the
  /// crossing and not on every tick after it. Cleared whenever the rest is
  /// restarted or extended past zero.
  bool _restAlerted = false;

  /// Whether the rest bar is on screen. Separate from [_restStartedAt] on
  /// purpose: the bar goes away shortly after the buzz — counting overtime is
  /// a number nobody acts on — but the start time has to survive, because the
  /// rest a set actually got is measured from it.
  bool _showRestBar = false;
  Timer? _restBarHide;

  /// The display unit for this build. Stored values are always kg.
  WeightUnit _unit = WeightUnit.kg;

  /// Whether the opening exercise's rest target has been fetched yet.
  bool _restTargetLoaded = false;

  /// The keystroke waiting to be written, and its debounce.
  ({EditTarget target, String value})? _pending;
  Timer? _pendingWrite;

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
    // The tick no longer rebuilds the screen. It used to call setState on the
    // whole log — PageView included — once a second whether or not anything on
    // it showed a clock; the two widgets that need one now tick themselves.
    // This is left running only to catch the moment rest reaches zero, which
    // has to fire even with the keypad covering the bar.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _checkRestElapsed();
    });
    // The whole point of this screen is to be put down between sets, so the
    // screen must not lock while a workout is open.
    WakelockPlus.enable().ignore();
    // Load the tone now; the first rest of the session shouldn't be the one
    // that pays for decoding it.
    RestAlert.instance.warmUp().ignore();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _restBarHide?.cancel();
    // Anything typed in the last 300ms still belongs to the log.
    _flushWrite();
    WakelockPlus.disable().ignore();
    RestAlert.instance.release().ignore();
    _pages.dispose();
    super.dispose();
  }

  /// Buzzes once when rest reaches zero. Without this the timer only ever
  /// turns green, which you can't see with the phone face down on a bench.
  void _checkRestElapsed() {
    final startedAt = _restStartedAt;
    if (startedAt == null) {
      _restAlerted = false;
      return;
    }
    final remaining =
        _restTargetSeconds - DateTime.now().difference(startedAt).inSeconds;
    if (remaining > 0) {
      // An extended target puts rest back on the clock, so re-arm the alert.
      _restAlerted = false;
      return;
    }
    if (_restAlerted) return;
    _restAlerted = true;
    RestAlert.instance.fire();
    // Hold the "done" state briefly so picking the phone up right after the
    // buzz still shows what happened, then get out of the way.
    _restBarHide?.cancel();
    _restBarHide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showRestBar = false);
    });
  }

  /// How long the set being completed actually rested, or null when it is the
  /// first set of the exercise and there was nothing to rest from.
  ///
  /// Capped: a set completed forty minutes after the last one is a phone left
  /// on a bench, not a rest interval, and storing it would poison the default
  /// for next week.
  int? _restTakenSeconds() {
    final startedAt = _restStartedAt;
    if (startedAt == null) return null;
    final seconds = DateTime.now().difference(startedAt).inSeconds;
    if (seconds <= 0 || seconds > 1800) return null;
    return seconds;
  }

  /// Loads the rest target for the exercise now on screen.
  ///
  /// Per exercise rather than one number for the session: the target used to
  /// reset to 120 s every time the log opened, which is wrong for a heavy
  /// squat and wrong again for a cable fly.
  Future<void> _loadRestTarget(WorkoutDetail detail, int index) async {
    if (index < 0 || index >= detail.entries.length) return;
    final seconds = await ref.read(trainingRepositoryProvider).restTargetFor(
          exerciseId: detail.entries[index].exercise.id,
          sessionId: detail.workout.sessionId,
        );
    if (!mounted) return;
    setState(() => _restTargetSeconds = seconds);
  }

  void _startRest() {
    _restBarHide?.cancel();
    setState(() {
      _restStartedAt = DateTime.now();
      _restAlerted = false;
      _showRestBar = true;
    });
  }

  /// Nudging the timer sets the target for this exercise, for good: next week
  /// opens on the number you settled on.
  void _adjustRest(WorkoutDetail detail, int delta) {
    final seconds = (_restTargetSeconds + delta).clamp(15, 900).toInt();
    setState(() => _restTargetSeconds = seconds);

    if (detail.entries.isEmpty) return;
    final page = _page.clamp(0, detail.entries.length - 1);
    ref.read(trainingRepositoryProvider).setRestTarget(
          exerciseId: detail.entries[page].exercise.id,
          sessionId: detail.workout.sessionId,
          seconds: seconds,
        );
  }

  void _dismissRestBar() {
    _restBarHide?.cancel();
    setState(() => _showRestBar = false);
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
    // Everything below the database speaks the display unit; everything at or
    // below the repository speaks kilograms.
    _unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final c = context.c;

    // The first page's rest target isn't known until the workout loads.
    if (detail != null && !_restTargetLoaded) {
      _restTargetLoaded = true;
      _loadRestTarget(detail, _page);
    }

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
              // Its own clock, so the session timer advances without the rest
              // of the screen rebuilding behind it once a second.
              Ticking(
                builder: (context) => Text(
                  '${_elapsed(detail.workout.startedAt)}  ·  '
                  '${_doneSets(detail)} of ${_totalSets(detail)} sets',
                  style: context.t.labelMedium,
                ),
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
                          unit: _unit,
                          editing: _editing,
                          buffer: _buffer,
                          onEdit: _focus,
                          rowKeyFor: _rowKey,
                          onToggleDone: _toggleDone,
                          onNextExercise: () => _goToPage(index + 1),
                          onMove: (delta) => _move(detail, index, delta),
                        );
                      },
                    ),
            ),
            if (_showRestBar && _restStartedAt != null && _editing == null)
              RestTimerBar(
                startedAt: _restStartedAt!,
                targetSeconds: _restTargetSeconds,
                onAdjust: (delta) => _adjustRest(detail, delta),
                onDismiss: _dismissRestBar,
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

  /// One key per set row, so the row being typed into can be scrolled back
  /// into view when the keypad takes half the screen.
  final _rowKeys = <String, GlobalKey>{};

  GlobalKey _rowKey(String setId) =>
      _rowKeys.putIfAbsent(setId, GlobalKey.new);

  void _focus(SetLog set, SetField field) {
    _flushWrite();
    setState(() {
      _editing = EditTarget(set.id, field);
      _buffer = switch (field) {
        SetField.weight => _fmtLoadIn(set.weight),
        SetField.added => _fmtLoadIn(set.addedWeight),
        SetField.reps => set.reps?.toString() ?? '',
      };
    });
    _revealRow(set.id);
  }

  /// The keypad is a sibling in the Column, so opening it shrinks the page
  /// under it. Nothing scrolled the active row back, which on an exercise with
  /// five or more sets could leave you typing into a row you cannot see.
  void _revealRow(String setId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _rowKeys[setId]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: Motion.base,
        curve: Motion.curve,
      );
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
    // Ghosts are stored in kg and shown in the display unit.
    final hint = switch (target.field) {
      SetField.weight => _fmtLoadIn(ghost?.weight),
      SetField.added => _fmtLoadIn(ghost?.addedWeight),
      SetField.reps => ghost?.reps?.toString() ?? '',
    };

    final isLast = cells.isNotEmpty && cells.last == target;
    // The key has to name what it does. On a reps field with nothing typed and
    // no ghost to borrow from, "Done" completes nothing at all.
    final needsReps = target.field == SetField.reps &&
        (int.tryParse(_buffer) ?? 0) <= 0 &&
        ghost?.reps == null;

    return SetKeypad(
      title:
          '${entry.exercise.name}  ·  Set ${setPosition + 1}  ·  '
          '${target.field.labelIn(_unit)}',
      field: target.field,
      unit: _unit,
      value: _buffer,
      hint: hint.isEmpty ? null : hint,
      onUseHint: hint.isEmpty ? null : () => _commit(hint, target),
      nextLabel: needsReps
          ? 'Reps?'
          : isLast
              ? 'Done'
              : 'Next',
      onKey: (key) {
        final next = applyKey(
          _buffer,
          key,
          field: target.field,
          unit: _unit,
          hint: double.tryParse(hint),
        );
        _commit(next, target);
      },
      onNext: () => _advance(detail, cells, target),
      onDismiss: () {
        _flushWrite();
        setState(() => _editing = null);
      },
    );
  }

  /// Buffers the keystroke on screen immediately and the write shortly after.
  ///
  /// Every digit used to be its own `updateSet`, and every write re-ran the
  /// three queries behind `watchWorkoutDetail` for the whole workout. Invisible
  /// on a new phone, not on an old one, and it burns battery for an hour a
  /// session. The pending write is flushed on Next, on dismiss, on page turn
  /// and on dispose, so nothing typed can be lost.
  void _commit(String next, EditTarget target) {
    setState(() => _buffer = next);
    _pendingWrite?.cancel();
    _pending = (target: target, value: next);
    _pendingWrite = Timer(const Duration(milliseconds: 300), _flushWrite);
  }

  void _flushWrite() {
    _pendingWrite?.cancel();
    _pendingWrite = null;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;

    final repo = ref.read(trainingRepositoryProvider);
    final typed = double.tryParse(pending.value);
    // Typed in the display unit, stored in kilograms — always.
    final parsed = typed == null ? null : _unit.toKg(typed);

    switch (pending.target.field) {
      case SetField.weight:
        repo.updateSet(pending.target.setId, weight: Value(parsed));
      case SetField.added:
        repo.updateSet(pending.target.setId, addedWeight: Value(parsed));
      case SetField.reps:
        repo.updateSet(pending.target.setId, reps: Value(typed?.round()));
    }
  }

  /// Moves to the next value. Leaving a reps field marks that set complete and
  /// starts the rest clock — the two things you'd otherwise forget to do.
  void _advance(WorkoutDetail detail, List<EditTarget> cells, EditTarget from) {
    _flushWrite();

    if (from.field == SetField.reps) {
      // Read the buffer, not the row: the write for this keystroke may still be
      // in flight, and a stale row would silently skip marking the set done.
      var reps = int.tryParse(_buffer) ?? 0;
      // A weight with no reps used to do nothing at all while the key said
      // "Done": the keypad simply closed. Fall back to last time's reps, which
      // is what adopting the ghost would have written anyway; with no ghost to
      // fall back on the key says "Reps?" and this never runs.
      if (reps <= 0) {
        final located = _locate(detail, from.setId);
        if (located != null) {
          final ghost =
              _ghostSet(_prefill[located.$1.exercise.id], located.$3);
          if (ghost?.reps != null) {
            reps = ghost!.reps!;
            _commit(reps.toString(), from);
            _flushWrite();
          }
        }
      }

      if (reps > 0) {
        _adoptGhost(from.setId);
        ref.read(trainingRepositoryProvider).updateSet(
              from.setId,
              isDone: const Value(true),
              // Rest was already being measured; it was simply thrown away.
              restSeconds: Value(_restTakenSeconds()),
            );
        HapticFeedback.mediumImpact();
        _startRest();
      } else {
        // Nothing to complete the set with: keep the field, keep the keypad.
        return;
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
      _startRest();
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
    _flushWrite();
    _loadRestTarget(detail, index);
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

  /// A stored kg value as the number this phone types in.
  String _fmtLoadIn(double? kg) =>
      kg == null ? '' : formatInUnit(kg, _unit);

}

/// Last time's sets as one line: "22.5×8, 22.5×8, 20×7".
String _summariseSets(PrefillResult prefill, LoadMode mode, WeightUnit unit) {
  final parts = <String>[];
  for (final s in prefill.sets) {
    final load = mode == LoadMode.bodyweightPlus ? s.addedWeight : s.weight;
    final reps = s.reps;
    final loadLabel = switch (mode) {
      LoadMode.bodyweight => 'BW',
      LoadMode.bodyweightPlus =>
        load == null ? 'BW' : 'BW+${formatInUnit(load, unit)}',
      _ => load == null ? '—' : formatInUnit(load, unit),
    };
    parts.add(reps == null ? loadLabel : '$loadLabel×$reps');
  }
  return parts.join(', ');
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
    required this.unit,
    required this.editing,
    required this.buffer,
    required this.onEdit,
    required this.rowKeyFor,
    required this.onToggleDone,
    required this.onNextExercise,
    required this.onMove,
  });

  final int index;
  final int total;
  final ExerciseEntry entry;
  final String? nextName;
  final PrefillResult? prefill;

  /// Display unit for every weight on this page. Storage is always kg.
  final WeightUnit unit;

  final EditTarget? editing;
  final String buffer;
  final void Function(SetLog, SetField) onEdit;
  final GlobalKey Function(String setId) rowKeyFor;
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
                  // The shape of last time's work, in one line. Per-set ghosts
                  // answer "what do I put in this row"; this answers "what did
                  // I actually do", which is the question the app exists for.
                  if (prefill?.hasSuggestion ?? false) ...[
                    const SizedBox(height: 2),
                    Text(
                      _summariseSets(prefill!, entry.exercise.loadMode, unit),
                      style: context.t.labelMedium?.copyWith(
                        color: c.textSecondary,
                        fontFeatures: tabular,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
                    key: rowKeyFor(entry.sets[i].id),
                    set: entry.sets[i],
                    position: i,
                    loadMode: entry.exercise.loadMode,
                    unit: unit,
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
