// Non-web stand-ins for browser_web.dart: widget tests use them as they
// are; the installed apps plug real storage and files in (see NativeIO).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'cast_feeder.dart';
import 'youtube_handle.dart';

/// The installed apps (Android, iOS, desktop) plug their own file
/// storage, pickers and sharing in here at start-up (see native_setup.dart).
/// Unset, as in tests, everything stays in memory.
class NativeIO {
  /// Where the library and media are kept (the app's own storage).
  static String? dataDir;
  static Future<List<(String, String)>> Function()? pickText;
  static Future<List<(String, Uint8List)>> Function()? pickFonts;
  static Future<List<(String, Uint8List)>> Function(
    List<String> extensions,
    bool multiple,
  )?
  pickBinary;
  static Future<List<(String, String, Uint8List)>> Function({
    bool videos,
    bool audio,
    bool multiple,
  })?
  pickMedia;
  static Future<void> Function(String name, Uint8List bytes, String mime)? save;
  static void Function(String url)? openUrl;
  static Future<Uint8List?> Function(String url)? fetch;

  /// The metronome's click (accent: the bar's first beat).
  static void Function(bool accent)? click;

  /// Plays a sound (a WAV file's bytes): a chord being played.
  static void Function(Uint8List wav)? playWav;
  static void Function()? stopWav;

  /// The pads: loop a WAV (crossfading over the seconds given), stop
  /// (fading), and the volume.
  static void Function(Uint8List wav, double fade)? padPlay;
  static void Function(double fade)? padStop;
  static void Function(double volume)? padVolume;

  /// The launcher icon (Android): the one in use, choose one, and the
  /// phone's icon shape ('circle', 'squircle', 'rounded', 'square').
  static Future<String?> Function()? appIcon;
  static Future<void> Function(String icon)? setAppIcon;
  static Future<String?> Function()? phoneIconShape;

  /// Things shared to the app or opened with it (Android): files and text.
  static void Function(
    void Function(List<(String, Uint8List)> files) onFiles,
    void Function(String text, String? subject) onText,
  )?
  listenShared;

  /// A site's page in a browser inside the app, for the person to look
  /// at; when they tap Import, [script] runs on the page and its result
  /// comes back (null: closed without importing).
  static Future<String?> Function(
    BuildContext context,
    String url,
    String script,
  )?
  browseImport;

  /// A web page / video inside the app (the YouTube player).
  static Widget Function(String src)? embed;
  static Widget Function(String id, YouTubeHandle handle)? youTube;

  /// Casting was stopped from the app (stop projecting).
  static void Function()? stopCast;

  /// Projector messages, also for an external display (Android).
  static void Function(Map<String, dynamic> message)? onSend;

  /// YouTube recordings open in the browser (no embedded web player).
  static bool youTubeInBrowser = false;

  // Desktop apps: the projector is a window of the app.
  static void Function()? openProjector;
  static void Function()? toggleFullscreen;
  static void Function()? closeWindow;
  static void Function(void Function() callback)? onWindowClose;
}

class SyncChannel {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sent = [];

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  /// Only these message types go out (null: all). A window editing
  /// another computer's library sends library changes only.
  Set<String>? sendOnly;

  void send(Map<String, dynamic> message) {
    if (sendOnly != null && !sendOnly!.contains(message['type'])) return;
    sent.add(message);
    // Tests read the latest; a long-running app mustn't keep them all.
    if (sent.length > 500) sent.removeRange(0, sent.length - 200);
    NativeIO.onSend?.call(message);
  }

  bool casting = false;

  void listenAsReceiver() {}

  Future<String?> startCast() async {
    casting = true;
    return null;
  }

  void stopCast() {
    casting = false;
    NativeIO.stopCast?.call();
  }

  /// Simulates a message from another window (tests).
  void receive(Map<String, dynamic> message) => _controller.add(message);
}

String currentView() => 'operator';

/// Casting with pictures through the local server (web app only).
SlideCaster? get browserCaster => null;

/// YouTube recordings open in the browser (desktop app: no web player).
bool get youTubeInBrowser => NativeIO.youTubeInBrowser;

void openProjectorWindow() => NativeIO.openProjector?.call();

void toggleFullscreen() => NativeIO.toggleFullscreen?.call();

/// Last download (for tests).
(String, int)? lastDownload;

void downloadTextFile(
  String filename,
  String contents, {
  String mime = 'application/json',
}) {
  lastDownload = (filename, contents.length);
  NativeIO.save?.call(
    filename,
    Uint8List.fromList(utf8.encode(contents)),
    mime,
  );
}

void downloadBytes(String filename, Uint8List bytes, String mime) {
  lastDownload = (filename, bytes.length);
  NativeIO.save?.call(filename, bytes, mime);
}

Future<List<(String, String)>> pickTextFiles() async =>
    await NativeIO.pickText?.call() ?? [];

