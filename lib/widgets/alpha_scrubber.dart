import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// A–Z index down the edge of a list (like Niagara Launcher's). Hover and
/// the letters near the pointer swell and bow outwards in a smooth wave;
/// press or drag and the list jumps to the letter under your finger, with a
/// big bubble showing which one. Letters with nothing under them are dim
/// (and skipped: you land on the nearest one that has songs).
class AlphaScrubber extends StatefulWidget {
  final List<String> letters;
  final Set<String> available;
  final ValueChanged<String> onLetter;

  const AlphaScrubber({
    super.key,
    required this.letters,
    required this.available,
    required this.onLetter,
  });

  static const width = 24.0;

  /// Phones and touch screens: a wider strip, easy to hit with a finger.
  static const touchWidth = 40.0;

  static bool _touch(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      MediaQuery.sizeOf(context).width < 600;

  /// The strip's width here.
  static double widthFor(BuildContext context) =>
      _touch(context) ? touchWidth : width;

  @override
  State<AlphaScrubber> createState() => _AlphaScrubberState();
}

class _AlphaScrubberState extends State<AlphaScrubber>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;

  /// Pointer height (what the wave follows) and the eased one drawn.
  double? _targetY;
  double _y = 0;

  /// 0 = at rest, ~0.75 = hovering, 1 = dragging.
  double _expand = 0;
  double _targetExpand = 0;
  bool _dragging = false;
  String? _current;
  double _height = 1;

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    final ease = 1 - math.exp(-dt * 18);
    if (_targetY != null) _y += (_targetY! - _y) * ease;
    _expand += (_targetExpand - _expand) * (1 - math.exp(-dt * 14));
    _frame.value++;
    final settled =
        (_targetExpand - _expand).abs() < 0.002 &&
        (_targetY == null || (_targetY! - _y).abs() < 0.3);
    if (settled && _targetExpand == 0) {
      _expand = 0;
      _ticker.stop();
    }
  }

  double get _slot => _height / widget.letters.length;

  void _point(double y, {required bool select}) {
    final first = _targetY == null || (_expand < 0.05 && !_dragging);
    _targetY = y.clamp(0, _height);
    if (first) _y = _targetY!;
    _wake();
    if (!select) return;
    // The letter under the finger, or the nearest one that has songs.
    final i = (y / _slot).floor().clamp(0, widget.letters.length - 1);
    String? pick;
    for (var d = 0; d < widget.letters.length && pick == null; d++) {
      for (final j in [i - d, i + d]) {
        if (j >= 0 &&
            j < widget.letters.length &&
            widget.available.contains(widget.letters[j])) {
          pick = widget.letters[j];
          break;
        }
      }
    }
    if (pick != null && pick != _current) {
      _current = pick;
      HapticFeedback.selectionClick();
      widget.onLetter(pick);
    }
  }

  void _start(double y) {
    _dragging = true;
    _targetExpand = 1;
    _current = null;
    _point(y, select: true);
  }

  void _end() {
    _dragging = false;
    _targetExpand = _hovering ? 0.75 : 0;
    _wake();
  }

  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        _height = c.maxHeight;
        return MouseRegion(
          onEnter: (e) {
            _hovering = true;
            if (!_dragging) _targetExpand = 0.75;
            _point(e.localPosition.dy, select: false);
          },
          onHover: (e) => _point(e.localPosition.dy, select: false),
          onExit: (_) {
            _hovering = false;
            if (!_dragging) _targetExpand = 0;
            _wake();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) => _start(d.localPosition.dy),
            onVerticalDragUpdate: (d) =>
                _point(d.localPosition.dy, select: true),
            onVerticalDragEnd: (_) => _end(),
            onTapDown: (d) => _start(d.localPosition.dy),
            onTapUp: (_) => _end(),
            onTapCancel: _end,
            child: CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _ScrubberPainter(
                repaint: _frame,
                state: this,
                scheme: scheme,
                touch: AlphaScrubber._touch(context),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  final _AlphaScrubberState state;
  final ColorScheme scheme;
  final bool touch;
  _ScrubberPainter({
    required Listenable repaint,
    required this.state,
    required this.scheme,
    this.touch = false,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final letters = state.widget.letters;
    final slot = size.height / letters.length;
    final expand = state._expand;
    final y = state._y;
    // Bigger letters for fingers.
    final base = math.min(touch ? 13.0 : 11.0, slot * (touch ? 0.85 : 0.8));
    for (var i = 0; i < letters.length; i++) {
      final cy = (i + 0.5) * slot;
      // A bell-shaped wave around the pointer, about three letters wide.
      final d = (cy - y) / math.max(slot, 14);
      final m = expand * math.exp(-(d * d) / 4.5);
      final has = state.widget.available.contains(letters[i]);
      final current = state._dragging && letters[i] == state._current;
      final colour = current
          ? scheme.primary
          : has
          ? Color.lerp(scheme.onSurfaceVariant, scheme.onSurface, m)!
          : scheme.outlineVariant;
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            fontSize: base * (1 + 0.9 * m),
            fontWeight: current || m > 0.5 ? FontWeight.w800 : FontWeight.w600,
            color: colour,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Bulges outwards (to the left) near the pointer.
      final cx = size.width / 2 - 30 * m;
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }

    // The big letter bubble while dragging.
    final shown = state._current;
    if (shown != null && state._dragging && expand > 0.2) {
      final r = 28.0 * expand;
      final center = Offset(-58, y.clamp(r, size.height - r));
      canvas.drawCircle(
        center + const Offset(0, 2),
        r,
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(center, r, Paint()..color = scheme.primaryContainer);
      final tp = TextPainter(
        text: TextSpan(
          text: shown,
          style: TextStyle(
            fontSize: 26 * expand,
            fontWeight: FontWeight.w700,
            color: scheme.onPrimaryContainer,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.scheme != scheme || old.state != state || old.touch != touch;
}
