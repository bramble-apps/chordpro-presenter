// Browser-only helpers (projector window sync, fullscreen, file import/export).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'cast_feeder.dart';
import 'youtube_handle.dart';

/// Sends messages between the operator tab and projector windows.
/// All windows of the app on the same browser share this channel.
class SyncChannel {
  final web.BroadcastChannel _channel = web.BroadcastChannel(
    'bilingual_projector',
  );
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// Cast / presentation connections (Chromecast, presentation displays).
  /// They get every message too, since a cast screen can't hear the
  /// BroadcastChannel.
  final List<_PresentationConnection> _connections = [];

  SyncChannel() {
    _channel.onmessage = ((web.MessageEvent event) {
      _receive(event.data.dartify());
    }).toJS;
    _relayReady = _connectRelay();
  }

  /// This window's id on the network relay.
  final String _cid =
      '${DateTime.now().microsecondsSinceEpoch}'
      '${(DateTime.now().hashCode & 0xffff)}';
  late final Future<bool> _relayReady;

  /// Message ids already handled (a message can arrive both over the
  /// BroadcastChannel and the network relay).
  final _seen = <String>{};
  final _seenOrder = <String>[];
  var _counter = 0;

  /// When served by tools/serve.py, every screen on the network (phones,
  /// TVs, Chromecasts, any browser) is kept in sync through it.
  Future<bool> _connectRelay() async {
    try {
      final r = await web.window.fetch('relay/ping'.toJS).toDart;
      if (!r.ok) return false;
      relayInfo =
          jsonDecode((await r.text().toDart).toDart) as Map<String, dynamic>;
      final events = web.EventSource('relay/events?cid=$_cid');
      events.onmessage = ((web.MessageEvent e) => _receive(
        e.data.dartify(),
      )).toJS;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Relay details (projector link, Chromecast support), if available.
  static Map<String, dynamic>? relayInfo;

  void _receive(Object? data) {
    if (data is! String) return;
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) return;
    final mid = decoded['mid'];
    if (mid is String) {
      if (!_seen.add(mid)) return;
      _seenOrder.add(mid);
      if (_seenOrder.length > 500) _seen.remove(_seenOrder.removeAt(0));
    }
    _controller.add(decoded);
  }

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  /// Whether a cast / presentation connection is open.
  bool get casting => _connections.any((c) => c.state == 'connected');

  /// Only these message types go out (null: all). A window editing
  /// another computer's library sends library changes only.
  Set<String>? sendOnly;

  void send(Map<String, dynamic> message) {
    if (sendOnly != null && !sendOnly!.contains(message['type'])) return;
    final text = jsonEncode({...message, 'mid': '$_cid-${_counter++}'});
    _channel.postMessage(text.toJS);
    for (final c in _connections) {
      if (c.state == 'connected') c.send(text.toJS);
    }
    _relayReady.then((ok) {
      if (!ok) return;
      web.window.fetch(
        'relay/send'.toJS,
        web.RequestInit(
          method: 'POST',
          body: text.toJS,
          headers:
              {'X-Client': _cid, 'Content-Type': 'application/json'}.jsify()!
                  as web.HeadersInit,
        ),
      );
    });
  }

  void _attach(_PresentationConnection c) {
    _connections.add(c);
    c.onmessage = ((web.MessageEvent e) => _receive(e.data.dartify())).toJS;
    void gone(web.Event _) {
      _connections.remove(c);
      _controller.add({'type': 'castEnded'});
    }

    c.onclose = gone.toJS;
    c.onterminate = gone.toJS;
  }

  /// Projector side: listen to the cast connection(s) this page was
  /// started with, if it is a cast / presentation receiver.
  void listenAsReceiver() {
    final presentation = web.window.navigator.getProperty<JSObject?>(
      'presentation'.toJS,
    );
    final receiver = presentation?.getProperty<JSObject?>('receiver'.toJS);
    if (receiver == null) return;
    final list = receiver.getProperty<JSPromise<JSObject>>(
      'connectionList'.toJS,
    );
    list.toDart.then((l) {
      final conns = l.getProperty<JSArray<_PresentationConnection>>(
        'connections'.toJS,
      );
      for (final c in conns.toDart) {
        _attach(c);
      }
      l.setProperty(
        'onconnectionavailable'.toJS,
        ((JSObject e) => _attach(
          e.getProperty<_PresentationConnection>('connection'.toJS),
        )).toJS,
      );
    });
  }

  /// Operator side: shows the browser's cast picker (Chromecasts and
  /// presentation displays) and sends the projector view to the chosen
  /// one. Returns null on success, or a reason it didn't start.
  Future<String?> startCast() async {
    if (!castSupported) {
      return 'Casting needs Chrome, Edge or another Chromium browser.';
    }
    try {
      final url = Uri.base.resolve('?view=projector&cast=1').toString();
      final request = _PresentationRequest(url.toJS);
      final connection = await request.start().toDart;
      _attach(connection);
      return null;
    } catch (e) {
      final text = '$e';
      if (text.contains('NotAllowed') || text.contains('Abort')) {
        return 'Cast cancelled.';
      }
      if (text.contains('NotFound')) {
        return 'No Chromecast or presentation display found on this network.';
      }
      return 'Could not cast: $text';
    }
  }

  void stopCast() {
    for (final c in [..._connections]) {
      c.terminate();
    }
    _connections.clear();
  }
}

@JS('PresentationRequest')
extension type _PresentationRequest._(JSObject _) implements JSObject {
  external factory _PresentationRequest(JSString url);
  external JSPromise<_PresentationConnection> start();
}

extension type _PresentationConnection._(JSObject _) implements JSObject {
  external String get state;
  external void send(JSString data);
  external void terminate();
  external set onmessage(JSFunction? f);
  external set onclose(JSFunction? f);
  external set onterminate(JSFunction? f);
}

/// Casting (Presentation API) is available: Chrome, Edge, Brave, Opera and
/// Chrome on Android. Not Safari, Firefox or Zen.
bool get castSupported => globalContext.has('PresentationRequest');

/// A display attached to this computer (including an AirPlay display the
/// Mac uses as a separate screen).
class DisplayInfo {
  final String label;
  final bool primary;
  final int left, top, width, height;
  const DisplayInfo(
    this.label,
    this.primary,
    this.left,
    this.top,
    this.width,
    this.height,
  );
}

/// Whether the browser can list displays (Window Management API, Chromium).
bool get displayListSupported => web.window.has('getScreenDetails');

/// Lists displays (asks the user's permission the first time).
Future<List<DisplayInfo>> listDisplays() async {
  if (!displayListSupported) return [];
  try {
    final details = await web.window
        .callMethod<JSPromise<JSObject>>('getScreenDetails'.toJS)
        .toDart;
    final screens = details.getProperty<JSArray<JSObject>>('screens'.toJS);
    var i = 0;
    return [
      for (final s in screens.toDart)
        DisplayInfo(
          s.getProperty<JSString?>('label'.toJS)?.toDart.isNotEmpty == true
              ? s.getProperty<JSString>('label'.toJS).toDart
              : 'Display ${++i}',
          s.getProperty<JSBoolean>('isPrimary'.toJS).toDart,
          s.getProperty<JSNumber>('availLeft'.toJS).toDartInt,
          s.getProperty<JSNumber>('availTop'.toJS).toDartInt,
          s.getProperty<JSNumber>('availWidth'.toJS).toDartInt,
          s.getProperty<JSNumber>('availHeight'.toJS).toDartInt,
        ),
    ];
  } catch (_) {
    return [];
  }
}

/// Opens the projector window filling the given display.
void openProjectorOn(DisplayInfo d) {
  web.window.open(
    '?view=projector',
    'bilingual_projector_display',
    'popup=yes,left=${d.left},top=${d.top},width=${d.width},height=${d.height}',
  );
}

/// Running on a Mac (for AirPlay display instructions).
bool get isMac => web.window.navigator.platform.toLowerCase().contains('mac');

/// Which screen this browser window should show (`?view=projector`).
String currentView() => Uri.base.queryParameters['view'] ?? 'operator';

void openProjectorWindow() {
  web.window.open(
    '?view=projector',
    'bilingual_projector_display',
    'popup=yes,width=1280,height=800',
  );
}

void toggleFullscreen() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  } else {
    web.document.documentElement?.requestFullscreen();
  }
}

