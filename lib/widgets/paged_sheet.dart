// The settable render properties keep private fields behind setters.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A chord sheet set as printed pages: laid out at real paper size (in
/// points, like the PDF) and drawn at [scale] screen pixels a point
/// (1: its text the size of the scroll view's), centred; null: scaled to
/// the available width. The pages run on with a divider between them, like
/// Bramble Pages'.
///
/// The first [spanning] children (title, artist…) run across the top of
/// page 1. The rest flow down the columns, column to column and page to
/// page. A child is never split; one taller than a whole column starts at
/// the top of a column and runs past its foot.
class PagedSheet extends MultiChildRenderObjectWidget {
  final Size paper;
  final int columns;
  final int spanning;
  final double margin;
  final double columnGap;
  final double pageGap;
  final Color pageColor;
  final Color edgeColor;
  final double? scale;

  /// Called at the end of each layout, with the sheet's new size (the zoom
  /// sets its scroll there, in the same frame).
  final VoidCallback? onLayout;

  const PagedSheet({
    this.scale,
    this.onLayout,
    super.key,
    required this.paper,
    required this.columns,
    required this.spanning,
    required this.pageColor,
    required this.edgeColor,
    this.margin = 40,
    this.columnGap = 20,
    this.pageGap = 0,
    super.children,
  });

  @override
  RenderPagedSheet createRenderObject(BuildContext context) => RenderPagedSheet(
    paper: paper,
    columns: columns,
    spanning: spanning,
    margin: margin,
    columnGap: columnGap,
    pageGap: pageGap,
    pageColor: pageColor,
    edgeColor: edgeColor,
    scale: scale,
  )..onLayout = onLayout;

  @override
  void updateRenderObject(BuildContext context, RenderPagedSheet renderObject) {
    renderObject
      ..paper = paper
      ..columns = columns
      ..spanning = spanning
      ..margin = margin
      ..columnGap = columnGap
      ..pageGap = pageGap
      ..pageColor = pageColor
      ..edgeColor = edgeColor
      ..fixedScale = scale
      ..onLayout = onLayout;
  }
}

class _PageParentData extends ContainerBoxParentData<RenderBox> {}

class RenderPagedSheet extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PageParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PageParentData> {
  RenderPagedSheet({
    required Size paper,
    required int columns,
    required int spanning,
    required double margin,
    required double columnGap,
    required double pageGap,
    required Color pageColor,
    required Color edgeColor,
    double? scale,
  }) : _fixedScale = scale,
       _paper = paper,
       _columns = columns,
       _spanning = spanning,
       _margin = margin,
       _columnGap = columnGap,
       _pageGap = pageGap,
       _pageColor = pageColor,
       _edgeColor = edgeColor;

  Size _paper;
  set paper(Size v) {
    if (v == _paper) return;
    _paper = v;
    markNeedsLayout();
  }

