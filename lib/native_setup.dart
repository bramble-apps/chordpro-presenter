// Start-up for the installed apps (Android, iOS, desktop): the library and
// media are saved as files in the app's own storage on the device, files
// are imported with the system file picker, and exports go out through the
// share sheet (save to Files / Drive, send by email…).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'browser.dart';
import 'native_cast.dart';
import 'native_display.dart';
import 'youtube_handle.dart';
import 'bramble_icons.dart';

const _mimes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'm4v': 'video/x-m4v',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/ogg',
  'flac': 'audio/flac',
};

String _mimeOf(String name) =>
    _mimes[name.split('.').last.toLowerCase()] ?? 'application/octet-stream';

/// Video backgrounds on desktop (Flutter's video player has no Linux /
/// Windows version of its own).
void _desktopVideo() {
  if (Platform.isLinux || Platform.isWindows) fvp.registerWith();
}

Future<void> setUpNativeIO() async {
  _desktopVideo();
  try {
    await NativeCast.init();
  } catch (e) {
    debugPrint('Cast unavailable: $e');
  }
  await _setUpClick();
  _setUpAppIcon();
  _setUpShare();
  // The embedded YouTube player needs a web view (phones only; desktop
  // apps open recordings in the browser).
  if (Platform.isAndroid || Platform.isIOS) {
    NativeIO.embed = (src) => _YouTubeEmbed(src: src);
    NativeIO.youTube = (id, handle) =>
        _YouTubePlayer(key: ValueKey(handle), id: id, handle: handle);
    // Song sites that turn away apps fetching their pages: the page in a
    // browser here, imported when the person taps Import.
    NativeIO.browseImport = (context, url, script) => Navigator.of(context)
        .push<String>(
          MaterialPageRoute(
            builder: (_) => _ImportBrowser(url: url, script: script),
          ),
        );
  }
  NativeIO.stopCast = () {
    NativeCast.stop();
    NativeDisplays.hide();
  };
  // Casting is Google Cast here, not the browser's.
  castSupported = false;
  isMac = Platform.isMacOS;

  await _useAppStorage();

  NativeIO.pickText = () async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Import songs');
    return [
      for (final f in files)
        (
          f.name,
          utf8.decode(await f.xFile.readAsBytes(), allowMalformed: true),
        ),
    ];
  };

  NativeIO.pickBinary = (extensions, multiple) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose files',
      type: FileType.custom,
      allowedExtensions: [for (final e in extensions) e.replaceFirst('.', '')],
    );
    return [
      for (final f in multiple ? files : files.take(1))
        (f.name, await f.xFile.readAsBytes()),
    ];
  };

  NativeIO.pickFonts = () async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Add fonts');
    return [
      for (final f in files)
        if (RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(f.name))
          (f.name, await f.xFile.readAsBytes()),
    ];
  };

  NativeIO.pickMedia =
      ({bool videos = true, bool audio = false, bool multiple = false}) async {
        final files = await FilePicker.pickFiles(
          dialogTitle: audio ? 'Add media' : 'Choose a background',
          type: audio
              ? FileType.custom
              : videos
              ? FileType.media
              : FileType.image,
          allowedExtensions: audio ? _mimes.keys.toList() : null,
        );
        return [
          for (final f in files)
            (f.name, _mimeOf(f.name), await f.xFile.readAsBytes()),
        ];
      };

  NativeIO.save = (name, bytes, mime) async {
    // Desktop: the system's "Save as" window (choose folder and name).
    if (!Platform.isAndroid && !Platform.isIOS) {
      await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: mime,
        dialogTitle: 'Save $name',
      );
      return;
    }
    // Phones: the share sheet (save to Files / Drive, send by email…).
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mime, name: name)],
        fileNameOverrides: [name],
        subject: name,
      ),
    );
  };

  NativeIO.openUrl = (url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  };

  NativeIO.fetch = (url) async {
    // Only full addresses (the web app's server routes don't exist here).
    if (!url.startsWith('http')) return null;
    final r = await http.get(Uri.parse(url));
    return r.statusCode == 200 ? Uint8List.fromList(r.bodyBytes) : null;
  };
}

/// The library and media live in the app's own storage on the device.
Future<void> _useAppStorage() async {
  // Phones: the app's private documents. Desktop: the app's own data
  // folder (on Linux ~/.local/share/…), not the person's Documents.
  final docs = Platform.isAndroid || Platform.isIOS
      ? await getApplicationDocumentsDirectory()
      : await getApplicationSupportDirectory();
  NativeIO.dataDir = '${docs.path}/bilingual_projector';
  await Directory(NativeIO.dataDir!).create(recursive: true);
}

/// The projector on an external display runs separately from the operator
/// but on the same device, so it reads pictures and videos straight from
/// the app's storage.
Future<void> setUpProjectorIO() async {
  _desktopVideo();
  try {
    await _useAppStorage();
  } catch (e) {
    debugPrint('Projector storage unavailable: $e');
  }
}