/// Saves [contents] as a file download.
void downloadTextFile(
  String filename,
  String contents, {
  String mime = 'application/json',
}) {
  final blob = web.Blob(
    [contents.toJS].toJS,
    web.BlobPropertyBag(type: '$mime;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}

/// Saves binary [bytes] (e.g. a PDF) as a file download.
void downloadBytes(String filename, Uint8List bytes, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}

/// Shows the browser's file picker. The (hidden) input is attached to the
/// page while open: Safari doesn't report the chosen file for an input that
/// isn't in the document. Completes with null if the user cancels.
/// The last picker stays on the page until the next one opens: some
/// browsers (Zen / newer Firefox) stop delivering a file's contents once
/// its input element is removed, so it must outlive the read.
web.HTMLInputElement? _lastPicker;

Future<web.FileList?> _openPicker(String accept, {bool multiple = false}) {
  _lastPicker?.remove();
  final completer = Completer<web.FileList?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = multiple
    ..accept = accept;
  input.style
    ..position = 'fixed'
    ..left = '-1000px'
    ..opacity = '0';
  web.document.body!.append(input);
  _lastPicker = input;
  void done(web.FileList? files) {
    if (!completer.isCompleted) completer.complete(files);
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      debugLog('change: ${input.files?.length} file(s)');
      done(input.files);
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      debugLog('cancel event');
      done(null);
    }).toJS,
  );
  debugLog('open picker accept=$accept ua=${web.window.navigator.userAgent}');
  input.click();
  return completer.future;
}

/// Opens the browser file picker and returns (name, text) for each file.
Future<List<(String, String)>> pickTextFiles() async => _readFiles(
  await _openPicker(
    '.json,.cho,.chopro,.chordpro,.crd,.pro,.txt,.show',
    multiple: true,
  ),
);

Future<List<(String, String)>> _readFiles(web.FileList? files) async {
  final results = <(String, String)>[];
  if (files == null) return results;
  for (var i = 0; i < files.length; i++) {
    final file = files.item(i);
    if (file == null) continue;
    final text = utf8.decode(await _fileBytes(file), allowMalformed: true);
    results.add((file.name, text));
  }
  return results;
}

/// Opens a link (e.g. a YouTube reference) in a new tab.
void openUrl(String url) => web.window.open(url, '_blank');

/// Durable key-value storage in IndexedDB (room for large libraries;
/// localStorage is capped at ~5 MB).
class KeyValueStore {
  static const _dbName = 'bilingual_projector';
  static const _store = 'kv';
  web.IDBDatabase? _db;

  Future<web.IDBDatabase> _open() async {
    if (_db != null) return _db!;
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_store);
    }).toJS;
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('Could not open browser storage'));
    }).toJS;
    return _db = await completer.future;
  }

  Future<String?> read(String key) async {
    final db = await _open();
    final request = db
        .transaction(_store.toJS)
        .objectStore(_store)
        .get(key.toJS);
    final completer = Completer<String?>();
    request.onsuccess = ((web.Event _) {
      final value = request.result.dartify();
      completer.complete(value is String ? value : null);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('Could not read browser storage'));
    }).toJS;
    final value = await completer.future;
    return value ?? _migrateFromLocalStorage(key);
  }

  Future<void> write(String key, String value) async {
    final db = await _open();
    final tx = db.transaction(_store.toJS, 'readwrite');
    tx.objectStore(_store).put(value.toJS, key.toJS);
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
    tx.onerror = ((web.Event _) {
      completer.completeError(StateError('Could not save to browser storage'));
    }).toJS;
    return completer.future;
  }

  /// Binary values (images, videos) stored as-is, without base64.
  Future<void> writeBytes(String key, Uint8List value) async {
    final db = await _open();
    final tx = db.transaction(_store.toJS, 'readwrite');
    tx.objectStore(_store).put(value.toJS, key.toJS);
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
    tx.onerror = ((web.Event _) {
      completer.completeError(StateError('Could not save media'));
    }).toJS;
    return completer.future;
  }

  Future<Uint8List?> readBytes(String key) async {
    final db = await _open();
    final request = db
        .transaction(_store.toJS)
        .objectStore(_store)
        .get(key.toJS);
    final completer = Completer<Uint8List?>();
    request.onsuccess = ((web.Event _) {
      final r = request.result;
      completer.complete(
        r != null && r.isA<JSUint8Array>() ? (r as JSUint8Array).toDart : null,
      );
    }).toJS;
    request.onerror = ((web.Event _) => completer.complete(null)).toJS;
    return completer.future;
  }

  Future<void> delete(String key) async {
    final db = await _open();
    final tx = db.transaction(_store.toJS, 'readwrite');
    tx.objectStore(_store).delete(key.toJS);
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
    tx.onerror = ((web.Event _) => completer.complete()).toJS;
    return completer.future;
  }

  /// Earlier versions saved via shared_preferences in localStorage.
  Future<String?> _migrateFromLocalStorage(String key) async {
    final legacyKey = 'flutter.$key';
    final legacy = web.window.localStorage.getItem(legacyKey);
    if (legacy == null) return null;
    final decoded = jsonDecode(legacy); // stored as a JSON-encoded string
    if (decoded is! String) return null;
    await write(key, decoded);
    web.window.localStorage.removeItem(legacyKey);
    return decoded;
  }
}

