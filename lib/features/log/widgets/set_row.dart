import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/db/database.dart';
import '../../../domain/enums.dart';
import '../../../domain/metrics.dart';
import '../../../domain/prefill.dart';
import '../../../domain/units.dart';
import '../log_screen.dart';
import 'keypad.dart';

export 'keypad.dart' show SetField, SetFieldX, SetKeypad, applyKey;

/// One set: type, load, reps, done.
///
/// Last time's numbers sit in the fields as ghost text rather than in a
/// separate column — you compare against them at the exact moment you're
/// deciding what to lift, and beating one lights up immediately.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.position,
    required this.loadMode,
    required this.unit,
    required this.ghost,
    required this.editing,
    required this.buffer,
    required this.onEdit,
    required this.onToggleDone,
    required this.onOpenActions,
  });

  final SetLog set;
  final int position;
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
    final c = context.c;
    final beaten = _beatsGhost();

    // No Dismissible: the log turns pages horizontally, so a sideways drag on a
    // row cannot also mean "delete". Set actions live behind the type chip.
    return Container(
      color: set.isDone ? c.surfaceHigh.withValues(alpha: 0.5) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.xs,
      ),
      child: Row(
        children: [
          _TypeChip(set: set, position: position, onTap: onOpenActions),
          const SizedBox(width: Space.md),
          if (loadMode == LoadMode.bodyweight)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Bodyweight', style: context.t.labelMedium),
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
                suffix: unit.label,
                value: loadMode == LoadMode.bodyweightPlus
                    ? set.addedWeight
                    : set.weight,
                ghost: loadMode == LoadMode.bodyweightPlus
                    ? ghost?.addedWeight
                    : ghost?.weight,
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
            width: 78,
            child: _ValueCell(
              unit: unit,
              field: SetField.reps,
              suffix: 'reps',
              value: set.reps?.toDouble(),
              ghost: ghost?.reps?.toDouble(),
              active:
                  editing?.setId == set.id && editing?.field == SetField.reps,
              buffer: buffer,
              onTap: () => onEdit(set, SetField.reps),
            ),
          ),
          const SizedBox(width: Space.sm),
          _DoneButton(
            done: set.isDone,
            highlight: beaten,
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
    required this.active,
    required this.buffer,
    required this.onTap,
    this.prefix,
    this.suffix,
  });

  final SetField field;

  /// Reps are unitless; weights are stored in kg and shown in this.
  final WeightUnit unit;

  final double? value;
  final double? ghost;
  final bool active;
  final ValueListenable<String> buffer;
  final VoidCallback onTap;
  final String? prefix;
  final String? suffix;

  @override
  State<_ValueCell> createState() => _ValueCellState();
}

class _ValueCellState extends State<_ValueCell> {
  /// Brief accent wash after a ghost turns into a real value, so adoption is
  /// something you see happen rather than something you infer from grey
  /// becoming white in gym lighting.
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

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: widget.active
              ? c.accent.withValues(alpha: 0.12)
              : (_flash ? c.accent.withValues(alpha: 0.28) : c.surfaceHigh),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: widget.active ? c.accent : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (widget.prefix != null) ...[
              Text(widget.prefix!, style: context.t.labelMedium),
              const SizedBox(width: 2),
            ],
            if (showingGhost) ...[
              Text(
                '·',
                style: context.t.labelLarge?.copyWith(color: c.textTertiary),
              ),
              const SizedBox(width: 3),
            ],
            Expanded(
              child: Text(
                hasValue ? display : (ghostText.isEmpty ? '—' : ghostText),
                style: context.t.labelLarge?.copyWith(
                  color: hasValue ? c.textPrimary : c.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
            if (widget.suffix != null)
              Text(widget.suffix!, style: context.t.labelSmall),
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

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.set,
    required this.position,
    required this.onTap,
  });

  final SetLog set;
  final int position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isWorking = set.setType == SetType.working;
    final color = switch (set.setType) {
      SetType.warmup => c.textTertiary,
      SetType.working => c.textSecondary,
      SetType.backoff => c.textTertiary,
      SetType.drop => c.deload,
      SetType.restPause => c.deload,
      SetType.amrap => c.accent,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isWorking ? Colors.transparent : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: isWorking ? c.border : Colors.transparent),
        ),
        child: Text(
          isWorking ? '${position + 1}' : set.setType.shortLabel,
          style: context.t.labelMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.done,
    required this.highlight,
    required this.onTap,
  });

  final bool done;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A beaten set gets the accent; a merely completed one stays quiet, so the
    // colour still means something.
    final bg = done
        ? (highlight ? c.accent : c.positive.withValues(alpha: 0.18))
        : c.surfaceHigh;
    final fg = done ? (highlight ? c.onAccent : c.positive) : c.textTertiary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(
          highlight && done ? Icons.trending_up : Icons.check,
          size: 18,
          color: fg,
        ),
      ),
    );
  }
}
