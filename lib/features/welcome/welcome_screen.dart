import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../account/sign_in_flow.dart';
import 'curl_illustration.dart';
import 'google_mark.dart';

/// One screen, one question, asked once.
///
/// The question is where the history is kept, which is the only thing about the
/// user this app cannot infer. It is deliberately **not** a wizard step in front
/// of building a programme: the user is the planner, and nothing here asks
/// about training.
///
/// **A threshold, not a page**, and THEME grants it four things it grants
/// nowhere else — see THEME → the threshold screen for all four and why. Two
/// equal buttons rather than one primary and a text link, pill-shaped rather
/// than `Radii.control`, a wordmark above the fold, and Google's own four
/// colours on the control that opens Google's own sheet.
///
/// Top to bottom: the wordmark, the mark at the size a drawing would have been,
/// a display line, the two answers, and one paragraph saying what each does.
/// Nothing is centred on the page as a whole — the wordmark sits at the top,
/// the answers at the bottom, and the drawing and its line sit in the upper
/// third with the empty space under them, which is what makes it read as a door
/// rather than as a form.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  /// The screen arrives rather than appearing.
  ///
  /// THEME's motion rule is that motion *confirms a change and never performs*,
  /// and an entrance is a performance — see THEME → the threshold screen, which
  /// grants it here and nowhere else. What it buys is worth the exception: this
  /// is the first frame of the app anyone ever sees, there is nothing on screen
  /// to confirm yet, and a page that assembles itself in front of you reads as
  /// something being made for you rather than a form being presented to you.
  ///
  /// One shot, 620ms, never replayed. The mark settles first and the rest
  /// follows it up the page, each part a beat behind the last.
  late final AnimationController _entrance = AnimationController(
    duration: const Duration(milliseconds: 620),
    vsync: this,
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// One part's share of the entrance: [order] beats in, over [span] of it.
  Animation<double> _step(int order) {
    const beat = 0.11;
    final start = (order * beat).clamp(0.0, 0.7);
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        start,
        (start + 0.5).clamp(0.0, 1.0),
        curve: Motion.emphasized,
      ),
    );
  }

  /// True from the tap until the account is signed in or the sheet is closed.
  ///
  /// The one thing on this screen that waits on a network, and the reason it
  /// may: nothing has been written yet and there is no history to read. Every
  /// screen after this one reads local disk and waits on nothing
  /// ([SYNC.md § 15](SYNC.md#15-what-sync-may-never-do) rule 1).
  bool _signingIn = false;

  /// Sign in, settle the two histories, and record the answer.
  ///
  /// The flow itself is shared with Settings — [signInAndAdopt] — because the
  /// same question is asked at both doors and the *other* door is the likelier
  /// one to meet a phone with a month of training on it.
  ///
  /// [answerWelcome] is told not to seed **when adoption ran**: it has already
  /// dealt with the catalog, and an account that holds one hands over the
  /// user's own rather than being given a second under different ids
  /// ([SYNC.md § 10](SYNC.md#10-adoption)). A build that can authenticate but
  /// cannot reach an account settled nothing, so that phone still needs a
  /// catalog to train from.
  Future<void> _signIn() async {
    // Captured before the await, because answering swaps this whole screen out
    // from under the widget that started it.
    final db = ref.read(databaseProvider);
    final adopted = ref.read(adoptionProvider) != null;

    setState(() => _signingIn = true);
    try {
      final outcome = await signInAndAdopt(context, ref);
      if (outcome != SignInOutcome.signedIn) return;
      await answerWelcome(db, WelcomeAnswer.account, seed: !adopted);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _decline() =>
      answerWelcome(ref.read(databaseProvider), WelcomeAnswer.local);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A build with no configuration cannot reach an account, so it does not ask
    // where the history should live — there is only one answer available, and
    // offering the other would be a button that can only fail.
    final canSignIn = ref.watch(syncConfiguredProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mark = dark
        ? 'assets/brand/mark_white.png'
        : 'assets/brand/mark_ink.png';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.xxxl),
              _Arrive(
                step: _step(0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      mark,
                      height: _Threshold.markHeight,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(width: Space.sm),
                    // The one lockup in the app, and the only place a wordmark
                    // is set at display size — the threshold names the app
                    // before anything else on it means anything.
                    Text(
                      'Deltoid',
                      style: context.t.displaySmall?.copyWith(
                        fontWeight: _Threshold.lockupWeight,
                      ),
                    ),
                  ],
                ),
              ),

              // The drawing takes whatever is left between the wordmark and the
              // display line, rather than a fixed height: on a short phone it
              // scales down instead of pushing the answers off the bottom.
              const SizedBox(height: Space.xxl),
              Expanded(
                child: AnimatedBuilder(
                  animation: _step(1),
                  builder: (context, child) {
                    final t = _step(1).value.clamp(0.0, 1.0);
                    return Opacity(
                      opacity: t,
                      // Settles down to its size rather than growing into it: a
                      // shape that ends on 1.0 from above has landed, one that
                      // arrives from below is still going somewhere.
                      child: Transform.scale(
                        scale: 1 + 0.04 * (1 - t),
                        child: child,
                      ),
                    );
                  },
                  // A shade under the space it is given, so the drawing has air
                  // on both sides of it rather than touching the line above and
                  // the line below.
                  child: const Center(
                    child: FractionallySizedBox(
                      heightFactor: _Threshold.drawing,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: CurlIllustration(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.xxl),
              _Arrive(
                step: _step(2),
                // Inset past the page gutter, so the line breaks well short of
                // the buttons under it. A display line that runs the full width
                // of the widest control on the page reads as a paragraph.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  child: Text(
                    // What the app is, in one line, rather than what this screen
                    // does. The screen's own question is answered by the two
                    // buttons under it, and a line asking it as well would be the
                    // same fact twice (THEME rule 6).
                    'Your training sidekick, right in the pocket!',
                    textAlign: TextAlign.center,
                    // Lighter and a shade smaller than the page-title scale: the
                    // reference line is a sentence, not a heading, and w800 makes
                    // it shout at the one screen with nothing to shout about.
                    style: context.t.displaySmall?.copyWith(
                      fontWeight: _Threshold.lockupWeight,
                      height: _Threshold.taglineHeight,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.huge),

              if (canSignIn) ...[
                _Arrive(
                  step: _step(3),
                  child: _ThresholdButton(
                    label: _signingIn ? 'Signing in' : 'Continue with Google',
                    icon: const GoogleMark(),
                    busy: _signingIn,
                    // Disabled while Google's sheet is up, so a second tap
                    // cannot open a second one behind the first.
                    onTap: _signingIn ? null : _signIn,
                  ),
                ),
                const SizedBox(height: Space.lg),
                // The two answers are alternatives, not a sequence, and the
                // rule with a word in it is what says so — without it a second
                // pill under the first reads as the next step.
                _Arrive(step: _step(4), child: const _OrDivider()),
                const SizedBox(height: Space.lg),
              ],
              // **Equal standing**, which on this screen means a button of the
              // same size and shape rather than a text link. Declining is a real
              // answer: Settings offers the same connection later, and nothing
              // ever asks again. Only the fill differs, because one of the two
              // opens someone else's sheet and the other does not.
              _Arrive(
                step: _step(5),
                child: _ThresholdButton(
                  // The only answer left when there is no account to offer, so
                  // it becomes the filled one rather than the alternative to
                  // something that is not on screen.
                  label: canSignIn ? 'Continue on this phone' : 'Start training',
                  filled: !canSignIn,
                  icon: Icon(
                    Icons.smartphone_rounded,
                    size: Sizes.glyph,
                    // The label picks its own colour from `filled`; the glyph
                    // is passed in, so it has to follow the same fill or it
                    // disappears into the accent.
                    color: canSignIn ? c.textPrimary : c.onAccent,
                  ),
                  onTap: _signingIn ? null : _decline,
                ),
              ),
              const SizedBox(height: Space.xl),
              _Arrive(
                step: _step(6),
                child: Text(
                  // Both outcomes, in the order the buttons are in, each in terms
                  // of what happens to the *training* rather than to the data.
                  canSignIn
                      ? 'Sign in with Google to back up your training data, '
                            'so that a lost phone doesn\'t mean lost progress. '
                            'The app works fully offline regardless, and you '
                            'can connect to Google at any time from Settings.'
                      : 'Everything you log stays on this phone. Back it up '
                            'whenever you like from Settings, and keep the '
                            'file wherever you keep your own files.',
                  textAlign: TextAlign.center,
                  style: context.t.bodySmall?.copyWith(
                    color: c.textTertiary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three things on this screen that the app's tokens do not already say.
///
/// Everything else comes from them: the answer buttons are [Sizes.control] tall
/// with a [Sizes.glyph] icon, like every button in the app, and the wordmark and
/// the display line are `displaySmall` — the size and the tracking are the
/// scale's, and only the weight and the line spacing are set here, because a
/// name and a sentence are not the number a card is about.
abstract final class _Threshold {
  /// The mark, set to the cap height of the name beside it.
  static const markHeight = 22.0;

  /// A wordmark and a sentence at `displaySmall`'s size but not its weight:
  /// `w700` is the weight a number is read at, and neither of these is one.
  static const lockupWeight = FontWeight.w600;

  /// Looser than `displaySmall`'s 26 on 22, so two centred lines read as a
  /// sentence rather than as a heading that wrapped.
  static const taglineHeight = 1.4;

  /// The drawing's share of the space left between the wordmark and the line.
  /// Under 1 so it has air on both sides rather than touching either.
  static const drawing = 0.88;
}

/// A hairline broken by the word `OR`, between the two answers.
///
/// A rule rather than a gap, because the gap alone says "and then", and these
/// two are "or".
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final line = Expanded(child: Container(height: 1, color: c.border));

    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Text(
            'OR',
            style: context.t.labelSmall?.copyWith(color: c.textTertiary),
          ),
        ),
        line,
      ],
    );
  }
}

/// One part of the entrance: it fades up and rises a little into place.
///
/// A rise of 10 rather than 24 — the page is arriving, not sliding in from
/// somewhere. Anything further reads as a transition between two screens.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.step, required this.child});

  final Animation<double> step;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: step,
    builder: (context, child) => Opacity(
      opacity: step.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - step.value)),
        child: child,
      ),
    ),
    child: child,
  );
}

