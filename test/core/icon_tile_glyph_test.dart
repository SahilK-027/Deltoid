import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The glyph on an identity tile is the fill's own hue taken down, and every
/// tile has to read at the same strength — the whole reason the palettes are
/// solved for equal contrast rather than picked.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('every identity fill gets a glyph of its own hue, at 3.2:1 or better',
      () {
    for (final palette in [DeltoidColors.dark, DeltoidColors.light]) {
      for (final fill in palette.identity) {
        final glyph = IconTile.glyphOn(fill);

        expect(_contrast(glyph, fill), greaterThanOrEqualTo(3.2),
            reason: 'glyph on $fill is too close to it');
        // Same hue: a black or white glyph would make the tile two colours.
        // Two degrees of slack for the 8-bit round trip through HSL — a hue is
        // stored as three bytes and comes back a fraction of a degree off.
        expect(
          HSLColor.fromColor(glyph).hue,
          closeTo(HSLColor.fromColor(fill).hue, 2.0),
          reason: 'glyph on $fill drifted off the hue',
        );
        expect(
          HSLColor.fromColor(glyph).lightness,
          lessThan(HSLColor.fromColor(fill).lightness),
          reason: 'glyph on $fill is not darker than it',
        );
      }
    }
  });

  test('the semantic fills — deload, positive, progress — resolve too', () {
    for (final palette in [DeltoidColors.dark, DeltoidColors.light]) {
      for (final fill in [
        palette.deload,
        palette.positive,
        palette.progress,
        palette.negative,
      ]) {
        expect(_contrast(IconTile.glyphOn(fill), fill),
            greaterThanOrEqualTo(3.2));
      }
    }
  });
}
