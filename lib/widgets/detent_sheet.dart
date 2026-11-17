// Phones: a sheet from the bottom, the screen's full width, as the Bramble
// apps' sheets (notes_mobile ui/sheet.dart DetentSheet): it rises to nearly
// full height, drags down to half height or shut, a flick carrying it to the
// next resting place; scrolling lists and the text inside scroll as usual.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../eink.dart';

/// Whether this screen gets sheets instead of dialogs (phones).
bool useDetentSheet(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      MediaQuery.sizeOf(context).width < 600;
}

/// Shows [builder]'s page in a [DetentSheet]; its `Navigator.pop(result)`
/// closes it, as a dialog's would. Dragged shut, it returns null.
Future<T?> showDetentSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final eink = isEink(context);
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: eink ? Colors.transparent : const Color(0x55000000),
      barrierLabel: 'Close',
      transitionDuration: motion(context, const Duration(milliseconds: 260)),
      reverseTransitionDuration: motion(
        context,
        const Duration(milliseconds: 220),
      ),
      pageBuilder: (context, animation, _) =>
          DetentSheet(animation: animation, child: builder(context)),
    ),
  );
}

class DetentSheet extends StatefulWidget {
  final Widget child;

  /// The route's: the sheet slides down when the route closes.
  final Animation<double> animation;

  const DetentSheet({super.key, required this.child, required this.animation});

  @override
  State<DetentSheet> createState() => _DetentSheetState();
}

class _DetentSheetState extends State<DetentSheet>
    with SingleTickerProviderStateMixin {
  /// The sheet's height.
  late final _h = AnimationController.unbounded(vsync: this);
  double _available = 600;
  bool _started = false, _closing = false;

  double get _large => _available - 8;

  /// The page's least height (shorter: it's cut off, not squeezed).
  static const _minContent = 320.0;
  double get _medium => math.max(240, _available * 0.55);

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_routeStatus);
  }

  /// The route closing (Save, Cancel, a tap outside): slide down.
  void _routeStatus(AnimationStatus s) {
    if (s == AnimationStatus.reverse && !_closing) {
      _closing = true;
      _to(0, ms: 220);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_routeStatus);
    _h.dispose();
    super.dispose();
  }

  TickerFuture _to(double h, {int ms = 260}) => _h.animateTo(
    h,
    duration: motion(context, Duration(milliseconds: ms)),
    curve: Curves.easeOutCubic,
  );

  void _drag(DragUpdateDetails d) =>
      _h.value = (_h.value - d.delta.dy).clamp(0.0, _large);

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final h = _h.value;
    final double target;
    if (v > 600) {
      target = h > _medium + 20 ? _medium : 0;
    } else if (v < -600) {
      target = h < _medium - 20 ? _medium : _large;
    } else {
      target = [
        0.0,
        _medium,
        _large,
      ].reduce((a, b) => (a - h).abs() < (b - h).abs() ? a : b);
    }
    if (target == 0) {
      _closing = true;
      _to(0, ms: 220).whenComplete(() {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else {
      _to(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final eink = isEink(context);
    return Padding(
      // Below the status bar; above the keyboard when it's up.
      padding: EdgeInsets.only(
        top: mq.padding.top,
        bottom: mq.viewInsets.bottom,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          _available = box.maxHeight;
          if (!_started) {
            _started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _to(_large);
            });
          }
          return AnimatedBuilder(
            animation: _h,
            builder: (context, child) {
              // (The keyboard may leave less room than it had.)
              final h = math.min(_h.value, _large);
              if (h <= 0.5) return const SizedBox.shrink();
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: h,
                    child: child!,
                  ),
                ],
              );
            },
            child: GestureDetector(
              // Drags that nothing inside takes (the grabber, the header)
              // move the sheet.
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: _drag,
              onVerticalDragEnd: _dragEnd,
              child: Material(
                color:
                    Theme.of(context).dialogTheme.backgroundColor ??
                    scheme.surfaceContainerHigh,
                elevation: inkE(8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(inkR(18)),
                  ),
                  side: eink
                      ? BorderSide(color: scheme.outline, width: einkStroke)
                      : BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                // Laid out at least this tall, cut off while the sheet is
                // lower (rising, or dragged down), never squeezed. (The same
                // widgets at every height: what's typed in it stays.)
                child: LayoutBuilder(
                  builder: (context, c) {
                    final h = math.max(c.maxHeight, _minContent);
                    return ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: h,
                        maxHeight: h,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: mq.padding.bottom),
                          child: Column(
                            children: [
                              // The grabber.
                              SizedBox(
                                height: 16,
                                child: Center(
                                  child: Container(
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: scheme.outline,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(child: widget.child),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
