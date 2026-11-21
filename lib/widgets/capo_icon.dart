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
    // drawn on a 24 × 24 grid in the app icons' style (Bramble Icons:
    // Phosphor's 1.5 line, round ends, outlines only, lines stopping short
    // of what they pass behind)
    final k = size.width / 24;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.5 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // the capo bar across the strings
    const bar = (top: 8.6, bottom: 12.6);
    // five strings, from the nut to below the fret, behind the bar
    for (final x in [6.0, 9.0, 12.0, 15.0, 18.0]) {
      canvas.drawLine(Offset(x * k, 4 * k), Offset(x * k, (bar.top - 1.4) * k), line);
      canvas.drawLine(Offset(x * k, (bar.bottom + 1.4) * k), Offset(x * k, 20 * k), line);
    }
    // the nut
    canvas.drawLine(Offset(4.5 * k, 4 * k), Offset(19.5 * k, 4 * k), line);
    // a fret below the capo
    canvas.drawLine(Offset(4.5 * k, 16.5 * k), Offset(19.5 * k, 16.5 * k), line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(3 * k, bar.top * k, 21 * k, bar.bottom * k),
        Radius.circular(2 * k),
      ),
      line,
    );
  }

  @override
  bool shouldRepaint(_CapoPainter o) => o.color != color;
}