/// The threshold screen's answer button: a full-width pill, `accent` fill, glyph
/// left of a centred label.
///
/// Local to this screen on purpose. It is not a [PrimaryButton] with a rounder
/// corner — it is the shape a *choice between two equals* takes, and the app has
/// exactly one screen that offers one. Promoting it to the design system would
/// invite a second screen to use it, and a second screen would have a primary
/// action and a secondary one, which is what [PrimaryButton] and
/// [SecondaryButton] already say properly.
class _ThresholdButton extends StatelessWidget {
  const _ThresholdButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = true,
    this.busy = false,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  /// Waiting on Google, with the glyph replaced by a spinner.
  ///
  /// **The one spinner the app allows on a screen rather than in a sheet**, and
  /// it is allowed for the same reason this screen may wait at all: nothing has
  /// been written yet, there is no history to read, and the user is waiting on
  /// somebody else's sheet to open. Every screen after this one reads local
  /// disk and waits on nothing
  /// ([SYNC.md § 15](SYNC.md#15-what-sync-may-never-do) rule 1), which is why
  /// there is no second one anywhere.
  ///
  /// Dimming the glyph and changing the label said *disabled*, not *working*. A
  /// tap that produces a greyer button and then nothing — Google's own sheet
  /// can take seconds to appear on a cold start — is a tap the user makes
  /// again.
  final bool busy;

