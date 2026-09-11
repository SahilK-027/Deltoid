import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/enums.dart';
import '../../../domain/units.dart';
import 'plate_view.dart';

enum SetField { weight, reps, added }

extension SetFieldX on SetField {
  bool get isDecimal => this != SetField.reps;

  /// One rep, or one pair of plates — 2.5 kg on a kilo bar, 5 lb on a pound
  /// one. A 2.5 lb step is not a thing any gym stocks.
  ///
  /// A timed hold steps by **half a minute**, which is the unit a hold is
  /// actually adjusted in: nobody plans a plank thirty-one seconds long, and a
  /// one-second step would need thirty taps to say what one says.
  double stepIn(WeightUnit unit, {bool isTime = false}) {
    if (this != SetField.reps) return unit.step;
    return isTime ? 30 : 1;
  }
}

/// A clock field's buffer is the digits typed, filling from the right the way
/// every timer on the phone does: `2` is `0:02`, `25` is `0:25`, `225` is
/// `2:25`. Four digits maximum, so the field tops out at `99:59` — and a digit
/// that would push the seconds past `59` is refused rather than stored as a
/// time that cannot exist.
int secondsFromDigits(String digits) {
  if (digits.isEmpty) return 0;
  final padded = digits.padLeft(3, '0');
  final minutes = int.parse(padded.substring(0, padded.length - 2));
  final seconds = int.parse(padded.substring(padded.length - 2));
  return minutes * 60 + seconds;
}

String digitsFromSeconds(int seconds) {
  if (seconds <= 0) return '';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  final raw = m == 0 ? '$s' : '$m${s.toString().padLeft(2, '0')}';
  return raw;
}

/// What a clock buffer reads as while it is being typed.
String formatDigits(String digits) =>
    digits.isEmpty ? '' : formatClock(secondsFromDigits(digits));

/// A docked numeric pad instead of the OS keyboard.
///
/// The system keyboard is the wrong tool with chalky hands mid-set: small
/// targets, a layout that shifts, and no notion of "add 2.5kg". This one keeps
/// the log visible above it and puts a plate increment one tap away.
class SetKeypad extends StatelessWidget {
  const SetKeypad({
    super.key,
    required this.field,
    required this.unit,
    required this.buffer,
    required this.onKey,
    required this.onNext,
    required this.onDismiss,
    this.nextLabel = 'Next',
    this.barKg,
    this.isTime = false,
    this.partial = false,
    this.onTogglePartial,
  });

  final SetField field;
  final WeightUnit unit;

  /// The count field of a timed hold: digits fill a clock from the right and
  /// the step keys move by half a minute.
  final bool isTime;

  /// Current buffer, shown in the readout. A notifier rather than a value so
  /// a keystroke repaints this row and the cell being typed into, and nothing
  /// else on the screen.
  final ValueListenable<String> buffer;

  /// A digit, `.`, or `⌫`.
  final ValueChanged<String> onKey;

  final VoidCallback onNext;
  final VoidCallback onDismiss;

  final String nextLabel;

  /// Empty bar weight, when this movement is loaded on one. Drives the plate
  /// view above the digits; null means no bar and no diagram.
  final double? barKg;

  /// Whether the digits are landing in the set's **partial** count rather than
  /// its full reps. Null [onTogglePartial] means this field has no partials to
  /// speak of — a load, or a hold — and the key is not offered at all.
  final bool partial;
  final VoidCallback? onTogglePartial;

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
              // No "Last time" button either. The ghost in the cell being
              // typed into already shows last time's number, and `Next` adopts
              // it when nothing is typed, so a button repeating it was the same
              // number printed twice.
              Align(
                alignment: Alignment.centerRight,
                child: PadDismissButton(onPressed: onDismiss),
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
                isTime: isTime,
                onKey: onKey,
                onNext: onNext,
                nextLabel: nextLabel,
                partial: partial,
                onTogglePartial: onTogglePartial,
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
    required this.isTime,
    required this.onKey,
    required this.onNext,
    required this.nextLabel,
    required this.partial,
    required this.onTogglePartial,
  });

  final SetField field;
  final WeightUnit unit;
  final bool isTime;
  final ValueChanged<String> onKey;
  final VoidCallback onNext;
  final String nextLabel;
  final bool partial;
  final VoidCallback? onTogglePartial;

  @override
  Widget build(BuildContext context) {
    final step = field.stepIn(unit, isTime: isTime);
    // A time steps by a time: `+0:30`, not `+30`, so the key says the same
    // thing the field it is changing says.
    final stepLabel = isTime
        ? formatClock(step.round())
        : step == step.roundToDouble()
            ? step.toStringAsFixed(0)
            : step.toStringAsFixed(1);

    return Column(
      children: [
        // Phone order, not calculator order: `1 2 3` on the top row. Every
        // other pad this thumb uses — the dialler, the passcode, the timer —
        // counts downwards, and a pad that counts upwards is one you have to
        // look at.
        _row([
          _Key(label: '1', onTap: () => onKey('1')),
          _Key(label: '2', onTap: () => onKey('2')),
          _Key(label: '3', onTap: () => onKey('3')),
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
          _Key(label: '7', onTap: () => onKey('7')),
          _Key(label: '8', onTap: () => onKey('8')),
          _Key(label: '9', onTap: () => onKey('9')),
          _Key(label: '+$stepLabel', onTap: () => onKey('+'), muted: true),
        ]),
        _row([
          if (field.isDecimal)
            _Key(label: '.', onTap: () => onKey('.'))
          else if (onTogglePartial != null)
            _PartialKey(partial: partial, onTap: onTogglePartial!)
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
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: PadKey(
          label: label ?? '',
          icon: icon,
          onTap: onTap,
          muted: muted,
          accent: accent,
        ),
      );
}

/// One key on a pad: the set keypad's digits and its `Next`, and the stopwatch
/// pad's Start and Stop. One key, so the two pads under the same thumb are the
/// same height, the same corner and the same ink.
///
/// An [icon] with an empty [label] is a glyph key; both is a glyph leading its
/// word. [accent] is the key that ends the entry. With no [onTap] the key keeps
/// its slot and draws nothing.
class PadKey extends StatelessWidget {
  const PadKey({
    super.key,
    this.label = '',
    this.icon,
    required this.onTap,
    this.muted = false,
    this.accent = false,
    this.haptic = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool muted;
  final bool accent;

  /// A selection tick under the thumb on every key typed. The stopwatch's
  /// Start and Stop pass false, because they give their own heavier one — and
  /// Stop gives none for a mis-tap inside the first second.
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = accent ? c.accent : c.surfaceHigh;
    final fg = accent ? c.onAccent : (muted ? c.textSecondary : c.textPrimary);
    final text = Text(
      label,
      style: context.t.titleMedium?.copyWith(
        color: fg,
        fontFeatures: tabular,
      ),
    );

    return SizedBox(
      height: Sizes.key,
      child: Material(
        color: onTap == null ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onTap == null
              ? null
              : () {
                  if (haptic) HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Center(
            child: switch ((icon, label.isEmpty)) {
              (final glyph?, true) => Icon(glyph, size: 20, color: fg),
              (final glyph?, false) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(glyph, size: 20, color: fg),
                    const SizedBox(width: Space.sm),
                    text,
                  ],
                ),
              (null, _) => text,
            },
          ),
        ),
      ),
    );
  }
}

/// The ⌄ that puts a pad away, top right of both pads.
class PadDismissButton extends StatelessWidget {
  const PadDismissButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        width: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: const Icon(Icons.keyboard_hide_outlined),
          onPressed: onPressed,
        ),
      );
}

