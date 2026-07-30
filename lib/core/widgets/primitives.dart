import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Uppercase eyebrow above a group. Used instead of heavy headers to keep the
/// hierarchy quiet.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: Space.xs,
        right: Space.xs,
        bottom: Space.xs,
      ),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: context.t.labelSmall)),
          ?trailing,
        ],
      ),
    );
  }
}

/// The standard grouped container. One radius, one hairline, no shadows —
/// depth comes from surface colour, not elevation.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.onTap,
    this.highlightColor,
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Draws the outline in this colour instead of the usual hairline, for cards
  /// that need to stand out (an unfinished session, a deload).
  final Color? highlightColor;

  /// Replaces the usual surface. Only the one card a screen is *about* should
  /// use this — a page where three cards are tinted has no focal point, which
  /// is the state Today was in when every section looked equally important.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final content = AnimatedContainer(
      duration: Motion.fast,
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: highlightColor ?? c.border),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: content,
      ),
    );
  }
}

/// One number and what it means, stacked. Built for a row of siblings, so the
/// value sits on a fixed line height and the captions line up across tiles even
/// when one of them wraps.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.emphasis,
  });

  final String value;
  final String label;

  /// Paints the value. Null leaves it in the primary text colour — only the
  /// stat a card is arguing for should carry the accent.
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.t.titleLarge?.copyWith(
            color: emphasis,
            fontFeatures: tabular,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.xs),
        Text(
          label.toUpperCase(),
          style: context.t.labelSmall,
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Small status pill. `tone` picks the semantic colour.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = color ?? c.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: Space.xs),
          ],
          Text(
            text,
            style: context.t.labelSmall?.copyWith(color: fg, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

/// Yes/no gate in front of anything that loses work.
///
/// Every destructive action in the app goes through this, so the wording is
/// always "what happens", never "are you sure" — and [destructive] paints the
/// confirming button so the dangerous option is never the quiet one.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          style: destructive
              ? TextButton.styleFrom(foregroundColor: ctx.c.negative)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Shown when a list is genuinely empty. Explains the next action rather than
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Icon(icon, color: c.textTertiary, size: 24),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: context.t.titleMedium),
            const SizedBox(height: Space.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium,
            ),
            if (action != null) ...[
              const SizedBox(height: Space.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