// ---- Metronome click ----

/// A short tone that fades out (like the web version's oscillator click),
/// as a 16-bit mono WAV.
Uint8List _clickWav({required double hz}) {
  const rate = 44100;
  const seconds = 0.06;
  final n = (rate * seconds).round();
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
    final t = i / rate;
    // Loud at once, gone after ~50 ms (exponential, as on the web).
    final gain = 0.6 * math.pow(0.001 / 0.6, t / 0.05);
    final v = (math.sin(2 * math.pi * hz * t) * gain * 32767).round();
    data.setInt16(44 + i * 2, v.clamp(-32768, 32767), Endian.little);
  }
  return data.buffer.asUint8List();
}

Future<void> _setUpClick() async {
  try {
    final dir = await getTemporaryDirectory();
    Future<AudioPool> pool(String name, double hz) async {
      final f = File('${dir.path}/$name.wav');
      await f.writeAsBytes(_clickWav(hz: hz));
      return AudioPool.create(
        source: DeviceFileSource(f.path),
        maxPlayers: 4,
        playerMode: PlayerMode.lowLatency,
      );
    }

    final beat = await pool('click', 1000);
    final accent = await pool('click_accent', 1600);
    NativeIO.click = (isAccent) => (isAccent ? accent : beat).start();
    // Chords played from the diagrams / chord buttons (one at a time).
    final chords = AudioPlayer();
    NativeIO.playWav = (wav) async {
      await chords.stop();
      await chords.play(BytesSource(wav, mimeType: 'audio/wav'));
    };
    NativeIO.stopWav = () => chords.stop();
    _setUpPads();
  } catch (e) {
    debugPrint('Metronome sound unavailable: $e');
  }
}

// ---- Pads: a looping WAV per key, crossfaded between two players ----

void _setUpShare() {
  if (!Platform.isAndroid) return;
  const share = MethodChannel('bp/share');
  NativeIO.listenShared = (onFiles, onText) {
    void deliver(Object? items) {
      if (items is! List) return;
      final files = <(String, Uint8List)>[];
      for (final item in items) {
        if (item is! Map) continue;
        final bytes = item['bytes'];
        if (bytes is Uint8List) {
          files.add(('${item['name'] ?? 'Shared file'}', bytes));
        } else if (item['text'] is String) {
          onText(item['text'] as String, item['subject'] as String?);
        }
      }
      if (files.isNotEmpty) onFiles(files);
    }

    share.setMethodCallHandler((call) async {
      if (call.method == 'shared') deliver(call.arguments);
    });
    // What was shared before the app was ready.
    share.invokeMethod<List<Object?>>('take').then(deliver);
  };
}

void _setUpAppIcon() {
  if (!Platform.isAndroid) return;
  const icon = MethodChannel('bp/appicon');
  NativeIO.appIcon = () => icon.invokeMethod<String>('get');
  NativeIO.setAppIcon = (name) => icon.invokeMethod('set', {'icon': name});
  NativeIO.phoneIconShape = () => icon.invokeMethod<String>('phoneShape');
}

void _setUpPads() {
  if (Platform.isAndroid) {
    // Android's media player pauses briefly each time a loop restarts, so
    // the app streams the loop itself (PadPlayer.kt).
    const pads = MethodChannel('bp/pads');
    NativeIO.padPlay = (wav, fade) =>
        pads.invokeMethod('play', {'wav': wav, 'fade': fade});
    NativeIO.padStop = (fade) => pads.invokeMethod('stop', {'fade': fade});
    NativeIO.padVolume = (v) => pads.invokeMethod('volume', {'volume': v});
    return;
  }
  final level = <AudioPlayer, double>{}; // each player's fade level
  var master = 0.7;
  var playing = <AudioPlayer>[];

  // Moves [p]'s level to [to] over [seconds] (equal power), then [done].
  void ramp(AudioPlayer p, double to, double seconds, [VoidCallback? done]) {
    final from = level[p] ?? 0;
    final steps = math.max(1, (seconds * 25).round());
    var i = 0;
    Timer.periodic(const Duration(milliseconds: 40), (t) {
      i++;
      final x = i / steps;
      final v = to > from
          ? from + (to - from) * math.sin(x * math.pi / 2)
          : to + (from - to) * math.cos(x * math.pi / 2);
      level[p] = v;
      p.setVolume(v * master);
      if (i >= steps) {
        t.cancel();
        done?.call();
      }
    });
  }

  void fadeOut(double seconds) {
    for (final p in playing) {
      ramp(p, 0, seconds, () {
        level.remove(p);
        p.dispose();
      });
    }
    playing = [];
  }

  NativeIO.padPlay = (wav, fade) async {
    fadeOut(fade);
    final p = AudioPlayer();
    level[p] = 0;
    playing.add(p);
    await p.setReleaseMode(ReleaseMode.loop);
    await p.play(BytesSource(wav, mimeType: 'audio/wav'), volume: 0);
    if (playing.contains(p)) ramp(p, 1, fade);
  };
  NativeIO.padStop = fadeOut;
  NativeIO.padVolume = (v) {
    master = v;
    for (final p in playing) {
      p.setVolume((level[p] ?? 0) * v);
    }
  };
}

