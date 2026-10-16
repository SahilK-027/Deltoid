import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

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

// ─── Page furniture ─────────────────────────────────────────────────────────

/// The masthead: a small tracked eyebrow over a heavy uppercase title, both
/// inside the header band. One per screen, and the only uppercase on it.
///
/// Eyebrow and title are one block, and the actions sit beside it — the title's
/// baseline is the header's baseline. The buttons align to the eyebrow-and-title
/// pair and to nothing else: moved up onto the eyebrow's line they buy the title
/// a full page width it does not need and float against a 13sp line, and a third
/// line *inside* the block re-centres them against three lines and drags them
/// below the date.
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
                      // Sentence case. Uppercase does the work of size and
                      // weight, which `pageTitle` already has at 30/800, and it
                      // costs every title its word shapes — what a heading is
                      // actually read by. It also ellipsizes a long session
                      // name sooner, for nothing.
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
/// Every heading on a page background uses this widget, so that the type, the
/// 12 under it and the alignment of whatever sits on its right are decided in
/// one place. A hand-rolled `Row` of `headlineSmall` plus a count — which is
/// what a month heading wants to be — drifts off everyone else's padding within
/// a week.
///
/// A single line. There is no subtitle slot: a heading carrying a sentence
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
/// No underline. A rule under a word is the one decoration in the app that has
/// to be perfectly consistent to read as anything but a mistake, and it will
/// not be while some screens use this and others write their own `Text`. The
/// chevron says "goes somewhere" without needing to be.
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

// There is deliberately no `SectionLabel` — an uppercase eyebrow over a group.
// It contradicts the rule the type scale is built on: uppercase appears in
// exactly two places, the page title and the page eyebrow (THEME → Type). A
// component nothing calls is also a second answer to a question
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

/// The standard grouped container: one raised surface, one radius, no border
/// and no shadow. Depth in this application is conveyed by surface colour.
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
    this.radius = Radii.card,
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

/// A block set into a card or a sheet: `surfaceHigh` at the control radius,
/// the material of a field or a quiet button, so it reads as part of the panel
/// it sits in rather than as a second card on top of it.
///
/// The session list on Workouts, the date row of a past session, the day's note
/// on the summary, the muscles a bar-list row opens onto.
class InsetPanel extends StatelessWidget {
  const InsetPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Space.lg,
      vertical: Space.md,
    ),
    this.margin,
    this.width,
    this.minHeight,
    this.outline,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// `double.infinity` for a panel that spans its column whatever it holds.
  final double? width;
  final double? minHeight;

  /// The choice-card state: 2px [DeltoidColors.accent] on the one that is
  /// next or chosen.
  final BorderSide? outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      constraints: minHeight == null
          ? null
          : BoxConstraints(minHeight: minHeight!),
      padding: padding,
      decoration: BoxDecoration(
        color: context.c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.control),
        border: outline == null ? null : Border.fromBorderSide(outline!),
      ),
      child: child,
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
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.only(left: inset),
                child: const Divider(),
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
    this.subtitleLeading,
    this.subtitleMaxLines = 2,
  });

  final String title;
  final String? subtitle;

  /// Sits at the head of the subtitle line, before [subtitle] — a dense
  /// [AppChip] for the one word in the description that is also a filter.
  ///
  /// It handles its own taps, so the row's [onTap] is not the only available
  /// action: the muscle chip on an exercise row selects that muscle in the
  /// filter strip above the list rather than opening the exercise.
  final Widget? subtitleLeading;

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

  /// How many lines the subtitle may take before it is cut.
  ///
  /// Two is right for a row on a page, where the subtitle is one clause and a
  /// third line would push the row past the one below it. A row inside a sheet
  /// is the opposite case: the sheet exists *because* the choice needs room to
  /// explain itself, and a description cut mid-sentence there defeats the only
  /// reason it was moved off the page. Raise it where the words are the point.
  final int subtitleMaxLines;

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
        vertical: subtitle == null && subtitleLeading == null
            ? Space.md
            : Space.lg,
      ),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            SizedBox(
              width: 40,
              // Flush left in its column, not centred in it. Centred, the
              // glyph stands 9pt in from the gutter the title above it starts
              // at and leaves only 9pt of gap before the text, which looks both
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
                if (subtitle != null || subtitleLeading != null) ...[
                  const SizedBox(height: Space.xxs),
                  if (subtitleLeading == null)
                    Text(
                      subtitle!,
                      style: context.t.bodyMedium,
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Row(
                      children: [
                        subtitleLeading!,
                        if (subtitle != null) ...[
                          const SizedBox(width: Space.sm),
                          // One line beside the chip, not two: the chip fixes
                          // the line's height, and a second line of text next
                          // to a 26pt pill leaves it floating against the first.
                          Expanded(
                            child: Text(
                              subtitle!,
                              style: context.t.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
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
/// other surface keeps scale-and-dim (THEME → Space). This asks for ink explicitly.
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

/// A row whose trailing control is a pair of steps around a value. The one
/// shape in the app for "a small number, changed one notch at a time".
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    this.helper,
  });

  final String label;
  final String value;
  final String? helper;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The helper runs the full width **under** the row, never in the
    // subtitle slot.
    //
    // A stepper is 36 + 76 + 36 of controls plus its gaps, so a subtitle
    // beside one gets about 130pt — nine or ten words over two lines, and
    // every helper here is longer than that. They were all being cut mid
    // sentence: "For an exercise that has not been given its own…". Moving
    // the rows into a sheet did not fix it, because the stepper takes the
    // same width wherever the row is drawn; only taking the sentence off
    // that line does.
    final row = AppRow(
      title: label,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleIconButton(
            icon: Icons.remove_rounded,
            size: 36,
            tooltip: 'Decrease',
            tint: onDecrement == null ? c.textTertiary : null,
            onTap: onDecrement,
          ),
          SizedBox(
            width: 76,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: context.t.labelLarge,
            ),
          ),
          CircleIconButton(
            icon: Icons.add_rounded,
            size: 36,
            tooltip: 'Increase',
            tint: onIncrement == null ? c.textTertiary : null,
            onTap: onIncrement,
          ),
        ],
      ),
    );

    if (helper == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          // Aligned with the title above it, and carrying the row's bottom
          // padding, the row itself having none to give.
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: Text(helper!, style: context.t.bodyMedium),
        ),
      ],
    );
  }
}

