// Toolbar icons that move a little when the pointer comes over their button
// (or a finger touches it), like the sidebar button's divider bending into a
// chevron: quick and small, each easing into its "hovered" pose, holding it
// while the pointer stays and easing back when it leaves. Share's arrow
// lifts, the brush tilts, the projection screen pulls down a little, the
// settings knobs swap… Each part moves on its own: the icons are drawn from
// their shapes in the icon font (motion_paths.dart). Still on e-ink and with
// the system's reduced motion.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../eink.dart';
import 'capo_icon.dart';
import 'edit_song_icon.dart';
import 'metronome_icon.dart';
import 'motion_paths.dart';

/// What an icon is and its hovered pose.
enum IconMotion {
  share, // the arrow lifts out of the tray
  sticky, // the note tips a little
  insert, // the plus turns a quarter
  annotate, // the pen lifts, leaving a short stroke
  editSong, // the brackets open around the cursor
  structure, // the rows step right, one after another
  format, // the brush tilts
  present, // the four squares spread apart
  preview, // the small picture grows out of its corner
  projector, // the screen pulls down
  settings, // the sliders' knobs swap sides
  more, // the three dots spread
  play, // the triangle nudges forward
  autoscroll, // the two carets drop
  tuner, // the bars change height
  pads, // the waves shift
  blackout, // the eye half closes
  metronome, // the pendulum swings once (a preview of the beat)
  capo, // the capo slides down a fret
  note, // the note lifts and tilts
}

/// The pointer over a button (or a touch on it), for the [MotionIcon]
/// inside: put round the whole button so all of it starts the motion.
class MotionHover extends StatefulWidget {
  final Widget child;
  const MotionHover({super.key, required this.child});

  @override
  State<MotionHover> createState() => _MotionHoverState();
}

class _MotionHoverState extends State<MotionHover>
    with TickerProviderStateMixin {
  /// 0 → 1 while the pointer is over the button, back when it leaves.
  late final hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 160),
  );

  /// One short run each time the pointer comes over (the metronome's swing).
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  bool _still(BuildContext context) =>
      isEink(context) || MediaQuery.maybeDisableAnimationsOf(context) == true;

  void _enter() {
    if (_still(context)) return;
    hover.forward();
    if (!pulse.isAnimating) pulse.forward(from: 0);
  }

  /// (a touch: the pointer "leaves" once the pose has shown)
  Timer? _touch;

  void _leave() => hover.reverse();

  @override
  void dispose() {
    _touch?.cancel();
    hover.dispose();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _enter(),
    onExit: (_) => _leave(),
    child: Listener(
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse) return;
        _enter();
        _touch?.cancel();
        _touch = Timer(const Duration(milliseconds: 450), _leave);
      },
      child: _MotionScope(state: this, child: widget.child),
    ),
  );
}

class _MotionScope extends InheritedWidget {
  final _MotionHoverState state;
  const _MotionScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_MotionScope old) => old.state != state;
}

/// An icon of the toolbar that moves on hover: inside a [MotionHover]
/// (the button's), or with its own.
class MotionIcon extends StatelessWidget {
  final IconMotion motion;
  final double? size;
  final Color? color;
  const MotionIcon(this.motion, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_MotionScope>();
    if (scope == null) return MotionHover(child: this);
    final s = scope.state;
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color =
        this.color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: Listenable.merge([s.hover, s.pulse]),
      builder: (context, _) {
        // (eased like the sidebar button's chevron)
        final h = Curves.easeOut.transform(s.hover.value);
        switch (motion) {
          case IconMotion.metronome:
            // one swing out and back, small
            final p = s.pulse.value;
            return MetronomeIcon(
              swing: p <= 0 || p >= 1 ? 0 : .5 * math.sin(p * 2 * math.pi),
              size: size,
              color: color,
            );
          case IconMotion.capo:
            return CapoIcon(size: size, color: color, slide: h);
          case IconMotion.editSong:
            return EditSongIcon(size: size, color: color, open: h * .8);
          default:
            return CustomPaint(
              size: Size.square(size),
              painter: _MotionPainter(motion, color, h),
            );
        }
      },
    );
  }
}

