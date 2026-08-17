import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/tokens.dart';

/// The threshold screen's drawing: a figure curling a dumbbell.
///
/// Two layers, and the split is the whole design. `curl_line.svg` is the
/// figure — head, back, forearm and the four fingers over the bar — and takes
/// `textPrimary`, so it inverts with the theme like everything else. The
/// dumbbell is `curl_mass.svg` and takes one fixed hue, [DeltoidColors.lavender].
///
/// **The hue stands outside a rule THEME states plainly** — chrome is
/// monochrome and colour is data — and it is written into THEME → the threshold
/// screen rather than argued here. What buys it is that this screen holds no
/// data for a colour to be confused with: no regime, no series, no deload.
///
/// It does **not** cycle. A colour that moves on its own is motion performing
/// rather than confirming a change, and there is no change here to confirm.
///
/// The line and the mass are separate files rather than one, because a single
/// asset cannot be two colours where only one of them answers to the theme.
class CurlIllustration extends StatelessWidget {
  const CurlIllustration({super.key, this.size = const Size(268, 304)});

  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The dumbbell, behind the hand that holds it. A fixed hue rather
          // than a theme colour: the mass is the same lavender in both themes,
          // like the identity marks it is drawn from.
          SvgPicture.asset(
            'assets/brand/curl_mass.svg',
            colorFilter: const ColorFilter.mode(
              DeltoidColors.lavender,
              BlendMode.srcIn,
            ),
          ),
          SvgPicture.asset(
            'assets/brand/curl_line.svg',
            colorFilter: ColorFilter.mode(
              context.c.textPrimary,
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    );
  }
}
