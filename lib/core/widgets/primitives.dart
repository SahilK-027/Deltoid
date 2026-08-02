import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// The component vocabulary from THEME.md §5. Feature code composes these; it
/// does not draw its own cards, rows, buttons or sheets.

/// Press feedback for anything with a shape: a small scale-down and a dim.
///
/// Scale reads instantly and works identically on a 26pt chip and a full-width
/// card, because in both cases the whole thing moves. It is the wrong feedback
/// for a **row** — 1% of a full-width strip is invisible — which is what
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
    // It used to build the detector anyway, opaque, which made it a hole in
    // whatever it sat inside: `LinkAction('Change')` inside a tappable row
    // swallowed every tap that landed on the word `Change`, so the one part of
    // the row that names the action was the one part that did not perform it.
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
    this.topGap = Space.md,
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

  /// The gap between the status bar and the first line of the header. 12 is
  /// right when something small sits at the top — an eyebrow, or a row of
  /// buttons above the header. A page whose title is its first line needs more,
  /// or 30sp of uppercase starts hard against the notch and the band reads as
  /// part of the system bar rather than as the page.
  final double topGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        topGap,
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
                      // Sentence case. Uppercase was doing the work of size and
                      // weight, which `pageTitle` already has at 30/800 — and
                      // it cost every title its word shapes, which is what you
                      // actually read a heading by. It also made a long session
                      // name ellipsize sooner, for nothing.
                      title,
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

/// A spoken heading that divides a page into parts, with an optional link or
/// one small figure on the right. Sits on the page background — never inside a
/// card.
///
/// **Every heading on a page background is this widget**, so that the type, the
/// 12 under it and the alignment of whatever sits on its right are decided in
/// one place. History's month headings were a hand-rolled `Row` of
/// `headlineSmall` plus a count for exactly as long as it took for its padding
/// to drift from everyone else's.
///
/// **One line.** There is no subtitle slot: a heading that carries a sentence
/// is a different height than the heading above it, so no two sections on a
/// page start at the same distance from their content. What the sentence says
/// belongs to the thing it describes — inside the card, where it is read with
/// the numbers rather than above them.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.trailing,
  }) : assert(
          trailing == null || actionLabel == null,
          'A heading has one thing on its right: a link or a figure.',
        );

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A figure that belongs to the heading rather than to the rows under it —
  /// a month's session count. Not a control; use [actionLabel] for that.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: context.t.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: Space.sm),
            LinkAction(actionLabel!, onTap: onAction),
          ] else if (trailing != null) ...[
            const SizedBox(width: Space.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Tertiary action: primary-colour text with a small chevron. Not a coloured
/// link — colour is data, and "See all" is not data.
///
/// No underline. Some of these were underlined and some weren't, depending on
/// whether the screen used this widget or wrote its own `Text`, and a rule
/// under a word is the one decoration in the app that has to be perfectly
/// consistent to read as anything but a mistake. The chevron says "goes
/// somewhere" without needing to be.
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible, because a link is usually the right-hand half of a
            // `SectionHeader` row and its label is often an exercise name. On a
            // narrow phone, or inside a card, "All Bulgarian split squat
            // history" is wider than what is left of the line.
            Flexible(
              child: Text(
                label,
                style: context.t.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Space.xxs),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

// `SectionLabel` — an uppercase eyebrow over a group — was here, unused by any
// screen, and it contradicted the rule the type scale is built on: uppercase
// appears in exactly two places, the page title and the page eyebrow (THEME
// §3). A component nothing calls is a second answer to a question
// [SectionHeader] already answers.

/// The one search box. Three screens filter a list of exercises and each one
/// drew its own — different glyph, different hint colour, one of them with no
/// focused outline at all.
///
/// Everything about how it looks comes from `inputDecorationTheme`; this only
/// adds the glyph and the text size, which is `bodyLarge` because a search box
/// is typed into.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: context.t.bodyLarge?.copyWith(color: c.textPrimary),
      cursorColor: c.textPrimary,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: c.textTertiary),
      ),
    );
  }
}

