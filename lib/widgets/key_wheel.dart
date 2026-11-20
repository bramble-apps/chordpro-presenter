// The key picker as a circle of fifths: the wheel turns under a fixed lens at
// the top, and whatever sits in the lens is the key and its six chords (IV I V
// on the outside, ii vi iii inside). The song's own chords are marked on the
// wheel, borrowed ones too, so you can see where the song travels.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../eink.dart';
import '../music.dart';

/// The circle-of-fifths arithmetic behind the wheel (kept apart for tests).
class KeyWheelMath {
  /// Pitch class of each position, C at the top, clockwise in fifths.
  static const pcs = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5];

  static int mod12(int n) => ((n % 12) + 12) % 12;

  /// The position of the major key [pc].
  static int majorAt(int pc) => pcs.indexOf(mod12(pc));

  /// The position of the minor key [pc] (inside its relative major).
  static int minorAt(int pc) => majorAt(pc + 3);

  /// The position of a key.
  static int positionOf(MusicKey k) =>
      k.minor ? minorAt(k.root) : majorAt(k.root);

  /// The tonic's pitch class at position [i].
  static int tonicPc(int i, bool minor) =>
      mod12(pcs[mod12(i)] + (minor ? 9 : 0));

  /// Semitones from position [from] to [to], as the key menu shows them (−6…+5).
  static int offset(int from, int to) {
    var o = mod12(pcs[mod12(to)] - pcs[mod12(from)]);
    if (o > 5) o -= 12;
    return o;
  }

  /// Where a chord sits: (inside ring, position). Minor and diminished chords
  /// go inside, everything else (majors, sevenths, sus, power chords) outside.
  static (bool, int) place(Chord c) {
    final r = c.rest.toLowerCase();
    final dim =
        r.startsWith('dim') ||
        r.startsWith('°') ||
        r.contains('m7b5') ||
        r.contains('ø');
    if (c.minor || dim) return (true, minorAt(c.root));
    return (false, majorAt(c.root));
  }

  /// The song's chords as wheel marks: (inside, position) → how often.
  static Map<(bool, int), int> marks(Iterable<Chord> chords) {
    final out = <(bool, int), int>{};
    for (final c in chords) {
      final p = place(c);
      out[p] = (out[p] ?? 0) + 1;
    }
    return out;
  }

  /// The chords of the key at position [s]: (numeral, name, role), role 't'
  /// tonic, 'm' minor, 'd' diminished, '' major.
  static List<(String, String, String)> degrees(int s, bool minor) {
    // spelled as the key spells them (E major's vii° is D#°, not Eb°)
    final flats = MusicKey(tonicPc(s, minor), minor).prefersFlats;
    String note(int pc) => (flats ? _flat : _sharp)[mod12(pc)];
    String maj(int i) => note(pcs[mod12(i)]);
    String mi(int i) => '${note(pcs[mod12(i)] + 9)}m';
    String dim(int i) => '${note(pcs[mod12(i)] + 9)}°';
    if (!minor) {
      return [
        ('I', maj(s), 't'),
        ('ii', mi(s - 1), 'm'),
        ('iii', mi(s + 1), 'm'),
        ('IV', maj(s - 1), ''),
        ('V', maj(s + 1), ''),
        ('vi', mi(s), 'm'),
        ('vii°', dim(s + 2), 'd'),
      ];
    }
    return [
      ('i', mi(s), 't'),
      ('ii°', dim(s + 2), 'd'),
      ('III', maj(s), ''),
      ('iv', mi(s - 1), 'm'),
      ('v', mi(s + 1), 'm'),
      ('VI', maj(s - 1), ''),
      ('VII', maj(s + 1), ''),
    ];
  }

  static const _sharp = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  static const _flat = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];

  /// The position a degree chip leads to (its key at the top).
  static int degreeTarget(int s, bool minor, int j) => mod12(
    s +
        (minor
            ? const [0, 2, 0, -1, 1, -1, 1]
            : const [0, -1, 1, -1, 1, 0, 2])[j],
  );
}

