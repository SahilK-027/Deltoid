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

/// The colour a set type is marked in.
///
/// Warm-ups and drops are the two types this app actually has, and both are
/// facts about the set rather than chrome — so they get a hue, and a working
/// set stays grey. Without this the only difference between a warm-up and a
/// top set was one letter in the same colour as everything around it.
Color setTypeColour(BuildContext context, SetType type) => switch (type) {
  SetType.warmup => context.c.data,
  SetType.drop || SetType.restPause => context.c.deload,
  _ => context.c.textSecondary,
};

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
    final c = context.c;
    final label = context.t.labelSmall?.copyWith(color: c.textTertiary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Row(
        children: [
          SizedBox(width: SetRow.indexColumn, child: Text('SET', style: label)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              loadMode == LoadMode.bodyweight
                  ? 'LOAD'
                  : unit.label.toUpperCase(),
              style: label,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: Space.xs),
          SizedBox(
            width: SetRow.repsColumn,
            child: Text('REPS', style: label, textAlign: TextAlign.center),
          ),
          const SizedBox(width: Space.xs),
          SizedBox(
            width: SetRow.doneColumn,
            child: Icon(Icons.check_rounded, size: 14, color: c.textTertiary),
          ),
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
    required this.loadMode,
    required this.unit,
    required this.ghost,
    required this.editing,
    required this.buffer,
    required this.onEdit,
    required this.onToggleDone,
  });

  static const indexColumn = 34.0;
  static const repsColumn = 68.0;
  static const doneColumn = 40.0;
  static const fieldHeight = 42.0;

  /// A row's full height, fields plus their padding. The index column beside
  /// it is sized to this so a drop group's capsule lines up with its rows
  /// without stretching them — `CrossAxisAlignment.stretch` cannot do that job
  /// inside a scroll view, where the vertical constraint is unbounded.
  static const rowHeight = fieldHeight + Space.xs * 2;

  final SetLog set;
  final LoadMode loadMode;
  final WeightUnit unit;
  final PastSet? ghost;
  final EditTarget? editing;
  final ValueListenable<String> buffer;
  final void Function(SetLog, SetField) onEdit;
  final void Function(SetLog, bool) onToggleDone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final beaten = _beatsGhost();

    // No Dismissible: the log turns pages horizontally, so a sideways drag on a
    // row cannot also mean "delete". Set actions live behind the index chip.
    //
    // No indent for a drop set either. Indenting shifted every field on the row
    // out of its column, so the table stopped lining up exactly where it is
    // being read fastest — the letter in the index chip carries it instead.
    return AnimatedContainer(
      duration: Motion.fast,
      // Completed rows need to be obvious at a glance down the column, not on
      // inspection: the whole row steps onto a lighter surface.
      color: set.isDone ? c.surfaceHigh.withValues(alpha: 0.45) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.xs,
      ),
      child: Row(
        children: [
          if (loadMode == LoadMode.bodyweight)
            Expanded(
              child: Text(
                'Bodyweight',
                textAlign: TextAlign.center,
                style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
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
          const SizedBox(width: Space.xs),
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
          const SizedBox(width: Space.xs),
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
        height: SetRow.fieldHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
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
class SetIndexChip extends StatelessWidget {
  const SetIndexChip({
    super.key,
    required this.type,
    required this.label,
    required this.done,
    required this.onTap,
  });

  final SetType type;
  final String label;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final typed = type != SetType.working;
    final colour = setTypeColour(context, type);

    return Pressable(
      onTap: onTap,
      child: Container(
        width: SetRow.indexColumn,
        height: SetRow.indexColumn,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: typed ? colour.withValues(alpha: 0.18) : c.surfaceHigh,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: context.t.bodySmall?.copyWith(
            color: typed ? colour : (done ? c.textTertiary : c.textSecondary),
            fontWeight: FontWeight.w700,
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

    // An actual checkbox: empty square when open, filled when ticked. It was a
    // filled grey block with a grey tick already in it, which read as
    // "completed" on every row and made the real completed state invisible.
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: SetRow.doneColumn,
        height: SetRow.fieldHeight,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done
                  ? (beaten ? c.positive : c.accent)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(
                color: done ? Colors.transparent : c.textTertiary,
                width: 2,
              ),
            ),
            child: done
                ? Icon(
                    beaten
                        ? Icons.trending_up_rounded
                        : Icons.check_rounded,
                    size: 18,
                    color: c.onAccent,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
