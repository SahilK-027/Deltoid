import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/units.dart';
import 'plate_view.dart';

enum SetField { weight, reps, added }

extension SetFieldX on SetField {
  String labelIn(WeightUnit unit) => switch (this) {
    SetField.weight => 'Weight (${unit.label})',
    SetField.reps => 'Reps',
    SetField.added => 'Added (${unit.label})',
  };

  bool get isDecimal => this != SetField.reps;

  /// One rep, or one pair of plates — 2.5 kg on a kilo bar, 5 lb on a pound
  /// one. A 2.5 lb step is not a thing any gym stocks.
  double stepIn(WeightUnit unit) => this == SetField.reps ? 1 : unit.step;
}

/// A docked numeric pad instead of the OS keyboard.
///
/// The system keyboard is the wrong tool with chalky hands mid-set: small
/// targets, a layout that shifts, and no notion of "add 2.5kg". This one keeps
/// the log visible above it and puts the two things you actually want — last
/// time's numbers and a plate increment — one tap away.
class SetKeypad extends StatelessWidget {
  const SetKeypad({
    super.key,
    required this.field,
    required this.unit,
    required this.buffer,
    required this.onKey,
    required this.onNext,
    required this.onDismiss,
    this.hint,
    this.onUseHint,
    this.nextLabel = 'Next',
    this.barKg,
  });

  final SetField field;
  final WeightUnit unit;

  /// Current buffer, shown in the readout. A notifier rather than a value so
  /// a keystroke repaints this row and the cell being typed into, and nothing
  /// else on the screen.
  final ValueListenable<String> buffer;

  /// A digit, `.`, or `⌫`.
  final ValueChanged<String> onKey;

  final VoidCallback onNext;
  final VoidCallback onDismiss;

  /// Last time's value for this field, if any.
  final String? hint;
  final VoidCallback? onUseHint;
  final String nextLabel;

