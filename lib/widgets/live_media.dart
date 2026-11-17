import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../browser.dart';
import '../media.dart';
import '../media_library.dart';
import '../youtube_handle.dart';

/// Between the operator's player controls and the screen playing:
/// [seeks] (seconds) come in, [report] sends the progress back.
class LiveControl {
  static final seeks = StreamController<double>.broadcast();
  static void Function(double position, double duration, bool playing)? report;
}

/// A media library item on the projector: full screen (black around it)
/// or over the lyrics. Videos and audio play once with sound; YouTube in
/// its own player. The operator's [preview] stays silent and shows
/// YouTube as its still picture.
class LiveMediaView extends StatefulWidget {
  final LiveMedia live;
  final bool preview;

  const LiveMediaView({super.key, required this.live, this.preview = false});

  @override
  State<LiveMediaView> createState() => _LiveMediaViewState();
}

class _LiveMediaViewState extends State<LiveMediaView> {
  Uint8List? _image;
  VideoPlayerController? _video;
  Widget? _embed;
  final _yt = YouTubeHandle();
  StreamSubscription<double>? _seeks;
  DateTime _reported = DateTime(0);

  MediaItem get item => widget.live.item;

  @override
  void initState() {
    super.initState();
    _seeks = LiveControl.seeks.stream.listen(_seek);
    // The screen with the sound tells the operator how far along it is.
    if (!widget.preview) {
      _yt.onInfo = (pos, dur, playing) =>
          LiveControl.report?.call(pos, dur, playing);
    }
    _load();
  }

  @override
  void didUpdateWidget(LiveMediaView old) {
    super.didUpdateWidget(old);
    if (old.live.playing == widget.live.playing) return;
    final v = _video;
    if (v != null) widget.live.playing ? v.play() : v.pause();
    widget.live.playing ? _yt.play() : _yt.pause();
  }

  void _seek(double seconds) {
    _video?.seekTo(Duration(milliseconds: (seconds * 1000).round()));
    _yt.seekTo(seconds);
  }

  /// Video / audio progress, a few times a second.
  void _progress() {
    final v = _video?.value;
    if (v == null || widget.preview || !v.isInitialized) return;
    final now = DateTime.now();
    if (now.difference(_reported).inMilliseconds < 400 && v.isPlaying) return;
    _reported = now;
    LiveControl.report?.call(
      v.position.inMilliseconds / 1000,
      v.duration.inMilliseconds / 1000,
      v.isPlaying,
    );
  }

  Future<void> _load() async {
    final ref = item.file;
    switch (item.kind) {
      case MediaKind.image:
        if (ref == null) {
          if (item.url.isNotEmpty) setState(() {}); // network picture
          return;
        }
        final b = await MediaStore.bytes(ref);
        if (mounted && b != null && b.isNotEmpty) setState(() => _image = b);
      case MediaKind.video || MediaKind.audio:
        final url = ref == null ? item.url : await MediaStore.url(ref);
        if (url == null || url.isEmpty || !mounted) return;
        final c = VideoPlayerController.networkUrl(Uri.parse(url));
        try {
          await c.initialize();
          await c.setVolume(widget.preview ? 0 : 1);
          if (widget.live.playing) await c.play();
        } catch (e) {
          debugPrint('Media failed: $e');
        }
        if (!mounted) {
          c.dispose();
          return;
        }
        c.addListener(_progress);
        setState(() => _video = c);
      case MediaKind.youtube:
        final id = item.youtube;
        if (id == null || widget.preview) return;
        setState(() => _embed = youTubePlayer(id, _yt));
      case MediaKind.link:
        break;
    }
  }

  @override
  void dispose() {
    _seeks?.cancel();
    _yt.dispose();
    _video?.dispose();
    super.dispose();
  }

  Widget _content() {
    final video = _video;
    if (video != null && video.value.isInitialized) {
      if (item.kind == MediaKind.audio || video.value.size.isEmpty) {
        return widget.preview ? _badge(Icons.music_note) : const SizedBox();
      }
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: video.value.size.width,
          height: video.value.size.height,
          child: VideoPlayer(video),
        ),
      );
    }
    if (_image != null) {
      return Image.memory(_image!, fit: BoxFit.contain, gaplessPlayback: true);
    }
    if (item.kind == MediaKind.image && item.file == null) {
      return Image.network(pictureSource(item.url), fit: BoxFit.contain);
    }
    if (_embed != null) return _embed!;
    if (item.kind == MediaKind.youtube && item.thumbnailUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            pictureSource(item.thumbnailUrl!),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
          Center(child: _badge(Icons.smart_display)),
        ],
      );
    }
    return const SizedBox();
  }

  /// A big icon with the item's name (what the preview shows for sound).
  Widget _badge(IconData icon) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 140),
          Text(
            item.name,
            style: const TextStyle(color: Colors.white, fontSize: 48),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Sound only: the lyrics stay up.
    final soundOnly = item.kind == MediaKind.audio;
    final content = IgnorePointer(ignoring: widget.preview, child: _content());
    if (widget.live.mode == LiveMode.overlay || soundOnly) {
      return IgnorePointer(child: content);
    }
    return ColoredBox(color: Colors.black, child: content);
  }
}
