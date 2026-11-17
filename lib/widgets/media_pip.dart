import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../browser.dart';
import '../themes.dart';
import 'floating_panel.dart';
import '../eink.dart';

/// The YouTube video id in a link (watch, youtu.be, shorts, embed,
/// music…), or null.
String? youtubeId(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return null;
  final host = u.host.replaceFirst(RegExp(r'^(www|m|music)\.'), '');
  if (host == 'youtu.be') {
    return u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
  }
  if (host != 'youtube.com' && host != 'youtube-nocookie.com') return null;
  final v = u.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;
  final seg = u.pathSegments;
  if (seg.length >= 2 && ['shorts', 'embed', 'live', 'v'].contains(seg[0])) {
    return seg[1];
  }
  return null;
}

/// A link straight to an audio / video file the app can play itself.
bool isMediaFile(String url) => RegExp(
  r'\.(mp3|m4a|aac|wav|ogg|oga|opus|flac|mp4|m4v|webm|mov)(\?|#|$)',
  caseSensitive: false,
).hasMatch(url.trim());

/// Whether the app can play this link in its own little window.
bool canPlayInApp(String url) => youtubeId(url) != null || isMediaFile(url);

/// The player inside the floating window (picture-in-picture): a title
/// bar to drag it by, × to close. YouTube links play in YouTube's own
/// player; audio / video files in the app's player. Sized by its
/// [FloatingPanel].
class MediaPip extends StatefulWidget {
  final String url;
  final String title;
  final VoidCallback onClose;

  const MediaPip({
    super.key,
    required this.url,
    required this.title,
    required this.onClose,
  });

  static const barHeight = 36.0;

  /// Bar plus a 16:9 picture.
  static double heightFor(double width) => barHeight + width * 9 / 16;

  @override
  State<MediaPip> createState() => _MediaPipState();
}

class _MediaPipState extends State<MediaPip> {
  late Widget _player = _build();

  double get _radius => StyleExtras.of(context).panelRadius;
  VideoPlayerController? _video;

  Widget _build() {
    final id = youtubeId(widget.url);
    if (id != null) {
      return webEmbed(
        'https://www.youtube-nocookie.com/embed/$id?autoplay=1&rel=0',
        bottomRadius: _radius,
      );
    }
    final video = _video = VideoPlayerController.networkUrl(
      Uri.parse(widget.url.trim()),
    );
    video.initialize().then((_) {
      if (!mounted) return;
      video.play();
      setState(() {});
    });
    return _FilePlayer(controller: video);
  }

  @override
  void didUpdateWidget(MediaPip old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _video?.dispose();
      _video = null;
      _player = _build();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    setEmbedsInteractive(true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = StyleExtras.of(context).panelRadius;
    return Material(
      elevation: inkE(10),
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(inkR(radius)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          FloatingDragArea(
            child: SizedBox(
              height: MediaPip.barHeight,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close player',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            // Round the video's own lower corners too, to match the window.
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(inkR(radius)),
              ),
              child: ColoredBox(color: Colors.black, child: _player),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plays an audio / video file with simple controls.
class _FilePlayer extends StatelessWidget {
  final VideoPlayerController controller;
  const _FilePlayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        if (v.hasError) {
          return const Center(
            child: Text(
              "Couldn't play this file.",
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
        if (!v.isInitialized) {
          return const Center(child: AppSpinner());
        }
        final hasPicture = v.size.width > 0 && v.size.height > 0;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (hasPicture)
              Center(
                child: AspectRatio(
                  aspectRatio: v.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            else
              const Center(
                child: Icon(Icons.music_note, color: Colors.white38, size: 48),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Row(
                children: [
                  IconButton(
                    tooltip: v.isPlaying ? 'Pause' : 'Play',
                    color: Colors.white,
                    icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: v.isPlaying ? controller.pause : controller.play,
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
