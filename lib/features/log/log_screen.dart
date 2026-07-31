import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/foundation.dart';
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

  /// The keypad's in-progress text, held in a notifier rather than in state.
  ///
  /// It used to be a plain field passed down as a widget parameter, so every
  /// digit rebuilt the exercise page and every SetRow on it — the largest
  /// rebuild in the app, on its most frequent interaction. Only the cell being
  /// typed into and the keypad's own readout listen now.
  final _buffer = ValueNotifier<String>('');

  /// The set row currently swiped open, if any. Shared by every row on the
  /// screen so that opening one closes the last — two rows sitting open at once
  /// makes the next tap a guess.
  final _openSwipe = ValueNotifier<String?>(null);
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

  /// A page to land on as soon as the workout comes back holding it.
  ///
  /// [_goToPage] can only reach a page that exists in the build it runs in, and
  /// an exercise added a moment ago is not in one yet — the write has been made,
  /// the watched query has not returned. Adding an exercise therefore landed on
  /// the last of the *old* pages, which is the one it was already on.
  int? _wantedPage;

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
    _buffer.dispose();
    _openSwipe.dispose();
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
    final seconds = await ref
        .read(trainingRepositoryProvider)
        .restTargetFor(
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
  Future<void> _adjustRest(WorkoutDetail detail, int delta) async {
    final seconds = (_restTargetSeconds + delta).clamp(15, 900).toInt();
    setState(() => _restTargetSeconds = seconds);

    if (detail.entries.isEmpty) return;
    final page = _page.clamp(0, detail.entries.length - 1);
    final entry = detail.entries[page];
    final saved = await ref
        .read(trainingRepositoryProvider)
        .setRestTarget(
          exerciseId: entry.exercise.id,
          sessionId: detail.workout.sessionId,
          seconds: seconds,
        );

    // An exercise added mid-session has no slot in the template to hold this,
    // so the write matches nothing. Silently forgetting it is worse than
    // saying so: the timer would simply be back at 120s next week.
    if (saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Rest set for today. ${entry.exercise.name} is not in this '
          'session\'s template, so it will not be remembered.',
        ),
        duration: const Duration(seconds: 4),
      ),
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

    // The first page's rest target isn't known until the workout loads.
    if (detail != null && !_restTargetLoaded) {
      _restTargetLoaded = true;
      _loadRestTarget(detail, _page);
    }

    if (detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final wanted = _wantedPage;
    if (wanted != null && wanted < detail.entries.length) {
      _wantedPage = null;
      // After the frame: the PageView is being built with this exercise in it
      // right now, and animating to a page that does not exist yet does
      // nothing at all.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToPage(wanted);
      });
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
        body: Column(
          children: [
            _LogTopBar(
              title: detail.session?.name ?? 'Workout',
              isDeload: detail.workout.isDeload,
              startedAt: detail.workout.startedAt,
              done: _doneSets(detail),
              total: _totalSets(detail),
              onBack: () => Navigator.of(context).maybePop(),
              onFinish: () => _finish(detail),
            ),
            // No rail with nothing in it. An empty workout left a 68dp band of
            // nothing across the screen with one `+` floating at the far right
            // of it — a second, orphaned way to do exactly what the button in
            // the middle of the empty state does.
            if (detail.entries.isNotEmpty)
              ExerciseRail(
                entries: detail.entries,
                current: _page.clamp(0, detail.entries.length - 1),
                onSelect: _goToPage,
                onAdd: () => _addExercise(detail),
                onReorder: (ids) => ref
                    .read(trainingRepositoryProvider)
                    .reorderWorkoutExercises(ids),
              ),
            Expanded(
              child: detail.entries.isEmpty
                  // Two words and a full stop, where every other empty state in
                  // the app says what will appear here and what it costs you.
                  // The thing worth saying is that adding one here is a change
                  // to today and not to the programme.
                  ? EmptyState(
                      icon: Icons.fitness_center_rounded,
                      title: 'Nothing to log yet',
                      message:
                          'This session has no exercises in it. Add one and it '
                          'goes into today only — the template keeps its own '
                          'list.',
                      action: PrimaryButton(
                        label: 'Add an exercise',
                        onPressed: () => _addExercise(detail),
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
                          openSwipe: _openSwipe,
                          onEdit: _focus,
                          rowKeyFor: _rowKey,
                          onToggleDone: _toggleDone,
                          onNextExercise: () => _goToPage(index + 1),
                          onMove: (delta) => _move(detail, index, delta),
                        );
                      },
                    ),
            ),
            // Every set ticked: the only thing left to do is end the session,
            // so it stops being a text action in the corner and becomes the
            // one white button on the screen. Finishing early is still
            // possible from the top bar — it just isn't advertised.
            if (_editing != null ||
                _totalSets(detail) == 0 ||
                _doneSets(detail) < _totalSets(detail))
              const SizedBox.shrink()
            else
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.md,
                  Space.gutter,
                  Space.md,
                ),
                child: PrimaryButton(
                  label: 'Finish session',
                  onPressed: () => _finish(detail),
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

  GlobalKey _rowKey(String setId) => _rowKeys.putIfAbsent(setId, GlobalKey.new);

  void _focus(SetLog set, SetField field) {
    _flushWrite();
    setState(() {
      _editing = EditTarget(set.id, field);
      _buffer.value = switch (field) {
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
    final ghost = _ghostFor(
      prefill[entry.exercise.id],
      entry.sets,
      setPosition,
    );
    // Ghosts are stored in kg and shown in the display unit.
    final hint = switch (target.field) {
      SetField.weight => _fmtLoadIn(ghost?.weight),
      SetField.added => _fmtLoadIn(ghost?.addedWeight),
      SetField.reps => ghost?.reps?.toString() ?? '',
    };

    final isLast = cells.isNotEmpty && cells.last == target;
    // The key has to name what it does. On a reps field with nothing typed and
    // no ghost to borrow from, "Done" completes nothing at all.
    final needsReps =
        target.field == SetField.reps &&
        (int.tryParse(_buffer.value) ?? 0) <= 0 &&
        ghost?.reps == null;

    return SetKeypad(
      title:
          '${entry.exercise.name}  ·  '
          'Set ${_setLabelAt(entry.sets, setPosition)}  ·  '
          '${target.field.labelIn(_unit)}',
      field: target.field,
      unit: _unit,
      buffer: _buffer,
      hint: hint.isEmpty ? null : hint,
      onUseHint: hint.isEmpty ? null : () => _commit(hint, target),
      nextLabel: needsReps
          ? 'Reps?'
          : isLast
          ? 'Done'
          : 'Next',
      onKey: (key) {
        final next = applyKey(
          _buffer.value,
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
    // No setState: the notifier repaints the one cell and the readout.
    _buffer.value = next;
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
      var reps = int.tryParse(_buffer.value) ?? 0;
      // A weight with no reps used to do nothing at all while the key said
      // "Done": the keypad simply closed. Fall back to last time's reps, which
      // is what adopting the ghost would have written anyway; with no ghost to
      // fall back on the key says "Reps?" and this never runs.
      if (reps <= 0) {
        final located = _locate(detail, from.setId);
        if (located != null) {
          final ghost = _ghostFor(
            _prefill[located.$1.exercise.id],
            located.$1.sets,
            located.$3,
          );
          if (ghost?.reps != null) {
            reps = ghost!.reps!;
            _commit(reps.toString(), from);
            _flushWrite();
          }
        }
      }

      if (reps > 0) {
        _adoptGhost(from.setId);
        // Rest was already being measured; it was simply thrown away. Absent
        // rather than null when there is none to record: re-ticking a set an
        // hour later must not erase the rest it was actually given.
        final rest = _restTakenSeconds();
        ref
            .read(trainingRepositoryProvider)
            .updateSet(
              from.setId,
              isDone: const Value(true),
              restSeconds: rest == null ? const Value.absent() : Value(rest),
            );
        HapticFeedback.mediumImpact();
        // Not after the last one. The rest bar has nothing to count towards
        // with the work over, and it sits directly under the button asking you
        // to finish — the tick path already knew this and this one did not.
        if (_hasOpenSetsBesides(from.setId)) _startRest();
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
    if (done) {
      // Last time's numbers fill the blanks first: same weight as last week,
      // one more rep is the normal case and shouldn't need typing.
      _adoptGhost(set.id);

      // A set with nothing in it — and nothing coming from last time either —
      // cannot be ticked. It used to be allowed, and it wrote a completed set
      // with a null load and null reps: invisible to the progress chart,
      // useless as next week's prefill, and indistinguishable later from a set
      // that genuinely happened. Send the thumb to the empty field instead of
      // arguing about it.
      final empty = _firstEmptyField(set.id);
      if (empty != null) {
        HapticFeedback.selectionClick();
        final located = _locate(_detail!, set.id);
        if (located != null) _focus(located.$2, empty);
        return;
      }
    }
    // The same write the keypad's "Next" makes. Ticking the box by hand used to
    // record no rest at all, so how long a set rested depended on which of two
    // ways you had marked it done.
    final rest = done ? _restTakenSeconds() : null;
    ref
        .read(trainingRepositoryProvider)
        .updateSet(
          set.id,
          isDone: Value(done),
          restSeconds: rest == null ? const Value.absent() : Value(rest),
        );
    if (!done) return;
    HapticFeedback.mediumImpact();

    if (_hasOpenSetsBesides(set.id)) _startRest();
  }

  /// Whether any set other than [setId] is still open.
  ///
  /// Rest is the gap before the next set. Tick the last one in the session and
  /// there is no next set to rest for. The set being completed is excluded by
  /// id rather than by its flag: the write marking it done is still in flight,
  /// so it is still open in the snapshot this reads.
  bool _hasOpenSetsBesides(String setId) {
    final detail = _detail;
    if (detail == null) return false;
    return detail.entries
        .where((e) => e.workoutExercise.skipReason == SkipReason.none)
        .expand((e) => e.sets)
        .any((s) => s.id != setId && !s.isDone);
  }

  /// The field standing between this set and being logged, if any.
  ///
  /// Reps are always required. A load is required unless the movement is
  /// bodyweight, where there is nothing to enter.
  ///
  /// A blank the ghost is about to fill does not count. This read the row as it
  /// stood in the last build, but [_adoptGhost] runs immediately before it and
  /// its writes have not come back yet — so a set with last time's numbers
  /// waiting for it looked empty, and the first tap on the tick only filled the
  /// fields and opened the keypad. Logging the same numbers as last week, which
  /// is the single most common thing to do on this screen, took two taps on the
  /// same box and looked like the first one had missed.
  SetField? _firstEmptyField(String setId) {
    final detail = _detail;
    if (detail == null) return null;
    final located = _locate(detail, setId);
    if (located == null) return null;
    final (entry, set, position) = located;
    final ghost = _ghostFor(_prefill[entry.exercise.id], entry.sets, position);

    switch (entry.exercise.loadMode) {
      case LoadMode.bodyweightPlus:
        if (set.addedWeight == null && ghost?.addedWeight == null) {
          return SetField.added;
        }
      case LoadMode.total:
      case LoadMode.perSide:
        if (set.weight == null && ghost?.weight == null) {
          return SetField.weight;
        }
      case LoadMode.bodyweight:
        break;
    }
    if (set.reps == null && ghost?.reps == null) return SetField.reps;
    return null;
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
    final ghost = _ghostFor(_prefill[entry.exercise.id], entry.sets, position);
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
    // A workout with nothing in it has no page to go to, and `clamp(0, -1)`
    // throws rather than returning anything. Adding the first exercise to an
    // empty session went straight through here.
    if (detail == null || detail.entries.isEmpty) return;
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
    // somewhere off the end of the rail — once the build that has it arrives.
    _wantedPage = detail.entries.length;
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
      final outcome = await _confirmEarlyFinish(
        context,
        done: done,
        total: _totalSets(detail),
        unfinished: unfinished,
      );
      if (outcome == null || outcome == _FinishChoice.keepLogging) return;
      if (outcome == _FinishChoice.discard) {
        // Asked twice, because this is the one door in the app that throws
        // work away, and the sets behind it are already logged.
        if (!mounted) return;
        final sure = await confirmAction(
          context,
          title: 'Discard this session?',
          message:
              '$done logged set${done == 1 ? '' : 's'} '
              '${done == 1 ? 'is' : 'are'} deleted. This cannot be undone.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep it',
          destructive: true,
        );
        if (!sure) return;
        await repo.abandonWorkout(detail.workout.id);
        navigator.pop();
        return;
      }
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
  static List<({String name, int done, int total})> _unfinished(
    WorkoutDetail d,
  ) {
    final out = <({String name, int done, int total})>[];
    for (final entry in d.entries) {
      if (entry.workoutExercise.skipReason != SkipReason.none) continue;
      final total = entry.sets.length;
      final done = entry.sets.where((s) => s.isDone).length;
      if (total == 0 || done == total) continue;
      out.add((name: entry.exercise.name, done: done, total: total));
    }
    return out;
  }

  static int _totalSets(WorkoutDetail d) =>
      d.entries.expand((e) => e.sets).length;

  /// A stored kg value as the number this phone types in.
  String _fmtLoadIn(double? kg) => kg == null ? '' : formatInUnit(kg, _unit);
}

/// Prefill set aligned to a position in the current exercise, or null when
/// today has more sets than last time.
/// Which past set one of today's rows compares against.
///
/// Index for index broke the moment today's shape differed from last time's:
/// adding a single drop leg pushed every row under it onto the wrong ghost, so
/// the second working set started suggesting the first leg's dropped weight —
/// and adopting a blank row wrote that number in. Rows are matched inside their
/// own class instead: warm-ups against warm-ups, working sets against working
/// sets, legs against legs. An extra leg now costs that leg its ghost and
/// nothing else.
PastSet? _ghostFor(PrefillResult? prefill, List<SetLog> sets, int position) {
  if (prefill == null || position < 0 || position >= sets.length) return null;

  final want = _ghostClass(sets[position].setType);
  var rank = 0;
  for (var i = 0; i < position; i++) {
    if (_ghostClass(sets[i].setType) == want) rank++;
  }

  for (final past in prefill.sets) {
    if (_ghostClass(past.type) != want) continue;
    if (rank == 0) return past;
    rank--;
  }
  return null;
}

int _ghostClass(SetType type) => switch (type) {
  SetType.warmup => 0,
  _ when type.isContinuation => 2,
  _ => 1,
};

/// A single exercise, filling the screen.
///
/// The session used to be one long vertical stack, which meant scrolling past
/// finished work to reach the set in front of you. One exercise per page keeps
/// the thing you are actually doing at a fixed place on screen.
/// Session name, elapsed clock, and how far through the work you are.
///
/// The progress track replaces the `12 of 18 sets` line that used to sit under
/// the title. It is the same fact, and a bar answers "nearly done?" from across
/// a gym floor in a way two numbers never did.
class _LogTopBar extends StatelessWidget {
  const _LogTopBar({
    required this.title,
    required this.isDeload,
    required this.startedAt,
    required this.done,
    required this.total,
    required this.onBack,
    required this.onFinish,
  });

  final String title;
  final bool isDeload;

  /// Epoch milliseconds, UTC — the column's own storage format.
  final int startedAt;
  final int done;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final complete = total > 0 && done == total;

    return HeaderBand(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.sm,
              Space.sm,
              Space.gutter,
              0,
            ),
            child: Row(
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: onBack,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: context.t.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDeload) ...[
                            const SizedBox(width: Space.sm),
                            Pill('Deload', color: c.deload),
                          ],
                        ],
                      ),
                      // Its own clock, so the session timer advances without
                      // the rest of the screen rebuilding behind it once a
                      // second.
                      Ticking(
                        builder: (context) => Text(
                          _formatElapsed(startedAt),
                          style: context.t.labelSmall?.copyWith(
                            color: c.textSecondary,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Once everything is ticked this is the pinned white button at
                // the bottom instead, so it doesn't appear in two places.
                if (!complete) LinkAction('Finish', onTap: onFinish),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          // Full-bleed: inside the bar's padding, a finished session stopped a
          // gutter short at each end and the track never looked full.
          _ProgressTrack(done: done, total: total),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fraction = total == 0 ? 0.0 : done / total;
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Container(color: c.surfaceHigh),
            AnimatedContainer(
              duration: Motion.base,
              curve: Motion.curve,
              width: box.maxWidth * fraction,
              color: c.accent,
            ),
          ],
        ),
      ),
    );
  }
}

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
    required this.openSwipe,
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
  final ValueListenable<String> buffer;

  /// The one row swiped open across the whole screen.
  final ValueNotifier<String?> openSwipe;
  final void Function(SetLog, SetField) onEdit;
  final GlobalKey Function(String setId) rowKeyFor;
  final void Function(SetLog, bool) onToggleDone;
  final VoidCallback onNextExercise;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final skipped = entry.workoutExercise.skipReason != SkipReason.none;

    // Warm-ups are not set 1, and a drop run is one set rather than three:
    // counting rows shifted every number away from the programme it came from.
    final groups = _groupSets(entry.sets);
    final counted = groups
        .where((g) => g.sets.first.setType != SetType.warmup)
        .toList();
    final countedDone = counted
        .where((g) => g.sets.every((s) => s.isDone))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
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
                    entry.exercise.name,
                    style: context.t.headlineSmall?.copyWith(
                      color: skipped ? c.textTertiary : c.textPrimary,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!skipped && counted.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Set ${math.min(countedDone + 1, counted.length)} '
                      'of ${counted.length}',
                      style: context.t.bodyMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.xs),
                  _PrefillCaption(prefill: prefill),
                ],
              ),
            ),
            CircleIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Exercise actions',
              onTap: () => showExerciseMenu(
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
        const SizedBox(height: Space.xl),
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
          // No card. The table was inset by the page gutter and then again by
          // the card's own padding, so the SET column started 32dp in while
          // the exercise name above it started at 16 — the two things a reader
          // scans down this screen were on different vertical lines. On the
          // page it is also one less surface behind a row that already has a
          // fill of its own per field.
          Column(
            children: [
              SetTableHeader(loadMode: entry.exercise.loadMode, unit: unit),
              for (final group in groups)
                _SetGroup(
                  group: group,
                  entry: entry,
                  unit: unit,
                  editing: editing,
                  buffer: buffer,
                  openSwipe: openSwipe,
                  onEdit: onEdit,
                  rowKeyFor: rowKeyFor,
                  onToggleDone: onToggleDone,
                ),
              // The add button lives in the index column, directly under the
              // numbers it continues — no label, because a `+` under a
              // column of set numbers cannot mean anything else. The
              // `n of m done` line that used to sit here said what the
              // header already says.
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Row(
                  children: [
                    _RoundButton(
                      icon: Icons.add_rounded,
                      onTap: () => ref
                          .read(trainingRepositoryProvider)
                          .addSet(entry.workoutExercise.id),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.exercise.notes != null) ...[
            const SizedBox(height: Space.lg),
            Text(
              entry.exercise.notes!,
              style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
            ),
          ],
        ],
        if (nextName != null) ...[
          const SizedBox(height: Space.section),
          // Turning the page works too; this is the discoverable version.
          SecondaryButton(
            label: 'Next: $nextName',
            icon: Icons.arrow_forward_rounded,
            onPressed: onNextExercise,
          ),
        ],
      ],
    );
  }
}

enum _FinishChoice { finish, discard, keepLogging }

/// What to do about a session with sets still open.
///
/// This was a two-button confirm built out of a paragraph of text: the counts,
/// the exercise list and the caveat all ran together in one message, and the
/// only ways out were "Finish anyway" and "Keep logging". There was no way to
/// throw the session away from here at all — you had to un-tick every set to
/// get the "nothing logged" prompt that offered it.
Future<_FinishChoice?> _confirmEarlyFinish(
  BuildContext context, {
  required int done,
  required int total,
  required List<({String name, int done, int total})> unfinished,
}) {
  return showModalBottomSheet<_FinishChoice>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.c;
      return AppSheet(
        title: 'Finish with sets left?',
        subtitle: '$done of $total sets logged',
        footer: Column(
          children: [
            PrimaryButton(
              label: 'Finish session',
              onPressed: () => Navigator.of(sheet).pop(_FinishChoice.finish),
            ),
            const SizedBox(height: Space.sm),
            SecondaryButton(
              label: 'Keep logging',
              onPressed: () =>
                  Navigator.of(sheet).pop(_FinishChoice.keepLogging),
            ),
          ],
        ),
        children: [
          ListCard(
            children: [
              for (final e in unfinished)
                AppRow(
                  title: e.name,
                  trailing: Text(
                    '${e.done} of ${e.total}',
                    style: sheet.t.labelLarge?.copyWith(color: c.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(
            'The empty sets are discarded — the session is saved with exactly '
            'what you did.',
            style: sheet.t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          Center(
            child: Pressable(
              onTap: () => Navigator.of(sheet).pop(_FinishChoice.discard),
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Text(
                  'Discard this session',
                  style: sheet.t.titleMedium?.copyWith(color: c.negative),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// A run of rows that share one index chip.
///
/// A plain set is a group of one. Consecutive drop sets are a group of several:
/// they belong to the set above them, so they get a single `D` chip with a
/// spine running down beside them and a `+` at its foot to add another.
class _SetGroupData {
  const _SetGroupData(this.sets, this.positions, this.label, this.isDrop);

  final List<SetLog> sets;

  /// Each set's index in the exercise, needed to line a row up with its ghost.
  final List<int> positions;

  final String label;
  final bool isDrop;
}

/// Splits an exercise's sets into rows-with-a-chip and their drop legs.
///
/// A leg is a set whose `parentSetId` names the set above it. Grouping by
/// adjacency instead — every run of consecutive `drop` rows — could not tell
/// one drop set with two legs from two drop sets side by side, so converting
/// two sets in a row merged them into one.
List<_SetGroupData> _groupSets(List<SetLog> sets) {
  final at = {for (var i = 0; i < sets.length; i++) sets[i].id: i};

  /// A row that carries a chip of its own.
  ///
  /// Adjacency is not part of this. Legs were collected by walking forward from
  /// the head and stopping at the first row that was not its child, so a leg
  /// that ended up anywhere else — an orphan whose head was deleted, a leg of a
  /// leg — was skipped by the loop below *and* by the head that never reached
  /// it, and vanished from the table while still sitting in the database.
  bool isHead(SetLog s) {
    final parent = s.parentSetId;
    if (parent == null) return true;
    final i = at[parent];
    return i == null || sets[i].parentSetId != null;
  }

  final legsOf = <String, List<int>>{};
  for (var i = 0; i < sets.length; i++) {
    if (isHead(sets[i])) continue;
    legsOf.putIfAbsent(sets[i].parentSetId!, () => <int>[]).add(i);
  }

  final groups = <_SetGroupData>[];
  var counted = 0;

  for (var i = 0; i < sets.length; i++) {
    final set = sets[i];
    if (!isHead(set)) continue; // collected with its head

    final positions = <int>[i, ...?legsOf[set.id]];
    final legs = [for (final p in positions) sets[p]];

    final isDrop = set.setType == SetType.drop || legs.length > 1;
    final label = switch (set.setType) {
      SetType.warmup => 'W',
      // A drop is a set you dropped weight inside, so it takes a number of
      // its own — the reference numbers W, D, 2.
      SetType.drop => 'D',
      _ => '',
    };
    if (set.setType != SetType.warmup) counted++;

    groups.add(
      _SetGroupData(
        legs,
        positions,
        label.isEmpty ? '$counted' : label,
        isDrop,
      ),
    );
  }
  return groups;
}

/// What the chip beside a row prints, from the row's position in the exercise.
///
/// The keypad titled itself "Set 4" for the row marked `2` — it counted rows,
/// which is the one thing warm-ups and drop legs make meaningless.
String _setLabelAt(List<SetLog> sets, int position) {
  for (final group in _groupSets(sets)) {
    final k = group.positions.indexOf(position);
    if (k < 0) continue;
    return k == 0 ? group.label : '${group.label} · leg ${k + 1}';
  }
  return '${position + 1}';
}

class _SetGroup extends ConsumerWidget {
  const _SetGroup({
    required this.group,
    required this.entry,
    required this.unit,
    required this.editing,
    required this.buffer,
    required this.openSwipe,
    required this.onEdit,
    required this.rowKeyFor,
    required this.onToggleDone,
  });

  final _SetGroupData group;
  final ExerciseEntry entry;
  final WeightUnit unit;
  final EditTarget? editing;
  final ValueListenable<String> buffer;

  /// The one row swiped open across the whole screen.
  final ValueNotifier<String?> openSwipe;
  final void Function(SetLog, SetField) onEdit;
  final GlobalKey Function(String setId) rowKeyFor;
  final void Function(SetLog, bool) onToggleDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefill = ref
        .watch(workoutPrefillProvider(entry.workoutExercise.workoutId))
        .valueOrNull?[entry.exercise.id];
    final repo = ref.read(trainingRepositoryProvider);
    final last = group.sets.length - 1;

    void addLeg() => repo.addDropLeg(
      entry.workoutExercise.id,
      headSetId: group.sets.first.id,
    );

    // One index cell per row, always the same height as the row beside it.
    // The previous version stacked chip / spine / plus in a column of its own
    // and let [IntrinsicHeight] size the group, which stretched the first row
    // taller than the rest and slid every chip out of line with its row.
    //
    // No row wash. A completed set is said by its fields and its checkbox
    // (THEME §6); a full-width band behind the row was the loudest thing in
    // the table, and the table is mostly completed rows by the end.
    return Column(
      children: [
        for (var k = 0; k < group.sets.length; k++)
          // The whole row travels — chip, capsule segment and fields together.
          // Wrapped around the fields alone this slid the numbers out from
          // under a chip that stayed put, which reads as the table coming
          // apart rather than as one row moving aside.
          SwipeToDelete(
            rowId: group.sets[k].id,
            open: openSwipe,
            onDelete: () => repo.deleteSets(_deleteIds(k)),
            child: Row(
              children: [
                _IndexCell(
                  // The spine only exists to tie a drop run together. A group of
                  // one head keeps its square foot for the `+` row below it.
                  spine: !group.isDrop
                      ? _Spine.none
                      : (k == 0
                            ? _Spine.top
                            : (k == last ? _Spine.bottom : _Spine.middle)),
                  child: switch (k) {
                    0 => SetIndexChip(
                      type: group.sets.first.setType,
                      label: group.label,
                      done: group.sets.first.isDone,
                      onTap: () => _openActions(context, ref, k),
                    ),
                    // The `+` rides in the last leg's cell, level with the row
                    // it continues. Given a row of its own it left a cell-high
                    // gap under a dot that marked nothing, which on a two-row
                    // drop set was half the height of the group.
                    //
                    // Long-press is that leg's own actions: its cell is spoken
                    // for, and every other row in this column opens a sheet.
                    _ when k == last => _RoundButton(
                      icon: Icons.add_rounded,
                      onTap: addLeg,
                      onLongPress: () => _openActions(context, ref, k),
                    ),
                    // A middle leg's way into its type, note and delete.
                    _ => _LegMarker(onTap: () => _openActions(context, ref, k)),
                  },
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: KeyedSubtree(
                    key: rowKeyFor(group.sets[k].id),
                    child: SetRow(
                      set: group.sets[k],
                      loadMode: entry.exercise.loadMode,
                      unit: unit,
                      ghost: _ghostFor(prefill, entry.sets, group.positions[k]),
                      editing: editing,
                      buffer: buffer,
                      onEdit: onEdit,
                      onToggleDone: onToggleDone,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // A drop set whose last leg has been deleted has no cell to put the `+`
        // in but still has to offer one, or it can never be a drop set again.
        // This is the only case that costs a row.
        if (group.isDrop && group.sets.length == 1)
          Row(
            children: [
              _IndexCell(
                spine: _Spine.bottom,
                height: _footHeight,
                child: _RoundButton(icon: Icons.add_rounded, onTap: addLeg),
              ),
            ],
          ),
      ],
    );
  }

  /// Shorter than a set row: it holds a button, not a number to read. Exactly
  /// the button's own diameter, so the capsule's foot closes on its edge.
  static const _footHeight = SetRow.indexColumn;

  /// Everything deleting row [k] removes. Deleting the head of a drop group
  /// takes the whole group: its legs are continuations of that set and mean
  /// nothing without it.
  List<String> _deleteIds(int k) =>
      k == 0 ? [for (final s in group.sets) s.id] : [group.sets[k].id];

  void _openActions(BuildContext context, WidgetRef ref, int k) {
    showSetActions(
      context,
      ref,
      group.sets[k],
      // The label the chip prints, not the raw position. Tapping the set
      // marked `1` used to open a sheet headed "Set 2" whenever a warm-up or
      // a drop sat above it.
      label: k == 0 ? group.label : '${group.label} · leg ${k + 1}',
      deleteIds: _deleteIds(k),
    );
  }
}

enum _Spine { none, top, middle, bottom }

/// The fixed-width column down the left of the table. For a drop group the
/// cells join into one capsule behind the chip, the legs and the `+`.
class _IndexCell extends StatelessWidget {
  const _IndexCell({
    required this.spine,
    required this.child,
    this.height = SetRow.rowHeight,
  });

  final _Spine spine;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The full width of the column, with the chip flat on it. A narrower
    // capsule with a filled chip proud of it read as beads on a string —
    // three bulges down the left of the table instead of one run.
    const spineWidth = SetRow.indexColumn;
    const r = Radius.circular(spineWidth / 2);

    // The cap stops on the chip's own edge, not on the row's. A row is taller
    // than the chip in it, so a capsule drawn to the full height of the top row
    // reached half a chip above the `D` and ended in a rounded shoulder with
    // nothing under it — the same at the foot, around the `+`. Inset by the
    // gap between the two and the cap circumscribes the circle exactly.
    final inset = ((height - SetRow.indexColumn) / 2).clamp(0.0, height / 2);

    return SizedBox(
      width: SetRow.indexColumn,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (spine != _Spine.none)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  top: spine == _Spine.top ? inset : 0,
                  bottom: spine == _Spine.bottom ? inset : 0,
                ),
                child: Container(
                  width: spineWidth,
                  decoration: BoxDecoration(
                    color: c.surfaceHighest,
                    borderRadius: BorderRadius.vertical(
                      top: spine == _Spine.top ? r : Radius.zero,
                      bottom: spine == _Spine.bottom ? r : Radius.zero,
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// The width of the index column, so a capsule's foot closes on its edge.
  static const size = SetRow.indexColumn;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surfaceHigh, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.6, color: c.textSecondary),
      ),
    );
  }
}

/// A drop leg's index cell. The capsule already says the row belongs to the set
/// above it, so this is only a mark that something is here to press — and, like
/// every other chip in this column, the way into that row's type, note and
/// delete.
class _LegMarker extends StatelessWidget {
  const _LegMarker({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: SetRow.indexColumn,
        height: SetRow.rowHeight,
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: c.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Session length, as `m:ss` or `h:mm:ss`. Top-level because both the screen
/// and its top bar need it and neither owns the other.
String _formatElapsed(int startedAtMs) {
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
