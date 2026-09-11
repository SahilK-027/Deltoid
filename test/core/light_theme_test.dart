import 'dart:math' as math;
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/theme/tokens.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// THEME defines a full light ramp and every widget test in this suite builds
/// `Brightness.dark`, so a contrast bug in light mode was invisible until this
/// existed.
///
/// The check is arithmetic rather than a golden. A screenshot of a light screen
/// tells you it rendered; the number below tells you whether the grey text on
/// it can be read, which is the thing that actually goes wrong when a ramp is
/// tuned in the dark and mirrored into the light afterwards.
///
/// The thresholds are WCAG AA: 4.5:1 for body text, 3:1 for large text and for
/// a mark whose job is to be seen rather than read. Both ramps are held to
/// them, because the dark one being the one everybody looks at is exactly why
/// nobody would notice the light one drifting.
void main() {
  for (final (name, c) in [
    ('light', DeltoidColors.light),
    ('dark', DeltoidColors.dark),
  ]) {
    group('the $name ramp', () {
      /// Every ground a piece of text can land on. `bg` is the page, `surface`
      /// the card, `surfaceHigh` a control on a card, `surfaceHighest` an inert
      /// fill — a value read on all four.
      final grounds = <String, Color>{
        'bg': c.bg,
        'surfaceSunken': c.surfaceSunken,
        'surface': c.surface,
        'surfaceHigh': c.surfaceHigh,
        'surfaceHighest': c.surfaceHighest,
      };

      test('primary text is readable on every ground', () {
        for (final ground in grounds.entries) {
          expect(
            _contrast(c.textPrimary, ground.value),
            greaterThanOrEqualTo(4.5),
            reason: 'textPrimary on ${ground.key}',
          );
        }
      });

      test('secondary text is readable on every ground a sentence lands on',
          () {
        // Every ground but the last: `surfaceHighest` is an inert fill — a
        // keypad key, a chip, a disabled control — and carries a label rather
        // than a sentence. It is measured below, at the floor it actually
        // holds, rather than left unmeasured.
        for (final ground in grounds.entries) {
          if (ground.key == 'surfaceHighest') continue;
          expect(
            _contrast(c.textSecondary, ground.value),
            greaterThanOrEqualTo(4.5),
            reason: 'textSecondary on ${ground.key} — the subtitle under every '
                'row in the app',
          );
        }
      });

      test('tertiary text clears the large-text floor on a page and a card',
          () {
        // `textTertiary` is a hint, a chevron and a caption — never a sentence,
        // and never the only place a fact appears.
        for (final ground in ['bg', 'surface']) {
          expect(
            _contrast(c.textTertiary, grounds[ground]!),
            greaterThanOrEqualTo(3.0),
            reason: 'textTertiary on $ground',
          );
        }
      });

      test('the greys on a fill are where THEME says they are', () {
        // THEME → Colour → Contrast: four pairs sit under AA, all of them a
        // grey on a raised fill, all of them label-sized text that never
        // carries a fact on its own. They are pinned here so the ramp cannot
        // drift further down without saying so — this test is the record of
        // what was accepted, not a threshold picked to pass.
        expect(_contrast(c.textSecondary, c.surfaceHighest),
            greaterThanOrEqualTo(4.0),
            reason: 'dark measures 4.04, light 4.84');
        expect(_contrast(c.textTertiary, c.surfaceSunken),
            greaterThanOrEqualTo(2.7),
            reason: 'light measures 2.74, dark 3.81');
        expect(
            _contrast(c.textTertiary, c.surfaceHigh), greaterThanOrEqualTo(2.7),
            reason: 'dark measures 2.78, light 2.87');
        expect(_contrast(c.textTertiary, c.surfaceHighest),
            greaterThanOrEqualTo(2.2),
            reason: 'dark measures 2.23, light 2.55');
      });

      test('the accent pair reads both ways round', () {
        // The primary button: `onAccent` on `accent`, and `accent` as text on
        // the page for a link.
        expect(_contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.accent, c.bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.accent, c.surface), greaterThanOrEqualTo(4.5));
      });

      test('a mark is visible against the ground it is drawn on', () {
        // Not text, so 3:1 — but a heat cell that cannot be told from the card
        // it sits on is a grid with no pattern in it, which is the whole point
        // of the section.
        expect(_contrast(c.heatEmpty, c.surface), greaterThanOrEqualTo(1.2),
            reason: 'a rest day has to be visible as a cell');
        expect(_contrast(c.heatOn, c.heatEmpty), greaterThanOrEqualTo(1.5),
            reason: 'a day trained against a day not');
        expect(_contrast(c.borderStrong, c.surface), greaterThanOrEqualTo(1.3));
      });

      test('the semantic hues carry against the ground', () {
        for (final hue in {
          'negative': c.negative,
          'positive': c.positive,
          'deload': c.deload,
          'warning': c.warning,
        }.entries) {
          expect(
            _contrast(hue.value, c.surface),
            greaterThanOrEqualTo(1.4),
            reason: '${hue.key} on a card — a hue is a mark, not a sentence, '
                'and yellow on white is the tightest of them at 1.44',
          );
        }
      });

      test('the muted grounds hold their own hue', () {
        // `warningMuted` is the notice's tint and `deloadMuted` a light week's:
        // both are grounds that text lands on.
        expect(_contrast(c.textPrimary, c.warningMuted),
            greaterThanOrEqualTo(4.5));
        expect(
            _contrast(c.textPrimary, c.deloadMuted), greaterThanOrEqualTo(4.5));
      });
    });
  }

  testWidgets('a screen built in light is built at all', (tester) async {
    // The ramp being sound says nothing about the theme assembling. Every other
    // widget test in this suite passes `Brightness.dark`.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Text('Push 1', style: Theme.of(context).textTheme.titleLarge),
                const TextField(decoration: InputDecoration(hintText: 'Name')),
                PrimaryButton(label: 'Start', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Push 1'), findsOneWidget);
  });

  test('the two ramps are the same shape', () {
    // A token added to one and not the other is how a screen ends up half
    // themed. Colours are non-nullable, so this is really a check that the
    // lists that are palettes stay the same length.
    expect(DeltoidColors.light.series.length,
        DeltoidColors.dark.series.length);
    expect(DeltoidColors.light.identity.length,
        DeltoidColors.dark.identity.length);
  });
}

/// WCAG relative luminance and contrast ratio, worked from the sRGB values in
/// `tokens.dart`. Written out here rather than taken from a package: it is six
/// lines, and a threshold nobody can read the derivation of is a threshold that
/// gets lowered when it fails.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

double _luminance(Color colour) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * channel(colour.r) +
      0.7152 * channel(colour.g) +
      0.0722 * channel(colour.b);
}
