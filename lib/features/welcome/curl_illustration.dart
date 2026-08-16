import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/tokens.dart';

/// The threshold screen's drawing: a figure curling a dumbbell.
///
/// Two layers, and the split is the whole design. `curl_line.svg` is the
/// figure — head, back, forearm and the four fingers over the bar — and takes
/// `textPrimary`, so it inverts with the theme like everything else. The
/// dumbbell is `curl_mass.svg` and takes a **hue**, which it cycles through the
/// six identity colours.
///
/// **Both of those stand outside rules THEME states plainly**, and both are
/// written into THEME → the threshold screen rather than argued here: chrome is
/// monochrome and colour is data, and motion confirms a change rather than
/// performing. What buys them is that this screen holds no data for a colour to
/// be confused with — no regime, no series, no deload — and is seen once.
///
/// The line and the mass are separate files rather than one, because a single
/// asset cannot be two colours that both answer to the theme.
class CurlIllustration extends StatefulWidget {
  const CurlIllustration({super.key, this.size = const Size(268, 304)});

  final Size size;

  /// How long each hue is held. The cross-fade runs inside it.
  static const hold = Duration(seconds: 3);

  @override
  State<CurlIllustration> createState() => _CurlIllustrationState();
}

class _CurlIllustrationState extends State<CurlIllustration> {
  int _slot = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // A timer rather than a repeating controller: the colour is held still for
    // three seconds and then moves, which is a sequence of states rather than a
    // continuous animation. Nothing is being interpolated in between except the
    // fade, and `AnimatedSwitcher` owns that.
    _timer = Timer.periodic(CurlIllustration.hold, (_) {
      if (mounted) setState(() => _slot++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hue = c.identityAt(_slot);

    return SizedBox.fromSize(
      size: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The dumbbell, behind the hand that holds it.
          AnimatedSwitcher(
            duration: Motion.slow,
            switchInCurve: Motion.curve,
            switchOutCurve: Motion.curve,
            child: SvgPicture.asset(
              'assets/brand/curl_mass.svg',
              key: ValueKey(hue.toARGB32()),
              colorFilter: ColorFilter.mode(hue, BlendMode.srcIn),
            ),
          ),
          SvgPicture.asset(
            'assets/brand/curl_line.svg',
            colorFilter: ColorFilter.mode(c.textPrimary, BlendMode.srcIn),
          ),
        ],
      ),
    );
  }
}