/// Files ending in [extensions] (".pdf", ".zip"…): (name, bytes) each.
Future<List<(String, Uint8List)>> pickBinaryFiles(
  List<String> extensions, {
  bool multiple = true,
}) async => await NativeIO.pickBinary?.call(extensions, multiple) ?? [];

/// Last link opened in a new tab (for tests).
String? lastOpenedUrl;

void openUrl(String url) {
  lastOpenedUrl = url;
  NativeIO.openUrl?.call(url);
}

/// In-memory storage for tests.
/// Saved data: in memory (tests), or as files in [NativeIO.dataDir] on
/// the device (one file per key, written to a temporary file first and
/// then renamed, so a crash mid-save never leaves half a library).
class KeyValueStore {
  static final Map<String, String> memory = {};
  static final Map<String, Uint8List> bytes = {};

  File? _file(String key, String ext) {
    final dir = NativeIO.dataDir;
    if (dir == null) return null;
    final name = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('$dir/store/$name.$ext');
  }

  /// Writes to the same file, one after another (the newest wins).
  static final Map<String, Future<void>> _writing = {};
  static int _tmpCount = 0;

  Future<void> _put(File f, List<int> data) {
    final previous = _writing[f.path] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.${_tmpCount++}.tmp');
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(f.path);
    });
    _writing[f.path] = next;
    return next.whenComplete(() {
      if (identical(_writing[f.path], next)) _writing.remove(f.path);
    });
  }

  Future<String?> read(String key) async {
    final f = _file(key, 'txt');
    if (f == null) return memory[key];
    return await f.exists() ? f.readAsString() : null;
  }

  Future<void> write(String key, String value) async {
    final f = _file(key, 'txt');
    if (f == null) {
      memory[key] = value;
      return;
    }
    await _put(f, utf8.encode(value));
  }

  Future<void> delete(String key) async {
    memory.remove(key);
    bytes.remove(key);
    for (final ext in ['txt', 'bin']) {
      final f = _file(key, ext);
      if (f != null && await f.exists()) await f.delete();
    }
  }

  Future<void> writeBytes(String key, Uint8List value) async {
    final f = _file(key, 'bin');
    if (f == null) {
      bytes[key] = value;
      return;
    }
    await _put(f, value);
  }

  Future<Uint8List?> readBytes(String key) async {
    final f = _file(key, 'bin');
    if (f == null) return bytes[key];
    return await f.exists() ? f.readAsBytes() : null;
  }
}

Future<List<(String, Uint8List)>> pickFontFiles() async =>
    await NativeIO.pickFonts?.call() ?? [];

/// Number of metronome clicks played (for tests).
int clicksPlayed = 0;

void playClick({bool accent = false}) {
  clicksPlayed++;
  NativeIO.click?.call(accent);
}

/// Sounds played (for tests).
int soundsPlayed = 0;

/// Plays mono [samples] (−1…1) at [rate] samples a second.
void playSound(Float32List samples, int rate) {
  soundsPlayed++;
  final play = NativeIO.playWav;
  if (play != null) play(wavBytes(samples, rate));
}

/// Stops what [playSound] is playing.
void stopSound() => NativeIO.stopWav?.call();

/// The launcher icon (Android only; see NativeIO.appIcon).
bool get canChooseAppIcon => NativeIO.setAppIcon != null;
Future<String?> appIcon() async => NativeIO.appIcon?.call();
Future<void> setAppIcon(String icon) async => NativeIO.setAppIcon?.call(icon);
Future<String?> phoneIconShape() async => NativeIO.phoneIconShape?.call();

/// Files dropped on the window, shared to the app or opened with it
/// (Android: "Share →" and "Open with"; [onText] gets shared text and its
/// subject). Tests call [debugDropFiles] / [debugShareText].
void listenForDroppedFiles({
  required void Function(bool over) onDragging,
  required void Function(List<(String, Uint8List)> files) onDrop,
  void Function(String text, String? subject)? onText,
}) {
  _dropHandler = onDrop;
  _textHandler = onText;
  NativeIO.listenShared?.call(onDrop, onText ?? (_, _) {});
}

void Function(String text, String? subject)? _textHandler;

/// Shares [text] to the app as if from another app (tests).
void debugShareText(String text, [String? subject]) =>
    _textHandler?.call(text, subject);

void Function(List<(String, Uint8List)> files)? _dropHandler;

/// Drops [files] as if dragged onto the window (tests).
void debugDropFiles(List<(String, Uint8List)> files) =>
    _dropHandler?.call(files);

/// The pad calls made (for tests): `play <frames>`, `stop`, `volume <v>`.
final List<String> padLog = [];

/// Loops [left] / [right] (−1…1, [rate] a second), fading in over [fade]
/// seconds while what was playing fades out.
void padPlay(Float32List left, Float32List right, int rate, double fade) {
  padLog.add('play ${left.length}');
  NativeIO.padPlay?.call(wavStereo(left, right, rate), fade);
}

