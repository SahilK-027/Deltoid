import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

part 'primitives/page_furniture.dart';
part 'primitives/surfaces.dart';
part 'primitives/buttons.dart';
part 'primitives/marks.dart';
part 'primitives/sheets.dart';
part 'primitives/notices.dart';

/// The component vocabulary from THEME.md. Feature code composes these; it
/// does not draw its own cards, rows, buttons or sheets.

/// Press feedback for anything with a shape: a small scale-down and a dim.
///
/// Scale reads instantly and works identically on a 26pt chip and a full-width
/// card, because in both cases the whole thing moves. It is the wrong feedback
/// for a row, where 1% of a full-width strip is imperceptible. That is what
/// [InkRow] is for, and the only place this app inks.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far down it presses. Big surfaces need less travel than small ones to
  /// read as the same gesture.
  final double scale;

  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (!_enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // A `Pressable` with nothing to do is not a `Pressable` — it is its child.
    //
    // Building the detector anyway, opaque, makes it a hole in whatever it
    // sits inside: `LinkAction('Change')` inside a tappable row would swallow
    // every tap that landed on the word `Change`, leaving the one part of the
    // row that names the action as the one part that does not perform it.
    if (!_enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.fast,
        curve: Motion.curve,
        child: AnimatedOpacity(
          opacity: _down ? 0.86 : 1,
          duration: Motion.fast,
          child: widget.child,
        ),
      ),
    );
  }
}
