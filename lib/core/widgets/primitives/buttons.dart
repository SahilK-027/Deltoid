part of '../primitives.dart';

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
