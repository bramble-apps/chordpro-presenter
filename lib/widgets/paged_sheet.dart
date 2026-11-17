// The settable render properties keep private fields behind setters.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A chord sheet set as printed pages: laid out at real paper size (in
/// points, like the PDF) and scaled to the available width.
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

  const PagedSheet({
    super.key,
    required this.paper,
    required this.columns,
    required this.spanning,
    required this.pageColor,
    required this.edgeColor,
    this.margin = 40,
    this.columnGap = 20,
    this.pageGap = 16,
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
  );

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
      ..edgeColor = edgeColor;
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
  }) : _paper = paper,
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

  /// Paper points → screen pixels.
  double _scale = 1;
  int _pages = 1;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PageParentData) {
      child.parentData = _PageParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : _paper.width;
    _scale = width / _paper.width;
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
        data.offset = Offset(_margin, _margin + y);
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
          _margin + column * (columnWidth + _columnGap),
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
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushTransform(needsCompositing, offset, _transform, (ctx, o) {
      final canvas = ctx.canvas;
      final pageStride = _paper.height + _pageGap;
      for (var p = 0; p < _pages; p++) {
        final rect = (o + Offset(0, p * pageStride)) & _paper;
        canvas.drawRect(
          rect.shift(const Offset(0, 1.5)),
          Paint()
            ..color = const Color(0x22000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawRect(rect, Paint()..color = _pageColor);
        canvas.drawRect(
          rect,
          Paint()
            ..color = _edgeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6,
        );
      }
      defaultPaint(ctx, o);
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
