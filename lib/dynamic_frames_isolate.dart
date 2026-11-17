// Dynamic background frames in the installed apps: drawn on a thread of
// their own (see dynamic_frames.dart).
import 'dart:isolate';
import 'dart:typed_data';

import 'dynamic_bg.dart';

class DynamicFrames {
  final ReceivePort _from = ReceivePort();
  Isolate? _isolate;
  SendPort? _to;
  bool _busy = false;
  bool _disposed = false;
  DynamicFrame? _done;

  DynamicFrames() {
    _from.listen(_received);
    Isolate.spawn(_work, _from.sendPort).then((isolate) {
      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    });
  }

  void _received(Object? message) {
    if (message is SendPort) {
      _to = message;
    } else if (message is List) {
      _busy = false;
      _done = DynamicFrame(
        message[0] as String,
        message[1] as double,
        message[2] as int,
        message[3] as int,
        (message[4] as TransferableTypedData).materialize().asUint8List(),
      );
    }
  }

  /// Gives the newest finished frame of [bg] ([key]: its look) at [w] ×
  /// [h], if one came in since last asked, and asks for the next one, for
  /// time [t].
  DynamicFrame? pump(
    DynamicBg bg,
    String key,
    double t,
    int w,
    int h,
    int budgetMs,
  ) {
    final done = _done;
    _done = null;
    if (!_busy && _to != null) {
      _busy = true;
      _to!.send([key, bg.toJson(), t, w, h]);
    }
    return done != null && done.key == key && done.w == w && done.h == h
        ? done
        : null;
  }

  void dispose() {
    _disposed = true;
    _from.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}

/// The drawing thread: a frame for each request, in turn.
void _work(SendPort out) {
  final port = ReceivePort();
  out.send(port.sendPort);
  DynamicRenderer? renderer;
  String? made;
  port.listen((message) {
    final m = message as List;
    final key = m[0] as String, t = m[2] as double;
    final w = m[3] as int, h = m[4] as int;
    final want = '$key|$w|$h';
    if (made != want) {
      renderer = DynamicRenderer(DynamicBg.fromJson(m[1]), w, h);
      made = want;
    }
    final r = renderer!..begin(t);
    final pixels = Uint8List(r.w * r.h * 4);
    r.rows(0, r.h, pixels);
    out.send([key, t, r.w, r.h, TransferableTypedData.fromList([pixels])]);
  });
}