/// The wheel itself. [original] is the song's written key (null: unknown, shown
/// as C with offsets only); [offset] the current transposition; [chords] the
/// song's chords as written. [onChanged] gets the new offset when the wheel
/// comes to rest on a key.
class KeyWheel extends StatefulWidget {
  final MusicKey? original;
  final int offset;
  final List<Chord> chords;
  final ValueChanged<int> onChanged;
  final double size;
  const KeyWheel({
    super.key,
    required this.original,
    required this.offset,
    required this.chords,
    required this.onChanged,
    this.size = 300,
  });

  @override
  State<KeyWheel> createState() => _KeyWheelState();
}

class _KeyWheelState extends State<KeyWheel> with TickerProviderStateMixin {
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
  );
  late final bool _minor = widget.original?.minor ?? false;
  late final int _orig = widget.original == null
      ? 0
      : KeyWheelMath.positionOf(widget.original!);
  late final Map<(bool, int), int> _marks = KeyWheelMath.marks(widget.chords);
  int _sel = 0;
  // the offset last given to onChanged (the dialog doesn't rebuild with it)
  late int _reported = widget.offset;
  final _focus = FocusNode();
  double? _dragAngle;
  final _hist = <(Duration, double)>[];
  DateTime _wheelAt = DateTime(0);
  // the highlights (the key's chords, the tonic) per position, easing to the
  // key at the top whenever it changes, so they fade over instead of jumping
  final _keyW = List<double>.filled(12, 0), _tonicW = List<double>.filled(12, 0);
  late final Ticker _fade = createTicker(_fadeTick);
  Duration _fadeLast = Duration.zero;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 190,
    damping: 21,
  );

  @override
  void initState() {
    super.initState();
    // the current key: the original moved round by the offset
    final start = _orig + _steps(widget.offset);
    _pos.value = start.toDouble();
    _sel = KeyWheelMath.mod12(start);
    for (var k = 0; k < 12; k++) {
      _keyW[k] = _keyTarget(k);
      _tonicW[k] = _tonicTarget(k);
    }
    _pos.addListener(_moved);
    _pos.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        _settled();
      }
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    _pos.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Positions on the circle for a shift of [semitones] (a fifth is one step).
  static int _steps(int semitones) => KeyWheelMath.mod12(semitones * 7) > 6
      ? KeyWheelMath.mod12(semitones * 7) - 12
      : KeyWheelMath.mod12(semitones * 7);

  int get _offset => KeyWheelMath.offset(_orig, _sel);

  double _keyTarget(int k) => (((k - _sel) % 12 + 18) % 12 - 6).abs() <= 1 ? 1 : 0;
  double _tonicTarget(int k) => k == _sel ? 1 : 0;

  /// Eases the highlights toward the current key (about 200 ms).
  void _fadeTick(Duration elapsed) {
    final dt = (elapsed - _fadeLast).inMicroseconds / 1e6;
    _fadeLast = elapsed;
    final snap = isEink(context) || MediaQuery.of(context).disableAnimations;
    final f = snap ? 1.0 : 1 - math.exp(-dt / .065);
    var done = true;
    for (var k = 0; k < 12; k++) {
      for (final (w, t) in [(_keyW, _keyTarget(k)), (_tonicW, _tonicTarget(k))]) {
        w[k] += (t - w[k]) * f;
        if ((t - w[k]).abs() < .004) {
          w[k] = t;
        } else {
          done = false;
        }
      }
    }
    setState(() {});
    if (done) _fade.stop();
  }

  void _moved() {
    final s = KeyWheelMath.mod12(_pos.value.round());
    if (s != _sel) {
      setState(() => _sel = s);
      if (!_fade.isActive) {
        _fadeLast = Duration.zero;
        _fade.start();
      }
      HapticFeedback.selectionClick();
    }
    // (otherwise only the wheel repaints, from the position itself: no rebuild)
  }

  void _settled() {
    if (_offset != _reported) {
      _reported = _offset;
      widget.onChanged(_offset);
    }
  }

  /// Turns to whole position [target] with a spring (from [velocity], keys/s).
  void _springTo(double target, [double velocity = 0]) {
    if (isEink(context) || MediaQuery.of(context).disableAnimations) {
      _pos.value = target;
      _settled();
      return;
    }
    _pos.animateWith(SpringSimulation(_spring, _pos.value, target, velocity));
  }

  /// The nearest whole position showing key [k] (the short way round).
  double _nearest(int k) {
    final base = _pos.value.round();
    return (base + KeyWheelMath.mod12(k - base + 6) - 6).toDouble();
  }

  void jump(int k) => _springTo(_nearest(k));
  void step(int d) => _springTo((_pos.value.round() + d).toDouble());

  // pointer angle in positions (clockwise from the top), from the wheel's middle
  double _angle(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = local - c;
    return math.atan2(v.dx, -v.dy) * 180 / math.pi / 30;
  }

  void _panStart(DragStartDetails d) {
    _pos.stop();
    _dragAngle = _angle(d.localPosition);
    _hist
      ..clear()
      ..add((d.sourceTimeStamp ?? Duration.zero, _pos.value));
  }

  void _panUpdate(DragUpdateDetails d) {
    final a = _angle(d.localPosition);
    var delta = a - (_dragAngle ?? a);
    delta = (delta + 6) % 12 - 6;
    _dragAngle = a;
    // the wheel follows the finger: turning clockwise brings the keys on the left up
    _pos.value = _pos.value - delta;
    _hist.add((d.sourceTimeStamp ?? Duration.zero, _pos.value));
    if (_hist.length > 6) _hist.removeAt(0);
  }

  void _panEnd(DragEndDetails d) {
    var v = 0.0;
    if (_hist.length > 1) {
      final dt = (_hist.last.$1 - _hist.first.$1).inMicroseconds / 1e6;
      if (dt > 0) v = (_hist.last.$2 - _hist.first.$2) / dt;
    }
    v = v.clamp(-30.0, 30.0);
    _springTo((_pos.value + v * 0.16).roundToDouble(), v);
  }

  void _tap(TapUpDetails d) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final r = (d.localPosition - c).distance / (widget.size / 2);
    if (r < _WheelPainter.hub) {
      jump(_orig);
    } else if (r <= 1.0) {
      jump(KeyWheelMath.mod12((_angle(d.localPosition) + _pos.value).round()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = isEink(context);
    final keyName = KeyWheelMath.degrees(_sel, _minor).first.$2;
    final off = _offset;
    final offText = widget.original == null && off == 0
        ? 'original'
        : off == 0
        ? 'original'
        : (off > 0 ? '+$off' : '−${-off}');
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final d = {
          LogicalKeyboardKey.arrowRight: 1,
          LogicalKeyboardKey.arrowDown: 1,
          LogicalKeyboardKey.arrowLeft: -1,
          LogicalKeyboardKey.arrowUp: -1,
        }[e.logicalKey];
        if (d == null) return KeyEventResult.ignored;
        step(d);
        return KeyEventResult.handled;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                final now = DateTime.now();
                if (now.difference(_wheelAt).inMilliseconds < 110) return;
                _wheelAt = now;
                final dy = e.scrollDelta.dy != 0
                    ? e.scrollDelta.dy
                    : e.scrollDelta.dx;
                step(dy > 0 ? 1 : -1);
              }
            },
            child: GestureDetector(
              onPanStart: _panStart,
              onPanUpdate: _panUpdate,
              onPanEnd: _panEnd,
              onTapUp: _tap,
              child: SizedBox.square(
                dimension: widget.size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(widget.size),
                      painter: _WheelPainter(
                        pos: _pos,
                        keyW: _keyW,
                        tonicW: _tonicW,
                        sel: _sel,
                        orig: widget.original == null ? null : _orig,
                        minor: _minor,
                        // the song's chords move with the key: transposed by the offset
                        marks: {
                          for (final e in _marks.entries)
                            (
                              e.key.$1,
                              KeyWheelMath.mod12(e.key.$2 + (_sel - _orig)),
                            ): e.value,
                        },
                        scheme: scheme,
                        ink: ink,
                        textStyle: Theme.of(context).textTheme.bodyMedium!,
                      ),
                    ),
                    // the middle: the key, major / minor, the offset (tap: the original)
                    IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: motion(
                              context,
                              const Duration(milliseconds: 260),
                            ),
                            transitionBuilder: (child, a) => ScaleTransition(
                              scale: Tween(begin: .7, end: 1.0).animate(
                                CurvedAnimation(
                                  parent: a,
                                  curve: Curves.easeOutBack,
                                ),
                              ),
                              child: FadeTransition(opacity: a, child: child),
                            ),
                            child: Text(
                              keyName,
                              key: ValueKey(keyName),
                              style: TextStyle(
                                fontSize: widget.size * .13,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            _minor ? 'MINOR' : 'MAJOR',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.6,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            offText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: ink ? scheme.onSurface : scheme.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _chips(context, scheme, ink),
          if (_marks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: ink ? 8 : 14,
                  height: ink ? 8 : 10,
                  decoration: BoxDecoration(
                    color: ink
                        ? scheme.onSurface
                        : _WheelPainter.songTint(
                            scheme,
                            scheme.surfaceContainerHighest,
                          ),
                    shape: ink ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: ink ? null : BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Chords in this song',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chips(BuildContext context, ColorScheme scheme, bool ink) {
    final deg = KeyWheelMath.degrees(_sel, _minor);
    // which degrees the song uses (its chords moved into the current key)
    bool used(int j) {
      final target = KeyWheelMath.degreeTarget(_sel, _minor, j);
      final inner =
          deg[j].$3.contains('m') ||
          deg[j].$3 == 'd' ||
          (deg[j].$3 == 't' && _minor);
      return _marks.keys.any(
        (k) =>
            k.$1 == inner &&
            KeyWheelMath.mod12(k.$2 + (_sel - _orig)) == target,
      );
    }

    // seven to a row in the room there is (narrow screens: narrower chips)
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxWidth.isFinite ? box.maxWidth : widget.size;
        final w = ((room - 6 * 3) / 7).clamp(30.0, 46.0);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 3,
          runSpacing: 4,
          children: [
            for (var j = 0; j < deg.length; j++)
              _Chip(
                width: w,
                numeral: deg[j].$1,
                name: deg[j].$2,
                role: deg[j].$3,
                used: used(j),
                ink: ink,
                onTap: () => jump(KeyWheelMath.degreeTarget(_sel, _minor, j)),
              ),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String numeral, name, role;
  final bool used, ink;
  final double width;
  final VoidCallback onTap;
  const _Chip({
    required this.width,
    required this.numeral,
    required this.name,
    required this.role,
    required this.used,
    required this.ink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tonic = role == 't';
    final plain = scheme.surfaceContainerHighest;
    final bg = tonic
        ? (ink ? scheme.secondaryContainer : scheme.primaryContainer)
        : (used && !ink ? _WheelPainter.songTint(scheme, plain) : plain);
    final fg = tonic
        ? (ink ? scheme.onSecondaryContainer : scheme.onPrimaryContainer)
        : role == 'm'
        ? (ink || used ? scheme.onSurface : scheme.tertiary)
        : scheme.onSurface;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(inkR(10)),
        side: ink
            ? BorderSide(width: inkW(1), color: scheme.outline)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(inkR(10)),
        onTap: onTap,
        child: Opacity(
          opacity: role == 'd' ? .6 : 1,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                children: [
                  Text(
                    numeral,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      name,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: width < 40 ? 13 : 14,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                  // (e-ink: a dot when the song uses this chord; in colour the chip is tinted)
                  if (ink) ...[
                    const SizedBox(height: 2),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: used ? scheme.onSurface : Colors.transparent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  /// The wheel's turn (in keys): the painter repaints as it moves.
  final Animation<double> pos;
  final List<double> keyW, tonicW;
  final int sel;
  final int? orig;
  final bool minor;
  final Map<(bool, int), int> marks;
  final ColorScheme scheme;
  final bool ink;
  final TextStyle textStyle;
  _WheelPainter({
    required this.pos,
    required this.keyW,
    required this.tonicW,
    required this.sel,
    required this.orig,
    required this.minor,
    required this.marks,
    required this.scheme,
    required this.ink,
    required this.textStyle,
  }) : super(repaint: pos);

  // ring edges as fractions of the radius
  static const outer = .86, mid = .60, hub = .35;

  static Color markColor(ColorScheme s, bool ink) =>
      ink ? s.onSurface : s.secondary;

  /// A segment or chip the song uses: [base] washed with the song's colour.
static Color songTint(ColorScheme s, Color base) =>
      Color.alphaBlend(songColor(s).withValues(alpha: .22), base);

  /// The song's colour: the theme accent's opposite hue, so it never reads as
  /// the lens's (or the minor chords') colour, whatever the colour theme.
  static Color songColor(ColorScheme s) {
    final h = HSLColor.fromColor(s.primary);
    final dark = s.brightness == Brightness.dark;
    return h
        .withHue((h.hue + 165) % 360)
        .withSaturation(math.max(h.saturation, .40).clamp(0, .5))
        .withLightness(dark ? .62 : .48)
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = size.width / 2;
    final rot = -pos.value * 30;
    Offset at(double r, double deg) {
      final a = deg * math.pi / 180;
      return c + Offset(r * math.sin(a), -r * math.cos(a));
    }

    Path seg(double r0, double r1, double a0, double a1) {
      final p = Path();
      final s0 = (a0 - 90) * math.pi / 180, sw = (a1 - a0) * math.pi / 180;
      p.arcTo(Rect.fromCircle(center: c, radius: r1), s0, sw, true);
      p.arcTo(Rect.fromCircle(center: c, radius: r0), s0 + sw, -sw, false);
      p.close();
      return p;
    }

    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ink ? inkW(2) : 2
      ..color = ink ? scheme.onSurface : scheme.surface;
    final segBg = scheme.surfaceContainerHighest;
    final innerBg = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: .04),
      scheme.surfaceContainerHigh,
    );
    final keyOuter = ink
        ? scheme.surface
        : Color.alphaBlend(scheme.primary.withValues(alpha: .22), segBg);
    final keyInner = ink
        ? scheme.surface
        : Color.alphaBlend(scheme.tertiary.withValues(alpha: .20), innerBg);
    final tonic = ink ? scheme.secondaryContainer : scheme.primary;
    final onTonic = ink ? scheme.onSecondaryContainer : scheme.onPrimary;

    for (var k = 0; k < 12; k++) {
      // the highlights as eased by the state (they fade to a new key, not jump)
      final keyW = Curves.easeInOut.transform(this.keyW[k].clamp(0.0, 1.0));
      final tonicW = Curves.easeInOut.transform(this.tonicW[k].clamp(0.0, 1.0));
      final a = k * 30 + rot;
      final wO = minor ? 0.0 : tonicW, wI = minor ? tonicW : 0.0;
      final tO = wO > .5, tI = wI > .5;
      // a chord the song uses: its segment tinted in the song's colour (as the key's are, in theirs)
      final songO = !ink && marks.containsKey((false, k)), songI = !ink && marks.containsKey((true, k));
      var baseO = Color.lerp(segBg, keyOuter, keyW)!, baseI = Color.lerp(innerBg, keyInner, keyW)!;
      if (songO) baseO = songTint(scheme, baseO);
      if (songI) baseI = songTint(scheme, baseI);
      canvas.drawPath(seg(R * mid, R * outer, a - 15, a + 15), Paint()..color = Color.lerp(baseO, tonic, wO)!);
      canvas.drawPath(seg(R * hub, R * mid, a - 15, a + 15), Paint()..color = Color.lerp(baseI, tonic, wI)!);
      canvas.drawPath(seg(R * mid, R * outer, a - 15, a + 15), gap);
      canvas.drawPath(seg(R * hub, R * mid, a - 15, a + 15), gap);
      final majName = MusicKey(KeyWheelMath.pcs[k], false).name;
      final minName = MusicKey(KeyWheelMath.mod12(KeyWheelMath.pcs[k] + 9), true).name;
      final majInk = Color.lerp(songO ? scheme.onSurface : Color.lerp(scheme.onSurfaceVariant, scheme.onSurface, keyW)!, onTonic, wO)!;
      final minKey = ink ? scheme.onSurface : scheme.tertiary;
      final minInk = Color.lerp(songI ? scheme.onSurface : Color.lerp(scheme.onSurfaceVariant, minKey, keyW)!, onTonic, wI)!;
      final majAt = at(R * (mid + outer) / 2, a), minAt = at(R * (hub + mid) / 2, a);
      final majBox = _text(canvas, majName, majAt, R * .13, FontWeight.w800, majInk);
      final minBox = _text(canvas, minName, minAt, R * .075, FontWeight.w600, minInk);
      // e-ink (black and white): the song's chords as dots instead
      for (final inner in [false, true]) {
        if (!ink) break;
        final n = marks[(inner, k)];
        if (n == null) continue;
        final r = R * (inner ? hub + .045 : mid + .045);
        final dot =
            (2.4 + math.min(3.0, math.sqrt(n.toDouble()) * .9)) * R / 150;
        final p = at(r, a);
        canvas.drawCircle(
          p,
          dot + 1.5,
          Paint()
            ..color =
                (inner
                        ? (k == sel && tI ? tonic : innerBg)
                        : (k == sel && tO ? tonic : segBg))
                    .withValues(alpha: .9),
        );
        canvas.drawCircle(p, dot, Paint()..color = markColor(scheme, ink));
      }
      // the original key: its name underlined (a minor song's, inside)
      if (orig == k) {
        final (p, box, inkC) = minor ? (minAt, minBox, minInk) : (majAt, majBox, majInk);
        final y = p.dy + box.height / 2 + R * .012;
        canvas.drawLine(
          Offset(p.dx - box.width / 2, y),
          Offset(p.dx + box.width / 2, y),
          Paint()
            ..strokeWidth = math.max(1.4, R * .012)
            ..strokeCap = StrokeCap.round
            ..color = inkC,
        );
      }
    }
    // the lens, fixed at the top over the key and its neighbours
    final lens = seg(R * hub - 1, R * outer + 3, -46, 46);
    if (!ink) {
      canvas.drawPath(
        lens,
        Paint()..color = scheme.primary.withValues(alpha: .06),
      );
    }
    canvas.drawPath(
      lens,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink ? inkW(2) : 1.6
        ..color = ink ? scheme.onSurface : scheme.primary.withValues(alpha: .8),
    );
    // the numerals of the lens's chords
    final num = minor
        ? const ['VI', 'III', 'VII', 'iv', 'i', 'v']
        : const ['IV', 'I', 'V', 'ii', 'vi', 'iii'];
    for (var i = 0; i < 3; i++) {
      _text(
        canvas,
        num[i],
        at(R * .945, (i - 1) * 30.0),
        R * .07,
        FontWeight.w700,
        ink ? scheme.onSurface : scheme.primary,
      );
      _text(
        canvas,
        num[i + 3],
        at(R * (hub - .07), (i - 1) * 30.0),
        R * .06,
        FontWeight.w700,
        ink ? scheme.onSurface : scheme.tertiary,
      );
    }
    // the hub
    canvas.drawCircle(c, R * hub - 2, Paint()..color = scheme.surfaceContainer);
    canvas.drawCircle(
      c,
      R * hub - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink ? inkW(2) : 1
        ..color = ink ? scheme.onSurface : scheme.outlineVariant,
    );
  }

  Size _text(
    Canvas canvas,
    String s,
    Offset at,
    double size,
    FontWeight w,
    Color color,
  ) {
    final key = '$s|$size|${w.value}|${color.toARGB32()}|${textStyle.fontFamily}';
    var tp = _laid[key];
    if (tp == null) {
      if (_laid.length > 400) _laid.clear();
      tp = _laid[key] = TextPainter(
      text: TextSpan(
        text: s,
        style: textStyle.copyWith(
          fontSize: size,
          fontWeight: w,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    }
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    return tp.size;
  }

  /// Laid-out labels, reused frame to frame (laying out 24 labels every frame
  /// made turning heavy).
  static final _laid = <String, TextPainter>{};

  @override
  // (the highlights ease in place without the wheel moving: always repaint)
  bool shouldRepaint(_WheelPainter o) => true;
}

/// The key wheel's panel: just above the Key button (over the toolbar), as
/// wide as fits (at most 360), the wheel sized to the room there is; centred
/// when there's no button to rise from.
class KeyWheelPopover extends StatelessWidget {
  final Rect? anchor;
  final bool setlistOnly;
  final Widget Function(double wheelSize) builder;

  /// The title row's text (null: no title row; tap outside to close).
  final String? title;
  final double maxWidth;

  /// The size given to [builder] from the panel's width and the height
  /// there is room for (default: the key wheel's).
  final double Function(double width, double room)? sizeFor;
  const KeyWheelPopover({
    super.key,
    required this.anchor,
    required this.setlistOnly,
    required this.builder,
    this.title = 'Key',
    this.maxWidth = 360,
    this.sizeFor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final pad = mq.padding;
    const margin = 8.0;
    final width = math.min(
      maxWidth,
      screen.width - 2 * margin - pad.left - pad.right,
    );
    // below the panel: the button's top (or the screen's foot); above: the status bar
    final bottomEdge = anchor == null
        ? screen.height - pad.bottom - margin
        : anchor!.top - margin;
    final room = bottomEdge - pad.top - margin;
    // the header, the chips, the legend and the padding take about 150
    final wheel = sizeFor?.call(width, room) ?? math.max(180.0, math.min(width - 32, room - 150));
    final left = anchor == null
        ? (screen.width - width) / 2
        : (anchor!.center.dx - width / 2).clamp(
            margin + pad.left,
            screen.width - width - margin - pad.right,
          );
    final ink = isEink(context);
    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          bottom: screen.height - bottomEdge,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: motion(context, const Duration(milliseconds: 260)),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Transform.scale(
              scale: .92 + .08 * t,
              // grows up out of the button
              alignment: anchor == null
                  ? Alignment.center
                  : Alignment(((anchor!.center.dx - left) / width) * 2 - 1, 1),
              child: Opacity(opacity: t, child: child),
            ),
            child: Material(
              color: scheme.surfaceContainerHigh,
              elevation: inkE(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(inkR(24)),
                side: ink
                    ? BorderSide(width: inkW(2), color: scheme.onSurface)
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: title == null ? const EdgeInsets.fromLTRB(16, 16, 12, 16) : const EdgeInsets.fromLTRB(16, 14, 6, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null)
                    Row(
                      children: [
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (setlistOnly) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'this setlist only',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.tertiary,
                              ),
                            ),
                          ),
                        ],
                        // (no close button: tapping outside closes it)
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: builder(wheel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