/// Switches the digits between a set's full reps and its partials.
///
/// One key with both halves showing, rather than a `P` that lights up: which
/// number you are typing into is the one thing on this pad you cannot work out
/// from the digits, and a toggle that only shows its own state makes you read
/// the field to find out where the last three taps went.
class _PartialKey extends StatelessWidget {
  const _PartialKey({required this.partial, required this.onTap});

  final bool partial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: SizedBox(
        height: Sizes.key,
        child: Material(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _half(context, 'F', selected: !partial),
                  _half(context, 'P', selected: partial),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _half(BuildContext context, String label, {required bool selected}) {
    final c = context.c;
    return Expanded(
      child: AnimatedContainer(
        duration: Motion.fast,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.cell),
        ),
        child: Text(
          label,
          style: context.t.labelLarge?.copyWith(
            color: selected ? c.onAccent : c.textTertiary,
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
  bool isTime = false,
}) {
  if (isTime) return _applyTimeKey(buffer, key, hint: hint);
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
      // A ceiling on the value, not on the digit count. Counting characters
      // lets `999.99` through and stops `1000.5` for being long rather than for
      // being wrong, which on a bar reads as the app refusing a legitimate
      // number.
      final value = double.tryParse(candidate);
      if (value == null || value > maxEntry(field)) return buffer;
      return candidate;
  }
}

/// The same keypad, typing a clock.
///
/// Digits fill from the right — `2` · `25` · `225` reads `0:02` · `0:25` ·
/// `2:25` — because that is how every timer on the phone is typed, and a hold
/// is a time you read off a clock rather than a count you tallied. A digit that
/// would push the seconds past `59` is refused: `0:75` is not a time, and
/// silently carrying it into `1:15` would change a number the user is watching
/// as they type it.
///
/// `+` / `−` move by half a minute and are done in **seconds**, not digits, so
/// `0:45 + 0:30` is `1:15` rather than a fourth digit appearing.
String _applyTimeKey(String buffer, String key, {double? hint}) {
  switch (key) {
    case '⌫':
      return buffer.isEmpty ? buffer : buffer.substring(0, buffer.length - 1);
    case '.':
      return buffer;
    case '+':
    case '-':
      final current = buffer.isEmpty
          ? (hint?.round() ?? 0)
          : secondsFromDigits(buffer);
      final raw = key == '+' ? current + 30 : current - 30;
      if (raw <= 0) return '';
      return digitsFromSeconds(raw > maxHoldSeconds ? maxHoldSeconds : raw);
    default:
      final candidate = buffer == '0' ? key : buffer + key;
      if (candidate.length > 4) return buffer;
      // The last two digits are the seconds, and there is no 75th second.
      if (candidate.length >= 2) {
        final tail = int.parse(candidate.substring(candidate.length - 2));
        if (tail > 59) return buffer;
      }
      return candidate;
  }
}

/// `99:59`. Four digits is the field's width, and an hour-long hold is not a
/// set — it is a walk.
const maxHoldSeconds = 99 * 60 + 59;

/// The largest number a field will accept.
///
/// 1000 for a load: more than anything anyone lifts, and small enough that a
/// stuck finger cannot write a number that breaks the axis of every chart it
/// lands in. Reps get their own ceiling — three digits of reps is already a
/// typo, and sharing the load's limit would let one row claim a thousand.
double maxEntry(SetField field) => field == SetField.reps ? 999 : 1000;
