// Dynamic background frames in the browser: drawn on the main thread, a
// few rows per screen refresh (see dynamic_frames.dart).
import 'dart:math' as math;
import 'dart:typed_data';

import 'dynamic_bg.dart';

class DynamicFrames {
  DynamicRenderer? _renderer;
  String? _made;
  Uint8List? _pixels;
  int _row = 0;
  double _t = 0;
  bool _open = false;

  /// Works on a frame of [bg] ([key]: its look) at [w] × [h] for at most
  /// about [budgetMs]; gives the frame once it is finished, else null. A
  /// new frame starts at time [t].
  DynamicFrame? pump(
    DynamicBg bg,
    String key,
    double t,
    int w,
    int h,
    int budgetMs,
  ) {
    final watch = Stopwatch()..start();
    final made = '$key|$w|$h';
    if (_made != made) {
      _renderer = DynamicRenderer(bg, w, h);
      _made = made;
      _open = false;
    }
    final r = _renderer!;
    if (!_open) {
      r.begin(t);
      _pixels = Uint8List(r.w * r.h * 4);
      _row = 0;
      _t = t;
      _open = true;
    }
    while (_row < r.h) {
      final end = math.min(_row + 6, r.h);
      r.rows(_row, end, _pixels!);
      _row = end;
      if (watch.elapsedMicroseconds >= budgetMs * 1000) break;
    }
    if (_row < r.h) return null;
    _open = false;
    return DynamicFrame(key, _t, r.w, r.h, _pixels!);
  }

  void dispose() {}
}
