// Toolbar icons that move a little when the pointer comes over their button
// (or a finger touches it), like the sidebar button's divider bending into a
// chevron: Share's arrow lifts, the pen draws a squiggle, the list's rows
// ripple, the brush sways, the four squares pop one after another… Each part
// moves on its own: the icons are drawn from their shapes in the icon font
// (motion_paths.dart). Still on e-ink and with the system's reduced motion.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../eink.dart';
import 'capo_icon.dart';
import 'edit_song_icon.dart';
import 'metronome_icon.dart';
import 'motion_paths.dart';

/// What an icon is and how it moves.
enum IconMotion {
  share, // the arrow lifts out of the tray and settles
  sticky, // the note tips and its folded corner flicks
  insert, // the plus turns a quarter and pops
  annotate, // the pen draws a squiggle
  editSong, // the brackets open around the cursor
  structure, // the rows ripple, one after another
  format, // the brush sways as if painting
  present, // the four squares grow and shrink, one after another
  preview, // the small picture grows out of its corner
  projector, // the screen pulls down
  settings, // the sliders' knobs swap sides (back when the pointer leaves)
  more, // the three dots hop in turn
  play, // the triangle nudges forward
  autoscroll, // the two carets drop in turn
  tuner, // the bars rise and fall (while the pointer stays)
  pads, // the waves swell (while the pointer stays)
  blackout, // the eye blinks
  metronome, // the pendulum swings (while the pointer stays)
  capo, // the capo slides down a fret and back
  note, // the note hops and tilts
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
  /// 0 → 1 while the pointer is over the button (eased back when it leaves).
  late final hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// One run, 0 → 1, each time the pointer comes over.
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Round and round while the pointer stays (a phase, 0 → 1).
  late final loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _still(BuildContext context) =>
      isEink(context) || MediaQuery.maybeDisableAnimationsOf(context) == true;

  void _enter() {
    if (_still(context)) return;
    hover.forward();
    if (!pulse.isAnimating) pulse.forward(from: 0);
    if (!loop.isAnimating) loop.repeat();
  }

  /// (a touch: the pointer "leaves" once the motion has played)
  Timer? _touch;

  void _leave() {
    hover.reverse().whenComplete(() {
      if (mounted && hover.value == 0) loop.stop();
    });
  }

  @override
  void dispose() {
    _touch?.cancel();
    hover.dispose();
    pulse.dispose();
    loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _enter(),
    onExit: (_) => _leave(),
    child: Listener(
      // (touch: the motion plays once as the finger comes down)
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse) return;
        _enter();
        _touch?.cancel();
        _touch = Timer(const Duration(milliseconds: 900), _leave);
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
      animation: Listenable.merge([s.hover, s.pulse, s.loop]),
      builder: (context, _) {
        final h = Curves.easeInOutCubic.transform(s.hover.value);
        final p = s.pulse.value;
        final l = s.loop.value;
        switch (motion) {
          case IconMotion.metronome:
            // (up to ~23°, settling as the pointer leaves)
            return MetronomeIcon(
              swing: h * .8 * math.sin(l * 2 * math.pi),
              size: size,
              color: color,
            );
          case IconMotion.capo:
            return CapoIcon(size: size, color: color, slide: _bump(p, 0, .8));
          case IconMotion.editSong:
            return EditSongIcon(
              size: size,
              color: color,
              open: _bump(p, 0, .7),
            );
          default:
            return CustomPaint(
              size: Size.square(size),
              painter: _MotionPainter(motion, color, h: h, p: p, l: l),
            );
        }
      },
    );
  }
}

/// 0 outside [from]…[to], rising to 1 and back inside it (a smooth bump).
double _bump(double t, double from, double to) {
  if (t <= from || t >= to) return 0;
  return math.sin(math.pi * (t - from) / (to - from));
}

