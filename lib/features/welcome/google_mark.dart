import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Google's `G`, as Google draws it.
///
/// **The one place in this app a hue means nothing of its own** — see
/// THEME → the threshold screen, which grants this and nothing else. These four
/// colours are not from the app's palette and never mix with it: they are
/// somebody else's identity, on the one control that opens somebody else's
/// sheet, and a user looking for the Google button is looking for exactly this
/// shape in exactly these colours.
///
/// The official asset rather than a hand-drawn approximation. A brand mark is
/// the one drawing in an app that is not ours to interpret: an arc a few degrees
/// out reads as a knock-off, and nothing in a test can tell you it is wrong.
/// Vector, so it stays sharp at any size and needs no density variants.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/brand/google_g.svg', width: size, height: size);
}