  /// Empty bar weight, when this movement is loaded on one. Drives the plate
  /// view above the digits; null means no bar and no diagram.
  final double? barKg;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.md,
            Space.md,
            Space.md,
            Space.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No title, and no readout of what is being typed. Both said what
              // the screen behind them already says: the exercise and set are
              // in the header, the field is the one outlined in the table, and
              // the digits land in that field as they are pressed. A keypad
              // that captions itself is a keypad covering the thing it is
              // captioning.
              Row(
                children: [
                  if (hint != null && onUseHint != null)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                        ),
                        side: BorderSide(color: c.borderStrong),
                        foregroundColor: c.textSecondary,
                      ),
                      onPressed: onUseHint,
                      child: Text('Last: $hint'),
                    ),
                  const Spacer(),
                  SizedBox(
                    height: 28,
                    width: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.keyboard_hide_outlined),
                      onPressed: onDismiss,
                    ),
                  ),
                ],
              ),
              // The plate view grows in and collapses to nothing, rather than
              // sitting in a reserved slot: an empty 60pt band above the digits
              // on every reps field was paying for the diagram whether or not
              // there was one to draw. [AnimatedSize] means the keys still do
              // not *jump* — they slide, once, over 220ms.
              if (barKg != null && field == SetField.weight)
                ValueListenableBuilder<String>(
                  valueListenable: buffer,
                  builder: (context, value, _) {
                    final load = plateLoadFor(
                      buffer: value,
                      barKg: barKg,
                      unit: unit,
                    );
                    return AnimatedSize(
                      duration: Motion.base,
                      curve: Motion.curve,
                      alignment: Alignment.topCenter,
                      child: load == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: Space.xs),
                              child: PlateView(load: load, unit: unit),
                            ),
                    );
                  },
                ),
              const SizedBox(height: Space.sm),
              _KeyGrid(
                field: field,
                unit: unit,
                onKey: onKey,
                onNext: onNext,
                nextLabel: nextLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyGrid extends StatelessWidget {
  const _KeyGrid({
    required this.field,
    required this.unit,
    required this.onKey,
    required this.onNext,
    required this.nextLabel,
  });

  final SetField field;
  final WeightUnit unit;
  final ValueChanged<String> onKey;
  final VoidCallback onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final step = field.stepIn(unit);
    final stepLabel = step == step.roundToDouble()
        ? step.toStringAsFixed(0)
        : step.toStringAsFixed(1);

    return Column(
      children: [
        _row([
          _Key(label: '7', onTap: () => onKey('7')),
          _Key(label: '8', onTap: () => onKey('8')),
          _Key(label: '9', onTap: () => onKey('9')),
          _Key(
            icon: Icons.backspace_outlined,
            onTap: () => onKey('⌫'),
            muted: true,
          ),
        ]),
        _row([
          _Key(label: '4', onTap: () => onKey('4')),
          _Key(label: '5', onTap: () => onKey('5')),
          _Key(label: '6', onTap: () => onKey('6')),
          _Key(label: '−$stepLabel', onTap: () => onKey('-'), muted: true),
        ]),
        _row([
          _Key(label: '1', onTap: () => onKey('1')),
          _Key(label: '2', onTap: () => onKey('2')),
          _Key(label: '3', onTap: () => onKey('3')),
          _Key(label: '+$stepLabel', onTap: () => onKey('+'), muted: true),
        ]),
        _row([
          if (field.isDecimal)
            _Key(label: '.', onTap: () => onKey('.'))
          else
            const _Key(label: '', onTap: null),
          _Key(label: '0', onTap: () => onKey('0')),
          _Key(label: nextLabel, onTap: onNext, accent: true, flex: 2),
        ]),
      ],
    );
  }

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: Space.sm),
          children[i],
        ],
      ],
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    required this.onTap,
    this.muted = false,
    this.accent = false,
    this.flex = 1,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool muted;
  final bool accent;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = accent ? c.accent : (muted ? c.surfaceHigh : c.surfaceHigh);
    final fg = accent ? c.onAccent : (muted ? c.textSecondary : c.textPrimary);

    return Expanded(
      flex: flex,
      child: SizedBox(
        height: 52,
        child: Material(
          color: onTap == null ? Colors.transparent : bg,
          borderRadius: BorderRadius.circular(Radii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 20, color: fg)
                  : Text(
                      label ?? '',
                      style: context.t.titleMedium?.copyWith(
                        color: fg,
                        fontFeatures: tabular,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Applies a keypad press to the current buffer.
///
/// Kept pure and separate from the widget so the increment and backspace edge
/// cases are unit-testable.
///
/// [hint] is last time's value for this field, when there is one. It only ever
/// matters for `+` / `−` on an empty buffer: "one plate more than last time" is
/// the most common intent in the gym, and starting that from zero made it a
/// three-tap operation ending in a dead `2.5`.
String applyKey(
  String buffer,
  String key, {
  required SetField field,
  WeightUnit unit = WeightUnit.kg,
  double? hint,
}) {
  switch (key) {
    case '⌫':
      return buffer.isEmpty ? buffer : buffer.substring(0, buffer.length - 1);
    case '.':
      if (!field.isDecimal || buffer.contains('.')) return buffer;
      return buffer.isEmpty ? '0.' : '$buffer.';
    case '+':
    case '-':
      // An empty buffer means "I haven't said anything yet", so step from last
      // time. Once anything is typed the buffer wins — including a typed 0.
      final current =
          double.tryParse(buffer) ?? (buffer.isEmpty ? hint ?? 0 : 0);
      final step = field.stepIn(unit);
      final raw = key == '+' ? current + step : current - step;
      if (raw < 0) return '0';
      // Stepping stops at the ceiling rather than refusing to move: holding `+`
      // should come to rest on the largest number this field allows, not do
      // nothing once it gets there.
      final next = raw > maxEntry(field) ? maxEntry(field) : raw;
      if (field == SetField.reps) return next.toStringAsFixed(0);
      return next == next.roundToDouble()
          ? next.toStringAsFixed(0)
          : next.toStringAsFixed(1);
    default:
      if (buffer == '0') return key;
      final candidate = buffer + key;
      // A ceiling on the value, not on the digit count. The old rule counted
      // characters, which let `999.99` through and stopped `1000.5` for being
      // long rather than for being wrong — and on a bar that reads as the app
      // refusing a legitimate number.
      final value = double.tryParse(candidate);
      if (value == null || value > maxEntry(field)) return buffer;
      return candidate;
  }
}

/// The largest number a field will accept.
///
/// 1000 for a load: more than anything anyone lifts, and small enough that a
/// stuck finger cannot write a number that breaks the axis of every chart it
/// lands in. Reps get their own ceiling — three digits of reps is already a
/// typo, and sharing the load's limit would let one row claim a thousand.
double maxEntry(SetField field) => field == SetField.reps ? 999 : 1000;
