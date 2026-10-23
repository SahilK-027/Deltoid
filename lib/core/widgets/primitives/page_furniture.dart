part of '../primitives.dart';

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
