part of '../primitives.dart';

// ─── Notices ────────────────────────────────────────────────────────────────

/// A stated limit or consequence, in `warning` yellow on its own tinted ground.
///
/// The single component used to state why an action is unavailable. A grey
/// [EmptyBox]
/// above a stack of greyed-out cards is indistinguishable from the greyed-out
/// cards: everything on the screen is off, and nothing on it says which part is
/// the reason.
///
/// Yellow rather than red: `negative` is for destroying something, and a limit
/// destroys nothing. Its own token rather than `deload`'s amber, so a light
/// week and a refused action can be retuned independently.
///
/// Not for errors, and not for anything the user can dismiss. A notice states a
/// rule that is currently true.
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, required this.message, this.icon, this.title});

  final String message;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.warningMuted,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.warning_amber_rounded, size: 22, color: c.warning),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: context.t.titleSmall?.copyWith(color: c.warning),
                  ),
                  const SizedBox(height: Space.xxs),
                ],
                Text(
                  message,
                  // Body text, not yellow: the hue is the flag, and a whole
                  // paragraph in it reads as an error rather than a rule.
                  style: context.t.bodyMedium?.copyWith(color: c.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty states ───────────────────────────────────────────────────────────

/// An outlined box explaining what will appear in a region once there is
/// something to show. Inline — for a whole blank screen, use [EmptyState].
class EmptyBox extends StatelessWidget {
  const EmptyBox({
    super.key,
    required this.message,
    this.icon,
    this.dashed = false,
  });

  final String message;
  final IconData? icon;

  /// For a drop target rather than an empty region.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 26, color: c.textTertiary),
            const SizedBox(width: Space.lg),
          ],
          Expanded(child: Text(message, style: context.t.bodyMedium)),
        ],
      ),
    );
  }
}

/// Shown when a screen is genuinely empty. Explains the next action rather than
/// leaving a blank rectangle.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The scroll view is the outer widget and the centring happens inside it,
    // against a minimum height rather than a `Center`.
    //
    // The other way round — `Center(child: SingleChildScrollView(...))` — the
    // scroll view shrink-wraps its content and is then centred, so the
    // viewport is both shorter than the page and no taller than what it holds.
    // Content is clipped against its top *and* bottom edges, mid-screen, with
    // blank page either side, and scrolling uncovers nothing in either
    // direction because there is no free extent to scroll through.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxxl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - Space.xxxl * 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: c.surfaceHigh,
                  borderRadius: BorderRadius.circular(Radii.sheet),
                ),
                child: Icon(icon, color: c.textPrimary, size: 28),
              ),
              const SizedBox(height: Space.xl),
              Text(
                title,
                style: context.t.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.t.bodyMedium,
              ),
              if (action != null) ...[
                const SizedBox(height: Space.xxl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
