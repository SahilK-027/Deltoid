part of '../primitives.dart';

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