/// A spinner sized to sit where a row's glyph or chevron was.
///
/// A busy state is neither a disabled state nor an empty one. A row that drops
/// its
/// chevron and changes its title has told the user something happened; only a
/// moving thing tells them it is still happening. Sized inside the glyph box
/// rather than filling it, so it carries the same weight as the mark it stands
/// in for and the row does not change height.
class RowSpinner extends StatelessWidget {
  const RowSpinner({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: Sizes.glyph,
    height: Sizes.glyph,
    child: Center(
      child: SizedBox(
        width: Sizes.glyph - 4,
        height: Sizes.glyph - 4,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color ?? context.c.textSecondary,
        ),
      ),
    ),
  );
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
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Overrides the fill. Only for a destructive confirm, never for emphasis.
  final Color? tone;

  /// The width of its own words, 46 tall, rather than the width of the screen.
  ///
  /// For an action that adds a further item, rather than one that concludes a
  /// flow. Full width is a commitment — *this is what the screen is for* — and
  /// spending it on "New exercise" under a list of eighty of them puts the
  /// loudest shape on the page under the quietest intention, making a
  /// three-word label look like a banner. Finishing a session, saving an
  /// exercise, confirming a delete: those stay full width.
  final bool compact;

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
        height: compact ? Sizes.controlCompact : Sizes.control,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: Space.xl)
            : null,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (icon != null) ...[
              Icon(icon, size: Sizes.glyph, color: fg),
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
    this.fill,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// [DeltoidColors.surfaceHighest] for a button set into an [InsetPanel],
  /// where the usual `surfaceHigh` would be the panel's own grey and leave
  /// the button with no edge. Null for every other ground.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onPressed != null;
    final fg = enabled ? c.textPrimary : c.textTertiary;

    return Pressable(
      onTap: onPressed,
      scale: 0.975,
      child: Container(
        height: Sizes.control,
        decoration: BoxDecoration(
          color: fill ?? c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: Sizes.glyph, color: fg),
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
///
/// [tooltip] is required, and states the control's name rather than a hint:
/// a glyph on its own is the one kind of control that cannot say what it does.
/// Optional, it gets left off: six of thirteen call sites did, the ✕ on three
/// different sheets among them. Required, the label is the thing that has to be
/// written for the code to compile — the same argument `formatWeight` makes for
/// its unit.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.onLongPress,
    this.tint,
    this.fill,
    this.size = 40,
    this.glyphScale = 0.45,
    this.pressScale = 0.92,
  });

  final IconData icon;
  final VoidCallback? onTap;

  /// A second action on the same button. Takes the long press, so the tooltip
  /// stands down and the name is carried by `Semantics` alone.
  final VoidCallback? onLongPress;

  /// What this button does, in one or two words.
  final String tooltip;
  final Color? tint;
  final Color? fill;
  final double size;

  /// The glyph as a share of [size]. The `+` in the set table's index column
  /// is drawn larger, at 0.6, because the column is narrower than the button.
  final double glyphScale;

  /// How far it presses, as [Pressable.scale].
  final double pressScale;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final button = Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: pressScale,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? c.surfaceHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: size * glyphScale,
          color: tint ?? c.textPrimary,
        ),
      ),
    );
    // Named as well as tipped: a tooltip needs a long press to appear, which is
    // not a gesture anyone makes mid-set, and a screen reader reads neither the
    // circle nor the glyph inside it.
    return Semantics(
      button: true,
      label: tooltip,
      child: onLongPress == null
          ? Tooltip(message: tooltip, child: button)
          : button,
    );
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
    this.dense = false,
    this.hue,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  /// The category's own colour, where the label names a category that already
  /// has one — a muscle, whose hue is the bar it is counted in (THEME → Components).
  ///
  /// Unselected it is a dot before the label and the pill stays grey: chrome is
  /// monochrome (rule 1), and a list of coloured pills over a list of exercise
  /// names would be the loudest thing on the screen. Selected it fills, with the
  /// label taken down out of its own fill the way [IconTile] does — white on
  /// `yellow` is 1.4:1, and near-black would make the chip two colours.
  final Color? hue;

  /// Marks a chip that opens a picker rather than toggling.
  final bool caret;

  /// The in-row variant: 26 tall, same `label` text, for a chip that sits
  /// *inside* a list row rather than in the filter strip above it. A 40pt chip
  /// on a row's subtitle line makes the row 90 tall and reads as the row's
  /// control rather than as one word in its description.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fill = selected ? (hue ?? c.accent) : c.surfaceHigh;
    final fg = selected
        ? (hue == null ? c.onAccent : IconTile.glyphOn(hue!))
        : c.textPrimary;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.curve,
        height: dense ? 26 : 40,
        padding: EdgeInsets.symmetric(horizontal: dense ? Space.sm : Space.md),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: Space.sm),
            ] else if (hue != null && !selected) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
              ),
              const SizedBox(width: Space.xs),
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
        ],
      ),
    );
  }
}