/// Fades the pad out over [fade] seconds.
void padStop(double fade) {
  padLog.add('stop');
  NativeIO.padStop?.call(fade);
}

/// The pad's volume (0–1).
void padVolume(double volume) {
  padLog.add('volume ${volume.toStringAsFixed(2)}');
  NativeIO.padVolume?.call(volume);
}

void onWindowClose(void Function() callback) =>
    NativeIO.onWindowClose?.call(callback);

/// Files the next media picker call returns (tests).
List<(String, String, Uint8List)> nextPickedMedia = [];

Future<List<(String, String, Uint8List)>> pickMediaFiles({
  bool videos = true,
  bool audio = false,
  bool multiple = false,
}) async {
  final out = nextPickedMedia;
  nextPickedMedia = [];
  if (out.isEmpty && NativeIO.pickMedia != null) {
    return NativeIO.pickMedia!(
      videos: videos,
      audio: audio,
      multiple: multiple,
    );
  }
  return out;
}

String blobUrl(Uint8List bytes, String mime) => 'blob:test';

void debugLog(String message) {}

bool castSupported = true;

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

bool displayListSupported = false;

Future<List<DisplayInfo>> listDisplays() async => [];

void openProjectorOn(DisplayInfo d) {}

bool isMac = true;

Future<Map<String, dynamic>?> relayDetails() async => null;

/// A request to the app's local server (none outside the web app).
Future<Object?> localServer(String path, {Map<String, dynamic>? post}) =>
    throw UnsupportedError('No local server here');

Future<Object?> postBytesToServer(String path, Uint8List bytes) =>
    throw UnsupportedError('No local server here');

Future<List<Map<String, dynamic>>> castDevices() async => [];

Future<void> castStart(String id) async {}

Future<void> castStop(String id) async {}

int castStopAlls = 0;

Future<void> castStopAll() async => castStopAlls++;

Future<(String, String, String)?> pickMediaToServer({
  bool videos = true,
  bool audio = false,
}) async => null;

Future<List<(String, String, String)>> pickMediaListToServer({
  bool audio = false,
}) async => const [];

Future<(String, String, String)?> uploadMediaBytes(
  String name,
  String mime,
  Uint8List bytes,
) async => null;

Future<Uint8List?> fetchBytes(String url) async => NativeIO.fetch?.call(url);

int reloads = 0;

void reloadPage() => reloads++;

int closes = 0;

void closeWindow() {
  closes++;
  NativeIO.closeWindow?.call();
}

bool get micAllowedHere => true;

class WebMic {
  final int sampleRate;
  final void Function() stop;
  WebMic(this.sampleRate, this.stop);
}

Future<WebMic> openWebMic(void Function(Float32List samples) onSamples) =>
    throw UnsupportedError('Only in a browser');

Future<String> describeAudioInputs() async => 'not a browser';

/// Last embed shown (for tests).
String? lastEmbed;

Widget webEmbed(String src, {double bottomRadius = 0}) {
  lastEmbed = src;
  return NativeIO.embed?.call(src) ??
      const ColoredBox(color: Color(0xFF000000));
}

/// A YouTube player controlled through [handle] (see youtube_handle.dart).
Widget youTubePlayer(String id, YouTubeHandle handle) =>
    NativeIO.youTube?.call(id, handle) ??
    const ColoredBox(color: Color(0xFF000000));

void setEmbedsInteractive(bool on) {}

/// A WAV file (16-bit mono) of [samples] (−1…1) at [rate].
Uint8List wavBytes(Float32List samples, int rate) {
  final n = samples.length;
  final data = ByteData(44 + n * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A WAV file (16-bit stereo) of [left] / [right] (−1…1) at [rate].
Uint8List wavStereo(Float32List left, Float32List right, int rate) {
  final n = left.length;
  final data = ByteData(44 + n * 4);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + n * 4, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 2, Endian.little) // stereo
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 4, Endian.little)
    ..setUint16(32, 4, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, n * 4, Endian.little);
  for (var i = 0; i < n; i++) {
    data
      ..setInt16(
        44 + i * 4,
        (left[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      )
      ..setInt16(
        46 + i * 4,
        (right[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
  }
  return data.buffer.asUint8List();
}

/// Whether a site's page can be opened in a browser inside the app, for
/// importing from (sites that turn away apps fetching pages themselves).
bool get canImportFromBrowser => NativeIO.browseImport != null;

/// Opens [url] in the in-app browser; when the person taps Import, the
/// result of [script] on the page (null: closed without importing).
Future<String?> importFromBrowser(
  BuildContext context,
  String url,
  String script,
) async => NativeIO.browseImport?.call(context, url, script);

/// (Web only: the page behind the app's canvas.)
void setPageBackground(int argb) {}
