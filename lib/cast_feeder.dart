// Casting with pictures, for every app (Android, and the web / Linux app
// through its local server): each slide is drawn here exactly like the
// projector, sent ahead of time to ChordPro Presenter's receiver on the
// TV (cast_receiver/), and shown with a tiny "show" message — the TV only
// cross-fades two pictures, which even a Chromecast does smoothly..

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'dynamic_bg.dart';
import 'media.dart';
import 'media_library.dart';
import 'projection.dart';
import 'state.dart';
import 'widgets/slide_capture.dart';

/// Sends slides to a TV over some connection (the Cast SDK on Android, our
/// Cast client on desktop, the local server in the web app).
class SlideCaster {
  /// Sends one JSON message to the receiver; true when it went through.
  final Future<bool> Function(String json) send;

  /// The TV being cast to (its name), or null.
  final ValueNotifier<String?> connected;

  /// Reports problems (shown under the device list on Android).
  final void Function(String step)? onStep;

  SlideCaster({required this.send, required this.connected, this.onStep});

  /// Cast messages are limited to 64 KB, so slides go in pieces.
  static const _pieceSize = 48000;

  /// Slides the TV has (this connection).
  final Set<String> _onTv = {};

  /// Waiting to be sent: id -> picture. The one about to be shown jumps
  /// the queue.
  final Map<String, Uint8List> _queue = {};
  String? _urgent;
  bool _sending = false;

  /// A fresh connection: the TV has none of the slides yet.
  void reset() {
    _onTv.clear();
    _queue.clear();
    _urgent = null;
  }

  bool has(String id) => _onTv.contains(id) || _queue.containsKey(id);

  /// Sends slide [id] to the TV in the background.
  void put(String id, Uint8List png) {
    if (connected.value == null || _onTv.contains(id)) return;
    _queue[id] = png;
    _pump();
  }

  /// Shows slide [id] (sent with [put]), fading over [fade] seconds. If it
  /// hasn't arrived yet, the TV shows it as soon as it does.
  Future<void> showSlide(String id, {double fade = 0.25}) async {
    if (connected.value == null) return;
    if (_queue.containsKey(id)) _urgent = id;
    await _send({'type': 'show', 'id': id, 't': fade});
  }

  /// Fades the TV to black (blackout).
  Future<void> clear() => _send({'type': 'clear'});

  /// Plays YouTube video [youtube] over the slides on the TV (null: stops).
  Future<void> media({String? youtube}) =>
      _send({'type': 'media', 'youtube': youtube});

  /// An animated wallpaper the TV draws itself behind the slides
  /// ([DynamicRenderer.castSpec]; null: none).
  Future<void> background(Map<String, Object>? spec) =>
      _send({'type': 'bg', 'spec': spec});

  Future<bool> _send(Map<String, Object?> message) async {
    try {
      final ok = await send(jsonEncode(message))
          .timeout(const Duration(seconds: 5));
      if (!ok) onStep?.call('A message did not reach the TV');
      return ok;
    } catch (e) {
      onStep?.call('Sending to the TV failed: $e');
      return false;
    }
  }

  Future<void> _pump() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty && connected.value != null) {
        final id = _urgent != null && _queue.containsKey(_urgent)
            ? _urgent!
            : _queue.keys.first;
        if (id == _urgent) _urgent = null;
        final png = _queue.remove(id)!;
        final data = base64Encode(png);
        final n = (data.length / _pieceSize).ceil();
        // All pieces at once: the connection keeps them in order.
        final results = await Future.wait([
          for (var i = 0; i < n; i++)
            _send({
              'type': 'put',
              'id': id,
              'i': i,
              'n': n,
              'mime': 'image/png',
              'data': data.substring(
                i * _pieceSize,
                ((i + 1) * _pieceSize).clamp(0, data.length),
              ),
            }),
        ]);
        if (results.every((r) => r)) _onTv.add(id);
      }
    } finally {
      _sending = false;
    }
  }
}

/// While casting, draws the current song's slides, sends them to the TV
/// ahead of time and shows the selected one (or black, for blackout).
class CastFeeder extends StatefulWidget {
  final PresenterModel model;

  /// Null: not casting with pictures here (the child is all there is).
  final SlideCaster? caster;
  final Widget child;

  const CastFeeder({
    super.key,
    required this.model,
    required this.caster,
    required this.child,
  });

  @override
  State<CastFeeder> createState() => _CastFeederState();
}

class _CastFeederState extends State<CastFeeder> {
  PresenterModel get model => widget.model;
  SlideCaster? get caster => widget.caster;
  bool get _on => caster?.connected.value != null;
  Timer? _debounce;

  /// What the slides look like (settings, view, key, font, text…): when it
  /// changes, every slide is drawn again.
  String? _look;

  /// Pictures of the current song's slides, by slide id.
  final Map<String, Uint8List> _drawn = {};
  bool _drawing = false;
  bool _warm = false; // backgrounds / fonts already loaded once
  String? _shown;

  /// The library media last sent ('' for none).
  String _liveSent = '';

  /// The wallpaper recipe the TV has (null: unknown, '' for none).
  String? _bgSent;

  /// An animated wallpaper the TV draws itself (the lyrics look only; the
  /// stage view is one picture).
  DynamicBg? get _tvWallpaper {
    final s = model.shownProjection;
    if (model.projection.view == ProjectionView.stage) return null;
    return s.bgType == BackgroundType.dynamic ? s.bgDynamic : null;
  }

  @override
  void initState() {
    super.initState();
    caster?.connected.addListener(_connected);
    model.addListener(_changed);
    model.inkVersion.addListener(_changed);
    model.selection.addListener(_selected);
  }

