import 'package:flutter/material.dart';

import '../eink.dart';

/// The sidebar toggle, drawn like Bramble Notes': a rounded window with a
/// divider near its left edge. With [chevron] going 0 → 1 the divider bends
/// into a chevron pointing which way the sidebar will go ([pointLeft]: it
/// will close). Takes its colour and size from the surrounding [IconTheme],
/// like [Icon].
class SidebarIcon extends StatelessWidget {
  final double? size;
  final Color? color;
  final double chevron;
  final bool pointLeft;
  const SidebarIcon({
    super.key,
    this.size,
    this.color,
    this.chevron = 0,
    this.pointLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: _SidebarPainter(
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
          chevron,
          pointLeft,
        ),
      ),
    );
  }
}

class _SidebarPainter extends CustomPainter {
  final Color color;
  final double chevron;
  final bool pointLeft;
  const _SidebarPainter(this.color, this.chevron, this.pointLeft);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24 × 24 grid.
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromLTRBR(2.8, 4.8, 21.2, 19.2, const Radius.circular(3.4)),
      stroke,
    );
    // The divider, its ends drawn in and its middle pushed out as it bends
    // into the chevron (‹ to close, › to open).
    final t = Curves.easeInOut.transform(chevron.clamp(0.0, 1.0));
    const x = 9.0;
    final tip = pointLeft ? x - 1.6 : x + 1.6;
    final back = pointLeft ? x + 1.0 : x - 1.0;
    double lerp(double a, double b) => a + (b - a) * t;
    final path = Path()
      ..moveTo(lerp(x, back), lerp(4.8, 8.7))
      ..lineTo(lerp(x, tip), 12)
      ..lineTo(lerp(x, back), lerp(19.2, 15.3));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_SidebarPainter old) =>
      old.color != color || old.chevron != chevron || old.pointLeft != pointLeft;
}

/// The sidebar button: [SidebarIcon] whose divider bends into a chevron
/// while the pointer is over it (which way: [open] → ‹, closing).
class SidebarToggleButton extends StatefulWidget {
  final bool open;
  final VoidCallback onPressed;
  const SidebarToggleButton({
    super.key,
    required this.open,
    required this.onPressed,
  });

  @override
  State<SidebarToggleButton> createState() => _SidebarToggleButtonState();
}

class _SidebarToggleButtonState extends State<SidebarToggleButton> {
  var _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: IconButton(
      tooltip: widget.open ? 'Hide sidebar' : 'Show sidebar',
      onPressed: widget.onPressed,
      icon: TweenAnimationBuilder<double>(
        tween: Tween(end: _hover ? 1 : 0),
        duration: motion(context, const Duration(milliseconds: 180)),
        curve: Curves.easeOut,
        builder: (context, v, _) =>
            SidebarIcon(chevron: v, pointLeft: widget.open),
      ),
    ),
  );
}
