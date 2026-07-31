import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/db/database.dart';
import '../../../domain/enums.dart';
import '../../../domain/metrics.dart';
import '../../../domain/prefill.dart';
import '../../../domain/units.dart';
import '../log_screen.dart';
import 'keypad.dart';

export 'keypad.dart' show SetField, SetFieldX, SetKeypad, applyKey;

/// The column headings above the set table.
///
/// The units live here and nowhere else. They used to sit inside every field as
/// a `kg` / `reps` suffix, which is the same word printed five times down a
/// column and a chunk of the width of a field you have to read a number out of
/// at arm's length.
class SetTableHeader extends StatelessWidget {
  const SetTableHeader({
    super.key,
    required this.loadMode,
    required this.unit,
  });

  final LoadMode loadMode;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final label = context.t.labelSmall?.copyWith(color: context.c.textTertiary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Row(
        children: [
          SizedBox(width: SetRow.indexColumn, child: Text('SET', style: label)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              loadMode == LoadMode.bodyweight
                  ? 'LOAD'
                  : unit.label.toUpperCase(),
              style: label,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: Space.sm),
          SizedBox(
            width: SetRow.repsColumn,
            child: Text('REPS', style: label, textAlign: TextAlign.center),
          ),
          const SizedBox(width: Space.sm),
          SizedBox(width: SetRow.doneColumn, child: Text('✓', style: label)),
        ],
      ),
    );
  }
}

/// One set: index, load, reps, done.
///
/// Last time's numbers sit in the fields as ghost text rather than in a
/// separate column — you compare against them at the exact moment you're
/// deciding what to lift, and beating one lights up immediately.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.label,
    required this.loadMode,
    required this.unit,
    required this.ghost,
    required this.editing,
    required this.buffer,
    required this.onEdit,
    required this.onToggleDone,
    required this.onOpenActions,
  });

  static const indexColumn = 40.0;
  static const repsColumn = 78.0;
  static const doneColumn = 44.0;

  final SetLog set;

  /// What the index chip prints: a working set's number, or `W` / `D` / `RP`
  /// for the types that aren't counted. Worked out by the page, which is the
  /// only thing that can see the other sets.
  final String label;

  final LoadMode loadMode;
  final WeightUnit unit;
  final PastSet? ghost;
  final EditTarget? editing;
  final ValueListenable<String> buffer;
  final void Function(SetLog, SetField) onEdit;
  final void Function(SetLog, bool) onToggleDone;

  /// Opens the per-set sheet: type, note, delete.
  final VoidCallback onOpenActions;

  @override
  Widget build(BuildContext context) {
    final beaten = _beatsGhost();
    // A drop or rest-pause set belongs to the set above it, so it is indented
    // under it rather than given an index of its own.
    final nested = set.setType.isContinuation;

    // No Dismissible: the log turns pages horizontally, so a sideways drag on a
    // row cannot also mean "delete". Set actions live behind the index chip.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg + (nested ? Space.lg : 0),
        Space.xs,
        Space.lg,
        Space.xs,
      ),
      child: Row(
        children: [
          _IndexChip(
            label: label,
            done: set.isDone,
            nested: nested,
            onTap: onOpenActions,
          ),
          const SizedBox(width: Space.md),
          if (loadMode == LoadMode.bodyweight)
            Expanded(
              child: Text(
                'Bodyweight',
                textAlign: TextAlign.center,
                style: context.t.bodyMedium?.copyWith(
                  color: context.c.textSecondary,
                ),
              ),
            )
          else
            Expanded(
              child: _ValueCell(
                unit: unit,
                field: loadMode == LoadMode.bodyweightPlus
                    ? SetField.added
                    : SetField.weight,
                prefix: loadMode == LoadMode.bodyweightPlus ? 'BW +' : null,
                value: loadMode == LoadMode.bodyweightPlus
                    ? set.addedWeight
                    : set.weight,
                ghost: loadMode == LoadMode.bodyweightPlus
                    ? ghost?.addedWeight
                    : ghost?.weight,
                done: set.isDone,
                active:
                    editing?.setId == set.id &&
                    editing?.field ==
                        (loadMode == LoadMode.bodyweightPlus
                            ? SetField.added
                            : SetField.weight),
                buffer: buffer,
                onTap: () => onEdit(
                  set,
                  loadMode == LoadMode.bodyweightPlus
                      ? SetField.added
                      : SetField.weight,
                ),
              ),
            ),
          const SizedBox(width: Space.sm),
          SizedBox(
            width: repsColumn,
            child: _ValueCell(
              unit: unit,
              field: SetField.reps,
              value: set.reps?.toDouble(),
              ghost: ghost?.reps?.toDouble(),
              done: set.isDone,
              active:
                  editing?.setId == set.id && editing?.field == SetField.reps,
              buffer: buffer,
              onTap: () => onEdit(set, SetField.reps),
            ),
          ),
          const SizedBox(width: Space.sm),
          _DoneBox(
            done: set.isDone,
            beaten: beaten,
            onTap: () => onToggleDone(set, !set.isDone),
          ),
        ],
      ),
    );
  }

  /// True when this set beats the same slot last time.
  bool _beatsGhost() {
    final g = ghost;
    if (g == null || !set.isDone) return false;

    // Bodyweight is held constant: within a single comparison it is the same
    // number on both sides, so it cancels and cannot skew the result.
    const assumedBodyweight = 100.0;

    return beatsPrevious(
      load: effectiveLoad(
        mode: loadMode,
        weight: set.weight,
        addedWeight: set.addedWeight,
        bodyweightKg: assumedBodyweight,
      ),
      reps: set.reps,
      previousLoad: effectiveLoad(
        mode: loadMode,
        weight: g.weight,
        addedWeight: g.addedWeight,
        bodyweightKg: assumedBodyweight,
      ),
      previousReps: g.reps,
    );
  }
}