/// Tabs with a white underline under the live one (THEME → Components).
///
/// A strip rather than a list: a training day is a context to switch between
/// rather than an item to scroll past. It scrolls horizontally and extends past
/// the right edge, so the
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
    this.leadingLabel,
    this.leadingIcon,
    this.leadingSelected = false,
    this.onLeading,
  }) : assert(
         leadingLabel == null || leadingIcon != null,
         'A leading tab is told apart by its glyph, so it has to carry one.',
       );

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  /// A tab ahead of [labels] that is not one of them: the overview of the
  /// things the other tabs each hold one of.
  ///
  /// Set apart by [leadingIcon] and a hairline after it, and by nothing else.
  /// A hue would read as data (THEME rule 1), and the tab is chrome.
  final String? leadingLabel;
  final IconData? leadingIcon;

  /// Whether the leading tab is the one open. While it is, no tab of [labels]
  /// is drawn selected, whatever [index] holds.
  final bool leadingSelected;
  final VoidCallback? onLeading;

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
  /// itself; otherwise adding a further day appears to have no effect.
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
    // 48 at the standard font, and taller by whatever the label grows. A tab
    // is one line of its label over a fixed 23 of padding and underline, so a
    // fixed 48 left a larger system font overflowing every tab in the strip.
    final style = context.t.titleMedium;
    final size = style?.fontSize ?? 16;
    final line = style?.height ?? 1.375;
    final grown =
        (MediaQuery.textScalerOf(context).scale(size) - size) * line;
    return SizedBox(
      height: 48 + math.max(0.0, grown),
      // Full width, or the strip is only as wide as the tabs in it — and a
      // `Column` centres a child narrower than itself, so a regime with one day
      // would put `Legs` and `Add day +` in the middle of the band while a
      // regime with six had them against the gutter like everything else.
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Row(
          children: [
            if (widget.leadingLabel != null) ...[
              _Tab(
                label: widget.leadingLabel!,
                icon: widget.leadingIcon,
                selected: widget.leadingSelected,
                onTap: widget.onLeading,
              ),
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: Space.xs),
                color: c.surfaceHighest,
              ),
            ],
            for (var i = 0; i < widget.labels.length; i++)
              _Tab(
                key: _keys[i] ??= GlobalKey(),
                label: widget.labels[i],
                selected: i == widget.index && !widget.leadingSelected,
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
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? tint;
  final IconData? icon;

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
                Space.md,
                Space.md,
                Space.md,
                Space.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color:
                          selected ? c.textPrimary : (tint ?? c.textSecondary),
                    ),
                    const SizedBox(width: Space.xs),
                  ],
                  Text(
                    label,
                    style: context.t.titleMedium?.copyWith(
                      color:
                          selected ? c.textPrimary : (tint ?? c.textSecondary),
                    ),
                  ),
                ],
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
    required this.color,
    this.size = 44,
    this.solid = true,
    this.glyph,
  });

  final IconData icon;

  /// Overrides the glyph's colour, for a tile whose fill is chrome rather
  /// than a hue: the Phase card's `surfaceHigh` tile, whose glyph is
  /// `textPrimary` because a phase is not an identity (THEME → Phase card).
  final Color? glyph;

  /// Required rather than defaulted. A tile's colour is what it means, and a
  /// default would be a meaning no caller chose: every tile reached for one
  /// explicitly anyway, and the blue it fell back to is now progress.
  final Color color;
  final double size;

  /// Filled in [color] with the glyph knocked out. Off gives a tinted wash for
  /// a mark that must not outshout its row.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final tint = color;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: solid ? tint : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: glyph ?? (solid ? glyphOn(tint) : tint),
      ),
    );
  }

  /// The glyph takes the fill's own hue, darkened, rather than white or
  /// black.
  ///
  /// White breaks outright on a saturated yellow (1.9:1), and near-black fixes
  /// the ratio at the cost of the point: a tile is one colour with a shape cut
  /// out of it, and a black shape makes it two. Same hue, same saturation, less
  /// light — the mark stays "the green one" at arm's length, which is the only
  /// job it has.
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

