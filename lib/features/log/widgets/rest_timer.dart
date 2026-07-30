import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

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
  });

  final DateTime startedAt;
  final int targetSeconds;
  final ValueChanged<int> onAdjust;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
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
                  Icon(
                    over ? Icons.check_circle_outline : Icons.timer_outlined,
                    size: 18,
                    color: over ? c.positive : c.textSecondary,
                  ),
                  const SizedBox(width: Space.md),
                  // Counting up past zero is a number nobody acts on, so the
                  // bar states the fact and stops. What was actually rested is
                  // still measured from `startedAt` by the log screen.
                  if (over)
                    Text(
                      'Rest done',
                      style: context.t.titleMedium?.copyWith(
                        color: c.positive,
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
                    Text('rest', style: context.t.labelSmall),
                  ],
                  const Spacer(),
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
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
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
