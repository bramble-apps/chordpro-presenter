import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../dynamic_bg.dart';
import '../dynamic_frames.dart';

/// Runs for as long as the app: every dynamic background shows the same
/// moment, and carries on where it was when shown again.
final Stopwatch _clock = Stopwatch()..start();

double _now() => _clock.elapsedMicroseconds / 1e6;

/// How many frames have been put on screen (for tests).
@visibleForTesting
int dynamicFramesShown = 0;

/// Stills (a background at its first moment) drawn so far: slide tiles and
/// the preset picker show the same few over and over.
final Map<String, ui.Image> _stills = {};
final Map<String, Future<ui.Image?>> _stillsComing = {};

Future<ui.Image?> _still(DynamicBg bg, String key, int w, int h) {
  final id = '$key|$w|$h';
  return _stillsComing[id] ??= () async {
    final done = Completer<ui.Image>();
    final rgba = DynamicRenderer.frame(bg, 0, w, h);
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    final image = await done.future;
    _stills[id] = image;
    _stillsComing.remove(id);
    // Keep the newest few.
    while (_stills.length > 48) {
      _stills.remove(_stills.keys.first)?.dispose();
    }
    return image;
  }();
}

/// The last frame a moving background showed, by look and size: one shown
/// again (switching views brings a new preview) starts from it instead of
/// black while its first frame is drawn.
final Map<String, ui.Image> _lastFrames = {};

/// Completes once every still asked for so far is drawn (before taking a
/// picture of slides that show one).
Future<void> dynamicStillsReady() => Future.wait(_stillsComing.values.toList());

/// [bg]'s first moment as a PNG picture of shape [aspect] (width / height),
/// for exports that can't move.
Future<Uint8List?> dynamicStillPng(DynamicBg bg, {double aspect = 16 / 9}) async {
  const w = 480;
  final h = (w / aspect).round().clamp(2, 4 * w);
  await _still(bg, bg.lookKey, w, h);
  final image = _stills['${bg.lookKey}|$w|$h'];
  final data = await image?.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// A dynamic background filling its box: moving, or ([animate] off) its
/// first moment as a still.
class DynamicBackground extends StatefulWidget {
  final DynamicBg bg;
  final bool animate;

  /// How many pixels wide it is drawn (then scaled up smoothly: the
  /// picture is soft by nature).
  final int pixels;

  const DynamicBackground({
    super.key,
    required this.bg,
    this.animate = true,
    this.pixels = 480,
  });

  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground>
    with TickerProviderStateMixin {
  late String _key = widget.bg.lookKey;
  late DynamicBg _bg = widget.bg.copy();
  Ticker? _ticker;
  DynamicFrames? _frames;
  final _repaint = ValueNotifier<int>(0);

  /// The picture's size in pixels (from the box's shape).
  int _w = 0, _h = 0;

  /// The newest frame, and the one before (while fading to the newest).
  ui.Image? _image, _before;

  /// When the newest frame arrived, and how long it fades in (0: at once).
  double _since = 0, _fade = 0;

  @override
  void didUpdateWidget(DynamicBackground old) {
    super.didUpdateWidget(old);
    final key = widget.bg.lookKey;
    if (key != _key) {
      _key = key;
      _bg = widget.bg.copy();
      if (!widget.animate) _loadStill();
    }
    if (old.animate != widget.animate) _start();
  }

  /// Size known (or changed): start moving, or draw the still.
  void _sized(int w, int h) {
    if (w == _w && h == _h) return;
    _w = w;
    _h = h;
    _start();
  }

  void _start() {
    if (_w == 0) return;
    if (widget.animate) {
      // (something to show at once: the last frame of this look at this
      // size, else its first moment, until the moving frames come)
      if (_image == null) {
        final last = _lastFrames['$_key|$_w|$_h'];
        if (last != null) {
          _show(last.clone(), fade: false);
        } else {
          _loadStill();
        }
      }
      _frames ??= DynamicFrames();
      _ticker ??= createTicker(_tick)..start();
    } else {
      _ticker?.dispose();
      _ticker = null;
      _frames?.dispose();
      _frames = null;
      _loadStill();
    }
  }

  void _loadStill() {
    final key = _key, w = _w, h = _h;
    final ready = _stills['$key|$w|$h'];
    if (ready != null) {
      _show(ready.clone(), fade: false);
      return;
    }
    _still(_bg, key, w, h).then((_) {
      final image = _stills['$key|$w|$h'];
      if (image == null || !mounted) return;
      if (key != _key || w != _w || h != _h) return;
      // (moving: only while no moving frame has come yet)
      if (widget.animate && _image != null) return;
      _show(image.clone(), fade: false);
    });
  }

  void _tick(Duration _) {
    // (The app's own clock: the ticker's slows down in e-ink mode.)
    final now = _now();
    // Frames land on 60ths of a second, like Keydeck's.
    final t = (now * 60).floorToDouble() / 60;
    // Small ones share the thread with the operator's screen: less time.
    final frame = _frames?.pump(_bg, _key, t, _w, _h, widget.pixels > 320 ? 8 : 4);
    if (frame != null) {
      ui.decodeImageFromPixels(
        frame.rgba,
        frame.w,
        frame.h,
        ui.PixelFormat.rgba8888,
        (image) {
          if (!mounted || !widget.animate || frame.key != _key) {
            image.dispose();
          } else {
            _show(image, fade: true);
          }
        },
      );
    }
    if (_fade > 0 && now - _since <= _fade + 0.1) _repaint.value++;
  }

  void _show(ui.Image image, {required bool fade}) {
    final now = _now();
    final gap = now - _since;
    _before?.dispose();
    _before = _image;
    _image = image;
    // Frames coming slower than 30 a second (a slow device, or the
    // browser): each one fades into the next, so the motion stays smooth.
    _fade = fade && _before != null && gap > 0.034 && gap < 1 ? gap * 0.95 : 0;
    _since = now;
    dynamicFramesShown++;
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frames?.dispose();
    // (kept for the next one of this look and size)
    final last = _image;
    if (widget.animate && last != null && _w > 0) {
      _lastFrames.remove('$_key|$_w|$_h')?.dispose();
      _lastFrames['$_key|$_w|$_h'] = last.clone();
      while (_lastFrames.length > 8) {
        _lastFrames.remove(_lastFrames.keys.first)?.dispose();
      }
    }
    _image?.dispose();
    _before?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = c.biggest;
      if (size.isFinite && !size.isEmpty) {
        final w = widget.pixels;
        final h = (w * size.height / size.width).round().clamp(2, 4 * w);
        _sized(w, h);
      }
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _DynamicPainter(this, _repaint),
        ),
      );
    },
  );
}

class _DynamicPainter extends CustomPainter {
  final _DynamicBackgroundState state;
  _DynamicPainter(this.state, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final image = state._image;
    if (image == null) return;
    final to = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.low;
    void draw(ui.Image i) => canvas.drawImageRect(
      i,
      Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()),
      to,
      paint,
    );
    final before = state._before;
    final k = state._fade <= 0
        ? 1.0
        : ((_now() - state._since) / state._fade).clamp(0.0, 1.0);
    if (k < 1 && before != null) {
      draw(before);
      paint.color = Color.fromRGBO(0, 0, 0, k);
    }
    draw(image);
  }

  @override
  bool shouldRepaint(_DynamicPainter old) => true;
}
