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
///
/// Smooth at 120 Hz: each column's content is its own layer (scrolling
/// moves it, nothing is repainted), and its lines' places are measured once
/// per layout; scrolling just compares numbers and touches only the lines
/// that come into or leave view.
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
  final _windows = <_Window>[];

  ScrollPosition? get _position => _newest(widget.controller);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(SnakeColumns old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_scrolled);
      widget.controller.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrolled);
    super.dispose();
  }

  double get _offset => _position?.pixels ?? 0;

  void _scrolled() {
    final s = _offset;
    for (final w in _windows) {
      w.update(s);
    }
  }

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
        while (_windows.length < widget.columns) {
          _windows.add(_Window());
        }
        _windows.length = widget.columns;
        final cols = <Widget>[];
        for (var i = 0; i < widget.columns; i++) {
          final w = _windows[i]
            ..by = step * i
            ..step = step;
          w.remeasure(_offset);
          final column = i == 0
              ? SingleChildScrollView(
                  controller: widget.controller,
                  padding: pad,
                  // (its own layer: scrolling moves it, no repaint)
                  child: RepaintBoundary(child: w.root(widget.first)),
                )
              : _following(
                  _Follower(
                    controller: widget.controller,
                    by: step * i,
                    padding: pad,
                    child: RepaintBoundary(child: w.root(widget.others())),
                  ),
                );
          if (i > 0) {
            cols.add(
              VerticalDivider(width: 1, thickness: inkW(1), color: divider),
            );
          }
          cols.add(
            Expanded(child: _WindowScope(window: w, child: column)),
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
/// the scroll plus [by]. (Only the move is redone as it scrolls.)
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
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0,
        maxHeight: double.infinity,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, content) => Transform.translate(
            offset: Offset(0, -((_newest(controller)?.pixels ?? 0) + by)),
            child: content,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// One column's lines: where each sits in the content (measured once per
/// layout), and which ones are whole inside the column at a scroll.
class _Window {
  double by = 0, step = 1;
  final _rootKey = GlobalKey();
  final _lines = <_SeamLineState>{};
  final _top = <_SeamLineState, double>{};
  final _bottom = <_SeamLineState, double>{};
  var _measuring = false;

  Widget root(Widget child) => KeyedSubtree(key: _rootKey, child: child);

  void add(_SeamLineState l) {
    _lines.add(l);
    remeasure(null);
  }

  void remove(_SeamLineState l) {
    _lines.remove(l);
    _top.remove(l);
    _bottom.remove(l);
  }

  double _s = 0;

  /// The lines' places again, once laid out (a new size, a new song…).
  void remeasure(double? s) {
    if (s != null) _s = s;
    if (_measuring) return;
    _measuring = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      final root = _rootKey.currentContext?.findRenderObject() as RenderBox?;
      if (root == null || !root.attached) return;
      _top.clear();
      _bottom.clear();
      for (final l in _lines) {
        final box = l.context.findRenderObject() as RenderBox?;
        if (box == null || !box.attached || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero, ancestor: root).dy;
        _top[l] = y;
        _bottom[l] = y + box.size.height;
      }
      update(_s);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// At scroll [s]: each line shown while whole inside this column.
  void update(double s) {
    _s = s;
    final from = s + by - .5, to = s + by + step + .5;
    for (final l in _lines) {
      final t = _top[l], b = _bottom[l];
      if (t == null || b == null) continue;
      l.show(t >= from && b <= to);
    }
  }
}

class _WindowScope extends InheritedWidget {
  final _Window window;
  const _WindowScope({required this.window, required super.child});

  @override
  bool updateShouldNotify(_WindowScope old) => old.window != window;
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
  _Window? _window;
  var _shown = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final w = context
        .dependOnInheritedWidgetOfExactType<_WindowScope>()
        ?.window;
    if (w != _window) {
      _window?.remove(this);
      _window = w;
      w?.add(this);
    }
  }

  @override
  void didUpdateWidget(SeamLine old) {
    super.didUpdateWidget(old);
    // (its content may have changed size: places measured again)
    _window?.remeasure(null);
  }

  @override
  void dispose() {
    _window?.remove(this);
    super.dispose();
  }

  void show(bool shown) {
    if (shown != _shown && mounted) setState(() => _shown = shown);
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

