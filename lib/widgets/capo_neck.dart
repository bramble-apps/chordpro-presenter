// The capo picker: a guitar neck running down from the nut, with the capo
// dragged along it. Real fret spacing, inlays on 3, 5, 7, 9 and 12; the neck
// glides along when the capo nears the edge of the part shown.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../eink.dart';

/// The highest capo position offered (12 is the open shapes an octave up).
const capoMax = 11;

/// The neck's geometry (kept apart for tests): where fret [n] sits along a
/// neck of [length], and the fret under a point along it.
class CapoNeckMath {
  static const span = 12.4; // frets drawn: just past the 12th
  static double fretAt(double n, double length) =>
      length * (1 - math.pow(2, -n / 12)) / (1 - math.pow(2, -span / 12));
  static double fretOf(double at, double length) =>
      -12 * math.log(1 - (at / length) * (1 - math.pow(2, -span / 12))) / math.ln2;

  /// Where the capo sits for a (fractional) fret: just behind the fret wire;
  /// at 0 and below, parked above the nut.
  static double capoAt(double f, double length) {
    double at(int n) => n <= 0
        ? -14.0 + n * 20
        : fretAt(n.toDouble(), length) - .3 * (fretAt(n.toDouble(), length) - fretAt(n - 1.0, length));
    final n0 = f.floor();
    return at(n0) + (at(n0 + 1) - at(n0)) * (f - n0);
  }
}

/// The neck with its capo. [capo] is where it starts; [onChanged] gets the
/// fret when the capo comes to rest on a new one. [height] is the room for
/// the part of the neck shown.
class CapoNeck extends StatefulWidget {
  final int capo;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onMoving;
  final double height;
  const CapoNeck({super.key, required this.capo, required this.onChanged, this.onMoving, this.height = 420});

  @override
  State<CapoNeck> createState() => _CapoNeckState();
}

class _CapoNeckState extends State<CapoNeck> with TickerProviderStateMixin {
  static const _width = 132.0;
  static const _top = 26.0; // above the nut: room for the parked capo
  static const _length = 560.0; // the whole neck, nut to just past the 12th fret
  late final AnimationController _f = AnimationController.unbounded(vsync: this, value: widget.capo.toDouble());
  late int _fret = widget.capo;
  late int _reported = widget.capo;
  double _off = 0; // how far down the neck the part shown has glided
  late final Ticker _glide = createTicker(_glideTick);
  final _hist = <(Duration, double)>[];
  bool _moved = false;
  Offset? _down;
  DateTime _wheelAt = DateTime(0);

  static const _spring = SpringDescription(mass: 1, stiffness: 220, damping: 22);

  double get _visible => widget.height;
  double get _total => _top + _length + 12;

  @override
  void initState() {
    super.initState();
    _off = _wantOff(_capoY(_f.value), jump: true);
    _f.addListener(_moving);
    _f.addStatusListener((s) {
      if (s == AnimationStatus.completed) _settled();
    });
  }

  @override
  void dispose() {
    _glide.dispose();
    _f.dispose();
    super.dispose();
  }

  double _capoY(double f) => _top + CapoNeckMath.capoAt(f, _length);

  /// The window's offset that keeps the capo in view, gliding near the edges.
  double _wantOff(double y, {bool jump = false}) {
    final margin = math.min(80.0, _visible * .2);
    var want = _off;
    if (jump || y > _off + _visible - margin) want = y - (_visible - margin);
    if (y < _off + margin) want = y - margin;
    return want.clamp(0.0, math.max(0.0, _total - _visible));
  }

  void _moving() {
    final f = _f.value.round().clamp(0, capoMax);
    if (f != _fret) {
      _fret = f;
      widget.onMoving?.call(f);
      HapticFeedback.selectionClick();
    }
    if (!_glide.isActive) _glide.start();
    setState(() {});
  }

  void _glideTick(Duration _) {
    final want = _wantOff(_capoY(_f.value));
    final snap = isEink(context) || MediaQuery.of(context).disableAnimations;
    _off += (want - _off) * (snap ? 1 : .2);
    if ((want - _off).abs() < .3) {
      _off = want;
      if (!_f.isAnimating && _down == null) _glide.stop();
    }
    setState(() {});
  }

  void _settled() {
    if (_fret != _reported) {
      _reported = _fret;
      widget.onChanged(_fret);
    }
  }

  void _to(double target, [double velocity = 0]) {
    final t = target.roundToDouble().clamp(0.0, capoMax.toDouble());
    if (isEink(context) || MediaQuery.of(context).disableAnimations) {
      _f.value = t;
      _settled();
      return;
    }
    _f.animateWith(SpringSimulation(_spring, _f.value, t, velocity));
  }

  void step(int d) => _to(_f.value.round() + d.toDouble());

