import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A metronome: the pyramid case with its pendulum. [swing] tilts the
/// pendulum (−1 = full left, 0 = upright, 1 = full right).
class MetronomeIcon extends StatelessWidget {
  final double swing;
  final double? size;
  final Color? color;
  const MetronomeIcon({super.key, this.swing = 0, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: _MetronomePainter(
          swing: swing,
          color: color ?? theme.color ?? Colors.black,
        ),
      ),
    );
  }
}

class _MetronomePainter extends CustomPainter {
  final double swing;
  final Color color;
  _MetronomePainter({required this.swing, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24 × 24 grid, like the Material icons.
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // The case: a tall trapezoid with a flat top.
    final body = Path()
      ..moveTo(5.5, 21)
      ..lineTo(9.6, 3.2)
      ..lineTo(14.4, 3.2)
      ..lineTo(18.5, 21)
      ..close();
    canvas.drawPath(body, line);
    // The scale window line across the lower case.
    canvas.drawLine(const Offset(7.2, 16.6), const Offset(16.8, 16.6), line);
    // The pendulum from its pivot, with the sliding weight.
    const pivot = Offset(12, 16.6);
    final a = swing.clamp(-1.0, 1.0) * 0.5; // up to ~29°
    final dir = Offset(math.sin(a), -math.cos(a));
    canvas.drawLine(pivot, pivot + dir * 13, line);
    canvas.drawCircle(pivot + dir * 8.2, 1.9, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MetronomePainter old) =>
      old.swing != swing || old.color != color;
}
