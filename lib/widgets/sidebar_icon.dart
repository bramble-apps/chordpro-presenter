import 'package:flutter/material.dart';

/// The sidebar toggle drawn like Apple's stock "sidebar.left" symbol: a
/// rounded window with a pane on the left holding three short lines.
/// Takes its colour and size from the surrounding [IconTheme], like [Icon].
class SidebarIcon extends StatelessWidget {
  final double? size;
  final Color? color;
  const SidebarIcon({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: _SidebarPainter(
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _SidebarPainter extends CustomPainter {
  final Color color;
  const _SidebarPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24 × 24 grid.
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromLTRBR(2.8, 4.8, 21.2, 19.2, const Radius.circular(3.4)),
      stroke,
    );
    canvas.drawLine(const Offset(9.2, 4.8), const Offset(9.2, 19.2), stroke);
    final lines = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final y in [8.4, 10.9, 13.4]) {
      canvas.drawLine(Offset(5.0, y), Offset(7.0, y), lines);
    }
  }

  @override
  bool shouldRepaint(_SidebarPainter old) => old.color != color;
}