  /// The (fractional) fret under a point on the neck.
  double _fretUnder(Offset local) {
    final y = local.dy + _off - _top; // (only the height matters, so the 8 of room doesn't)
    if (y < 0) return y / 24;
    return CapoNeckMath.fretOf(math.min(y, CapoNeckMath.fretAt(CapoNeckMath.span, _length) - 1), _length) + .3;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
        final d = {
          LogicalKeyboardKey.arrowDown: 1,
          LogicalKeyboardKey.arrowRight: 1,
          LogicalKeyboardKey.arrowUp: -1,
          LogicalKeyboardKey.arrowLeft: -1,
        }[e.logicalKey];
        if (d == null) return KeyEventResult.ignored;
        step(d);
        return KeyEventResult.handled;
      },
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            final now = DateTime.now();
            if (now.difference(_wheelAt).inMilliseconds < 110) return;
            _wheelAt = now;
            step(e.scrollDelta.dy > 0 ? 1 : -1);
          }
        },
        child: GestureDetector(
          onVerticalDragStart: (d) {
            _f.stop();
            _down = d.localPosition;
            _moved = true;
            _hist
              ..clear()
              ..add((d.sourceTimeStamp ?? Duration.zero, _f.value));
          },
          onVerticalDragUpdate: (d) {
            _f.value = _fretUnder(d.localPosition).clamp(-.6, capoMax + .4);
            _hist.add((d.sourceTimeStamp ?? Duration.zero, _f.value));
            if (_hist.length > 6) _hist.removeAt(0);
          },
          onVerticalDragEnd: (d) {
            _down = null;
            var v = 0.0;
            if (_hist.length > 1) {
              final dt = (_hist.last.$1 - _hist.first.$1).inMicroseconds / 1e6;
              if (dt > 0) v = (_hist.last.$2 - _hist.first.$2) / dt;
            }
            v = v.clamp(-25.0, 25.0);
            _to(_f.value + v * .08, v);
            _moved = false;
          },
          onTapUp: (d) {
            if (!_moved) _to(_fretUnder(d.localPosition) + .35);
          },
          child: ClipRect(
            child: CustomPaint(
              size: Size(_width + 44, _visible),
              painter: _NeckPainter(
                capo: _f.value,
                fret: _fret,
                off: _off,
                top: _top,
                length: _length,
                width: _width,
                scheme: scheme,
                ink: isEink(context),
                textStyle: Theme.of(context).textTheme.bodySmall!,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeckPainter extends CustomPainter {
  final double capo, off, top, length, width;
  final int fret;
  final ColorScheme scheme;
  final bool ink;
  final TextStyle textStyle;
  _NeckPainter({required this.capo, required this.fret, required this.off, required this.top, required this.length, required this.width, required this.scheme, required this.ink, required this.textStyle});

  @override
  void paint(Canvas canvas, Size size) {
    // (8 of room on the left: the capo reaches past the neck's edge)
    canvas.translate(8, -off);
    final dark = scheme.brightness == Brightness.dark;
    // the fretboard: rosewood, a shade lighter down the middle (e-ink: paper)
    final wood = ink ? scheme.surface : (dark ? const Color(0xFF3B2A22) : const Color(0xFF5A3E2E));
    final woodHi = ink ? scheme.surface : (dark ? const Color(0xFF4A3529) : const Color(0xFF6E4C38));
    final metal = ink ? scheme.onSurface : const Color(0xFFCFC8BE);
    final pearl = ink ? scheme.onSurface : const Color(0xFFEFE6DC);
    final end = top + length + 12;
    final board = Rect.fromLTWH(0, 0, width, end);
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, Radius.circular(inkR(8))),
      Paint()..shader = LinearGradient(colors: [wood, woodHi, wood]).createShader(board),
    );
    if (ink) {
      canvas.drawRRect(RRect.fromRectAndRadius(board, Radius.zero), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = inkW(2)
        ..color = scheme.onSurface);
    }
    // the nut
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-3, top - 6, width + 6, 7), const Radius.circular(2)), Paint()..color = pearl);
    double mid(int n) => top + (CapoNeckMath.fretAt(n - 1.0, length) + CapoNeckMath.fretAt(n.toDouble(), length)) / 2;
    for (var n = 1; n <= 12; n++) {
      final y = top + CapoNeckMath.fretAt(n.toDouble(), length);
      // inlays
      if (const [3, 5, 7, 9].contains(n)) canvas.drawCircle(Offset(width / 2, mid(n)), 5, Paint()..color = pearl.withValues(alpha: .85));
      if (n == 12) {
        for (final dx in [-20.0, 20.0]) {
          canvas.drawCircle(Offset(width / 2 + dx, mid(n)), 5, Paint()..color = pearl.withValues(alpha: .85));
        }
      }
      // the fret wire
      canvas.drawLine(Offset(0, y), Offset(width, y), Paint()
        ..strokeWidth = 2.2
        ..color = metal);
      // its number beside the neck
      if (n <= capoMax) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$n',
            style: textStyle.copyWith(
              fontSize: 12,
              fontWeight: n == fret ? FontWeight.w700 : FontWeight.w400,
              color: n == fret ? (ink ? scheme.onSurface : scheme.primary) : scheme.onSurfaceVariant,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(width + 26 - tp.width / 2, mid(n) - tp.height / 2));
      }
    }
    // six strings, the bass ones thicker
    for (var i = 0; i < 6; i++) {
      final x = 12 + i * (width - 24) / 5;
      canvas.drawLine(Offset(x, top - 20), Offset(x, end), Paint()
        ..strokeWidth = 1 + (5 - i) * .25
        ..color = metal.withValues(alpha: .85));
    }
    // the capo: a bar across the strings, its clamp knob at the side (dimmed when parked)
    final y = top + CapoNeckMath.capoAt(capo, length);
    final c = ink ? scheme.onSurface : scheme.primary;
    final parked = capo < -.2 ? .35 : 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-7, y - 8, width + 14, 16), const Radius.circular(8)),
      Paint()..color = c.withValues(alpha: parked),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(width + 4, y - 5, 12, 10), const Radius.circular(5)),
      Paint()..color = Color.lerp(c, Colors.black, .25)!.withValues(alpha: parked),
    );
  }

  @override
  bool shouldRepaint(_NeckPainter o) => true;
}
