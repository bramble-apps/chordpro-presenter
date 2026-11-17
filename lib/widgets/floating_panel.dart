import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../browser.dart';

/// A little window floating over the app (the video player, the projector
/// preview, sticky notes). Place it with `Positioned.fill` in a Stack: it
/// moves within that area.
///
/// * Dragging follows the pointer exactly; let go and it carries on with
///   the throw's speed, easing to a stop.
/// * Coming to rest near an edge, it settles gently against it.
/// * Corner grips resize it (keeping its shape unless [freeAspect]).
/// * Its spot and size are remembered (per [id]) while the app is open,
///   and reported through [onSettled] for saving.
class FloatingPanel extends StatefulWidget {
  /// Remembers position and size under this name.
  final String id;

  /// Height for a given width (keeps the panel's shape when resizing).
  /// Ignored with [freeAspect].
  final double Function(double width) heightFor;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;

  /// Width and height resize independently (sticky notes).
  final bool freeAspect;
  final double initialHeight;
  final double minHeight;
  final double maxHeight;

  /// Where it starts (before it's moved): an alignment in the area, or an
  /// exact spot.
  final Alignment start;
  final Offset? startAt;

  /// The whole panel drags (otherwise only [FloatingDragArea]s inside).
  final bool dragAnywhere;

  /// Grips on all four corners (otherwise bottom-right only).
  final bool allCorners;

  /// Has resize grips at all (a toolbar keeps its size).
  final bool resizable;

  /// Room kept above the panel (for a toolbar shown over it); part of the
  /// panel's box, so it stays on screen too.
  final double overhang;

  /// Space kept from the area's edges.
  final double margin;

  /// After a move or resize: where the panel (not counting [overhang])
  /// ended up.
  final ValueChanged<Rect>? onSettled;

  final Widget child;

  const FloatingPanel({
    super.key,
    required this.id,
    required this.child,
    this.heightFor = _sixteenNine,
    this.initialWidth = 320,
    this.minWidth = 200,
    this.maxWidth = 720,
    this.freeAspect = false,
    this.initialHeight = 200,
    this.minHeight = 80,
    this.maxHeight = 900,
    this.start = Alignment.bottomLeft,
    this.startAt,
    this.dragAnywhere = false,
    this.allCorners = false,
    this.resizable = true,
    this.overhang = 0,
    this.margin = 16,
    this.onSettled,
  });

  static double _sixteenNine(double w) => w * 9 / 16;

  /// Pulled toward an edge when resting this close to it.
  static const snapDistance = 40.0;

  static final Map<String, (Offset, Size)> _remembered = {};

  /// Drops what was remembered for [id] (it moved somewhere else).
  static void forget(String id) => _remembered.remove(id);

  /// Whether the panel around [context] is being moved or resized (e.g. to
  /// hide a toolbar meanwhile).
  static ValueListenable<bool>? movingOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_FloatingScope>()?.state.moving;

  @override
  State<FloatingPanel> createState() => _FloatingPanelState();
}