  /// Filled with `accent`, or the same pill drawn as an outline.
  ///
  /// Not a primary/secondary split — both answers are equally real. The outline
  /// is what keeps two full-width pills from reading as one control repeated.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // **Busy is not disabled**, and the fill is what says which. A button that
    // greys itself out the moment it is tapped has told the user it is no
    // longer a button, and Google's sheet can take seconds to appear on a cold
    // start — long enough to try again. The other answer *is* disabled while
    // this one works, and that difference has to be visible.
    final working = onTap == null && busy;
    final enabled = onTap != null || working;

    return Pressable(
      onTap: onTap,
      scale: 0.975,
      child: Container(
        height: Sizes.control,
        decoration: BoxDecoration(
          // `surfaceHigh` is the app's secondary-button fill everywhere else,
          // so the unfilled answer is the same material as every other quiet
          // control rather than a hole in the page.
          color: filled ? (enabled ? c.accent : c.surfaceHigh) : c.surfaceHigh,
          border: filled ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // **The spinner follows the words, the glyph leads them.** A mark
            // in front of a label says *whose* sheet this opens, which is the
            // whole reason Google's colours are allowed here; a spinner in the
            // same place would claim the same thing and be answering a
            // different question. After the label it reads as what it is — the
            // sentence, and then the fact that it is still going.
            if (!busy) ...[
              Opacity(opacity: enabled ? 1 : 0.4, child: icon),
              const SizedBox(width: Space.md),
            ],
            Flexible(
              child: Text(
                label,
                style: context.t.titleMedium?.copyWith(
                  color: !enabled
                      ? c.textTertiary
                      : filled
                      ? c.onAccent
                      : c.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (busy) ...[
              const SizedBox(width: Space.md),
              RowSpinner(color: filled ? c.onAccent : c.textPrimary),
            ],
          ],
        ),
      ),
    );
  }
}