/// Opens the file picker for files ending in [extensions] (".pdf", ".zip"…);
/// returns (name, bytes) for each.
Future<List<(String, Uint8List)>> pickBinaryFiles(
  List<String> extensions, {
  bool multiple = true,
}) async =>
    _readBinary(await _openPicker(extensions.join(','), multiple: multiple));

/// Files dragged onto the window from the computer: [onDragging] while
/// they're over it (to show a drop target), [onDrop] with each file's
/// (name, bytes). Text or links dragged in are left to the browser.
void listenForDroppedFiles({
  required void Function(bool over) onDragging,
  required void Function(List<(String, Uint8List)> files) onDrop,
  void Function(String text, String? subject)? onText,
}) {
  // Files opened with the Linux app ("Open with", or a file given at
  // start): its window hands them over as {name, b64} in
  // window.__chordproPending and calls window.__chordproOpen().
  void takeOpened() {
    final pending = globalContext.getProperty<JSAny?>('__chordproPending'.toJS);
    if (pending == null || !pending.isA<JSArray>()) return;
    globalContext.setProperty('__chordproPending'.toJS, null);
    final files = <(String, Uint8List)>[];
    for (final f in (pending as JSArray<JSObject>).toDart) {
      // A remote control link (chordpropresenter://next).
      final url = f.getProperty<JSString?>('url'.toJS)?.toDart;
      if (url != null) {
        onText?.call(url, null);
        continue;
      }
      final name = f.getProperty<JSString?>('name'.toJS)?.toDart ?? 'File';
      final b64 = f.getProperty<JSString?>('b64'.toJS)?.toDart;
      if (b64 == null) continue;
      files.add((name, base64Decode(b64)));
    }
    if (files.isNotEmpty) onDrop(files);
  }

  globalContext.setProperty('__chordproOpen'.toJS, takeOpened.toJS);
  takeOpened();

  var depth = 0;
  bool hasFiles(web.DragEvent e) {
    final types = e.dataTransfer?.types.toDart ?? const <JSString>[];
    return types.any((t) => t.toDart == 'Files');
  }

  web.window.addEventListener(
    'dragenter',
    ((web.DragEvent e) {
      if (!hasFiles(e)) return;
      e.preventDefault();
      if (depth++ == 0) onDragging(true);
    }).toJS,
  );
  web.window.addEventListener(
    'dragover',
    ((web.DragEvent e) {
      if (!hasFiles(e)) return;
      // Without this the browser opens the file instead.
      e.preventDefault();
      e.dataTransfer?.dropEffect = 'copy';
    }).toJS,
  );
  web.window.addEventListener(
    'dragleave',
    ((web.DragEvent e) {
      if (!hasFiles(e)) return;
      if (--depth <= 0) {
        depth = 0;
        onDragging(false);
      }
    }).toJS,
  );
  web.window.addEventListener(
    'drop',
    ((web.DragEvent e) {
      if (!hasFiles(e)) return;
      e.preventDefault();
      depth = 0;
      onDragging(false);
      final files = e.dataTransfer?.files;
      _readBinary(files).then((read) {
        if (read.isNotEmpty) onDrop(read);
      });
    }).toJS,
  );
}

