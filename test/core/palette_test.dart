import 'package:deltoid/core/theme/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three colours mean one thing each, everywhere: blue is progress, orange is
/// a deload, red is a deletion. A regime, a muscle region or a chart line
/// wearing one of them would claim that meaning, so the identity set and the
/// chart lines are checked against all three rather than trusted to a comment.
void main() {
  for (final (name, c) in [
    ('dark', DeltoidColors.dark),
    ('light', DeltoidColors.light),
  ]) {
    group('$name palette', () {
      final reserved = {c.progress, c.deload, c.negative};

      test('six identity colours, all different', () {
        expect(c.identity, hasLength(6));
        expect(c.identity.toSet(), hasLength(6));
      });

      test('no identity colour is a reserved one', () {
        for (final hue in c.identity) {
          expect(reserved, isNot(contains(hue)), reason: '$hue is reserved');
        }
      });

      test('the identity order is the one the bar list was tuned for', () {
        expect(c.identity, [
          DeltoidColors.pink,
          DeltoidColors.cyan,
          DeltoidColors.yellow,
          DeltoidColors.lavender,
          DeltoidColors.sand,
          DeltoidColors.green,
        ]);
      });

      test('chart lines start with progress and borrow no other reserved hue',
          () {
        expect(c.chartLines.first, c.progress);
        expect(c.chartLines.toSet(), hasLength(c.chartLines.length));
        for (final hue in c.chartLines.skip(1)) {
          expect(reserved, isNot(contains(hue)), reason: '$hue is reserved');
        }
      });

      test('progress is the palette blue and deload the palette orange', () {
        expect(c.progress, DeltoidColors.blue);
        expect(c.deload, DeltoidColors.orange);
      });

      test('set types never borrow a reserved colour', () {
        expect(reserved, isNot(contains(c.warmup)));
        expect(reserved, isNot(contains(c.dropSet)));
      });

      test('a weigh-in never borrows a reserved colour', () {
        expect(reserved, isNot(contains(c.weighIn)));
        expect(c.weighIn, DeltoidColors.lavender);
      });

      test('the phases never borrow a reserved colour', () {
        for (final hue in [c.bulk, c.cut, c.maintenance]) {
          expect(reserved, isNot(contains(hue)), reason: '$hue is reserved');
        }
        expect(c.bulk, DeltoidColors.lavender);
        expect(c.cut, DeltoidColors.cyan);
        expect(c.maintenance, c.textSecondary);
      });
    });
  }
}
