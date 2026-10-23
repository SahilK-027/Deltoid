part of '../primitives.dart';

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
