// The scroll view in columns: one song running from column to column, all
// scrolling together, so what goes off the top of the second column is what
// just came in at the foot of the first. Lines show only while they fit
// whole in their column, fading in and out quickly at its edges.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../eink.dart';

/// The controller's scroll view (the newest: switching views, the old one
/// and the new one are both on it for a moment).
ScrollPosition? _newest(ScrollController c) =>
    c.positions.isEmpty ? null : c.positions.last;

/// Columns narrower than this go back to one (phones, a fold's cover
/// screen, a small window).
const snakeMinColumnWidth = 300.0;

/// How many columns fit [width] (at most [wanted]).
int snakeColumnsFor(int wanted, double width) {
  var n = wanted.clamp(1, 3);
  while (n > 1 && width / n < snakeMinColumnWidth) {
    n--;
  }
  return n;
}

/// [columns] columns of one flow: the first is [first] in a scroll view on
/// [controller] (the real one: section keys, annotations); the others are
/// [others] (the same content without keys), each a column further on,
/// following the same scroll. Drags and the wheel in any column scroll it.
class SnakeColumns extends StatefulWidget {
  final ScrollController controller;
  final int columns;
  final EdgeInsets padding;
  final Widget first;
  final Widget Function() others;

  const SnakeColumns({
    super.key,
    required this.controller,
    required this.columns,
    required this.padding,
    required this.first,
    required this.others,
  });

  @override
  State<SnakeColumns> createState() => _SnakeColumnsState();
}

class _SnakeColumnsState extends State<SnakeColumns> {
  Drag? _drag;

  ScrollPosition? get _position => _newest(widget.controller);

  Widget _following(Widget column) => Listener(
    // the wheel over a following column scrolls the first
    onPointerSignal: (e) {
      if (e is! PointerScrollEvent) return;
      final p = _position;
      if (p == null) return;
      GestureBinding.instance.pointerSignalResolver.register(
        e,
        (_) => p.pointerScroll(e.scrollDelta.dy),
      );
    },
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (d) =>
          _drag = _position?.drag(d, () => _drag = null),
      onVerticalDragUpdate: (d) => _drag?.update(d),
      onVerticalDragEnd: (d) => _drag?.end(d),
      onVerticalDragCancel: () => _drag?.cancel(),
      child: column,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pad = widget.padding;
    final divider = Theme.of(context).colorScheme.outlineVariant;
    return LayoutBuilder(
      builder: (context, box) {
        // what a column shows between its top and bottom padding: the next
        // column carries on from there
        final step = math.max(40.0, box.maxHeight - pad.vertical);
        final cols = <Widget>[];
        for (var i = 0; i < widget.columns; i++) {
          final column = i == 0
              ? SingleChildScrollView(
                  controller: widget.controller,
                  padding: pad,
                  child: widget.first,
                )
              : _following(
                  _Follower(
                    controller: widget.controller,
                    by: step * i,
                    padding: pad,
                    child: widget.others(),
                  ),
                );
          if (i > 0) {
            cols.add(VerticalDivider(width: 1, thickness: inkW(1), color: divider));
          }
          cols.add(
            Expanded(
              child: _ColumnWindow(
                controller: widget.controller,
                padding: pad,
                child: column,
              ),
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cols,
        );
      },
    );
  }
}

/// A column further on: the content laid out as in the first, moved up by
/// the scroll plus [by].
class _Follower extends StatelessWidget {
  final ScrollController controller;
  final double by;
  final EdgeInsets padding;
  final Widget child;
  const _Follower({
    required this.controller,
    required this.by,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, content) => OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform.translate(
            offset: Offset(0, -((_newest(controller)?.pixels ?? 0) + by)),
            child: content,
          ),
        ),
        child: content,
      ),
    );
  }
}

/// A column's readable window (inside its top and bottom padding), for
/// [SeamLine]s in it.
class _ColumnWindow extends InheritedWidget {
  final ScrollController controller;
  final EdgeInsets padding;
  const _ColumnWindow({
    required this.controller,
    required this.padding,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ColumnWindow old) =>
      old.controller != controller || old.padding != padding;
}

/// A line of the sheet: in columns, shown only while it fits whole in its
/// column, fading in and out quickly at the edges. (Anywhere else: just the
/// line.)
class SeamLine extends StatefulWidget {
  final Widget child;
  const SeamLine({super.key, required this.child});

  @override
  State<SeamLine> createState() => _SeamLineState();
}

class _SeamLineState extends State<SeamLine> {
  _ColumnWindow? _window;
  BuildContext? _windowContext;
  var _shown = true;
  var _pending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final element = context
        .getElementForInheritedWidgetOfExactType<_ColumnWindow>();
    final w = element?.widget as _ColumnWindow?;
    context.dependOnInheritedWidgetOfExactType<_ColumnWindow>();
    if (w?.controller != _window?.controller) {
      _window?.controller.removeListener(_moved);
      w?.controller.addListener(_moved);
    }
    _window = w;
    _windowContext = element;
    _moved();
  }

  @override
  void dispose() {
    _window?.controller.removeListener(_moved);
    super.dispose();
  }

  /// (checked once the frame is laid out and painted, when every column is
  /// where the scroll puts it)
  void _moved() {
    if (_window == null || _pending) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (mounted) _check();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _check() {
    final w = _window, wc = _windowContext;
    final me = context.findRenderObject() as RenderBox?;
    final win = wc?.findRenderObject() as RenderBox?;
    if (w == null || me == null || win == null || !me.attached || !win.attached) {
      return;
    }
    final top = me.localToGlobal(Offset.zero).dy;
    final bottom = top + me.size.height;
    final at = win.localToGlobal(Offset.zero).dy;
    final shown =
        top >= at + w.padding.top - .5 &&
        bottom <= at + win.size.height - w.padding.bottom + .5;
    if (shown != _shown) setState(() => _shown = shown);
  }

  @override
  Widget build(BuildContext context) {
    if (_window == null) return widget.child;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: motion(context, const Duration(milliseconds: 120)),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}