/// The radio from THEME → Components: selected is a filled disc with a dark
/// dot punched out of it,
/// unselected a 2px ring in `textTertiary`. No accent hue, and no Material
/// `Radio`, whose ripple and 48pt slop belong to a different design language.
///
/// It is the trailing control of an [AppRow] — a list of rows that are one
/// choice each, where a [SegmentedPill] would put three words in a track and
/// lose the room to say what each one means.
/// A trailing figure on a row, in the value size with the row's own chevron
/// after it.
///
/// Shared because three screens want the same trailing slot — an exercise's
/// fields, and Settings' unit and rest rows — and a hand-rolled `Row` that
/// looks like one drifts off the others within a week, which is the argument
/// THEME makes for section headers and holds here for the same reason.
class RowValue extends StatelessWidget {
  const RowValue(this.text, {super.key}) : pending = false;

  /// An unanswered question, while a new exercise is being drafted: the word
  /// `Choose` in `textTertiary` where the value will go. Not a dash — a dash is
  /// for a measurement that should exist and doesn't (rule 4), and this is a
  /// question awaiting an answer.
  const RowValue.orChoose(String? value, {super.key})
      : text = value ?? 'Choose',
        pending = value == null;

  /// A value the row states and does not let you change: the figure in
  /// `textTertiary`, the ink of something that is not an answer of yours. The
  /// chevron stays, because the row still opens a sheet that says why.
  const RowValue.fixed(this.text, {super.key}) : pending = true;

