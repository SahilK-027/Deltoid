import 'package:flutter/material.dart';

/// The Material Symbols `monitoring` glyph: five bars under a rising line.
///
/// Flutter's `Icons` does not ship it, and THEME rules out a near-miss such as
/// `insights` or `show_chart` for the Progress tab, so it is drawn here from
/// the symbol's own path rather than pulled in with a whole icon font for one
/// glyph. It takes `IconTheme` colour and size like a real icon.
///
/// The symbol's filled and outlined variants are the same shape — the bars and
/// the line have no interior to fill — so the selected tab is told apart by
/// brightness and the label's weight alone, which is what the bar relies on
/// anyway.
class MonitoringIcon extends StatelessWidget {
  const MonitoringIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MonitoringPainter(tint)),
    );
  }
}

class _MonitoringPainter extends CustomPainter {
  const _MonitoringPainter(this.color);

  final Color color;

  /// The symbol's path on its own 960-unit grid, with y measured down from the
  /// top rather than up from the baseline as the font stores it.
  static final Path _glyph = () {
    final p = Path();
    void bar(double left, double top, double bevelTo) {
      // Each bar is a column whose top is cut at an angle to meet the line.
      p
        ..moveTo(left, 840)
        ..lineTo(left, top)
        ..lineTo(left + 60, bevelTo)
        ..lineTo(left + 60, 840)
        ..close();
    }

    bar(120, 764, 704);
    bar(285, 604, 544);
    bar(450, 544, 605);
    bar(615, 605, 545);
    bar(780, 444, 384);

    p
      ..moveTo(120, 633)
      ..lineTo(120, 548)
      ..lineTo(400, 270)
      ..lineTo(560, 430)
      ..lineTo(840, 149)
      ..lineTo(840, 234)
      ..lineTo(560, 516)
      ..lineTo(400, 356)
      ..close();
    return p;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 960, size.height / 960);
    canvas.drawPath(_glyph, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MonitoringPainter old) => old.color != color;
}
