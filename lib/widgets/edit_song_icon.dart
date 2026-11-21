import 'package:flutter/material.dart';

/// The "edit song" icon: square brackets (a ChordPro chord) with a text
/// cursor between them. Takes its colour and size from the surrounding
/// [IconTheme], like [Icon].
class EditSongIcon extends StatelessWidget {
  final double? size;
  final Color? color;

  /// How far the brackets have opened round the cursor (0–1; hover).
  final double open;
  const EditSongIcon({super.key, this.size, this.color, this.open = 0});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: _EditSongPainter(
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
          open,
        ),
      ),
    );
  }
}

class _EditSongPainter extends CustomPainter {
  final Color color;
  final double open;
  const _EditSongPainter(this.color, this.open);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24 × 24 grid, in the app icons' style (Bramble Icons:
    // Phosphor's 1.5 line, round ends and corners).
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // (opening: each bracket out by up to 1.6)
    final o = 1.6 * open;
    // [
    canvas.drawPath(
      Path()
        ..moveTo(7.8 - o, 6.5)
        ..lineTo(4.6 - o, 6.5)
        ..lineTo(4.6 - o, 17.5)
        ..lineTo(7.8 - o, 17.5),
      pen,
    );
    // ]
    canvas.drawPath(
      Path()
        ..moveTo(16.2 + o, 6.5)
        ..lineTo(19.4 + o, 6.5)
        ..lineTo(19.4 + o, 17.5)
        ..lineTo(16.2 + o, 17.5),
      pen,
    );
    // The text cursor (an I-beam), taller than the brackets.
    final cursor = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(12, 3), const Offset(12, 21), cursor);
    canvas.drawLine(const Offset(10.3, 3), const Offset(13.7, 3), cursor);
    canvas.drawLine(const Offset(10.3, 21), const Offset(13.7, 21), cursor);
  }

  @override
  bool shouldRepaint(_EditSongPainter old) =>
      old.color != color || old.open != open;
}
