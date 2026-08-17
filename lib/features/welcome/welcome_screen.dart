import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/toast.dart';
import '../../data/sync/sync_auth.dart';
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

  Future<void> _signIn() async {
    final auth = ref.read(syncAuthProvider);
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the await, because answering swaps this whole screen out
    // from under the widget that started it.
    final db = ref.read(databaseProvider);

    if (auth == null) {
      showToastOn(messenger, 'This build cannot sign in.', destructive: true);
      return;
    }

    setState(() => _signingIn = true);
    try {
      await auth.signInWithGoogle();
      await answerWelcome(db, WelcomeAnswer.account);
    } on SyncAuthCancelled {
      // Backing out of Google's own sheet is an answer to Google, not to this
      // screen. Nothing is said and the question stands.
    } on SyncAuthFailure catch (e) {
      showToastOn(messenger, e.message, destructive: true);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _decline() =>
      answerWelcome(ref.read(databaseProvider), WelcomeAnswer.local);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
                      height: 22,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(width: Space.sm),
                    // The one lockup in the app, and the only place a wordmark
                    // is set at display size — the threshold names the app
                    // before anything else on it means anything.
                    Text(
                      'Deltoid',
                      style: context.t.displayMedium?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // The drawing is a fixed share of the page rather than everything
              // left over: it sits in the upper third with the display line
              // under it, and the empty space belongs *below* the pair, which is
              // what pushes the answers to the bottom edge where a threshold
              // wants them.
              const Spacer(flex: 2),
              AnimatedBuilder(
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
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.26,
                  child: const Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: CurlIllustration(),
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
                    style: context.t.displayLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 4),

              _Arrive(
                step: _step(3),
                child: _ThresholdButton(
                  label: _signingIn ? 'Signing in' : 'Continue with Google',
                  icon: const GoogleMark(),
                  // Disabled while Google's sheet is up, so a second tap cannot
                  // open a second one behind the first.
                  onTap: _signingIn ? null : _signIn,
                ),
              ),
              const SizedBox(height: Space.lg),
              // The two answers are alternatives, not a sequence, and the rule
              // with a word in it is what says so — without it a second pill
              // under the first reads as the next step.
              _Arrive(step: _step(4), child: const _OrDivider()),
              const SizedBox(height: Space.lg),
              // **Equal standing**, which on this screen means a button of the
              // same size and shape rather than a text link. Declining is a real
              // answer: Settings offers the same connection later, and nothing
              // ever asks again. Only the fill differs, because one of the two
              // opens someone else's sheet and the other does not.
              _Arrive(
                step: _step(5),
                child: _ThresholdButton(
                  label: 'Continue on this phone',
                  filled: false,
                  icon: Icon(
                    Icons.smartphone_rounded,
                    size: 19,
                    color: c.textPrimary,
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
                  'Sign in with Google to back up your training data, '
                  'so that a lost phone doesn\'t mean lost progress. '
                  'The app works fully offline regardless, and you can '
                  'connect to Google at any time from Settings.',
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
  });

  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  /// Filled with `accent`, or the same pill drawn as an outline.
  ///
  /// Not a primary/secondary split — both answers are equally real. The outline
  /// is what keeps two full-width pills from reading as one control repeated.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onTap != null;

    return Pressable(
      onTap: onTap,
      scale: 0.975,
      child: Container(
        height: 54,
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
            // Dimmed rather than removed while a sign-in is in flight: the row
            // must not change width, or the label shifts as it changes.
            Opacity(opacity: enabled ? 1 : 0.4, child: icon),
            const SizedBox(width: Space.md),
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
          ],
        ),
      ),
    );
  }
}
