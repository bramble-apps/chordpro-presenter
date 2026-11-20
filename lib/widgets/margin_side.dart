// Which margin the section labels go in: two small icon buttons, each like a
// quote-block icon (a bar beside lines of text), the bar on the left or the
// right. Compact enough for a phone.
import 'package:flutter/material.dart';

/// Picks 'left' or 'right' for labels in margins.
class MarginSidePicker extends StatelessWidget {
  final String side;
  final ValueChanged<String> onChanged;
  const MarginSidePicker({super.key, required this.side, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    style: const ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(
        value: 'left',
        icon: RailIcon(right: false),
        tooltip: 'Left margin',
      ),
      ButtonSegment(
        value: 'right',
        icon: RailIcon(right: true),
        tooltip: 'Right margin',
      ),
    ],
    selected: {side == 'right' ? 'right' : 'left'},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}

/// A bar on the left (or [right]) beside three lines of text, in the icon
/// colour.
class RailIcon extends StatelessWidget {
  final bool right;
  final double size;
  const RailIcon({super.key, required this.right, this.size = 20});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _RailIconPainter(
      right,
      IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _RailIconPainter extends CustomPainter {
  final bool right;
  final Color color;
  _RailIconPainter(this.right, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // on a 24 × 24 grid, like the Material icons
    final k = size.width / 24;
    double x(double v) => (right ? 24 - v : v) * k;
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    // the bar
    canvas.drawLine(Offset(x(4), 5 * k), Offset(x(4), 19 * k), p..strokeWidth = 2.6 * k);
    // the text: three lines, the last shorter
    p.strokeWidth = 2 * k;
    for (final (y, end) in [(7.0, 20.0), (12.0, 20.0), (17.0, 15.5)]) {
      canvas.drawLine(Offset(x(9), y * k), Offset(x(end), y * k), p);
    }
  }

  @override
  bool shouldRepaint(_RailIconPainter o) => o.right != right || o.color != color;
}