/// [h] (0–1) as the share of it reached by item [i] of [n], each starting a
/// little after the one before (a gentle stagger that ends with all there).
double _stagger(double h, int i, int n, {double gap = .25}) {
  final start = i * gap / math.max(1, n - 1);
  return ((h - start) / (1 - gap)).clamp(0.0, 1.0);
}

final _shapes = <String, List<Path>>{};

/// [name]'s shapes, parsed once.
List<Path> _shapesOf(String name) =>
    _shapes[name] ??= [for (final d in motionPaths[name]!) _parse(d)];

/// SVG path data as the font tool writes it (absolute M L H V Q C Z).
Path _parse(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLHVQCZ]|-?\d*\.?\d+')
      .allMatches(d)
      .map((m) => m[0]!)
      .toList();
  var i = 0;
  double n() => double.parse(tokens[i++]);
  var op = 'M';
  var x = 0.0, y = 0.0;
  while (i < tokens.length) {
    if (RegExp(r'^[MLHVQCZ]$').hasMatch(tokens[i])) op = tokens[i++];
    switch (op) {
      case 'M':
        path.moveTo(x = n(), y = n());
        op = 'L';
      case 'L':
        path.lineTo(x = n(), y = n());
      case 'H':
        path.lineTo(x = n(), y);
      case 'V':
        path.lineTo(x, y = n());
      case 'Q':
        path.quadraticBezierTo(n(), n(), x = n(), y = n());
      case 'C':
        path.cubicTo(n(), n(), n(), n(), x = n(), y = n());
      case 'Z':
        path.close();
    }
  }
  return path;
}

class _MotionPainter extends CustomPainter {
  final IconMotion motion;
  final Color color;

  /// How far into its hovered pose (eased, 0–1).
  final double h;

  _MotionPainter(this.motion, this.color, this.h);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    /// Draws [shape] moved [by] (grid units), scaled and turned about [at]
    /// (its centre unless given).
    void draw(
      Path shape, {
      Offset by = Offset.zero,
      double scale = 1,
      double scaleY = 1,
      double turn = 0,
      Offset? at,
    }) {
      final c = at ?? shape.getBounds().center;
      canvas
        ..save()
        ..translate(by.dx + c.dx, by.dy + c.dy)
        ..rotate(turn)
        ..scale(scale, scale * scaleY)
        ..translate(-c.dx, -c.dy)
        ..drawPath(shape, fill)
        ..restore();
    }