// ---- YouTube in the floating player ----

/// The video's id in an embed / watch / youtu.be link.
String _videoId(String src) {
  final m = RegExp(
    r'(?:/embed/|[?&]v=|youtu\.be/|/shorts/|/live/)([A-Za-z0-9_-]{6,})',
  ).firstMatch(src);
  return m?.group(1) ?? '';
}

/// YouTube's embedded player in a web view, inside the floating window (so
/// it moves, resizes and rounds its corners with it, in any orientation;
/// no automatic full screen). It's loaded from a small page with a web
/// address, which YouTube needs for embeds in apps (otherwise: "video
/// player configuration error").
class _YouTubeEmbed extends StatefulWidget {
  final String src;
  const _YouTubeEmbed({required this.src});

  @override
  State<_YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<_YouTubeEmbed> {
  late final WebViewController _web = _create();

  WebViewController _create() {
    final id = _videoId(widget.src);
    final autoplay = widget.src.contains('autoplay=1') ? 1 : 0;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      // Start playing without a second tap.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    c.loadHtmlString(
      '<!doctype html><html><head>'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}'
      'iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>'
      '</head><body><iframe '
      'src="https://www.youtube-nocookie.com/embed/$id?autoplay=$autoplay'
      '&playsinline=1&fs=0&rel=0&modestbranding=1" '
      'allow="autoplay; encrypted-media; picture-in-picture" '
      'referrerpolicy="strict-origin-when-cross-origin"></iframe>'
      '</body></html>',
      baseUrl: 'https://bilingualprojector.app/',
    );
    return c;
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}

/// A YouTube player the app controls (play, pause, seek) through the
/// embed's own messages, relayed by a small page around it.
class _YouTubePlayer extends StatefulWidget {
  final String id;
  final YouTubeHandle handle;
  const _YouTubePlayer({super.key, required this.id, required this.handle});

  @override
  State<_YouTubePlayer> createState() => _YouTubePlayerState();
}

class _YouTubePlayerState extends State<_YouTubePlayer> {
  late final WebViewController _web = _create();

  WebViewController _create() {
    const origin = 'https://bilingualprojector.app';
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'Player',
        onMessageReceived: (m) => widget.handle.receive(m.message, jsonDecode),
      );
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    c.loadHtmlString(
      '<!doctype html><html><head>'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}'
      'iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>'
      '</head><body><iframe src="${youTubeEmbedUrl(widget.id, origin)}" '
      'allow="autoplay; encrypted-media" '
      'referrerpolicy="strict-origin-when-cross-origin"></iframe><script>'
      'var f=document.querySelector("iframe"),heard=false;'
      'function post(m){m.id=1;m.channel="widget";'
      'f.contentWindow.postMessage(JSON.stringify(m),"*");}'
      'var ask=setInterval(function(){if(heard){clearInterval(ask);return;}'
      'post({event:"listening"});},500);'
      'addEventListener("message",function(e){if(typeof e.data!=="string")'
      'return;heard=true;Player.postMessage(e.data);});'
      'function cmd(func,args){post({event:"command",func:func,args:args});}'
      '</script></body></html>',
      baseUrl: '$origin/',
    );
    widget.handle.send = (func, args) =>
        c.runJavaScript('cmd(${jsonEncode(func)},${jsonEncode(args)})');
    return c;
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: WebViewWidget(controller: _web));
}

/// A song site's page, as in a browser, with Import at the top: tapping it
/// reads the song off the page the person is looking at (see
/// [NativeIO.browseImport]).
class _ImportBrowser extends StatefulWidget {
  final String url;
  final String script;
  const _ImportBrowser({required this.url, required this.script});

  @override
  State<_ImportBrowser> createState() => _ImportBrowserState();
}

class _ImportBrowserState extends State<_ImportBrowser> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      ),
    )
    ..loadRequest(Uri.parse(widget.url));
  int _progress = 0;
  bool _reading = false;

  Future<void> _import() async {
    setState(() => _reading = true);
    try {
      var result = await _web.runJavaScriptReturningResult(widget.script);
      // Android hands a string back JSON-quoted.
      if (result is String && result.startsWith('"')) {
        result = jsonDecode(result) as String;
      }
      if (mounted) Navigator.of(context).pop('$result');
    } catch (_) {
      if (!mounted) return;
      setState(() => _reading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't read the song on this page.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Uri.parse(widget.url).host.replaceFirst('www.', '')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(BrambleIcons.downloadSimple),
              label: const Text('Import'),
              onPressed: _progress < 100 || _reading ? null : _import,
            ),
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _web),
    );
  }
}
