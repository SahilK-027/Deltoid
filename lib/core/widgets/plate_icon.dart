import 'package:flutter/material.dart';

/// A stack of plates, drawn rather than borrowed.
///
/// Material ships exactly one piece of gym equipment — a dumbbell — and it is
/// the icon every training app on the phone already wears. This is the shape
/// the app is actually about: plates, biggest at the bottom, the way they sit
/// against a rack.
///
/// Drawn as geometry rather than as a font glyph or an asset, because at nav
/// size the whole icon is six rounded rectangles and a path would be harder to
/// tune than the numbers below. It also means it inherits `IconTheme` colour
/// and size like a real icon, and costs nothing at build time.
///
/// [filled] is the live tab: solid bars. Unselected draws the same bars as
/// outlines, which is the filled/outlined pair every other destination gets
/// from Material.
class PlateIcon extends StatelessWidget {
  const PlateIcon({super.key, this.size = 24, this.color, this.filled = false});

  final double size;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PlateStackPainter(color: tint, filled: filled),
      ),
    );
  }
}

class _PlateStackPainter extends CustomPainter {
  const _PlateStackPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  /// Widths as a fraction of the icon, bottom plate first. The taper is what
  /// makes it read as *stacked* rather than as a list: three equal bars are a
  /// hamburger menu.
  static const _widths = [1.0, 0.74, 0.48];

  @override
  void paint(Canvas canvas, Size size) {
    // A 24dp icon on a 62dp bar: three bars, three gaps, and the whole stack
    // sitting on the optical centre rather than the geometric one.
    final unit = size.height / 24;
    final barHeight = 5.0 * unit;
    final gap = 2.5 * unit;
    final stackHeight = barHeight * 3 + gap * 2;
    final top = (size.height - stackHeight) / 2;

    final stroke = 1.8 * unit;
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < _widths.length; i++) {
      final width = size.width * _widths[i];
      // Bottom plate first, so the widest is lowest — a stack leans on the
      // floor, not on the top of the frame.
      final y = top + (2 - i) * (barHeight + gap);
      final rect = Rect.fromLTWH(
        (size.width - width) / 2,
        y,
        width,
        barHeight,
      );
      // Inset by half the stroke, or an outlined bar sits half a pixel outside
      // the box and the widest one clips against the icon's edge.
      final drawn = filled ? rect : rect.deflate(stroke / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(drawn, Radius.circular(barHeight / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PlateStackPainter old) =>
      old.color != color || old.filled != filled;
}