  int _columns;
  set columns(int v) {
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  int _spanning;
  set spanning(int v) {
    if (v == _spanning) return;
    _spanning = v;
    markNeedsLayout();
  }

  double _margin;
  set margin(double v) {
    if (v == _margin) return;
    _margin = v;
    markNeedsLayout();
  }

  double _columnGap;
  set columnGap(double v) {
    if (v == _columnGap) return;
    _columnGap = v;
    markNeedsLayout();
  }

  double _pageGap;
  set pageGap(double v) {
    if (v == _pageGap) return;
    _pageGap = v;
    markNeedsLayout();
  }

  Color _pageColor;
  set pageColor(Color v) {
    if (v == _pageColor) return;
    _pageColor = v;
    markNeedsPaint();
  }

  Color _edgeColor;
  set edgeColor(Color v) {
    if (v == _edgeColor) return;
    _edgeColor = v;
    markNeedsPaint();
  }

  VoidCallback? onLayout;
  double? _fixedScale;
  set fixedScale(double? v) {
    if (v == _fixedScale) return;
    _fixedScale = v;
    markNeedsLayout();
  }

  /// Paper points → screen pixels.
  double _scale = 1;

  /// Where the pages start across (in points: centred in a wider box).
  double _x0 = 0;
  int _pages = 1;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PageParentData) {
      child.parentData = _PageParentData();
    }
  }

  @override
  void performLayout() {
    final double width;
    if (_fixedScale case final s?) {
      _scale = s;
      final pageW = _paper.width * s;
      final room = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : constraints.minWidth;
      width = room > pageW ? room : pageW;
    } else {
      width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : _paper.width;
      _scale = width / _paper.width;
    }
    _x0 = (width / _scale - _paper.width) / 2;
    final contentWidth = _paper.width - _margin * 2;
    final contentHeight = _paper.height - _margin * 2;
    final columnWidth = (contentWidth - _columnGap * (_columns - 1)) / _columns;
    final pageStride = _paper.height + _pageGap;

    var page = 0, column = 0;
    var top = 0.0; // where the columns start on this page (below the title)
    var y = 0.0; // next free spot in the current column
    var index = 0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _PageParentData;
      if (index < _spanning) {
        child.layout(
          BoxConstraints.tightFor(width: contentWidth),
          parentUsesSize: true,
        );
        data.offset = Offset(_x0 + _margin, _margin + y);
        y += child.size.height;
        top = y;
      } else {
        child.layout(
          BoxConstraints.tightFor(width: columnWidth),
          parentUsesSize: true,
        );
        final h = child.size.height;
        // Doesn't fit below what's already in this column: next column,
        // then next page.
        if (y + h > contentHeight && y > top) {
          column++;
          y = top;
          if (column >= _columns) {
            column = 0;
            page++;
            top = 0;
            y = 0;
          }
        }
        data.offset = Offset(
          _x0 + _margin + column * (columnWidth + _columnGap),
          page * pageStride + _margin + y,
        );
        y += h;
      }
      index++;
      child = data.nextSibling;
    }
    _pages = page + 1;
    size = constraints.constrain(
      Size(width, (_pages * pageStride - _pageGap) * _scale),
    );
    onLayout?.call();
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    // The pages as one strip: a light, even shadow round it (drawn at
    // screen size, not scaled with the pages), the paper, and a divider
    // where one page meets the next.
    final pageStride = _paper.height + _pageGap;
    final strip = Rect.fromLTWH(
      offset.dx + _x0 * _scale,
      offset.dy,
      _paper.width * _scale,
      (_pages * pageStride - _pageGap) * _scale,
    );
    context.canvas
      ..drawRect(
        strip.shift(const Offset(0, 1)),
        Paint()
          ..color = const Color(0x1A000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawRect(strip, Paint()..color = _pageColor)
      ..drawRect(
        strip,
        Paint()
          ..color = _edgeColor.withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    final divider = Paint()
      ..color = _edgeColor
      ..strokeWidth = 1;
    for (var p = 1; p < _pages; p++) {
      final y = (strip.top + (p * pageStride - _pageGap / 2) * _scale)
          .roundToDouble() +
          .5;
      context.canvas.drawLine(
        Offset(strip.left, y),
        Offset(strip.right, y),
        divider,
      );
    }
    // The pages' content, only what's in view (a long song's other pages
    // aren't drawn on every frame of a scroll or a zoom).
    context.pushTransform(needsCompositing, offset, _transform, (ctx, o) {
      final view = ctx.canvas.getLocalClipBounds().inflate(40);
      var child = firstChild;
      while (child != null) {
        final data = child.parentData! as _PageParentData;
        if (((o + data.offset) & child.size).overlaps(view)) {
          ctx.paintChild(child, o + data.offset);
        }
        child = data.nextSibling;
      }
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, local) =>
          defaultHitTestChildren(result, position: local),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
    super.applyPaintTransform(child, transform);
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => _paper.width;
  @override
  double computeMinIntrinsicHeight(double width) => _paper.height;
  @override
  double computeMaxIntrinsicHeight(double width) => _paper.height;
}

/// The page view's zoom, shared by every song (kept as you swipe between
/// them): 1 is Fit Width, as in Pages: the page spans the view, edge to
/// edge.
final pageZoom = ValueNotifier<double>(1);

/// Pages that scroll and zoom like Bramble Pages': a pinch (or a trackpad
/// pinch, or Ctrl + the wheel) zooms as it goes, the point under the
/// fingers staying under them, and eases back to fit the width when let go
/// close to it. (Zooming only rescales the pages: their text isn't laid
/// out again, so following every step stays smooth.)
class ZoomablePages extends StatefulWidget {
  final ScrollController controller;
  final EdgeInsets padding;
  final double paperWidth;

  /// The pages at a scale (screen pixels a point); [onLayout] goes to the
  /// [PagedSheet].
  final Widget Function(double scale, VoidCallback onLayout) builder;

  const ZoomablePages({
    super.key,
    required this.controller,
    required this.padding,
    required this.paperWidth,
    required this.builder,
  });

  @override
  State<ZoomablePages> createState() => _ZoomablePagesState();
}

class _ZoomablePagesState extends State<ZoomablePages>
    with SingleTickerProviderStateMixin {
  static const _min = .4, _max = 4.0;

  /// How close to fitting the width a zoom snaps back to it.
  static const _snapNear = .1;
  final _across = ScrollController();
  final _touches = <int, Offset>{};
  // two fingers down: their last spread and middle
  double? _lastDist;
  Offset _lastFocal = Offset.zero;
  // a trackpad pinch (native): its last scale
  double _lastPanScale = 1;
  double _fit = 1;
  double _room = 0;
  // where to scroll once laid out at a new zoom (down, across)
  (double, double)? _pending;
  // the wheel / browser trackpad pinch: when it has stopped
  Timer? _settle;
  late final _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    pageZoom.addListener(_changed);
  }

  @override
  void dispose() {
    pageZoom.removeListener(_changed);
    _settle?.cancel();
    _snap.dispose();
    _across.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _pinching => _lastDist != null;

  /// Zooms to [z] (clamped), the page point that was under [from] ending
  /// up under [to]; the scroll is set as the pages are laid out at it, in
  /// the same frame.
  void _zoomTo(double z, Offset from, Offset to) {
    final z0 = pageZoom.value;
    final z1 = z.clamp(_min, _max);
    if (z1 == z0 && from == to) return;
    final r = z1 / z0;
    final v = widget.controller, h = _across;
    // (across, the pages run edge to edge: no padding)
    final top = widget.padding.top;
    const left = 0.0;
    // (from where the last step left it, if it isn't laid out yet)
    final vAt = _pending?.$1 ?? (v.hasClients ? v.offset : 0.0);
    final hAt = _pending?.$2 ?? (h.hasClients ? h.offset : 0.0);
    // (across, the page is centred while narrower than the room: the point
    // is taken from the page's own edge)
    double centred(double z) =>
        math.max(0, (_room - widget.paperWidth * _fit * z) / 2);
    final onPage = hAt + from.dx - left - centred(z0);
    _pending = (
      math.max(0, (vAt + from.dy - top) * r + top - to.dy),
      math.max(0, onPage * r + centred(z1) + left - to.dx),
    );
    pageZoom.value = z1;
  }

  /// The pages laid out (at a new zoom): the scroll that keeps the point,
  /// set before this frame is painted.
  void _laidOut() {
    final want = _pending;
    if (want == null) return;
    _pending = null;
    final v = widget.controller, h = _across;
    if (v.hasClients) v.position.correctPixels(want.$1);
    if (h.hasClients) h.position.correctPixels(want.$2);
    // (past the end: back to it, once the new length is known)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in [v, h]) {
        if (c.hasClients && c.offset > c.position.maxScrollExtent) {
          c.jumpTo(c.position.maxScrollExtent);
        }
      }
    });
  }

  /// A pinch let go: close to fitting the width, it eases there.
  void _ended(Offset at) {
    final z = pageZoom.value;
    if (z == 1 || (z - 1).abs() > _snapNear) return;
    _snap.stop();
    final from = z;
    void step() => _zoomTo(from + (1 - from) * Curves.easeOut.transform(_snap.value), at, at);
    _snap
      ..removeListener(_snapStep ?? () {})
      ..value = 0;
    _snapStep = step;
    _snap
      ..addListener(step)
      ..forward();
  }

  VoidCallback? _snapStep;

  /// A wheel step with Ctrl, or a trackpad pinch (which a browser sends as
  /// zoom steps): zoomed at once about the pointer; a moment after the last
  /// step, it's over.
  void _zoomStep(double factor, Offset at) {
    _snap.stop();
    _zoomTo(pageZoom.value * factor, at, at);
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 160), () {
      if (mounted) _ended(at);
    });
  }

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      final [a, b] = _touches.values.toList();
      _snap.stop();
      setState(() {
        _lastDist = (a - b).distance;
        _lastFocal = (a + b) / 2;
      });
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    final last = _lastDist;
    if (_touches.length == 2 && last != null && last > 0) {
      final [a, b] = _touches.values.toList();
      final dist = (a - b).distance, focal = (a + b) / 2;
      _zoomTo(pageZoom.value * dist / last, _lastFocal, focal);
      _lastDist = dist;
      _lastFocal = focal;
    }
  }

  void _up(PointerEvent e) {
    _touches.remove(e.pointer);
    if (_lastDist != null && _touches.length < 2) {
      setState(() => _lastDist = null);
      _ended(_lastFocal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.padding;
    return LayoutBuilder(
      builder: (context, box) {
        // (Fit Width: the whole width, edge to edge, as in Pages)
        final room = box.maxWidth;
        // zoom 1: Fit Width
        _fit = math.max(0.1, room / widget.paperWidth);
        _room = room;
        final scale = _fit * pageZoom.value;
        final scroll = _pinching ? const NeverScrollableScrollPhysics() : null;
        return Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          // a trackpad pinch (native)
          onPointerPanZoomStart: (e) => _lastPanScale = 1,
          onPointerPanZoomUpdate: (e) {
            if ((e.scale - 1).abs() < .01 && _lastPanScale == 1) return;
            _snap.stop();
            _zoomTo(
              pageZoom.value * e.scale / _lastPanScale,
              e.localPosition,
              e.localPosition,
            );
            _lastPanScale = e.scale;
          },
          onPointerPanZoomEnd: (e) {
            if (_lastPanScale != 1) _ended(e.localPosition);
            _lastPanScale = 1;
          },
          child: ClipRect(
            child: SingleChildScrollView(
              controller: widget.controller,
              physics: scroll,
              padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
              child: SingleChildScrollView(
                controller: _across,
                physics: scroll,
                scrollDirection: Axis.horizontal,
                // (not cut off at the top padding: the pages run up behind
                // the toolbars; the window's own edges clip them)
                clipBehavior: Clip.none,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: room),
                  // Ctrl (⌘) + the wheel, or a browser's trackpad pinch:
                  // zoom about the pointer (caught here, inside the scroll
                  // views, so it isn't a scroll)
                  child: Listener(
                    onPointerSignal: (e) {
                      Offset here() {
                        final at = context.findRenderObject() as RenderBox?;
                        return at?.globalToLocal(e.position) ?? Offset.zero;
                      }

                      if (e is PointerScaleEvent) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          e,
                          (_) => _zoomStep(e.scale, here()),
                        );
                        return;
                      }
                      if (e is! PointerScrollEvent) return;
                      final keys = HardwareKeyboard.instance;
                      if (!keys.isControlPressed && !keys.isMetaPressed) {
                        return;
                      }
                      GestureBinding.instance.pointerSignalResolver.register(
                        e,
                        (_) => _zoomStep(
                          math.exp(-e.scrollDelta.dy / 300),
                          here(),
                        ),
                      );
                    },
                    // (centred in the room while narrower than it)
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: widget.builder(scale, _laidOut),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
