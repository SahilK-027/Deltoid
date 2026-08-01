import 'package:flutter/material.dart';

/// A loaded dumbbell: two plates a side on a short, thick bar.
///
/// Material ships one piece of gym equipment and it is a thinner, longer
/// dumbbell than this — drawn at icon weight rather than at nav weight, it goes
/// spindly against the solid grid, clock and gear beside it. This one is built
/// to hold its own in that row: heavier bar, plates with real width, and a
/// silhouette that still reads at 24dp.
///
/// Geometry rather than a font glyph or an asset. The whole icon is five
/// rounded rectangles, the numbers are easier to tune than a path, and it
/// inherits `IconTheme` colour and size like a real icon.
///
/// [filled] is the live tab. Unselected draws the same shape as outlines, which
/// is the filled/outlined pair every other destination gets from Material.
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
        painter: _DumbbellPainter(color: tint, filled: filled),
      ),
    );
  }
}

class _DumbbellPainter extends CustomPainter {
  const _DumbbellPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is in 24ths, so the shape scales exactly.
    final u = size.width / 24;
    final mid = size.height / 2;

    final stroke = 1.8 * u;
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;

    void bar(double left, double width, double height, double radius) {
      final rect = Rect.fromLTWH(left * u, mid - height * u / 2, width * u,
          height * u);
      // An outlined shape sits half a stroke outside its box, so the outermost
      // plates would clip against the icon's edge.
      final drawn = filled ? rect : rect.deflate(stroke / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(drawn, Radius.circular(radius * u)),
        paint,
      );
    }

    // Outer plates, then inner, then the handle between them. Inner plates are
    // taller: that difference is the whole reason it reads as *loaded* rather
    // than as a barbell drawn end-on.
    bar(1, 3.4, 9, 1.4);
    bar(5, 3.4, 14, 1.6);
    bar(19.6, 3.4, 9, 1.4);
    bar(15.6, 3.4, 14, 1.6);
    bar(8.4, 7.2, 4.4, 1.2);
  }

  @override
  bool shouldRepaint(_DumbbellPainter old) =>
      old.color != color || old.filled != filled;
}
