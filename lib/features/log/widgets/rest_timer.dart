import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ticking.dart';

/// Rest clock that starts itself when a set is checked off.
///
/// Replaces "100s break" written as prose in a notes column: the number is
/// captured without asking for a single extra tap.
class RestTimerBar extends StatelessWidget {
  const RestTimerBar({
    super.key,
    required this.startedAt,
    required this.targetSeconds,
    required this.onAdjust,
    required this.onDismiss,
    this.aboveKeypad = false,
  });

  final DateTime startedAt;
  final int targetSeconds;
  final ValueChanged<int> onAdjust;
  final VoidCallback onDismiss;

  /// Whether the keypad is open underneath this bar. The keypad holds the
  /// bottom inset when it is there, and two widgets both insetting for one
  /// gesture bar leaves a band of surface between them.
  final bool aboveKeypad;

  @override
  Widget build(BuildContext context) {
    // The bar keeps its own clock: the log screen does not rebuild itself once
    // a second on everyone's behalf.
    return Ticking(builder: _build);
  }

  Widget _build(BuildContext context) {
    final c = context.c;
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    final remaining = targetSeconds - elapsed;
    final over = remaining < 0;
    final progress = (elapsed / targetSeconds).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        bottom: !aboveKeypad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: c.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(over ? c.positive : c.accent),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              child: Row(
                children: [
                  // **The clock takes what is left, not what it wants.**
                  //
                  // A `Spacer` between two groups of natural size holds only
                  // until the row is narrower than the two groups together, and
                  // the bar stays up while the keypad is open — which on a
                  // small screen overflows by a few pixels. The striped band
                  // that draws over an overflow is not something to put under a
                  // set. The controls are fixed and the words give way
                  // instead.
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          over
                              ? Icons.check_circle_outline
                              : Icons.timer_outlined,
                          size: 18,
                          color: over ? c.positive : c.textSecondary,
                        ),
                        const SizedBox(width: Space.md),
                        // Counting up past zero is a number nobody acts on, so
                        // the bar states the fact and stops. What was actually
                        // rested is still measured from `startedAt` by the log
                        // screen.
                        if (over)
                          Flexible(
                            child: Text(
                              'Rest finished',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.t.titleMedium?.copyWith(
                                color: c.positive,
                              ),
                            ),
                          )
                        else ...[
                          Text(
                            _format(remaining),
                            style: context.t.titleMedium?.copyWith(
                              fontFeatures: tabular,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          // The one word here that can be dropped without
                          // losing a fact: the clock beside it is the timer.
                          Flexible(
                            child: Text(
                              'rest',
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: context.t.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!over) ...[
                    _StepButton(label: '−30', onTap: () => onAdjust(-30)),
                    const SizedBox(width: Space.sm),
                    _StepButton(label: '+30', onTap: () => onAdjust(30)),
                    const SizedBox(width: Space.sm),
                  ],
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.surfaceHigh,
      borderRadius: BorderRadius.circular(Radii.cell),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.cell),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          child: Text(
            label,
            style: context.t.labelMedium?.copyWith(color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}