class _ValueCell extends StatefulWidget {
  const _ValueCell({
    required this.field,
    required this.unit,
    required this.value,
    required this.ghost,
    required this.done,
    required this.active,
    required this.buffer,
    required this.onTap,
    this.prefix,
  });

  final SetField field;

  /// Reps are unitless; weights are stored in kg and shown in this.
  final WeightUnit unit;

  final double? value;
  final double? ghost;
  final bool done;
  final bool active;
  final ValueListenable<String> buffer;
  final VoidCallback onTap;
  final String? prefix;

  @override
  State<_ValueCell> createState() => _ValueCellState();
}

class _ValueCellState extends State<_ValueCell> {
  /// Brief wash after a ghost turns into a real value, so adoption is something
  /// you see happen rather than something you infer from grey becoming white in
  /// gym lighting.
  bool _flash = false;
  Timer? _flashEnd;

  @override
  void didUpdateWidget(_ValueCell old) {
    super.didUpdateWidget(old);
    if (old.value == null && widget.value != null && !widget.active) {
      _flashEnd?.cancel();
      setState(() => _flash = true);
      _flashEnd = Timer(Motion.slow, () {
        if (mounted) setState(() => _flash = false);
      });
    }
  }

  @override
  void dispose() {
    _flashEnd?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only the cell being typed into listens to the keypad buffer, so a
    // keystroke repaints one cell rather than the page.
    if (!widget.active) return _build(context, _fmt(widget.value, widget));
    return ValueListenableBuilder<String>(
      valueListenable: widget.buffer,
      builder: (context, buffer, _) => _build(context, buffer),
    );
  }

  Widget _build(BuildContext context, String display) {
    final c = context.c;
    final hasValue = display.isNotEmpty;
    final ghostText = _fmt(widget.ghost, widget);
    // A suggestion must never look like a record. The difference is carried by
    // colour and a leading dot, and it has to survive a glance from arm's
    // length with the phone on the floor.
    //
    // It used to be italic as well — but no italic face is bundled, so Skia
    // synthesised a slant by shearing the upright glyphs. Faux oblique on the
    // screen this app is mostly used on was the cheapest-looking thing in it.
    final showingGhost = !hasValue && ghostText.isNotEmpty;

    // A logged value steps back rather than lighting up: once the row is ticked
    // it is a record, and the row still to be filled is the one worth looking
    // at. The tick is what says "done", not the numbers going bold.
    final valueColour = !hasValue
        ? c.textTertiary
        : (widget.done ? c.textSecondary : c.textPrimary);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          // Focus is an outline on nothing, not a tinted box: the field being
          // typed into should read as open, and a fill plus a border is two
          // signals for one state.
          color: widget.active
              ? Colors.transparent
              : (_flash ? c.surfaceHighest : c.surfaceHigh),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: widget.active ? c.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.prefix != null) ...[
              Text(
                widget.prefix!,
                style: context.t.labelSmall?.copyWith(color: c.textTertiary),
              ),
              const SizedBox(width: 3),
            ],
            if (showingGhost) ...[
              Text(
                '·',
                style: context.t.labelLarge?.copyWith(color: c.textTertiary),
              ),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                hasValue ? display : (ghostText.isEmpty ? '—' : ghostText),
                style: context.t.labelLarge?.copyWith(color: valueColour),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double? v, _ValueCell cell) {
    if (v == null) return '';
    if (cell.field == SetField.reps) {
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    }
    return formatInUnit(v, cell.unit);
  }
}

/// The set's number, or its letter. Also the way into the set's own actions —
/// type, note, delete — because the row has no room for a trailing menu and the
/// screen has no spare horizontal gesture to give a swipe.
class _IndexChip extends StatelessWidget {
  const _IndexChip({
    required this.label,
    required this.done,
    required this.nested,
    required this.onTap,
  });

  final String label;
  final bool done;
  final bool nested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = nested ? 32.0 : SetRow.indexColumn;

    return Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: context.t.labelLarge?.copyWith(
            color: done ? c.textTertiary : c.textSecondary,
            fontSize: nested ? 13 : null,
          ),
        ),
      ),
    );
  }
}

class _DoneBox extends StatelessWidget {
  const _DoneBox({
    required this.done,
    required this.beaten,
    required this.onTap,
  });

  final bool done;

  /// Beat the same slot last time. The one place on this row where colour is
  /// allowed, because it is the only thing here that is a finding rather than
  /// a record.
  final bool beaten;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fill = done ? (beaten ? c.positive : c.accent) : c.surfaceHigh;

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        width: SetRow.doneColumn,
        height: 48,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(
          beaten && done ? Icons.trending_up_rounded : Icons.check_rounded,
          size: 20,
          color: done ? c.onAccent : c.textTertiary,
        ),
      ),
    );
  }
}