class _FloatingPanelState extends State<FloatingPanel>
    with TickerProviderStateMixin {
  late final _x = AnimationController.unbounded(vsync: this);
  late final _y = AnimationController.unbounded(vsync: this);
  late double _width;
  late double _height;
  bool _placed = false;
  Size _area = Size.zero;

  /// True while dragged, gliding or resized.
  final moving = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    final saved = FloatingPanel._remembered[widget.id];
    _width = saved?.$2.width ?? widget.initialWidth;
    _height = saved?.$2.height ?? widget.initialHeight;
    final at = saved?.$1 ?? widget.startAt;
    if (at != null) {
      _x.value = at.dx;
      _y.value = at.dy;
      _placed = true;
    }
  }

  @override
  void dispose() {
    _remember();
    _x.dispose();
    _y.dispose();
    moving.dispose();
    setEmbedsInteractive(true);
    super.dispose();
  }

  void _remember() => FloatingPanel._remembered[widget.id] = (
    Offset(_x.value, _y.value),
    Size(_width, _height),
  );

  /// The panel itself (without the overhang).
  Size get _size =>
      Size(_width, widget.freeAspect ? _height : widget.heightFor(_width));

  /// The whole box (panel plus room above it).
  Size get _box => Size(_size.width, _size.height + widget.overhang);

  /// The box's top-left can go from (lo) to (hi).
  (Offset, Offset) get _bounds {
    final m = widget.margin;
    final hi = Offset(
      math.max(m, _area.width - _box.width - m),
      math.max(m, _area.height - _box.height - m),
    );
    return (Offset(m, m), hi);
  }

  Offset _clamp(Offset p) {
    final (lo, hi) = _bounds;
    return Offset(p.dx.clamp(lo.dx, hi.dx), p.dy.clamp(lo.dy, hi.dy));
  }

  void _settled() {
    moving.value = false;
    _remember();
    widget.onSettled?.call(
      Offset(_x.value, _y.value + widget.overhang) & _size,
    );
  }

  // ---- Dragging ----

  void _grab() {
    _x.stop();
    _y.stop();
    moving.value = true;
    setEmbedsInteractive(false);
  }

  void _drag(Offset delta) {
    final p = _clamp(Offset(_x.value, _y.value) + delta);
    _x.value = p.dx;
    _y.value = p.dy;
  }

  /// Let go: glide on with the throw's speed, then settle (against an
  /// edge if close to one).
  void _release(Velocity velocity) {
    setEmbedsInteractive(true);
    final v = velocity.pixelsPerSecond;
    final speed = v.distance;
    // Cap very wild throws.
    final capped = speed > 4000 ? v * (4000 / speed) : v;
    final here = Offset(_x.value, _y.value);
    var target = _clamp(here + capped * 0.16);
    final (lo, hi) = _bounds;
    double snap(double t, double a, double b) {
      if (t - a < FloatingPanel.snapDistance) return a;
      if (b - t < FloatingPanel.snapDistance) return b;
      return t;
    }

    target = Offset(
      snap(target.dx, lo.dx, hi.dx),
      snap(target.dy, lo.dy, hi.dy),
    );
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: 170,
      ratio: 0.9,
    );
    _x.animateWith(SpringSimulation(spring, here.dx, target.dx, capped.dx));
    _y
        .animateWith(SpringSimulation(spring, here.dy, target.dy, capped.dy))
        .whenCompleteOrCancel(() {
          if (mounted && !_x.isAnimating) _settled();
        });
  }

  // ---- Resizing (corner grips) ----

  /// [corner]: which corner is pulled (−1 / +1 on each axis).
  void _resize(Offset delta, Alignment corner) {
    final m = widget.margin;
    final left = corner.x < 0, top = corner.y < 0;
    setState(() {
      if (widget.freeAspect) {
        // Width.
        final dw = left ? -delta.dx : delta.dx;
        final maxW = left ? _x.value + _width - m : _area.width - _x.value - m;
        final w = (_width + dw)
            .clamp(
              widget.minWidth,
              math.max(widget.minWidth, math.min(widget.maxWidth, maxW)),
            )
            .toDouble();
        if (left) _x.value += _width - w;
        _width = w;
        // Height.
        final dh = top ? -delta.dy : delta.dy;
        final maxH = top
            ? _y.value + _box.height - m - widget.overhang
            : _area.height - _y.value - widget.overhang - m;
        final h = (_height + dh)
            .clamp(
              widget.minHeight,
              math.max(widget.minHeight, math.min(widget.maxHeight, maxH)),
            )
            .toDouble();
        if (top) _y.value += _height - h;
        _height = h;
        return;
      }
      // Fixed shape: diagonal pulls count (in width terms).
      final ratio = _size.width / _size.height;
      final grow =
          ((left ? -delta.dx : delta.dx) +
              (top ? -delta.dy : delta.dy) * ratio) /
          2;
      final maxByArea = math.min(
        left ? _x.value + _width - m : _area.width - _x.value - m,
        _widthForHeight(
          top
              ? _y.value + _box.height - m - widget.overhang
              : _area.height - _y.value - widget.overhang - m,
        ),
      );
      final oldSize = _size;
      _width = (_width + grow).clamp(
        widget.minWidth,
        math.max(widget.minWidth, math.min(widget.maxWidth, maxByArea)),
      );
      if (left) _x.value += oldSize.width - _size.width;
      if (top) _y.value += oldSize.height - _size.height;
    });
  }

  double _widthForHeight(double h) {
    // heightFor is increasing; search for the width that gives h.
    var lo = 0.0, hi = 4000.0;
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      if (widget.heightFor(mid) > h) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return lo;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _area = c.biggest;
        if (!_placed) {
          _placed = true;
          final (lo, hi) = _bounds;
          final t = widget.start;
          _x.value = lo.dx + (hi.dx - lo.dx) * (t.x + 1) / 2;
          _y.value = lo.dy + (hi.dy - lo.dy) * (t.y + 1) / 2;
        } else {
          // Keep it on screen when the window shrinks.
          final p = _clamp(Offset(_x.value, _y.value));
          if (!_x.isAnimating) _x.value = p.dx;
          if (!_y.isAnimating) _y.value = p.dy;
        }
        final box = _box;
        // The child fills the whole box: the room above (for a toolbar)
        // and the panel under it.
        final content = SizedBox.fromSize(size: box, child: widget.child);
        final body = widget.dragAnywhere
            // (The interceptor keeps embedded video from swallowing the
            // drag in a browser.)
            ? PointerInterceptor(child: FloatingDragArea(child: content))
            : content;
        final corners = !widget.resizable
            ? const <Alignment>[]
            : widget.allCorners
            ? const [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight,
              ]
            : const [Alignment.bottomRight];
        return Stack(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_x, _y]),
              builder: (context, child) =>
                  Positioned(left: _x.value, top: _y.value, child: child!),
              child: _FloatingScope(
                state: this,
                child: SizedBox.fromSize(
                  size: box,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: body),
                      for (final corner in corners)
                        Positioned(
                          left: corner.x < 0 ? 0 : null,
                          right: corner.x > 0 ? 0 : null,
                          top: corner.y < 0 ? widget.overhang : null,
                          bottom: corner.y > 0 ? 0 : null,
                          // Over video: must catch the mouse itself.
                          child: PointerInterceptor(
                            child: _Grip(
                              corner: corner,
                              subtle: widget.allCorners,
                              onResize: (d) => _resize(d, corner),
                              state: this,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FloatingScope extends InheritedWidget {
  final _FloatingPanelState state;
  const _FloatingScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_FloatingScope old) => false;
}

/// The part of a [FloatingPanel] you drag it by (e.g. a title bar).
class FloatingDragArea extends StatelessWidget {
  final Widget child;
  const FloatingDragArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context
        .getInheritedWidgetOfExactType<_FloatingScope>()
        ?.state;
    if (state == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => state._grab(),
        onPanUpdate: (d) => state._drag(d.delta),
        onPanEnd: (d) => state._release(d.velocity),
        onPanCancel: () => state._release(Velocity.zero),
        child: child,
      ),
    );
  }
}

/// A resize grip in one corner.
class _Grip extends StatelessWidget {
  final Alignment corner;
  final void Function(Offset delta) onResize;
  final _FloatingPanelState state;

  /// Small and quiet (sticky notes) rather than the drawn lines.
  final bool subtle;

  const _Grip({
    required this.corner,
    required this.onResize,
    required this.state,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    final diagonal = (corner.x > 0) == (corner.y > 0);
    return Tooltip(
      message: 'Drag to resize',
      waitDuration: const Duration(milliseconds: 800),
      child: MouseRegion(
        cursor: diagonal
            ? SystemMouseCursors.resizeUpLeftDownRight
            : SystemMouseCursors.resizeUpRightDownLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => state._grab(),
          onPanUpdate: (d) => onResize(d.delta),
          onPanEnd: (_) {
            setEmbedsInteractive(true);
            state._settled();
          },
          onPanCancel: () {
            setEmbedsInteractive(true);
            state._settled();
          },
          child: SizedBox(
            width: subtle ? 18 : 26,
            height: subtle ? 18 : 26,
            child: subtle
                ? null
                : CustomPaint(painter: _GripPainter(corner: corner)),
          ),
        ),
      ),
    );
  }
}

class _GripPainter extends CustomPainter {
  final Alignment corner;
  const _GripPainter({required this.corner});

  @override
  void paint(Canvas canvas, Size size) {
    // Three short diagonal strokes in the corner, light with a dark edge
    // (shows on both video and light panels).
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(corner.x > 0 ? 1 : -1, corner.y > 0 ? 1 : -1);
    canvas.translate(-size.width / 2, -size.height / 2);
    for (final (colour, width) in [
      (const Color(0x99000000), 3.2),
      (const Color(0xDDFFFFFF), 1.6),
    ]) {
      final p = Paint()
        ..color = colour
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      for (final k in [6.0, 11.0, 16.0]) {
        canvas.drawLine(
          Offset(size.width - 4, size.height - 4 - k),
          Offset(size.width - 4 - k, size.height - 4),
          p,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.corner != corner;
}