/// The gap a search box sits in, above the list it filters. The same on a
/// screen and in a sheet — the box is the first thing under whatever header is
/// there, and 12 is the gap in both.
const searchFieldPadding = EdgeInsets.fromLTRB(
  Space.gutter,
  Space.md,
  Space.gutter,
  Space.md,
);

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
      // Clipped, so a row's ink stops at the card's corner instead of painting
      // a square one over it.
      clipBehavior: Clip.antiAlias,
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
    this.ink = true,
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

  /// Set false where the row's own trailing control is the feedback — a radio
  /// that snaps under the finger says "taken" faster than a wash crossing the
  /// row, and the two together read as two answers to one tap.
  final bool ink;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Space.lg,
        // A row carrying two lines needs more air than one carrying a label,
        // or the subtitle crowds the hairline under it and the list reads as
        // one grey block rather than as rows.
        vertical: subtitle == null ? Space.md : Space.lg,
      ),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            SizedBox(
              width: 40,
              // Flush left in its column, not centred in it. Centred, the glyph
              // stood 9pt in from the gutter the title above it starts at, and
              // left only 9pt of gap before the text — the icon looked both
              // indented and crowded at once.
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(icon, size: 24, color: tint ?? c.textPrimary),
              ),
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
    return InkRow(onTap: onTap, ink: ink, child: row);
  }
}