  final String text;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            style: pending
                ? context.t.labelLarge?.copyWith(color: context.c.textTertiary)
                : context.t.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Space.sm),
        Icon(Icons.chevron_right_rounded,
            size: 18, color: context.c.textTertiary),
      ],
    );
  }
}

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
/// Rule 5 expressed as a widget: a value with its unit beside it, one step
/// down and
/// in grey, sharing a baseline.
///
/// Hand-built, it is built seven ways — the summary's rows, the bodyweight
/// header, Today's elapsed clock, two volume widgets — each deciding for itself
/// whether the unit is `bodyMedium` or `bodySmall` and whether the pair shares
/// a baseline or a centre line. The rule is THEME → Value and unit; this is the
/// one place that implements it.
///
/// [dense] is the row form: `labelLarge` against a trailing edge, where the
/// page form is `displaySmall` and is the number a card is about.
class ValueUnit extends StatelessWidget {
  const ValueUnit({
    super.key,
    required this.value,
    this.unit,
    this.dense = false,
    this.emphasis,
  });

  final String value;

  /// Null where the value has no unit — a count of sets, a session name.
  final String? unit;

  /// The row form, for a value trailing an `AppRow` rather than heading a card.
  final bool dense;

  /// Paints the value. Only for a semantic reading — a record, a deload.
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final valueStyle = dense ? context.t.labelLarge : context.t.displaySmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            value,
            style: valueStyle?.copyWith(color: emphasis),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: Space.xs),
          Text(unit!, style: context.t.bodyMedium),
        ],
      ],
    );
  }
}

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
        ValueUnit(value: value, unit: unit, emphasis: emphasis),
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

/// The compact pill (THEME → Buttons): 36 tall, radius 999, `surfaceHigh`,
/// `label` text.
///
/// Without [onTap] it is a fact in a pill's shape, the Phase card's
/// `Week 7 of 12`, and opens nothing.
class CompactPill extends StatelessWidget {
  const CompactPill(this.text, {super.key, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        text,
        style: context.t.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (onTap == null) return pill;
    return Pressable(onTap: onTap, scale: 0.96, child: pill);
  }
}

/// A figure and the figure derived from it, inside a ring that is filled to a
/// share.
///
/// The log's bodyweight pill: `73.2 kg` over `+69.5 kg (95%)`, in a capsule
/// whose outline is drawn in [hue] for [fraction] of the way round and left as
/// track for the rest. The gap sits at the top centre, so 95 per cent reads as
/// a ring with a small piece missing rather than as a line that stops
/// somewhere. A ring rather than a fill, because the two lines inside it are
/// numbers to be read and a tinted ground behind them would cost the smaller
/// one its contrast.
class FigurePill extends StatelessWidget {
  const FigurePill({
    super.key,
    required this.figure,
    required this.detail,
    required this.hue,
    this.fraction = 1,
    this.onTap,
    this.semanticLabel,
  });

  final String figure;
  final String detail;
  final Color hue;

  /// How much of the ring is drawn in [hue], from 0 to 1.
  final double fraction;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// The ring's stroke: the weight of the app's other outlines, a focused
  /// field and a selected card, so a pill 40 tall is not carrying a heavier
  /// line than a field 48 tall.
  static const ringWidth = 2.0;