/// Opens the file picker for font files; returns (name, bytes) for each.
Future<List<(String, Uint8List)>> pickFontFiles() async =>
    _readBinary(await _openPicker('.ttf,.otf', multiple: true));

Future<List<(String, Uint8List)>> _readBinary(web.FileList? files) async {
  final results = <(String, Uint8List)>[];
  if (files == null) return results;
  for (var i = 0; i < files.length; i++) {
    final file = files.item(i);
    if (file == null) continue;
    results.add((file.name, await _fileBytes(file)));
  }
  return results;
}

web.AudioContext? _audio;

/// A short metronome tick (higher pitch on the first beat of the bar).
void playClick({bool accent = false}) {
  final ctx = _audio ??= web.AudioContext();
  if (ctx.state == 'suspended') ctx.resume();
  final osc = ctx.createOscillator();
  final gain = ctx.createGain();
  osc.frequency.value = accent ? 1600 : 1000;
  final t = ctx.currentTime;
  gain.gain
    ..setValueAtTime(0.6, t)
    ..exponentialRampToValueAtTime(0.001, t + 0.05);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(t);
  osc.stop(t + 0.06);
}

/// Plays mono [samples] (−1…1) at [rate] samples a second.
void playSound(Float32List samples, int rate) {
  final ctx = _audio ??= web.AudioContext();
  if (ctx.state == 'suspended') ctx.resume();
  final buffer = ctx.createBuffer(1, samples.length, rate);
  buffer.copyToChannel(samples.toJS, 0);
  final src = ctx.createBufferSource()..buffer = buffer;
  src.connect(ctx.destination);
  src.start();
  _lastSound = src;
}

web.AudioBufferSourceNode? _lastSound;

/// Stops what [playSound] is playing.
void stopSound() {
  try {
    _lastSound?.stop();
  } catch (_) {}
  _lastSound = null;
}

/// The launcher icon: Android only.
bool get canChooseAppIcon => false;
Future<String?> appIcon() async => null;
Future<void> setAppIcon(String icon) async {}
Future<String?> phoneIconShape() async => null;

// ---- Pads: one looping sound at a time, crossfaded ----

web.GainNode? _padBus;
final _padVoices = <(web.AudioBufferSourceNode, web.GainNode)>[];

JSArray<JSNumber> _curve(double from, double to) => [
  for (var i = 0; i <= 32; i++)
    // Equal power: sin in, cos out (no dip in the middle).
    (to > from
            ? from + (to - from) * math.sin(i / 32 * math.pi / 2)
            : to + (from - to) * math.cos(i / 32 * math.pi / 2))
        .toJS,
].toJS;

