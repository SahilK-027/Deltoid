import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/toast.dart';
import '../../data/sync/sync_auth.dart';

/// One screen, one question, asked once.
///
/// [THEME.md](THEME.md) permits exactly one illustrated page and this is it —
/// and it stays inside the rule banning an illustrated intro only while all of
/// this holds: one screen and never two, one question and not about training,
/// declining given equal standing, seen once, and the outcome named before the
/// question is put.
///
/// The question is where the history is kept, which is the only thing about the
/// user this app cannot infer. It is deliberately **not** a wizard step in front
/// of building a programme: the user is the planner, and nothing here asks
/// about training.
///
/// Top to bottom: the mark, a display line, a body line, the primary button, an
/// `OR` rule, the decline action. The only centred display line in the app,
/// which is what makes this read as a threshold rather than a page.
///
/// **The mark is the whole of the picture**, at the size a drawing would have
/// been. It is already a drawn shape in one ink that inverts with the theme, so
/// a second drawn object under it was one drawing too many on a page whose
/// whole job is to ask one question — see THEME → Illustration, which now
/// records that no screen carries one.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
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

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            // Generous vertical space, and centred — until the screen is short
            // enough that centring would crop it, at which point it scrolls.
            padding: const EdgeInsets.symmetric(
              horizontal: Space.gutter,
              vertical: Space.xxl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - Space.xxl * 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      // Two inks rather than a tint, because the mark is a
                      // drawn shape with soft edges: colouring the white one
                      // through a filter would harden every one of them.
                      dark
                          ? 'assets/brand/mark_white.png'
                          : 'assets/brand/mark_ink.png',
                      height: 132,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: Space.xxxl),
                  Text(
                    'Keep your training',
                    textAlign: TextAlign.center,
                    style: context.t.displayLarge,
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    // The outcome, not the mechanism. Nobody wants a sync; they
                    // want the four years of training to survive the phone.
                    'Sign in and your training survives a lost phone. It is '
                    'already there on the next one.',
                    textAlign: TextAlign.center,
                    style: context.t.bodyMedium,
                  ),
                  const SizedBox(height: Space.xxxl),
                  PrimaryButton(
                    label: _signingIn
                        ? 'Signing in'
                        : 'Back up to your Google account',
                    // Disabled while the sheet is up, so a second tap cannot
                    // open a second one behind the first.
                    onPressed: _signingIn ? null : _signIn,
                  ),
                  const SizedBox(height: Space.xl),
                  _Or(c: c),
                  const SizedBox(height: Space.xl),
                  // **Equal standing.** A plain text action at the size the
                  // primary is labelled at, in the primary ink, dead centre —
                  // not a grey `Skip` in a corner, not small print. Declining
                  // is a real answer and Settings offers the same connection
                  // later, so nothing here needs to argue with it.
                  Center(
                    child: Pressable(
                      onTap: _signingIn ? null : _decline,
                      scale: 0.96,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                          vertical: Space.md,
                        ),
                        child: Text(
                          'Use without an account',
                          style: context.t.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline either side of the word, which is the only place in the app a
/// rule carries a label. It separates two answers rather than decorating them:
/// without it the text action reads as a footnote to the button above it.
class _Or extends StatelessWidget {
  const _Or({required this.c});

  final DeltoidColors c;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Container(height: 1, color: c.border));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Text(
            // The one uppercase label outside a page eyebrow — see
            // THEME → the welcome screen, which spells this rule `OR`. It is a
            // separator rather than a heading, and lowercase at 11sp between
            // two hairlines reads as a word someone forgot to finish.
            'OR',
            style: context.t.labelSmall?.copyWith(color: c.textTertiary),
          ),
        ),
        line,
      ],
    );
  }
}
