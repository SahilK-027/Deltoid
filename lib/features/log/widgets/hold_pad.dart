import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ticking.dart';
import 'keypad.dart' show PadKey;

/// The keypad's replacement for a timed hold: a stopwatch, not ten digits.
///
/// A plank is not a number you know — it is a number you find out. Typing `62`
/// into a cell after a hold means reading a clock somewhere else and copying
/// it, and nobody does that with their forearms on the floor. This takes the
/// same docked slot the keypad takes, so the set table stays visible above it,
/// and asks for two taps: start, and stop.
///
/// Stopping writes the elapsed seconds, ticks the set and starts the rest
/// clock — the same thing leaving a reps field does, because it is the same
/// moment.
///
/// It counts **up**, with last time marked on the bar rather than counting
/// down to it. A countdown makes last time a ceiling you stop at; a hold is
/// the one thing in this app where "as long as you can" is the instruction,
/// and the clock going past the mark and turning green is the whole event.
class HoldPad extends StatefulWidget {
  const HoldPad({
    super.key,
    required this.onStop,
    required this.onType,
    this.current,
    this.previous,
  });

  /// Elapsed seconds, once the clock is stopped.
  final ValueChanged<int> onStop;

  /// Falls back to the digits, for a hold timed on the gym clock or a set
  /// being corrected hours later.
  final VoidCallback onType;

  /// What this set already holds, if anything.
  final int? current;

  /// Last time's hold for this slot: the mark on the bar, and the moment the
  /// clock turns green.
  final int? previous;

  @override
  State<HoldPad> createState() => _HoldPadState();
}

class _HoldPadState extends State<HoldPad> {
  DateTime? _startedAt;

  int get _elapsed => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inSeconds;

  void _start() {
    HapticFeedback.mediumImpact();
    setState(() => _startedAt = DateTime.now());
  }

  void _stop() {
    final seconds = _elapsed;
    setState(() => _startedAt = null);
    // A stop inside the first second is a mis-tap, not a one-second plank.
    if (seconds <= 0) return;
    HapticFeedback.mediumImpact();
    widget.onStop(seconds);
  }

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
              Row(
                children: [
                  // Only while the clock is stopped. Offering "type it" mid-set
                  // is offering to throw the running clock away.
                  //
                  // A pill rather than bare text: it is the one control on this
                  // pad that is not the clock, and a word on its own beside a
                  // 44sp readout does not read as something you can press.
                  if (_startedAt == null)
                    Material(
                      color: c.surfaceHigh,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        onTap: widget.onType,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                            vertical: Space.xs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.keyboard_outlined,
                                size: 16,
                                color: c.textSecondary,
                              ),
                              const SizedBox(width: Space.xs),
                              Text(
                                'Type it',
                                style: context.t.bodySmall?.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Holds the row's height when the pill goes, so the clock
                  // below does not jump up the moment the hold starts.
                  const SizedBox(height: 28),
                ],
              ),
              // Only the clock ticks. Everything else here is static, and the
              // set table above it must not repaint once a second.
              Ticking(builder: _clock),
              const SizedBox(height: Space.md),
              // Stop is the accent key, in the place the keypad's `Next` sits:
              // the action that ends the set is the action under your thumb.
              PadKey(
                icon: _startedAt != null
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                label: _startedAt != null ? 'Stop' : 'Start hold',
                accent: _startedAt != null,
                haptic: false,
                onTap: _startedAt == null ? _start : _stop,
              ),
              const SizedBox(height: Space.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clock(BuildContext context) {
    final c = context.c;
    final previous = widget.previous;
    final running = _startedAt != null;
    // Stopped, the pad shows what the set already holds, so re-opening a
    // logged hold reads as a record rather than as a clock at zero.
    final shown = running ? _elapsed : (widget.current ?? 0);
    final beaten = previous != null && shown > previous;

    return Column(
      children: [
        Text(
          _format(shown),
          // 44, over the 30sp cap, and the one place in the app that goes over
          // it — see THEME → Type. Read from the floor mid-plank, not a
          // heading competing with a page title.
          style: context.t.displayMedium?.copyWith(
            fontSize: 44,
            height: 1.1,
            color: beaten ? c.positive : c.textPrimary,
          ),
        ),
        const SizedBox(height: Space.sm),
        if (previous == null)
          Text(
            running ? 'Holding' : 'No previous hold to compare against',
            style: context.t.labelSmall,
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (shown / previous).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: c.surfaceHighest,
              valueColor: AlwaysStoppedAnimation(beaten ? c.positive : c.accent),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            beaten
                ? 'Past last time by ${shown - previous}s'
                : 'Last time ${_format(previous)}',
            style: context.t.labelSmall?.copyWith(
              color: beaten ? c.positive : c.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  /// `1:05`, not `65s`. A clock being watched second by second is the one
  /// place in this app minutes are worth the colon — the set table still
  /// prints the bare seconds it stores.
  static String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