  /// As tall as the [CircleIconButton]s it sits beside in a header, so the
  /// three read as one row of controls.
  static const height = 40.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: CustomPaint(
          painter: _RingPainter(
            hue: hue,
            track: c.surfaceHigh,
            fraction: fraction,
          ),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // `label` over `micro`: the two rungs whose line heights, 16
                // and 14, fit inside the ring at the height of a button.
                Text(
                  figure,
                  maxLines: 1,
                  style: context.t.bodySmall?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  style: context.t.labelSmall?.copyWith(
                    color: c.textSecondary,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The capsule outline of a [FigurePill]: a full track, and over it the part
/// of the way round that [fraction] covers.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.hue,
    required this.track,
    required this.fraction,
  });

  final Color hue;
  final Color track;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const w = FigurePill.ringWidth;
    final rect = (Offset.zero & size).deflate(w / 2);
    if (rect.width <= 0 || rect.height <= 0) return;
    final r = rect.height / 2;

    // Drawn by hand from the top centre, clockwise, so that the start of the
    // path is where the gap belongs. `addRRect` starts wherever the engine
    // starts it, which is not a thing to measure a gap from.
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(
        Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
      ..close();

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;

    canvas.drawPath(path, stroke..color = track);

    final share = fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction);
    if (share == 0) return;
    if (share == 1) {
      canvas.drawPath(path, stroke..color = hue);
      return;
    }
    for (final metric in path.computeMetrics()) {
      // The missing piece is centred on the top, half of it either side of
      // where the path begins.
      final gap = metric.length * (1 - share);
      canvas.drawPath(
        metric.extractPath(gap / 2, metric.length - gap / 2),
        stroke..color = hue,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.hue != hue || old.track != track || old.fraction != fraction;
}

// ─── Sheets and confirmations ───────────────────────────────────────────────

/// The header every sheet wears: title centred, subtitle under it, ✕ on the
/// right, hairline beneath.
///
/// The ✕ is placed on the right and is larger than a row's glyph, being the
/// one
/// control on the sheet that is not one of the choices, and on the left it
/// reads as the first item in the list rather than as the way out.
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
          // the hairline. The handle's margin plus a header inset would make
          // the gap above wider than the one below for no reason anyone could
          // name.
          padding: const EdgeInsets.fromLTRB(
            Space.sm,
            Space.lg,
            Space.sm,
            Space.lg,
          ),
          // A stack, not a row: the ✕ is a 48pt tap target and the title on its
          // own is 26 tall, so in a row the button sets the header's height and
          // leaves 22pt of dead charcoal under a one-line title. Out of the
          // flow, the text decides how tall the header is and the target
          // overhangs it into the handle's gap, where there is nothing to
          // collide with.
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Padding(
                // Room for the ✕ on both sides, so the title is centred on the
                // sheet rather than on what is left of it.
                padding: const EdgeInsets.symmetric(horizontal: 48),
                // Full width on purpose: a `Stack` takes its size from its
                // largest unpositioned child, so a shrink-wrapped title makes
                // the stack as narrow as the words in it and lands `right: 0`
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
              // Centred on the title's line — it closes the sheet, and centred
              // on the whole block it drags down beside a subtitle it has
              // nothing to do with.
              Positioned(
                right: 0,
                top: -11,
                child: CircleIconButton(
                  icon: Icons.close_rounded,
                  fill: Colors.transparent,
                  size: 48,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }
}

/// How much of the screen a capped sheet may take. See [showAppSheet].
const sheetMaxHeight = 0.7;

/// Opens a sheet. The one way the app opens one, so every sheet sits on the
/// same route and none can come out different from its neighbours.
///
/// **The route holds the system bars, not the sheet.** `useSafeArea` defaults
/// to false, and with `isScrollControlled` that lets the sheet take the whole
/// screen — the status bar included, which is where `Exercises` once ended up
/// drawn across the clock and the battery. It cannot be answered inside the
/// sheet: a modal route reports both `padding` and `viewPadding` as zero to its
/// own child — measured on a phone, not assumed — so the inset is the route's
/// to know.
///
/// Scroll-controlled always, so a sheet sizes to its content rather than to
/// the framework's nine-sixteenths cap, and without the framework's drag
/// handle, because [SheetHeader] draws its own, tighter one.
///
/// [dismissible] false holds the sheet open against the scrim and the drag,
/// for a question that must be answered.
///
/// [capped] is for a sheet whose content can outgrow the phone — twelve
/// muscles, twenty years. Uncapped, it opens edge to edge with the page it
/// came from nowhere in sight: a screen wearing a sheet's clothes, and a panel
/// with almost no distance left to travel, so its entrance and exit both read
/// as a cut. Capped, the page behind stays visible, and the barrier over it is
/// what says this is a question that can be dismissed. Every capped sheet
/// stops at the same height, [sheetMaxHeight], so two long lists never open to
/// two different lines.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool capped = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    isDismissible: dismissible,
    enableDrag: dismissible,
    constraints: capped
        ? BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * sheetMaxHeight,
          )
        : null,
    builder: builder,
  );
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
    // The sheet rides above the keyboard, and it is this component's job rather
    // than each caller's.
    //
    // Left to each caller, some sheets reserve it and the rest do not, so
    // anything with a field in it — a set note, a rep target, a session name
    // typed from the wrong screen — opens the keyboard straight over its own
    // Save button. Reserving the inset here also shortens the
    // scroll area rather than pushing it off the bottom, so a long sheet with
    // the keyboard up scrolls instead of overflowing.
    // And it clears the gesture bar under it, in the same reservation.
    //
    // `viewInsets.bottom + padding.bottom`, and the sum is right because the
    // two never overlap: `padding` is what the system chrome covers that the
    // keyboard does not, so with the keyboard up the gesture bar is already
    // excluded from it and the sum is just the keyboard. Taking the larger of
    // the two instead reserves nothing at all on a phone whose `viewPadding` is
    // reported as zero, and the last row of the sheet lands behind the
    // navigation bar.
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: media.viewInsets.bottom + media.padding.bottom,
      ),
      child: SafeArea(
        // Sides only — the bottom is reserved above, and letting `SafeArea` add
        // it again is how a sheet ends up double-padded.
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: title, subtitle: subtitle),
            Flexible(
              child: SingleChildScrollView(
                padding:
                    contentPadding ??
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
      ),
    );
  }
}