    switch (motion) {
      case IconMotion.share:
        final [tray, arrow] = _shapesOf('share');
        draw(tray);
        draw(arrow, by: Offset(0, -1.6 * h));
      case IconMotion.sticky:
        final [note, fold] = _shapesOf('sticky');
        const corner = Offset(3.3, 20.7);
        draw(note, turn: -.09 * h, at: corner);
        draw(fold, turn: -.09 * h, at: corner);
      case IconMotion.insert:
        final [picture, plus] = _shapesOf('insert');
        draw(picture);
        draw(plus, turn: math.pi / 2 * h);
      case IconMotion.annotate:
        final [pen, ...rest] = _shapesOf('annotate');
        // the pen lifts up and right, leaving a short stroke from its tip
        const tip = Offset(3.8, 20.2);
        final o = Offset(1.4, -1.0) * h;
        if (h > .02) {
          canvas.drawLine(
            tip + const Offset(-.4, 1.2),
            tip + const Offset(-.4, 1.2) + Offset(3.2 * h, 0),
            stroke..color = color.withValues(alpha: color.a * h),
          );
        }
        for (final s in [pen, ...rest]) {
          draw(s, by: o);
        }
      case IconMotion.structure:
        final shapes = _shapesOf('structure');
        // a row is a line and its dot: the same height
        final rows = <double>{
          for (final s in shapes) s.getBounds().center.dy.roundToDouble(),
        }.toList()..sort();
        for (final s in shapes) {
          final r = rows.indexOf(s.getBounds().center.dy.roundToDouble());
          draw(s, by: Offset(1.3 * _stagger(h, r, rows.length), 0));
        }
      case IconMotion.format:
        final [brush] = _shapesOf('format');
        draw(brush, turn: -.22 * h, at: const Offset(19, 5));
      case IconMotion.present:
        for (final s in _shapesOf('present')) {
          final c = s.getBounds().center;
          final out = Offset(c.dx < 12 ? -1 : 1, c.dy < 12 ? -1 : 1);
          draw(s, by: out * .9 * h);
        }
      case IconMotion.preview:
        final [frame, small] = _shapesOf('preview');
        draw(frame);
        draw(small, scale: 1 + .3 * h, at: const Offset(21, 19));
      case IconMotion.projector:
        _projector(canvas, fill);
      case IconMotion.settings:
        _settings(canvas, stroke);
      case IconMotion.more:
        final shapes = _shapesOf('more');
        draw(shapes.first);
        for (final d in shapes.skip(1)) {
          final x = d.getBounds().center.dx;
          draw(d, by: Offset((x - 12).sign * 1.1 * h, 0));
        }
      case IconMotion.play:
        final [play] = _shapesOf('play');
        draw(play, by: Offset(1.3 * h, 0));
      case IconMotion.autoscroll:
        final shapes = _shapesOf('autoscroll').toList()
          ..sort((a, b) => a.getBounds().top.compareTo(b.getBounds().top));
        for (final (i, s) in shapes.indexed) {
          draw(s, by: Offset(0, 1.4 * _stagger(h, i, shapes.length)));
        }
      case IconMotion.tuner:
        // the bars take the next frame's heights
        const next = [1.25, .8, 1.2, .75, 1.15];
        final bars = _shapesOf('tuner').toList()
          ..sort((a, b) => a.getBounds().left.compareTo(b.getBounds().left));
        for (final (i, s) in bars.indexed) {
          final x = s.getBounds().center.dx;
          draw(
            s,
            scaleY: 1 + (next[i % next.length] - 1) * h,
            at: Offset(x, 12),
          );
        }
      case IconMotion.pads:
        final waves = _shapesOf('pads').toList()
          ..sort((a, b) => a.getBounds().top.compareTo(b.getBounds().top));
        for (final (i, s) in waves.indexed) {
          draw(s, by: Offset((i.isEven ? 1 : -1) * 1.2 * h, 0));
        }
      case IconMotion.blackout:
        for (final s in _shapesOf('blackout')) {
          draw(s, scaleY: 1 - .3 * h, at: const Offset(12, 12));
        }
      case IconMotion.note:
        final [note] = _shapesOf('note');
        draw(
          note,
          by: Offset(0, -1.3 * h),
          turn: -.1 * h,
          at: const Offset(8, 20),
        );
      case IconMotion.metronome:
      case IconMotion.capo:
      case IconMotion.editSong:
        break; // (drawn by their own widgets)
    }
  }

  /// The projection screen pulls down: the case stays, the screen below it
  /// stretches, the pull tab drops with its foot.
  void _projector(Canvas canvas, Paint fill) {
    final [shape] = _shapesOf('projector');
    final d = 1.8 * h;
    const top = 6.9, bottom = 18.3; // (the case's foot, the screen's foot)
    canvas
      ..save()
      ..clipRect(const Rect.fromLTRB(0, -2, 24, top))
      ..drawPath(shape, fill)
      ..restore();
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, top, 24, bottom + d))
      ..translate(0, top)
      ..scale(1, (bottom - top + d) / (bottom - top))
      ..translate(0, -top)
      ..drawPath(shape, fill)
      ..restore();
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, bottom + d, 24, 28))
      ..translate(0, d)
      ..drawPath(shape, fill)
      ..restore();
  }

  /// Phosphor's horizontal sliders, drawn here so the knobs can move: they
  /// slide to swap sides while the pointer is over (and back after).
  void _settings(Canvas canvas, Paint stroke) {
    void slider(double y, double knob) {
      // (the knob a ring of 2.25; the line stops at it, each side)
      const r = 2.25, from = 3.75, to = 20.25;
      if (knob - r - from > .2) {
        canvas.drawLine(Offset(from, y), Offset(knob - r, y), stroke);
      }
      if (to - (knob + r) > .2) {
        canvas.drawLine(Offset(knob + r, y), Offset(to, y), stroke);
      }
      canvas.drawCircle(Offset(knob, y), r, stroke);
    }

    slider(7.5, 9.75 + 6 * h);
    slider(16.5, 15.75 - 6 * h);
  }

  @override
  bool shouldRepaint(_MotionPainter o) =>
      o.motion != motion || o.color != color || o.h != h;
}