void _padFadeOut(web.AudioContext ctx, double fade) {
  final t = ctx.currentTime;
  for (final (src, gain) in _padVoices) {
    final now = gain.gain.value.toDouble();
    try {
      gain.gain.cancelAndHoldAtTime(t);
    } catch (_) {
      gain.gain.cancelScheduledValues(t);
    }
    gain.gain.setValueCurveAtTime(_curve(now, 0), t + 0.01, fade);
    src.stop(t + fade + 0.05);
  }
  _padVoices.clear();
}

/// Loops [left] / [right] (−1…1, [rate] a second), fading in over [fade]
/// seconds while what was playing fades out.
void padPlay(Float32List left, Float32List right, int rate, double fade) {
  final ctx = _audio ??= web.AudioContext();
  if (ctx.state == 'suspended') ctx.resume();
  final bus = _padBus ??= ctx.createGain()..connect(ctx.destination);
  fade = math.max(fade, 0.05);
  _padFadeOut(ctx, fade);
  final buffer = ctx.createBuffer(2, left.length, rate);
  buffer.copyToChannel(left.toJS, 0);
  buffer.copyToChannel(right.toJS, 1);
  final src = ctx.createBufferSource()
    ..buffer = buffer
    ..loop = true;
  final gain = ctx.createGain();
  final t = ctx.currentTime;
  gain.gain.setValueAtTime(0, t);
  gain.gain.setValueCurveAtTime(_curve(0, 1), t + 0.01, fade);
  src.connect(gain);
  gain.connect(bus);
  src.start(t);
  _padVoices.add((src, gain));
}

/// Fades the pad out over [fade] seconds.
void padStop(double fade) {
  final ctx = _audio;
  if (ctx != null) _padFadeOut(ctx, math.max(fade, 0.05));
}

/// The pad's volume (0–1).
void padVolume(double volume) {
  final ctx = _audio, bus = _padBus;
  if (ctx == null || bus == null) return;
  bus.gain.setTargetAtTime(volume, ctx.currentTime, 0.05);
}

/// Runs [callback] when this window closes (used by the projector window
/// to tell the operator it went away).
void onWindowClose(void Function() callback) {
  web.window.addEventListener('pagehide', ((web.Event _) => callback()).toJS);
}

/// Opens the file picker for images/videos; returns (name, mime, bytes).
Future<List<(String, String, Uint8List)>> pickMediaFiles({
  bool videos = true,
  bool audio = false,
  bool multiple = false,
}) async => _readMedia(
  await _openPicker(_mediaAccept(videos, audio), multiple: multiple),
);

String _mediaAccept(bool videos, bool audio) =>
    ['image/*', if (videos) 'video/*', if (audio) 'audio/*'].join(',');

const _displayableImages = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/bmp',
};

/// Images the app can't draw itself (e.g. HEIC photos from an iPhone or
/// the Mac Photos library) are converted to JPEG with the browser's own
/// decoder. Anything else is returned unchanged.
Future<(String, String, Uint8List)> _displayable(web.File f) async {
  final bytes = await _fileBytes(f);
  final lower = f.name.toLowerCase();
  final heicName = lower.endsWith('.heic') || lower.endsWith('.heif');
  final mime = f.type.isNotEmpty ? f.type : (heicName ? 'image/heic' : '');
  final isImage = mime.startsWith('image/') || heicName;
  if (!isImage || _displayableImages.contains(mime)) {
    return (f.name, mime, bytes);
  }
  // Browsers without a HEIC decoder (Firefox, Zen, Chrome): convert with
  // the bundled heic2any library first.
  if (heicName || mime == 'image/heic' || mime == 'image/heif') {
    final jpeg = await _heicToJpeg(f);
    if (jpeg != null) {
      final name = '${f.name.replaceAll(RegExp(r'\.[^.]+$'), '')}.jpg';
      return (name, 'image/jpeg', jpeg);
    }
  }
  final url = web.URL.createObjectURL(f);
  try {
    final img = web.HTMLImageElement()..src = url;
    await img.decode().toDart;
    final canvas = web.HTMLCanvasElement()
      ..width = img.naturalWidth
      ..height = img.naturalHeight;
    (canvas.getContext('2d')! as web.CanvasRenderingContext2D).drawImage(
      img,
      0,
      0,
    );
    final dataUrl = canvas.toDataURL('image/jpeg', 0.92.toJS);
    final jpeg = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
    final name = '${f.name.replaceAll(RegExp(r'\.[^.]+$'), '')}.jpg';
    return (name, 'image/jpeg', jpeg);
  } catch (_) {
    return (f.name, mime, bytes);
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

Future<List<(String, String, Uint8List)>> _readMedia(
  web.FileList? files,
) async {
  final out = <(String, String, Uint8List)>[];
  if (files == null) return out;
  for (var i = 0; i < files.length; i++) {
    final f = files.item(i);
    if (f == null) continue;
    debugLog('file name=${f.name} type=${f.type} size=${f.size}');
    try {
      final r = await _displayable(f);
      debugLog('ready name=${r.$1} mime=${r.$2} bytes=${r.$3.length}');
      out.add(r);
    } catch (e) {
      debugLog('read failed: $e');
      rethrow;
    }
  }
  return out;
}

/// A temporary browser URL for in-memory bytes (used to play videos).
String blobUrl(Uint8List bytes, String mime) => web.URL.createObjectURL(
  web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime)),
);

