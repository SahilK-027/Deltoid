import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/phases.dart';
import '../theme/tokens.dart';

/// The phase colours, by kind (THEME → Semantic assignments).
extension PhaseHue on DeltoidColors {
  /// The phase's own hue: its legend swatch.
  Color phase(PhaseKind kind) => switch (kind) {
        PhaseKind.bulk => bulk,
        PhaseKind.cut => cut,
        PhaseKind.maintenance => maintenance,
      };

  /// The tint a phase lays behind a chart: `bulk` and `cut` at 20%, and
  /// `maintenance` at 16%, because a grey at 20% reads as a second surface
  /// rather than as a tint.
  Color phaseTint(PhaseKind kind) => phase(kind).withValues(
        alpha: kind == PhaseKind.maintenance ? 0.16 : 0.20,
      );
}

/// The Phase card's bodyweight sparkline, 72 tall: the weekly line in
/// `progress` over a tint for each phase, the latest week a filled dot.
///
/// No axis, as no sparkline has one (THEME → Phase card). A painter rather
/// than [CycleAxisChart]'s sparkline form, because this one is placed by day
/// rather than by slot: a phase starts on a Thursday, and its tint has to
/// start there too.
class PhaseSparkline extends StatelessWidget {
  const PhaseSparkline({super.key, required this.data, this.semanticLabel});

  final PhaseSparklineData data;

  /// What the line says, for a screen reader.
  final String? semanticLabel;

  static const height = 72.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _PhaseSparklinePainter(
            data: data,
            line: c.progress,
            ring: c.surface,
            tint: c.phaseTint,
          ),
        ),
      ),
    );
  }
}

class _PhaseSparklinePainter extends CustomPainter {
  _PhaseSparklinePainter({
    required this.data,
    required this.line,
    required this.ring,
    required this.tint,
  });

  final PhaseSparklineData data;
  final Color line;
  final Color ring;
  final Color Function(PhaseKind) tint;

  /// Room at each edge for the latest week's dot and its ring.
  static const _inset = 6.0;
  static const _dot = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final days = math.max(1, data.days);

    // The tints meet without a seam, so the corners are the chart's rather
    // than each band's.
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.mark)),
    );
    for (final band in data.bands) {
      final left = band.fromDay / days * size.width;
      final right = band.toDay / days * size.width;
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = tint(band.kind),
      );
    }
    canvas.restore();

    final weeks = data.weeks;
    if (weeks.isEmpty) return;

    final values = [for (final w in weeks) w.weightKg];
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    // Half a kilogram either side at least, so a flat month is drawn as a
    // flat line in the middle rather than as noise stretched to the edges.
    final pad = math.max(0.5, (hi - lo) * 0.1);
    final top = hi + pad;
    final span = (hi - lo) + pad * 2;

    final plotWidth = math.max(0.0, size.width - _inset * 2);
    final plotHeight = math.max(0.0, size.height - _inset * 2);
    Offset at(({double day, double weightKg}) w) => Offset(
          _inset + w.day / days * plotWidth,
          _inset + (top - w.weightKg) / span * plotHeight,
        );

    final points = [for (final w in weeks) at(w)];
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(points.last, _dot + 2, Paint()..color = ring);
    canvas.drawCircle(points.last, _dot, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_PhaseSparklinePainter old) =>
      old.data != data || old.line != line || old.ring != ring;
}

/// The swatches under a phase tint: a 10 square in each phase's hue, named
/// in the text colour around it, never in the hue (THEME → Semantic
/// assignments: cyan on a white card is 1.7:1).
class PhaseLegend extends StatelessWidget {
  const PhaseLegend({super.key, required this.kinds});

  final List<PhaseKind> kinds;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = context.t.labelSmall?.copyWith(color: c.textSecondary);
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.xs,
      children: [
        for (final kind in kinds)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: c.phase(kind),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Space.xs),
              Text(kind.label, style: style),
            ],
          ),
      ],
    );
  }
}
