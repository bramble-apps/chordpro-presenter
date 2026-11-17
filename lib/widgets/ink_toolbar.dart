import 'package:flutter/material.dart';

import '../eink.dart';
import 'color_picker.dart';
import 'ink_layer.dart';

/// The annotation tools, as a pill (shown in a floating panel): pen /
/// highlighter / eraser / move, the colour (of the pen or highlighter),
/// undo, redo and Done. Tapping the pen or highlighter again opens its
/// sizes and opacity.
class InkToolbar extends StatelessWidget {
  final InkController controller;
  final VoidCallback onDone;

  /// The pill's size (its floating panel is this size).
  static const size = Size(436, 84);

  const InkToolbar({super.key, required this.controller, required this.onDone});

  static const _swatches = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFFEB3B),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFF000000),
    Color(0xFFFFFFFF),
  ];

  Future<void> _pickColor(BuildContext context, Offset at) async {
    final c = controller;
    final v = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem<Object>(
          enabled: false,
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _swatches)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context, s),
                  child: _Dot(color: s, selected: s == c.color, size: 32),
                ),
            ],
          ),
        ),
        const PopupMenuItem<Object>(value: 'custom', child: Text('Custom…')),
      ],
    );
    if (v is Color) c.setColor(v);
    if (v == 'custom' && context.mounted) {
      final picked = await pickColor(context, c.color);
      if (picked != null) c.setColor(picked);
    }
  }

  /// The pen's or highlighter's sizes and opacity, in a popover just above
  /// its button ([at], on screen); tapping anywhere else closes it.
  void _showStyle(BuildContext context, Rect at) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (context, a, _, child) =>
          FadeTransition(opacity: a, child: child),
      pageBuilder: (context, _, _) {
        final screen = MediaQuery.sizeOf(context);
        const w = 264.0, h = 124.0;
        final left = (at.center.dx - w / 2).clamp(8.0, screen.width - w - 8);
        var top = at.top - h - 10;
        if (top < 8) top = at.bottom + 10;
        return Stack(
          children: [
            Positioned(
              left: left.toDouble(),
              top: top,
              width: w,
              height: h,
              child: InkStyleMenu(controller: controller),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        Widget tool(InkTool t, String tip) => _ToolButton(
          tool: t,
          tooltip: tip,
          selected: c.tool == t,
          color: switch (t) {
            InkTool.pen => c.penColor,
            InkTool.highlighter => c.highlighterColor,
            _ => scheme.onSurfaceVariant,
          },
          onTap: (rect) {
            if (c.tool == t && (t == InkTool.pen || t == InkTool.highlighter)) {
              _showStyle(context, rect);
            } else {
              c.tool = t;
            }
          },
        );
        Widget divider() => Container(
          width: 1,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: scheme.outlineVariant,
        );
        return SizedBox.fromSize(
          size: size,
          child: Material(
            elevation: inkE(10),
            color: scheme.surfaceContainerHigh,
            // A clear edge, so it stands out over slides and the sheet.
            shadowColor: isEink(context) ? Colors.transparent : Colors.black,
            shape: einkActive
                ? RoundedRectangleBorder(
                    side: BorderSide(
                      color: scheme.outline,
                      width: inkW(einkStroke),
                    ),
                  )
                : StadiumBorder(
                    side: BorderSide(color: scheme.outline, width: inkW(2)),
                  ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Column(
                children: [
                  // The grab bar (the whole pill drags).
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 9),
                    decoration: BoxDecoration(
                      color: scheme.outline,
                      borderRadius: BorderRadius.circular(inkR(3)),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        tool(InkTool.pen, 'Pen'),
                        tool(InkTool.highlighter, 'Highlighter'),
                        tool(InkTool.eraser, 'Eraser'),
                        tool(InkTool.select, 'Move and resize'),
                        const SizedBox(width: 4),
                        Builder(
                          builder: (context) => Tooltip(
                            message: c.tool == InkTool.highlighter
                                ? 'Highlighter colour'
                                : 'Pen colour',
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTapUp: (d) =>
                                  _pickColor(context, d.globalPosition),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: _Dot(color: c.color, size: 28),
                              ),
                            ),
                          ),
                        ),
                        divider(),
                        IconButton(
                          tooltip: 'Undo',
                          iconSize: 26,
                          icon: const Icon(Icons.undo),
                          onPressed: c.canUndo ? c.undo : null,
                        ),
                        IconButton(
                          tooltip: 'Redo',
                          iconSize: 26,
                          icon: const Icon(Icons.redo),
                          onPressed: c.canRedo ? c.redo : null,
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: 'Done',
                          iconSize: 26,
                          icon: const Icon(Icons.check),
                          onPressed: onDone,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  final bool selected;
  const _Dot({required this.color, this.size = 24, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: inkW(selected ? 3 : 1.5),
        ),
      ),
    );
  }
}

/// A tool standing up in the pill; the one in use stands taller.
class _ToolButton extends StatelessWidget {
  final InkTool tool;
  final String tooltip;
  final bool selected;
  final Color color;

  /// Tapped ([Rect]: the button on screen).
  final ValueChanged<Rect> onTap;

  const _ToolButton({
    required this.tool,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(inkR(10)),
        onTap: () {
          final box = context.findRenderObject() as RenderBox;
          onTap(box.localToGlobal(Offset.zero) & box.size);
        },
        child: SizedBox(
          width: 44,
          height: 56,
          // The move arrows stay put; the others stand taller in use.
          child: tool == InkTool.select
              ? Icon(
                  Icons.open_with,
                  size: 26,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                )
              : Align(
                  alignment: Alignment.bottomCenter,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: selected ? 52 : 38),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    builder: (context, h, _) => CustomPaint(
                      size: Size(28, h),
                      painter: _ToolPainter(
                        tool: tool,
                        tip: color,
                        body: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        edge: scheme.outline,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ToolPainter extends CustomPainter {
  final InkTool tool;
  final Color tip;
  final Color body;
  final Color edge;
  const _ToolPainter({
    required this.tool,
    required this.tip,
    required this.body,
    required this.edge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height;
    final fill = Paint()..color = body;
    final outline = Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    switch (tool) {
      case InkTool.pen:
        // Barrel, cone and a coloured point.
        const bw = 12.0;
        final top = 14.0;
        final barrel = RRect.fromLTRBAndCorners(
          cx - bw / 2,
          top,
          cx + bw / 2,
          h,
          topLeft: const Radius.circular(1),
          topRight: const Radius.circular(1),
        );
        canvas.drawRRect(barrel, fill);
        final cone = Path()
          ..moveTo(cx - bw / 2, top)
          ..lineTo(cx, 0)
          ..lineTo(cx + bw / 2, top)
          ..close();
        canvas.drawPath(cone, Paint()..color = const Color(0xFFE9D6B5));
        final point = Path()
          ..moveTo(cx - 3, 6)
          ..lineTo(cx, 0)
          ..lineTo(cx + 3, 6)
          ..close();
        canvas.drawPath(point, Paint()..color = tip);
        canvas.drawPath(cone, outline);
      case InkTool.highlighter:
        // Wide body and a slanted, coloured chisel tip.
        const bw = 16.0;
        final top = 14.0;
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - bw / 2,
            top,
            cx + bw / 2,
            h,
            const Radius.circular(3),
          ),
          fill,
        );
        final neck = Path()
          ..moveTo(cx - bw / 2, top)
          ..lineTo(cx - 5, 6)
          ..lineTo(cx + 5, 6)
          ..lineTo(cx + bw / 2, top)
          ..close();
        canvas.drawPath(neck, Paint()..color = body.withValues(alpha: 0.6));
        final chisel = Path()
          ..moveTo(cx - 5, 6)
          ..lineTo(cx - 5, 2)
          ..lineTo(cx + 5, 0)
          ..lineTo(cx + 5, 6)
          ..close();
        canvas.drawPath(chisel, Paint()..color = tip);
        canvas.drawPath(chisel, outline);
      case InkTool.eraser:
        // A block eraser: pink end on top.
        const bw = 16.0;
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - bw / 2,
            10,
            cx + bw / 2,
            h,
            const Radius.circular(3),
          ),
          fill,
        );
        final end = RRect.fromLTRBAndCorners(
          cx - bw / 2,
          0,
          cx + bw / 2,
          12,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(end, Paint()..color = const Color(0xFFF48FB1));
        canvas.drawRRect(end, outline);
      case InkTool.select:
        break;
    }
  }

  @override
  bool shouldRepaint(_ToolPainter old) =>
      old.tool != tool ||
      old.tip != tip ||
      old.body != body ||
      old.edge != edge;
}

/// Sizes (thin to thick) and an opacity slider for the pen or highlighter
/// in use.
class InkStyleMenu extends StatelessWidget {
  final InkController controller;
  const InkStyleMenu({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: inkE(10),
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(inkR(16)),
        side: BorderSide(color: scheme.outline, width: inkW(2)),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final hl = c.tool == InkTool.highlighter;
          final sizes = hl
              ? InkController.highlighterSizes
              : InkController.penSizes;
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < sizes.length; i++)
                      Tooltip(
                        message: 'Size ${i + 1}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(inkR(10)),
                          onTap: () => c.setSize(i),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: c.size == i
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(inkR(10)),
                            ),
                            child: CustomPaint(
                              painter: _SizePainter(
                                // Thin to thick, on the same scale for both.
                                width: 2.0 + i * (hl ? 2.6 : 1.8),
                                square: hl,
                                color: c.size == i
                                    ? scheme.surface
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Clear (checkered) to the colour.
                      Positioned.fill(
                        left: 12,
                        right: 12,
                        top: 8,
                        bottom: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(inkR(12)),
                          child: CustomPaint(
                            painter: _OpacityTrackPainter(c.color),
                          ),
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 24,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: Colors.white,
                          overlayColor: Colors.transparent,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 13,
                            elevation: inkE(3),
                          ),
                          trackShape: const RectangularSliderTrackShape(),
                        ),
                        child: Slider(
                          value: c.opacity,
                          min: 0.1,
                          semanticFormatterCallback: (v) =>
                              'Opacity ${(v * 100).round()}%',
                          onChanged: c.setOpacity,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A diagonal stroke, [width] thick (round pen / square highlighter).
class _SizePainter extends CustomPainter {
  final double width;
  final bool square;
  final Color color;
  const _SizePainter({
    required this.width,
    required this.square,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide * 0.24;
    final c = size.center(Offset.zero);
    canvas.drawLine(
      c + Offset(-d, d),
      c + Offset(d, -d),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = square ? StrokeCap.square : StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SizePainter old) =>
      old.width != width || old.square != square || old.color != color;
}

/// A checkerboard fading into [color] (the opacity slider's track).
class _OpacityTrackPainter extends CustomPainter {
  final Color color;
  const _OpacityTrackPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grey = Paint()..color = const Color(0xFFD6D6D6);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if ((x + y).isOdd) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), grey);
        }
      }
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 1)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_OpacityTrackPainter old) => old.color != color;
}