@JS('heic2any')
external JSPromise<JSAny> _heic2any(JSObject options);

Future<void>? _heicLibrary;

/// Loads web/js/heic2any.min.js (only when a HEIC photo is chosen).
Future<void> _loadHeicLibrary() => _heicLibrary ??= () {
  final done = Completer<void>();
  final script = web.HTMLScriptElement()..src = 'js/heic2any.min.js';
  script.onload = ((web.Event _) => done.complete()).toJS;
  script.onerror = ((web.Event _) {
    _heicLibrary = null;
    done.completeError(StateError('Could not load the HEIC converter'));
  }).toJS;
  web.document.head!.append(script);
  return done.future;
}();

/// HEIC/HEIF photo -> JPEG bytes, or null if it can't be converted.
Future<Uint8List?> _heicToJpeg(web.File f) async {
  try {
    await _loadHeicLibrary();
    final options = JSObject()
      ..setProperty('blob'.toJS, f)
      ..setProperty('toType'.toJS, 'image/jpeg'.toJS)
      ..setProperty('quality'.toJS, 0.9.toJS);
    var result = await _heic2any(options).toDart;
    // Multi-image HEIC files give a list; use the first picture.
    if (result.isA<JSArray>()) result = (result as JSArray).toDart.first!;
    final blob = result as web.Blob;
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  } catch (e) {
    web.console.warn('HEIC conversion failed: $e'.toJS);
    return null;
  }
}

/// Temporary diagnostics: records a step in the local server's log
/// (GET /__log?...). Nothing leaves this computer.
void debugLog(String message) {
  web.console.log('[debug] $message'.toJS);
  web.window.fetch('__log?${Uri.encodeQueryComponent(message)}'.toJS);
}

/// A file's bytes. Uses File.arrayBuffer(), falling back to the older
/// FileReader if that stalls (seen in Zen).
Future<Uint8List> _fileBytes(web.File f) async {
  try {
    final buffer = await f.arrayBuffer().toDart.timeout(
      const Duration(seconds: 8),
    );
    return buffer.toDart.asUint8List();
  } on TimeoutException {
    debugLog('arrayBuffer stalled; using FileReader');
    final done = Completer<Uint8List>();
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      done.complete((reader.result! as JSArrayBuffer).toDart.asUint8List());
    }).toJS;
    reader.onerror = ((web.Event _) {
      done.completeError(StateError('The browser could not read the file'));
    }).toJS;
    reader.readAsArrayBuffer(f);
    return done.future.timeout(const Duration(seconds: 20));
  }
}

// ---- Casting through the local server (any browser) ----

