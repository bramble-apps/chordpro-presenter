// Controls for an embedded YouTube player (web: an iframe; Android: a web
// view around one), through the messages YouTube's embed page understands
// (playVideo, pauseVideo, seekTo) and the progress it sends back.

class YouTubeHandle {
  /// Set by the player once it exists.
  void Function(String func, List<Object?> args)? send;

  /// Position and length (seconds), and whether it's playing; called a few
  /// times a second while it plays.
  void Function(double position, double duration, bool playing)? onInfo;

  /// Removes the player's listeners (set by the player).
  void Function()? close;

  void play() => send?.call('playVideo', const []);
  void pause() => send?.call('pauseVideo', const []);
  void seekTo(double seconds) => send?.call('seekTo', [seconds, true]);

  void dispose() {
    close?.call();
    send = null;
    onInfo = null;
  }

  /// Reads one message from the player (a JSON string): its progress.
  void receive(String json, Object? Function(String) decode) {
    Object? msg;
    try {
      msg = decode(json);
    } catch (_) {
      return; // not one of the player's messages
    }
    if (msg is! Map) return;
    final info = msg['info'];
    if (info is! Map) return;
    final pos = info['currentTime'];
    final dur = info['duration'];
    final state = info['playerState'];
    if (pos is num || dur is num || state is num) {
      _pos = pos is num ? pos.toDouble() : _pos;
      _dur = dur is num ? dur.toDouble() : _dur;
      // 1 playing, 3 loading, 2 paused, 0 ended; others (not started,
      // cued) say nothing yet.
      if (state is num && const [0, 1, 2, 3].contains(state)) {
        _playing = state == 1 || state == 3;
      }
      onInfo?.call(_pos, _dur, _playing);
    }
  }

  double _pos = 0, _dur = 0;
  bool _playing = true;
}

/// The embed address with the API switched on.
String youTubeEmbedUrl(String id, String origin) =>
    'https://www.youtube-nocookie.com/embed/$id?enablejsapi=1&autoplay=1'
    '&playsinline=1&rel=0&modestbranding=1&controls=0&fs=0'
    '&origin=${Uri.encodeComponent(origin)}';
