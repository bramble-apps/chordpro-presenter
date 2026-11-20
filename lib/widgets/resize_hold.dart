// Window resizing without re-laying out whole songs on every frame: while
// the window's size is changing, what's inside a [ResizeHold] keeps the
// layout it had (clipped), and is laid out once at the new size a moment
// after the resizing stops.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps [child]'s layout while the window is being resized (also while
/// [hold] is set), clipped to the room it has now; lays it out at the new
/// size once the size has stayed put for a moment.
class ResizeHold extends StatefulWidget {
  final bool hold;
  final Widget child;
  const ResizeHold({super.key, this.hold = false, required this.child});

  @override
  State<ResizeHold> createState() => _ResizeHoldState();
}

class _ResizeHoldState extends State<ResizeHold>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Size? _size;
  var _resizing = false;
  // when the size last changed (the frame after it); the frames watching
  // for the end belong to this widget, so they go when it does
  Duration? _changed;
  late final _ticker = createTicker(_tick);

  @override
  void initState() {
    super.initState();
    _size = _viewSize();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  static Size? _viewSize() => WidgetsBinding
      .instance
      .platformDispatcher
      .views
      .firstOrNull
      ?.physicalSize;

  @override
  void didChangeMetrics() {
    final size = _viewSize();
    if (size == null) return;
    if (_size != null && size != _size) {
      // (before the frame at the new size is laid out)
      _changed = null;
      if (!_resizing) setState(() => _resizing = true);
      if (!_ticker.isActive) _ticker.start();
    }
    _size = size;
  }

  /// Each frame while resizing: over once the size has stayed put 150 ms.
  void _tick(Duration elapsed) {
    final since = _changed ??= elapsed;
    if (elapsed - since >= const Duration(milliseconds: 150)) {
      _ticker.stop();
      setState(() => _resizing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: _Hold(hold: _resizing || widget.hold, child: widget.child),
  );
}

class _Hold extends SingleChildRenderObjectWidget {
  final bool hold;
  const _Hold({required this.hold, required super.child});

  @override
  _RenderHold createRenderObject(BuildContext context) => _RenderHold(hold);

  @override
  void updateRenderObject(BuildContext context, _RenderHold r) => r.hold = hold;
}

class _RenderHold extends RenderProxyBox {
  _RenderHold(this._hold);

  bool _hold;
  BoxConstraints? _last;

  set hold(bool value) {
    if (value == _hold) return;
    _hold = value;
    if (!value) markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.biggest;
      return;
    }
    final last = _last;
    if (_hold && last != null && child.hasSize) {
      // the same constraints as last time: no work for the child
      child.layout(last, parentUsesSize: true);
    } else {
      _last = constraints;
      child.layout(constraints, parentUsesSize: true);
    }
    size = constraints.constrain(child.size);
  }
}
