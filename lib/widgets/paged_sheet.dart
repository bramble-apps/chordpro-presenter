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
    context.pushTransform(needsCompositing, offset, _transform, defaultPaint);
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
/// them): 1 is the scroll view's text size.
final pageZoom = ValueNotifier<double>(1);

/// Pages that scroll and zoom like Bramble Pages': a pinch (or a trackpad
/// pinch, or Ctrl + the wheel) scales what's on screen at once, the point
/// under the fingers staying under them, and settles at the new zoom when
/// it ends, laid out sharp again.
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

class _ZoomablePagesState extends State<ZoomablePages> {
  static const _min = .5, _max = 3.0;
  final _across = ScrollController();
  final _touches = <int, Offset>{};
  // a pinch going on: where it started, and how far it has come
  double? _startDist;
  Offset _startFocal = Offset.zero;
  double _pinch = 1;
  Offset _focal = Offset.zero;
  double _fit = 1;
  double _room = 0;
  // where to scroll once laid out at a new zoom (down, across)
  (double, double)? _pending;
  // the wheel / trackpad pinch settling once it stops
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    pageZoom.addListener(_changed);
  }

  @override
  void dispose() {
    pageZoom.removeListener(_changed);
    _settle?.cancel();
    _across.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _pinching => _startDist != null || _pinch != 1;

  void _startPinch(Offset focal, [double? dist]) {
    _startDist = dist ?? 1;
    _startFocal = focal;
    _focal = focal;
    _pinch = 1;
  }

  void _movePinch(double scale, Offset focal) {
    final z = pageZoom.value;
    setState(() {
      _pinch = (z * scale).clamp(_min, _max) / z;
      _focal = focal;
    });
  }

  /// Settles a pinch (or a wheel step) at the new zoom: the page point that
  /// was under [from] ends up under [to].
  void _commit(double factor, Offset from, Offset to) {
    final z0 = pageZoom.value;
    final z1 = (z0 * factor).clamp(_min, _max);
    final r = z1 / z0;
    final v = widget.controller, h = _across;
    final top = widget.padding.top, left = widget.padding.left;
    final vAt = v.hasClients ? v.offset : 0.0;
    final hAt = h.hasClients ? h.offset : 0.0;
    // (across, the page is centred while narrower than the room: the point
    // is taken from the page's own edge)
    double centred(double z) =>
        math.max(0, (_room - widget.paperWidth * _fit * z) / 2);
    final onPage = hAt + from.dx - left - centred(z0);
    _pending = (
      (vAt + from.dy - top) * r + top - to.dy,
      onPage * r + centred(z1) + left - to.dx,
    );
    // The new zoom, the scroll set as it's laid out (_laidOut) and the
    // pinch's picture dropped, all in one frame: no flash in between.
    setState(() {
      _startDist = null;
      _pinch = 1;
    });
    pageZoom.value = z1;
  }

  /// The pages laid out (at a new zoom): the scroll that keeps the point,
  /// set before this frame is painted.
  void _laidOut() {
    final want = _pending;
    if (want == null) return;
    _pending = null;
    final v = widget.controller, h = _across;
    if (v.hasClients) v.position.correctPixels(math.max(0, want.$1));
    if (h.hasClients) h.position.correctPixels(math.max(0, want.$2));
    // (past the end: back to it, once the new length is known)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in [v, h]) {
        if (c.hasClients && c.offset > c.position.maxScrollExtent) {
          c.jumpTo(c.position.maxScrollExtent);
        }
      }
    });
  }

  /// A wheel step with Ctrl, or a trackpad pinch (which a browser sends as
  /// zoom steps): scaled at once like a touch pinch, about the pointer, and
  /// settled a moment after the last step.
  void _zoomStep(double factor, Offset at) {
    if (_startDist == null) _startPinch(at);
    _movePinch(_pinch * factor, _startFocal);
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 160), () {
      if (mounted) _commit(_pinch, _startFocal, _startFocal);
    });
  }

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      final [a, b] = _touches.values.toList();
      _startPinch((a + b) / 2, (a - b).distance);
      setState(() {});
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2 && _startDist != null) {
      final [a, b] = _touches.values.toList();
      _movePinch((a - b).distance / _startDist!, (a + b) / 2);
    }
  }

  void _up(PointerEvent e) {
    _touches.remove(e.pointer);
    if (_startDist != null && _touches.length < 2) {
      _commit(_pinch, _startFocal, _focal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.padding;
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxWidth - pad.horizontal;
        // (narrower than a page: the page shrinks to fit at zoom 1)
        _fit = (room / widget.paperWidth).clamp(0.1, 1.0);
        _room = room;
        final scale = _fit * pageZoom.value;
        // the pinch so far: what's on screen scaled about where it began,
        // and moved with the fingers
        final shown = Matrix4.identity()
          ..translateByDouble(_focal.dx, _focal.dy, 0, 1)
          ..scaleByDouble(_pinch, _pinch, 1, 1)
          ..translateByDouble(-_startFocal.dx, -_startFocal.dy, 0, 1);
        final scroll = _pinching ? const NeverScrollableScrollPhysics() : null;
        return Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          // a trackpad pinch
          onPointerPanZoomStart: (e) => _startPinch(e.localPosition),
          onPointerPanZoomUpdate: (e) {
            if ((e.scale - 1).abs() > .01 || _pinch != 1) {
              _movePinch(e.scale, e.localPosition);
            }
          },
          onPointerPanZoomEnd: (e) {
            if (_pinch != 1) {
              _commit(_pinch, _startFocal, _focal);
            } else {
              _startDist = null;
            }
          },
          child: ClipRect(
            child: Transform(
              transform: shown,
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
                  padding: EdgeInsets.only(left: pad.left, right: pad.right),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: room),
                    // Ctrl (⌘) + the wheel: zoom about the pointer (caught
                    // here, inside the scroll views, so it isn't a scroll)
                    child: Listener(
                      onPointerSignal: (e) {
                        Offset here() {
                          final at = context.findRenderObject() as RenderBox?;
                          return at?.globalToLocal(e.position) ?? Offset.zero;
                        }

                        // a trackpad pinch in a browser (the desktop app)
                        if (e is PointerScaleEvent) {
                          GestureBinding.instance.pointerSignalResolver
                              .register(e, (_) => _zoomStep(e.scale, here()));
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
          ),
        );
      },
    );
  }
}