  @override
  void didUpdateWidget(CastFeeder old) {
    super.didUpdateWidget(old);
    if (old.caster != caster) {
      old.caster?.connected.removeListener(_connected);
      caster?.connected.addListener(_connected);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    caster?.connected.removeListener(_connected);
    model.removeListener(_changed);
    model.inkVersion.removeListener(_changed);
    model.selection.removeListener(_selected);
    super.dispose();
  }

  void _connected() {
    // A new connection starts empty: send everything again.
    _shown = null;
    _bgSent = null;
    _changed();
  }

  /// Tells the TV which wallpaper to draw, when that changed.
  Future<void> _sendWallpaper() async {
    final c = caster;
    if (c == null) return;
    final bg = _tvWallpaper;
    final spec = bg == null ? null : DynamicRenderer.castSpec(bg);
    final key = spec == null ? '' : jsonEncode(spec);
    if (key == _bgSent) return;
    _bgSent = key;
    await c.background(spec);
  }

  String _lookNow() => jsonEncode([
    model.shownProjection.toJson(),
    model.projectorFont,
    model.projectorSize.width,
    model.projectorSize.height,
    model.stageData?.toJson(),
    model.slides,
    model.inkVersion.value,
  ]);

  String _id(int i) => '${_look.hashCode.toRadixString(36)}-$i';

  int get _index => model.slides.isEmpty
      ? 0
      : model.selection.value.clamp(0, model.slides.length - 1);

  /// The slide changed: show it right away (it's usually on the TV already).
  void _selected() {
    if (_on) _show();
  }

  /// Anything else changed: check whether the slides look different.
  void _changed() {
    if (!_on) {
      _shown = null;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final look = _lookNow();
      if (look != _look) {
        _look = look;
        _drawn.clear();
        _shown = null;
        _sendWallpaper();
      }
      _show();
      _drawAll();
    });
  }

  Future<void> _show() async {
    final c = caster;
    if (c == null) return;
    // From the media library: YouTube plays on the TV itself, a picture
    // is sent like a slide. (Video and audio files stay on this device.)
    final live = model.live;
    final liveKey = live == null ? '' : '${live.started}';
    if (liveKey != _liveSent) {
      _liveSent = liveKey;
      await c.media(youtube: live?.item.youtube);
    }
    final picture = live?.item.kind == MediaKind.image ? live!.item.file : null;
    if (picture != null && !model.blackout) {
      final id = 'live-$liveKey';
      if (_shown == id) return;
      _shown = id;
      final bytes = await MediaStore.bytes(picture);
      if (bytes == null || bytes.isEmpty) return;
      c.put(id, bytes);
      await c.showSlide(id, fade: model.transitionDuration);
      return;
    }
    if (model.blackout || model.slides.isEmpty) {
      if (_shown != '<black>') {
        _shown = '<black>';
        await c.clear();
      }
      return;
    }
    _look ??= _lookNow();
    if (_bgSent == null) await _sendWallpaper();
    final id = _id(_index);
    if (id == _shown) return;
    _shown = id;
    final png = _drawn[id];
    if (png != null) {
      c.put(id, png); // no-op if the TV has it
    } else {
      _drawAll(); // draws this one first
    }
    await c.showSlide(id, fade: model.transitionDuration);
  }

  /// Draws every slide of the song (the current one first, then the ones
  /// next to it) and sends them to the TV in the background.
  Future<void> _drawAll() async {
    final c = caster;
    if (c == null || _drawing || !mounted || !_on) return;
    _drawing = true;
    try {
      while (mounted && _on) {
        final n = model.slides.length;
        if (n == 0) break;
        final look = _look ??= _lookNow();
        final current = _index;
        final order = [
          for (var d = 0; d < n; d++)
            for (final i in d == 0 ? [current] : [current + d, current - d])
              if (i >= 0 && i < n) i,
        ];
        final todo = order.where((i) => !_drawn.containsKey(_id(i))).toList();
        if (todo.isEmpty) break;
        // The slide on screen alone (quick), then the rest in batches.
        final batch = todo.first == current ? [current] : todo.take(4).toList();
        if (!mounted) break;
        final wait = Duration(milliseconds: _warm ? 60 : 500);
        final stage = model.projection.view == ProjectionView.stage;
        // Stage view is the whole chord sheet with the slide highlighted;
        // the lyrics look is just the slide.
        final List<Uint8List> images = stage
            ? await captureStageSlides(
                context,
                slides: model.slides,
                indices: batch,
                settings: model.shownProjection,
                font: model.projectorFont,
                projectorSize: model.projectorSize,
                stage: model.stageData,
                firstWait: wait,
                ink: model.slideInk,
              )
            : [
                for (final image in await captureSlides(
                  context,
                  slides: [for (final i in batch) model.slides[i]],
                  settings: model.shownProjection,
                  font: model.projectorFont,
                  projectorSize: model.projectorSize,
                  stage: model.stageData,
                  width: 1280,
                  firstWait: wait,
                  // Over a wallpaper the TV draws: see-through.
                  noBackground: _tvWallpaper != null,
                  ink: [for (final i in batch) model.slideInk[i]],
                ))
                  image.png,
              ];
        _warm = true;
        // Settings changed while drawing: start over with the new look.
        if (look != _look) continue;
        for (var k = 0; k < images.length && k < batch.length; k++) {
          if (images[k].isEmpty) continue;
          final id = _id(batch[k]);
          _drawn[id] = images[k];
          c.put(id, images[k]);
        }
      }
    } finally {
      _drawing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
