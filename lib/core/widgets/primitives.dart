import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// The component vocabulary from THEME.md §5. Feature code composes these; it
/// does not draw its own cards, rows, buttons or sheets.

/// Press feedback for the whole app: a small scale-down and a dim, never an
/// ink ripple.
///
/// A ripple on charcoal is either invisible or a grey smear across the corner
/// radius, and it arrives *after* the finger. Scale reads instantly and works
/// identically on a 26pt chip and a full-width card.
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

// ─── Page furniture ─────────────────────────────────────────────────────────

/// The masthead: a small tracked eyebrow over a heavy uppercase title, both
/// inside the header band. One per screen, and the only uppercase on it.
///
/// Eyebrow and title are one block, and the actions sit beside it — the title's
/// baseline is the header's baseline. The actions were briefly moved up onto
/// the eyebrow's line to buy the title the full page width; it bought room the
/// title did not need and left the buttons floating against a 13sp line. A
/// third line was briefly added *inside* the block, which re-centred the
/// buttons against three lines and dragged them below the date. Both reverted:
/// the buttons align to the eyebrow-and-title pair, and nothing else.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.actions = const [],
    this.below,
    this.belowGap = Space.md,
  });

  final String title;

  /// Usually the date. Uppercased here, not by the caller.
  final String? eyebrow;

  final List<Widget> actions;

  /// Anything that belongs to the header rather than the page — a status line,
  /// a tab strip.
  final Widget? below;

  /// The gap above [below]. Smaller when what follows is a line *about* the
  /// title — a status reads as belonging to the date it sits under only if it
  /// is nearer to it than to whatever comes next.
  final double belowGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow!.toUpperCase(),
                        style: context.t.labelMedium,
                      ),
                      const SizedBox(height: Space.xs),
                    ],
                    Text(
                      title.toUpperCase(),
                      style: context.t.displayLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              for (final action in actions) ...[
                const SizedBox(width: Space.sm),
                action,
              ],
            ],
          ),
          if (below != null) ...[SizedBox(height: belowGap), below!],
        ],
      ),
    );
  }
}

/// The band the header sits in: `surface`, running edge to edge, ending in a
/// hairline. It is what separates "who I am" from "what I did".
class HeaderBand extends StatelessWidget {
  const HeaderBand({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      color: c.surface,
      child: SafeArea(bottom: false, child: child),
    );
  }
}

/// A spoken heading that divides a page into parts, with an optional underlined
/// link on the right. Sits on the page background — never inside a card.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.t.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    subtitle!,
                    style: context.t.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: Space.sm),
            LinkAction(actionLabel!, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

/// Tertiary action: underlined text in the primary colour. Not a coloured link
/// — colour is data, and "See all" is not data.
class LinkAction extends StatelessWidget {
  const LinkAction(this.label, {super.key, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Text(
          label,
          style: context.t.titleMedium?.copyWith(
            decoration: TextDecoration.underline,
            // A hairline. At 1.5 the rule was heavier than the stems of the
            // word above it, which made every link look like a heading with a
            // border under it rather than something to tap.
            decorationThickness: 1,
            decorationColor: c.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Uppercase eyebrow above a group. Kept for the few places a group needs a
/// whisper rather than a heading; prefer [SectionHeader].
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(), style: context.t.labelSmall),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ─── Surfaces ───────────────────────────────────────────────────────────────

/// The standard grouped container: one lifted surface, one radius, **no border
/// and no shadow**. Depth in this app is surface colour.
///
/// A card is a grouping device, not a frame. A page of six cards has no
/// hierarchy — prefer one [ListCard] holding rows.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.onTap,
    this.onLongPress,
    this.fill,
    this.outline,
    this.radius = Radii.xl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Replaces `surface`. For the one card a screen is about.
  final Color? fill;

  /// An outline, for the two cases that earn one: a selected choice card (2px
  /// [DeltoidColors.accent]) and an empty-state box (1px border).
  final BorderSide? outline;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final content = AnimatedContainer(
      duration: Motion.base,
      curve: Motion.curve,
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: outline == null ? null : Border.fromBorderSide(outline!),
      ),
      child: child,
    );

    if (onTap == null && onLongPress == null) return content;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.985,
      child: content,
    );
  }
}

/// A card that holds rows, with the hairlines between them inset to the text.
/// The workhorse: settings, session lists, exercise lists, menus.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children, this.inset = 56});

  final List<Widget> children;

  /// Where the divider starts. Matches the leading icon column so the rule
  /// lines up with the text, not with the card edge.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.only(left: inset),
                child: Divider(color: c.border, height: 1),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row inside a [ListCard]: bare white glyph, title, optional subtitle,
/// trailing control. 56 tall, 72 with a subtitle.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.tint,
    this.chevron = false,
  });

  final String title;
  final String? subtitle;

  /// A bare glyph. Colour it only to mark something semantic (a destructive
  /// action, a deload).
  final IconData? icon;

  /// Replaces [icon] outright — an [IconTile] for an identity, a thumbnail.
  final Widget? leading;

  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? tint;

  /// Adds the standard chevron. Ignored when [trailing] is set.
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            SizedBox(
              width: 40,
              child: Icon(icon, size: 22, color: tint ?? c.textPrimary),
            ),
          if (leading != null) const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.t.titleMedium?.copyWith(color: tint),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    subtitle!,
                    style: context.t.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Space.md),
            trailing!,
          ] else if (chevron) ...[
            const SizedBox(width: Space.sm),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.textTertiary),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Pressable(onTap: onTap, scale: 0.99, child: row);
  }
}

// ─── Buttons ────────────────────────────────────────────────────────────────