/// Writes a note. The one text-entry surface in the app, and a sheet.
///
/// A sheet rather than a centred `AlertDialog`, which would carry Material's
/// own buttons, open in the middle of the screen while the row that summoned it
/// sits at the bottom, and fight the keyboard for the same space.
///
/// Returns the trimmed text, or null if dismissed. An empty string is a valid
/// answer: a note that cannot be cleared is one that ceases to be used.
Future<String?> promptForNote(
  BuildContext context, {
  required String title,
  String? subtitle,
  String initial = '',
  String? hint,
  int maxLength = 500,
}) {
  return showAppSheet<String>(
    context,
    // The keyboard is `AppSheet`'s business — see the inset it reserves.
    builder: (sheet) => _NoteSheet(
      title: title,
      subtitle: subtitle,
      initial: initial,
      hint: hint,
      maxLength: maxLength,
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
          // limit is before it is reached. "60 left" answers a question that
          // only arises once the limit is already close.
          buildCounter:
              (
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
          // 2px outline when focused. Not `surfaceSunken`, the keypad's bed,
          // which on a `surface` sheet reads as a hole rather than as somewhere
          // to type.
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
/// one. The message states what will happen rather than asking for
/// confirmation in the abstract.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Go back',
  bool destructive = true,
  List<String> highlight = const [],
}) async {
  final answer = await showAppSheet<bool>(
    context,
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
                    tooltip: 'Close',
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              _ConfirmMessage(message: message, highlight: highlight),
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

/// The body of a confirmation, with the values that are actually changing lifted
/// out of it.
///
/// A confirmation is read in about a second, and the part that decides the
/// answer is the two or three words naming what it becomes. In one flat grey
/// paragraph those words are the same weight as `everywhere this exercise
/// appears`, so the sentence has to be read to the end to find them; in
/// `textPrimary` at 600 they are what the eye lands on and the rest is the
/// explanation it already expected.
class _ConfirmMessage extends StatelessWidget {
  const _ConfirmMessage({required this.message, required this.highlight});

  final String message;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = context.t.bodyLarge?.copyWith(color: c.textSecondary);
    if (highlight.isEmpty) return Text(message, style: base);

    final strong = base?.copyWith(
      color: c.textPrimary,
      fontWeight: FontWeight.w600,
    );
    // Longest first, so a term that contains another ("Olympic bar" over "bar")
    // wins the match rather than being cut in half by it.
    final terms = [...highlight.where((t) => t.isNotEmpty)]
      ..sort((a, b) => b.length.compareTo(a.length));
    if (terms.isEmpty) return Text(message, style: base);

    final pattern = RegExp(terms.map(RegExp.escape).join('|'));
    final spans = <TextSpan>[];
    var i = 0;
    for (final match in pattern.allMatches(message)) {
      if (match.start > i) {
        spans.add(TextSpan(text: message.substring(i, match.start)));
      }
      spans.add(TextSpan(text: match[0], style: strong));
      i = match.end;
    }
    if (i < message.length) spans.add(TextSpan(text: message.substring(i)));

    return Text.rich(TextSpan(children: spans), style: base);
  }
}

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