/// A wiggle that dies away over the run: [turns] swings, starting with [first].
double _wiggle(double t, {double turns = 2.5}) =>
    t <= 0 || t >= 1 ? 0 : math.sin(t * turns * 2 * math.pi) * (1 - t);

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

  /// Hover (eased, 0–1), the one-shot run (0–1), the loop's phase (0–1).
  final double h, p, l;

  _MotionPainter(
    this.motion,
    this.color, {
    required this.h,
    required this.p,
    required this.l,
  });

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

    /// Draws [shape] moved by [m] (in grid units), about [at].
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
        // up, then a little bounce back down into place
        draw(
          arrow,
          by: Offset(0, -3.2 * _bump(p, 0, .55) + .9 * _bump(p, .55, .8)),
        );
      case IconMotion.sticky:
        final [note, fold] = _shapesOf('sticky');
        // tipping on its bottom left corner, as if flicked
        final tip = .14 * _wiggle(p, turns: 1.5);
        draw(note, turn: tip, at: const Offset(3.3, 20.7));
        draw(fold, turn: tip, at: const Offset(3.3, 20.7));
      case IconMotion.insert:
        final [picture, plus] = _shapesOf('insert');
        draw(picture);
        draw(
          plus,
          turn:
              math.pi /
              2 *
              Curves.easeInOutBack.transform(math.min(1, p / .6)) *
              (p > 0 && p < 1 ? 1 : 0),
          scale: 1 + .3 * _bump(p, 0, .6),
        );
      case IconMotion.annotate:
        _annotate(canvas, fill, stroke);
      case IconMotion.structure:
        final shapes = _shapesOf('structure');
        // a row is a line and its dot: the same height
        final rows = <double>{
          for (final s in shapes) s.getBounds().center.dy.roundToDouble(),
        }.toList()..sort();
        for (final s in shapes) {
          final r = rows.indexOf(s.getBounds().center.dy.roundToDouble());
          draw(s, by: Offset(2.4 * _bump(p, r * .16, r * .16 + .5), 0));
        }
      case IconMotion.format:
        final [brush] = _shapesOf('format');
        // swaying from the handle's end, as if painting a stroke
        draw(brush, turn: .38 * _wiggle(p), at: const Offset(19, 5));
      case IconMotion.present:
        final shapes = _shapesOf('present').toList()
          // clockwise from the top left
          ..sort((a, b) {
            int order(Path s) {
              final c = s.getBounds().center;
              final top = c.dy < 12, left = c.dx < 12;
              return top ? (left ? 0 : 1) : (left ? 3 : 2);
            }

            return order(a).compareTo(order(b));
          });
        for (final (i, s) in shapes.indexed) {
          draw(s, scale: 1 + .3 * _bump(p, i * .15, i * .15 + .42));
        }
      case IconMotion.preview:
        final [frame, small] = _shapesOf('preview');
        draw(frame);
        draw(small, scale: 1 + .45 * _bump(p, 0, .7), at: const Offset(21, 19));
      case IconMotion.projector:
        _projector(canvas, fill);
      case IconMotion.settings:
        _settings(canvas, stroke);
      case IconMotion.more:
        final shapes = _shapesOf('more');
        final dots = shapes.skip(1).toList()
          ..sort((a, b) => a.getBounds().left.compareTo(b.getBounds().left));
        draw(shapes.first);
        for (final (i, d) in dots.indexed) {
          draw(d, by: Offset(0, -2.2 * _bump(p, i * .14, i * .14 + .4)));
        }
      case IconMotion.play:
        final [play] = _shapesOf('play');
        draw(play, by: Offset(2 * _bump(p, 0, .4) + .6 * _bump(p, .4, .6), 0));
      case IconMotion.autoscroll:
        final shapes = _shapesOf('autoscroll').toList()
          ..sort((a, b) => a.getBounds().top.compareTo(b.getBounds().top));
        for (final (i, s) in shapes.indexed) {
          draw(s, by: Offset(0, 2.4 * _bump(p, i * .18, i * .18 + .45)));
        }
      case IconMotion.tuner:
        for (final s in _shapesOf('tuner')) {
          final x = s.getBounds().center.dx;
          draw(
            s,
            scaleY: 1 + h * .38 * math.sin((l + x / 24) * 2 * math.pi),
            at: Offset(x, 12),
          );
        }
      case IconMotion.pads:
        final shapes = _shapesOf('pads').toList()
          ..sort((a, b) => a.getBounds().top.compareTo(b.getBounds().top));
        for (final (i, s) in shapes.indexed) {
          draw(s, by: Offset(0, h * 1.1 * math.sin(l * 2 * math.pi - i * 1.1)));
        }
      case IconMotion.blackout:
        // a blink (the lids meet, then open)
        final blink = 1 - .85 * _bump(p, .05, .4);
        for (final s in _shapesOf('blackout')) {
          draw(s, scaleY: blink, at: const Offset(12, 12));
        }
      case IconMotion.note:
        final [note] = _shapesOf('note');
        draw(
          note,
          by: Offset(0, -2.4 * _bump(p, 0, .45) + .7 * _bump(p, .45, .65)),
          turn: -.18 * _bump(p, 0, .55),
          at: const Offset(8, 20),
        );
      case IconMotion.metronome:
      case IconMotion.capo:
      case IconMotion.editSong:
        break; // (drawn by their own widgets)
    }
  }

  /// The pen draws a squiggle: its nib traces it (left behind as a line
  /// that fades), then the pen slides home.
  void _annotate(Canvas canvas, Paint fill, Paint stroke) {
    final [pen, ...rest] = _shapesOf('annotate');
    const tip = Offset(3.6, 20.4);
    Offset at(double s) =>
        Offset(-1.5 + 5 * s, -1.6 * math.sin(s * 3 * math.pi));
    final run = math.min(1.0, p / .7);
    final home = p > .7 ? 1 - (p - .7) / .3 : 1.0;
    if (p > 0 && p < 1) {
      final trail = Path()..moveTo(tip.dx + at(0).dx, tip.dy + at(0).dy);
      for (var i = 1; i <= 24; i++) {
        final s = run * i / 24;
        trail.lineTo(tip.dx + at(s).dx, tip.dy + at(s).dy);
      }
      canvas.drawPath(
        trail,
        stroke
          ..color = stroke.color.withValues(
            alpha: stroke.color.a * (p < .7 ? 1 : home),
          ),
      );
    }
    final o = p <= 0 || p >= 1 ? Offset.zero : at(run) * home;
    canvas
      ..save()
      ..translate(o.dx, o.dy)
      ..drawPath(pen, fill);
    for (final r in rest) {
      canvas.drawPath(r, fill);
    }
    canvas.restore();
  }

  /// The projection screen pulls down: the case stays, the screen below it
  /// stretches, the pull tab drops with its foot.
  void _projector(Canvas canvas, Paint fill) {
    final [shape] = _shapesOf('projector');
    final d = 2.2 * _bump(p, 0, .75);
    const top = 6.9, bottom = 18.3; // (the case's foot, the screen's foot)
    // the case
    canvas
      ..save()
      ..clipRect(const Rect.fromLTRB(0, -2, 24, top))
      ..drawPath(shape, fill)
      ..restore();
    // the screen, stretched
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, top, 24, bottom + d))
      ..translate(0, top)
      ..scale(1, (bottom - top + d) / (bottom - top))
      ..translate(0, -top)
      ..drawPath(shape, fill)
      ..restore();
    // the pull tab, lower by as much
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
      o.motion != motion ||
      o.color != color ||
      o.h != h ||
      o.p != p ||
      o.l != l;
}
