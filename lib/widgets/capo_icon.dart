// The capo icon: a fretboard (strings, the nut) with the capo bar across it.
import 'package:flutter/material.dart';

/// The capo icon at [size], in [color] (default: the icon theme's).
class CapoIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const CapoIcon({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _CapoPainter(color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface),
  );
}

class _CapoPainter extends CustomPainter {
  final Color color;
  _CapoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // drawn on a 24 × 24 grid, like the Material icons beside it
    final k = size.width / 24;
    Paint line(double w) => Paint()
      ..color = color
      ..strokeWidth = w * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // five strings
    for (final x in [6.0, 9.0, 12.0, 15.0, 18.0]) {
      canvas.drawLine(Offset(x * k, 4 * k), Offset(x * k, 20 * k), line(1.1));
    }
    // the nut
    canvas.drawLine(Offset(4 * k, 4 * k), Offset(20 * k, 4 * k), line(2.4));
    // a fret below the capo
    canvas.drawLine(Offset(5 * k, 16 * k), Offset(19 * k, 16 * k), line(1));
    // the capo bar across the strings
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(3.5 * k, 9.5 * k, 17 * k, 3.4 * k), Radius.circular(1.7 * k)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CapoPainter o) => o.color != color;
}