/// A tappable row, with ink.
///
/// The one place this app uses a ripple, and the reason is that a row has
/// nothing else to move: [Pressable]'s scale reads on a card, a chip or a
/// button because the whole shape travels, and on a full-width row against an
/// identical row above it, 1% of scale is invisible. A wash spreading from
/// where the finger landed is the only feedback a flat list can give.
///
/// It is not the app-wide default — `splashFactory` stays [NoSplash] and every
/// other surface keeps scale-and-dim (THEME §4). This asks for ink explicitly.
class InkRow extends StatelessWidget {
  const InkRow({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.ink = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// False keeps the press highlight and the haptic but drops the spreading
  /// wash, for rows whose own control already answers the tap.
  final bool ink;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        // Explicit, because the theme turns splashes off globally. `InkSparkle`
        // is the Android 12 ripple: a soft radial wash bounded to the row,
        // which falls off at the edges rather than stopping at them, and plays
        // to completion after the finger has gone.
        splashFactory: ink ? InkSparkle.splashFactory : NoSplash.splashFactory,
        // Tuned for charcoal. Material's default is `onSurface` at 12%, which
        // on `#1F1F1F` is a grey smear; a low-alpha white spreads as light
        // rather than as dirt, and reads on the light theme as a shadow.
        splashColor: c.textPrimary.withValues(alpha: 0.10),
        highlightColor: c.textPrimary.withValues(alpha: 0.04),
        child: child,
      ),
    );
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
    this.expand = false,
  });

  final List<({T value, String label})> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Stretch to the width available, segments sharing it equally. For a control
  /// that governs the whole page under it — a track hugging two short words on
  /// the left of an otherwise empty band reads as something left over.
  final bool expand;

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
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final segment in segments)
            if (expand)
              Expanded(
                child: Pressable(
                  onTap: () => onChanged(segment.value),
                  scale: 0.96,
                  child: AnimatedContainer(
                    duration: Motion.base,
                    curve: Motion.emphasized,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: segment.value == value
                          ? c.accent
                          : Colors.transparent,
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
              )
            else
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

/// Tabs with a white underline under the live one (THEME §7 day tabs, §8
/// exercise detail).
///
/// A strip, not a list: a training day is a context you switch, not an item you
/// scroll past. It scrolls horizontally and bleeds off the right edge, so the
/// clipped tab is the affordance — the same rule the chip rows follow.
///
/// [trailing] is a tab that is not one of the choices: `Add day +`, always last.
class UnderlineTabs extends StatefulWidget {
  const UnderlineTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
    this.trailingLabel,
    this.onTrailing,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  final String? trailingLabel;
  final VoidCallback? onTrailing;

  @override
  State<UnderlineTabs> createState() => _UnderlineTabsState();
}

class _UnderlineTabsState extends State<UnderlineTabs> {
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(UnderlineTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _reveal();
  }

  /// A day added at the end, or selected off-screen, has to come into view by
  /// itself — otherwise adding your sixth day looks like nothing happened.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[widget.index]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: Motion.base,
        curve: Motion.curve,
        alignment: 0.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 48,
      // Full width, or the strip is only as wide as the tabs in it — and a
      // `Column` centres a child narrower than itself, so a regime with one day
      // put `Legs` and `Add day +` in the middle of the band while a regime
      // with six had them against the gutter like everything else.
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Row(
          children: [
            for (var i = 0; i < widget.labels.length; i++)
              _Tab(
                key: _keys[i] ??= GlobalKey(),
                label: widget.labels[i],
                selected: i == widget.index,
                onTap: () => widget.onSelect(i),
              ),
            if (widget.trailingLabel != null)
              _Tab(
                label: widget.trailingLabel!,
                selected: false,
                tint: c.textTertiary,
                onTap: widget.onTrailing,
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tint,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      // `IntrinsicWidth` is what makes the stretch below legal. The strip is a
      // horizontal scroll, so the tab's incoming width is unbounded, and a
      // stretching column in unbounded space asks for an infinite width — one
      // "BoxConstraints forces an infinite width" at the top and then a hundred
      // "RenderBox was not laid out" behind it, which is the whole screen gone.
      // This measures the label first and gives the column a tight width.
      child: IntrinsicWidth(
        child: Column(
          // Stretch, so the rule is exactly as wide as the word above it. A
          // fixed width underlines `Legs` and `Upper body A` identically, which
          // reads as a marker parked near the tab rather than as the tab being
          // live.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.md, Space.md, Space.md, Space.sm),
              child: Text(
                label,
                style: context.t.titleMedium?.copyWith(
                  color: selected ? c.textPrimary : (tint ?? c.textSecondary),
                ),
              ),
            ),
            AnimatedContainer(
              duration: Motion.base,
              curve: Motion.emphasized,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? c.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ],
        ),
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
      child: Icon(icon, size: size * 0.5, color: solid ? glyphOn(tint) : tint),
    );
  }

  /// The glyph is **the fill's own hue, taken down** — not white, not black.
  ///
  /// White was the rule for a long time and broke outright on the old saturated
  /// yellow (1.9:1). Swapping to near-black fixed the ratio and lost the point:
  /// a tile is one colour with a shape cut out of it, and a black shape makes it
  /// two. Same hue, same saturation, less light — the mark stays "the green one"
  /// at arm's length, which is the only job it has.
  ///
  /// Solved rather than multiplied. A fixed `× 0.4` lands between 2.9:1 and
  /// 3.7:1 depending on where a hue sits, which is the uneven-set problem again
  /// one level down. This walks the lightness down until the glyph clears
  /// [_glyphContrast] against its own fill, so every tile in both themes reads
  /// at the same strength.
  static Color glyphOn(Color fill) {
    final hsl = HSLColor.fromColor(fill);
    for (var l = hsl.lightness; l >= 0.04; l -= 0.01) {
      final candidate = hsl.withLightness(l).toColor();
      if (_contrast(candidate, fill) >= _glyphContrast) return candidate;
    }
    // An almost-black fill has no room left below it: go up instead, which is
    // the same rule read the other way.
    for (var l = hsl.lightness; l <= 0.96; l += 0.01) {
      final candidate = hsl.withLightness(l).toColor();
      if (_contrast(candidate, fill) >= _glyphContrast) return candidate;
    }
    return hsl.withLightness(0.04).toColor();
  }

  /// Enough to name the shape at 22pt, not so much that the tile reads as two
  /// colours. 3:1 is the floor for a graphic; this sits just above it.
  static const _glyphContrast = 3.2;

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// The §5 radio: selected is a filled disc with a dark dot punched out of it,
/// unselected a 2px ring in `textTertiary`. No accent hue, and no Material
/// `Radio`, whose ripple and 48pt slop belong to a different design language.
///
/// It is the trailing control of an [AppRow] — a list of rows that are one
/// choice each, where a [SegmentedPill] would put three words in a track and
/// lose the room to say what each one means.
class AppRadio extends StatelessWidget {
  const AppRadio({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.curve,
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.accent : Colors.transparent,
        border: Border.all(
          color: selected ? c.accent : c.textTertiary,
          width: 2,
        ),
      ),
      child: selected
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.onAccent,
              ),
            )
          : null,
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

/// The header every sheet wears: title centred, subtitle under it, ✕ on the
/// right, hairline beneath.
///
/// The ✕ is on the **right** and larger than a row's glyph: it is the one
/// control on the sheet that is not one of the choices, and on the left it read
/// as the first item in the list rather than as the way out.
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
        // The grab handle, drawn here rather than by the framework. Material's
        // own sits in a 48pt interactive box, which put an inch of empty
        // charcoal over every sheet title; this is the same 36×4 bar with the
        // gap the design actually asks for.
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: Space.sm),
          decoration: BoxDecoration(
            color: c.surfaceHighest,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
        ),
        Padding(
          // Equal room above and below the title — 16 from the handle, 16 to
          // the hairline. The gap above used to be the handle's margin plus a
          // header inset, which made it wider than the one below for no reason
          // anyone could name.
          padding:
              const EdgeInsets.fromLTRB(Space.sm, Space.lg, Space.sm, Space.lg),
          // A stack, not a row: the ✕ is a 48pt tap target and the title on its
          // own is 26 tall, so in a row the button set the header's height and
          // left 22pt of dead charcoal under a one-line title. Out of the flow,
          // the text decides how tall the header is and the target overhangs it
          // into the handle's gap, where there is nothing to collide with.
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Padding(
                // Room for the ✕ on both sides, so the title is centred on the
                // sheet rather than on what is left of it.
                padding: const EdgeInsets.symmetric(horizontal: 48),
                // Full width on purpose: a `Stack` takes its size from its
                // largest unpositioned child, so a shrink-wrapped title made
                // the stack as narrow as the words in it and `right: 0` landed
                // beside the title instead of at the sheet's edge.
                child: SizedBox(
                  width: double.infinity,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Centred on the title's line — it closes the sheet, and centring
              // it on the whole block dragged it down beside a subtitle it has
              // nothing to do with.
              Positioned(
                right: 0,
                top: -11,
                child: CircleIconButton(
                  icon: Icons.close_rounded,
                  fill: Colors.transparent,
                  size: 48,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
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
    this.contentPadding,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Overrides the body's insets. Pass `EdgeInsets.zero` for a sheet whose
  /// content is full-bleed rows — a card inside a sheet is a panel inside a
  /// panel, and the gutter then double-insets rows that already carry their
  /// own padding.
  final EdgeInsets? contentPadding;

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
              padding: contentPadding ??
                  const EdgeInsets.fromLTRB(
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

/// Writes a note. The one text-entry surface in the app, and a sheet.
///
/// Every note used to be typed into a centred `AlertDialog` with Material's own
/// buttons on it — the one surface the rebrand never reached, and the one used
/// most. It also opened in the middle of the screen while the row that summoned
/// it sat at the bottom, and it fought the keyboard for the same space.
///
/// Returns the trimmed text, or null if dismissed. **Empty is a valid answer**:
/// a note you can write and never clear is a note you stop writing.
Future<String?> promptForNote(
  BuildContext context, {
  required String title,
  String? subtitle,
  String initial = '',
  String? hint,
  int maxLength = 500,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    // The sheet rides above the keyboard rather than behind it.
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: _NoteSheet(
        title: title,
        subtitle: subtitle,
        initial: initial,
        hint: hint,
        maxLength: maxLength,
      ),
    ),
  );
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.hint,
    required this.maxLength,
  });

  final String title;
  final String? subtitle;
  final String initial;
  final String? hint;
  final int maxLength;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      footer: PrimaryButton(
        label: 'Save',
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
      ),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          maxLength: widget.maxLength,
          // `120 / 500` — the convention, and the only form that says what the
          // limit *is* before you hit it. "60 left" answers a question you can
          // only ask once you are already near the end.
          buildCounter: (
            context, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) {
            final full = currentLength >= (maxLength ?? 0);
            return Text(
              '$currentLength / $maxLength',
              style: context.t.bodySmall?.copyWith(
                color: full ? context.c.negative : context.c.textTertiary,
              ),
            );
          },
          textCapitalization: TextCapitalization.sentences,
          style: context.t.bodyLarge?.copyWith(color: c.textPrimary),
          cursorColor: c.textPrimary,
          // Fill, radius, focused outline and padding all come from
          // `inputDecorationTheme` — `surfaceHigh` for the fill, and a white
          // 2px outline when focused. This field was on `surfaceSunken` once,
          // the keypad's bed, which on a `surface` sheet read as a hole rather
          // than as somewhere to type.
          decoration: InputDecoration(hintText: widget.hint),
        ),
      ],
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

// ─── Notices ────────────────────────────────────────────────────────────────

/// A stated limit or consequence, in `warning` yellow on its own tinted ground.
///
/// The one shape in the app for "this is why you can't". It exists because a
/// grey [EmptyBox] above a stack of greyed-out cards is indistinguishable from
/// the greyed-out cards: everything on the screen was off, and nothing on it
/// said which part was the reason.
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
        borderRadius: BorderRadius.circular(Radii.lg),
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
                  Text(title!,
                      style: context.t.titleSmall?.copyWith(color: c.warning)),
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