/// The one loud action on a screen: full width, white, dark label.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Overrides the fill. Only for a destructive confirm, never for emphasis.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onPressed != null;
    final bg = enabled ? (tone ?? c.accent) : c.surfaceHigh;
    final fg = enabled
        ? (tone == null ? c.onAccent : Colors.white)
        : c.textTertiary;

    return Pressable(
      onTap: onPressed,
      scale: 0.975,
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.curve,
        height: 54,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: Space.sm),
            ],
            Flexible(
              child: Text(
                label,
                style: context.t.titleMedium?.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quiet twin of [PrimaryButton]. Same metrics, grey fill.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onPressed != null;
    final fg = enabled ? c.textPrimary : c.textTertiary;

    return Pressable(
      onTap: onPressed,
      scale: 0.975,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: Space.sm),
            ],
            Flexible(
              child: Text(
                label,
                style: context.t.titleMedium?.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A circular icon control. A bare `IconButton` floating on charcoal has no
/// edges and reads as decoration.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.tint,
    this.fill,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? tint;
  final Color? fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final button = Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? c.surfaceHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size * 0.45, color: tint ?? c.textPrimary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Filter / action chip. Selected is a white fill, not a coloured one.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
    this.caret = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  /// Marks a chip that opens a picker rather than toggling.
  final bool caret;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = selected ? c.onAccent : c.textPrimary;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.curve,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: Space.sm),
            ],
            Text(label, style: context.t.bodySmall?.copyWith(color: fg)),
            if (caret) ...[
              const SizedBox(width: Space.xs),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

/// Segmented control: a grey track with a white pill behind the live segment.
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<({T value, String label})> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            Pressable(
              onTap: () => onChanged(segment.value),
              scale: 0.96,
              child: AnimatedContainer(
                duration: Motion.base,
                curve: Motion.emphasized,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: segment.value == value ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  segment.label,
                  style: context.t.bodySmall?.copyWith(
                    color: segment.value == value
                        ? c.onAccent
                        : c.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Marks ──────────────────────────────────────────────────────────────────

/// A rounded square holding one icon, tinted to an identity colour. The mark
/// that lets a history list be scanned rather than read.
///
/// Reserved for identities (a regime, a session). A row's ordinary leading
/// glyph is bare — see [AppRow].
class IconTile extends StatelessWidget {
  const IconTile(
    this.icon, {
    super.key,
    this.color,
    this.size = 44,
    this.solid = true,
  });

  final IconData icon;
  final Color? color;
  final double size;

  /// Filled in [color] with the glyph knocked out. Off gives a tinted wash for
  /// a mark that must not outshout its row.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = color ?? c.info;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: solid ? tint : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: solid ? Colors.white : tint),
    );
  }
}

/// One number and what it means. Built for a row of siblings, so captions line
/// up across tiles even when one wraps.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.emphasis,
    this.unit,
  });

  final String value;
  final String label;

  /// Trails the value at body size — `kg` is never set in the value size.
  final String? unit;

  /// Paints the value. Only for a semantic reading (a record, a deload).
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: context.t.displaySmall?.copyWith(color: emphasis),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: Space.xs),
              Text(unit!, style: context.t.bodyMedium),
            ],
          ],
        ),
        const SizedBox(height: Space.xxs),
        Text(label, style: context.t.bodySmall, maxLines: 2),
      ],
    );
  }
}

/// Small status pill. Tinted, never filled, unless it is the one live state on
/// the screen.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon, this.solid = false});

  final String text;
  final Color? color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = color ?? c.textSecondary;
    final fg = solid ? c.onAccent : tint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? tint : tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: Space.xs),
          ],
          Text(text, style: context.t.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

// ─── Sheets and confirmations ───────────────────────────────────────────────

/// The header every sheet wears: ✕ on the left, title centred, subtitle under
/// it, hairline beneath.
///
/// The subtitle is not optional in spirit: two sheets that both list session
/// names are indistinguishable without one line saying which question is being
/// asked.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.md),
          child: Row(
            children: [
              CircleIconButton(
                icon: Icons.close_rounded,
                fill: Colors.transparent,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      title,
                      style: context.t.headlineSmall,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: Space.xxs),
                      Text(
                        subtitle!,
                        style: context.t.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),
        Divider(color: c.border, height: 1),
      ],
    );
  }
}

/// Wraps sheet content: header, scrollable body, safe area.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Pinned under the scroll area — a Save button, usually.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: title, subtitle: subtitle),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                Space.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.lg,
              ),
              child: footer!,
            ),
        ],
      ),
    );
  }
}

/// Yes/no gate in front of anything that loses work.
///
/// Bottom-anchored, not a centred alert, and never two equal text buttons in a
/// row: the dangerous option is the loud one and the safe option is the quiet
/// one. The message says what happens, never "are you sure".
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Go back',
  bool destructive = true,
}) async {
  final answer = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) {
      final c = ctx.c;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.xl,
            Space.xl,
            Space.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(title, style: ctx.t.headlineSmall)),
                  const SizedBox(width: Space.md),
                  CircleIconButton(
                    icon: Icons.close_rounded,
                    fill: Colors.transparent,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                message,
                style: ctx.t.bodyLarge?.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: confirmLabel,
                tone: destructive ? c.negative : null,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: Space.xs),
              Pressable(
                onTap: () => Navigator.of(ctx).pop(false),
                scale: 0.97,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Text(cancelLabel, style: ctx.t.titleMedium),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return answer ?? false;
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
        borderRadius: BorderRadius.circular(Radii.lg),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(Radii.xxl),
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
            if (action != null) ...[const SizedBox(height: Space.xxl), action!],
          ],
        ),
      ),
    );
  }
}