/// Relay details once known: {"url": projector link, "cast": bool}.
Future<Map<String, dynamic>?> relayDetails() async {
  for (var i = 0; i < 20 && SyncChannel.relayInfo == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return SyncChannel.relayInfo;
}

Future<Object?> _json(String url, {Map<String, dynamic>? post}) async {
  final r = await web.window
      .fetch(
        url.toJS,
        post == null
            ? web.RequestInit()
            : web.RequestInit(
                method: 'POST',
                body: jsonEncode(post).toJS,
                headers:
                    {'Content-Type': 'application/json'}.jsify()!
                        as web.HeadersInit,
              ),
      )
      .toDart;
  final body = jsonDecode((await r.text().toDart).toDart);
  if (body is Map && body['error'] != null) {
    throw StateError('${body['error']}');
  }
  return body;
}

/// A request to the app's local server (tools/serve.py): GET, or POST
/// with [post] as JSON. Throws its error message.
Future<Object?> localServer(String path, {Map<String, dynamic>? post}) =>
    _json(path, post: post);

/// Chromecasts / Google TVs the local server can see.
Future<List<Map<String, dynamic>>> castDevices() async =>
    ((await _json('cast/devices')) as List).cast<Map<String, dynamic>>();

// The TV opens the projector page itself (no pictures sent from here).
SlideCaster? get browserCaster => null;

/// Sends [bytes] to the app's local server (a backup to save); returns
/// its JSON answer.
Future<Object?> postBytesToServer(String path, Uint8List bytes) async {
  final r = await web.window
      .fetch(path.toJS, web.RequestInit(method: 'POST', body: bytes.toJS))
      .toDart;
  return jsonDecode((await r.text().toDart).toDart);
}

Future<void> castStart(String id) => _json('cast/start', post: {'id': id});

Future<void> castStop(String id) => _json('cast/stop', post: {'id': id});

/// Stops the projector on every Chromecast showing it.
Future<void> castStopAll() => _json('cast/stopall', post: const {});

/// Picks an image/video and uploads it to the local server (tools/serve.py).
/// The browser sends the file itself, so the page never has to read it
/// (some browser extensions make that hang). Returns (id, name, mime), or
/// null if cancelled.
Future<(String, String, String)?> pickMediaToServer({
  bool videos = true,
  bool audio = false,
}) async {
  final files = await _openPicker(_mediaAccept(videos, audio));
  final f = files?.item(0);
  if (f == null) return null;
  return _upload(f.name, f.type, f);
}

/// Several files at once, each uploaded to the local server as above.
Future<List<(String, String, String)>> pickMediaListToServer({
  bool audio = false,
}) async {
  final files = await _openPicker(_mediaAccept(true, audio), multiple: true);
  return [
    for (var i = 0; i < (files?.length ?? 0); i++)
      if (files!.item(i) case final f?) await _upload(f.name, f.type, f),
  ];
}

/// Uploads [bytes] (a dropped file) to the local server.
Future<(String, String, String)?> uploadMediaBytes(
  String name,
  String mime,
  Uint8List bytes,
) => _upload(name, mime, bytes.toJS);

Future<(String, String, String)> _upload(
  String name,
  String type,
  JSAny body,
) async {
  debugLog('upload name=$name type=$type');
  final url =
      'media/upload?name=${Uri.encodeQueryComponent(name)}'
      '&type=${Uri.encodeQueryComponent(type)}';
  final r = await web.window
      .fetch(url.toJS, web.RequestInit(method: 'POST', body: body))
      .toDart
      .timeout(const Duration(minutes: 5));
  if (!r.ok) throw StateError('Upload failed (${r.status})');
  final j = jsonDecode((await r.text().toDart).toDart) as Map<String, dynamic>;
  debugLog('uploaded ${j['id']} ${j['mime']} ${j['size']}');
  return (j['id'] as String, j['name'] as String, j['mime'] as String);
}

/// Downloads bytes from a URL (e.g. media stored on the local server).
Future<Uint8List?> fetchBytes(String url) async {
  try {
    final r = await web.window.fetch(url.toJS).toDart;
    if (!r.ok) return null;
    return (await r.arrayBuffer().toDart).toDart.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Reloads this page (to pick up a new version of the app).
void reloadPage() => web.window.location.reload();

/// Closes this window (only works for windows the app opened itself).
void closeWindow() => web.window.close();

/// Browsers only allow the microphone on a secure page (https or this
/// computer's own localhost).
bool get micAllowedHere => web.window.isSecureContext;

// ---- Microphone (web) ----

/// A running browser microphone; [stop] releases it.
class WebMic {
  final int sampleRate;
  final void Function() stop;
  WebMic(this.sampleRate, this.stop);
}

/// Opens the microphone with as few demands as possible (no echo / noise
/// processing, the device's own sample rate) and calls [onSamples] with
/// mono samples (−1…1). Throws the browser's error if it can't.
Future<WebMic> openWebMic(void Function(Float32List samples) onSamples) async {
  final devices = web.window.navigator.mediaDevices;
  web.MediaStream stream;
  try {
    stream = await devices
        .getUserMedia(
          web.MediaStreamConstraints(
            audio: {
              'echoCancellation': false,
              'noiseSuppression': false,
              'autoGainControl': false,
              // Chrome's newer voice filter: off too (raw, like a meter).
              'voiceIsolation': false,
            }.jsify()!,
          ),
        )
        .toDart;
  } catch (_) {
    // Some setups refuse any preferences: plain "a microphone, please".
    stream = await devices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
  }
  final context = web.AudioContext();
  final source = context.createMediaStreamSource(stream);
  final processor = context.createScriptProcessor(2048, 1, 1);
  processor.onaudioprocess = ((web.AudioProcessingEvent e) {
    onSamples(Float32List.fromList(e.inputBuffer.getChannelData(0).toDart));
  }).toJS;
  source.connect(processor);
  processor.connect(context.destination);
  return WebMic(context.sampleRate.round(), () {
    processor.onaudioprocess = null;
    source.disconnect();
    processor.disconnect();
    for (final t in stream.getTracks().toDart) {
      t.stop();
    }
    context.close();
  });
}

/// What the browser can see (for working out microphone problems).
Future<String> describeAudioInputs() async {
  try {
    final list = await web.window.navigator.mediaDevices
        .enumerateDevices()
        .toDart;
    final inputs = list.toDart.where((d) => d.kind == 'audioinput').toList();
    return '${inputs.length} microphone(s) visible'
        '${inputs.isEmpty ? '' : ': ${inputs.map((d) => d.label.isEmpty ? '(unnamed)' : d.label).join(', ')}'}';
  } catch (e) {
    return 'devices unknown ($e)';
  }
}

// ---- Embedded players (YouTube…) ----

final List<web.HTMLIFrameElement> _embeds = [];
var _embedCount = 0;

/// An embedded web page (a YouTube player…) as a widget. Create it once
/// per page and keep it: each call makes a new embed. [bottomRadius] rounds
/// its lower corners (the page draws it, so Flutter's clipping can't).
Widget webEmbed(String src, {double bottomRadius = 0}) {
  final type = 'bp-embed-${_embedCount++}';
  ui_web.platformViewRegistry.registerViewFactory(type, (int id) {
    final frame = web.HTMLIFrameElement()
      ..src = src
      ..allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen'
      ..allowFullscreen = true;
    frame.style
      ..border = '0'
      ..borderRadius = '0 0 ${bottomRadius}px ${bottomRadius}px'
      ..width = '100%'
      ..height = '100%';
    _embeds.add(frame);
    return frame;
  });
  return HtmlElementView(viewType: type);
}

/// A YouTube player controlled through [handle] (play, pause, seek) that
/// reports its progress back to it.
Widget youTubePlayer(String id, YouTubeHandle handle) {
  final type = 'bp-yt-${_embedCount++}';
  ui_web.platformViewRegistry.registerViewFactory(type, (int _) {
    final frame = web.HTMLIFrameElement()
      ..src = youTubeEmbedUrl(id, web.window.location.origin)
      ..allow = 'autoplay; encrypted-media';
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%'
      ..pointerEvents = 'none';
    void post(Map<String, Object?> m) => frame.contentWindow?.postMessage(
      jsonEncode({...m, 'id': type, 'channel': 'widget'}).toJS,
      '*'.toJS,
    );
    // Ask for progress until the player answers.
    var heard = false;
    final ask = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (heard) {
        t.cancel();
      } else {
        post({'event': 'listening'});
      }
    });
    final listener = ((web.MessageEvent e) {
      if (!e.origin.contains('youtube')) return;
      final data = e.data;
      if (data == null || !data.isA<JSString>()) return;
      heard = true;
      handle.receive((data as JSString).toDart, jsonDecode);
    }).toJS;
    web.window.addEventListener('message', listener);
    handle.send = (func, args) =>
        post({'event': 'command', 'func': func, 'args': args});
    handle.close = () {
      ask.cancel();
      web.window.removeEventListener('message', listener);
    };
    return frame;
  });
  return HtmlElementView(viewType: type);
}

/// Embeds swallow the mouse; while dragging their window, turn that off so
/// the drag isn't lost when the pointer passes over the video.
void setEmbedsInteractive(bool on) {
  _embeds.removeWhere((f) => !f.isConnected);
  for (final f in _embeds) {
    f.style.pointerEvents = on ? 'auto' : 'none';
  }
}

/// YouTube plays in the app's own floating player in browsers.
bool get youTubeInBrowser => false;

/// The Linux app (Electron) opens sites in a window of its own with an
/// Import button (desktop/electron/main.js); a plain browser can't.
bool get canImportFromBrowser =>
    web.window.navigator.userAgent.contains('Electron');

/// Opens [url] in the Linux app's import window (a real browser window the
/// person looks at); when they tap Import there, the page's song comes back
/// through the local server's relay. [script] is for the Android app (the
/// Linux app's window runs its own copy). Null: closed without importing.
Future<String?> importFromBrowser(
  BuildContext context,
  String url,
  String script,
) async {
  if (!canImportFromBrowser) return null;
  final id = 'imp${DateTime.now().microsecondsSinceEpoch}';
  final done = Completer<String?>();
  final events = web.EventSource('relay/events?cid=$id');
  events.onmessage = ((web.MessageEvent e) {
    final data = e.data.dartify();
    if (data is! String) return;
    final msg = jsonDecode(data);
    if (msg is! Map || msg['id'] != id) return;
    if (msg['type'] == 'browserImport' && !done.isCompleted) {
      done.complete(jsonEncode(msg['page']));
    } else if (msg['type'] == 'browserImportClosed' && !done.isCompleted) {
      done.complete(null);
    }
  }).toJS;
  // The id rides along after "#cpp-import=", for main.js to answer with.
  web.window.open('$url#cpp-import=$id', '_blank');
  try {
    return await done.future;
  } finally {
    events.close();
  }
}

/// The page behind the app's canvas in [argb], the app's own colour there:
/// a window being resized shows it for a frame at its edges before the app
/// has caught up, so it should blend in.
void setPageBackground(int argb) {
  final css = '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  (web.document.documentElement as web.HTMLElement?)?.style.backgroundColor =
      css;
  web.document.body?.style.backgroundColor = css;
}
