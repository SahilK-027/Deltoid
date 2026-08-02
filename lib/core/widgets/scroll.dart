import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How everything in this app scrolls.
///
/// Damped, everywhere, on every platform. Android's default is
/// `ClampingScrollPhysics`: a list stops dead at the end of its content and a
/// flick decelerates on a curve tuned for a stretch indicator to do the rest of
/// the talking. It is not *wrong*, it just feels like furniture being pushed —
/// and this is an app you scroll one-handed with a bar in your other hand.
/// `BouncingScrollPhysics` carries the flick, resists at the edges and settles,
/// which is the difference between a list that stops and a list that arrives.
///
/// The overscroll glow goes with it: a stretch or a glow is what a clamping
/// list uses to say "that is the end", and a list that visibly resists has
/// already said it. Two answers to one question is one too many.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;

  /// A trackpad drag scrolls, which it does not by default — this matters on
  /// the desktop builds used to develop the thing.
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.mouse,
      };
}
