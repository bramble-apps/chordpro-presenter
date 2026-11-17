import 'package:flutter/foundation.dart';

/// Reads a song length: "3:45", "1:02:30", "225", "3m 45s", "4 min".
/// Null when it isn't one.
int? parseDuration(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  final clock = RegExp(r'^(\d+)(?::(\d{1,2}))?(?::(\d{1,2}))?$').firstMatch(t);
  if (clock != null) {
    final parts = [
      for (var i = 1; i <= 3; i++)
        if (clock.group(i) != null) int.parse(clock.group(i)!),
    ];
    // A bare number is seconds; with colons the last part is seconds.
    var total = 0;
    for (final p in parts) {
      total = total * 60 + p;
    }
    if (parts.length > 1 && parts.skip(1).any((p) => p > 59)) return null;
    return total > 0 ? total : null;
  }
  final words = RegExp(
    r'^(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:utes?|s)?)?)?\s*(?:(\d+)\s*s(?:ec(?:onds?|s)?)?)?$',
  ).firstMatch(t);
  if (words != null && words.group(0)!.trim().isNotEmpty) {
    int g(int i) => int.tryParse(words.group(i) ?? '') ?? 0;
    final total = g(1) * 3600 + g(2) * 60 + g(3);
    return total > 0 ? total : null;
  }
  return null;
}

/// "1:30", "12:05", "1:02:30".
String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Scrolls the open song's sheet from top to bottom in a set time: the
/// song's duration when it has one, else 1:30. Changed times are kept per
/// song (until the app is reloaded). The sheet does the scrolling; this
/// holds what it should do.
class Autoscroll extends ChangeNotifier {
  static const defaultSeconds = 90;
  static const step = 30;
  static const minSeconds = 5;
  static const maxSeconds = 3 * 3600;

  String? _songId;
  int _songDefault = defaultSeconds;
  final Map<String, int> _custom = {};

  /// The song being scrolled (only its sheet moves).
  String? get songId => _songId;

  /// Time to scroll the whole song.
  int get seconds => _custom[_songId] ?? _songDefault;

  bool _running = false;
  bool get running => _running;

  /// How far down the sheet is (0–1), reported by the sheet as it goes.
  final progress = ValueNotifier<double>(0);

  /// Where the sheet is scrolled to (0–1), whoever scrolled it (reported by
  /// the sheet; Band Sync shares it).
  final scrolled = ValueNotifier<double>(0);

  /// Asks the sheet to scroll to this point (0–1) — Band Sync following
  /// the leader. The sheet sets it back to null once there.
  final seek = ValueNotifier<double?>(null);

  /// Scrolls so that [from] → [to] takes [duration] seconds (Band Sync).
  void startFrom(double from, double to, double duration) {
    if (_songId == null) return;
    final span = (to - from).clamp(0.01, 1.0);
    seek.value = from.clamp(0.0, 1.0);
    setSeconds((duration / span).round());
    _running = true;
    notifyListeners();
  }

  /// The open song changed (or its details did).
  void setSong(String? id, String duration) {
    _songDefault = parseDuration(duration) ?? defaultSeconds;
    if (id != _songId) {
      _songId = id;
      _running = false;
      progress.value = 0;
    }
    notifyListeners();
  }

  void setSeconds(int value) {
    final v = value.clamp(minSeconds, maxSeconds);
    if (v == seconds || _songId == null) return;
    if (v == _songDefault) {
      _custom.remove(_songId);
    } else {
      _custom[_songId!] = v;
    }
    notifyListeners();
  }

  void add(int by) => setSeconds(seconds + by);

  /// Time left, from how far down the sheet is.
  int get remaining => (seconds * (1 - progress.value)).round();

  /// Sets the time left from here (the pace changes to match).
  void setRemaining(int value) {
    final left = 1 - progress.value;
    if (left < 0.01) return setSeconds(value);
    setSeconds((value.clamp(minSeconds, maxSeconds) / left).round());
  }

  void addRemaining(int by) => setRemaining(remaining + by);

  /// Back to the song's own duration (or 1:30).
  void reset() {
    if (_custom.remove(_songId) != null) notifyListeners();
  }

  bool get isCustom => _custom.containsKey(_songId);

  void toggle() => _running ? stop() : start();

  void start() {
    if (_running || _songId == null) return;
    _running = true;
    notifyListeners();
  }

  void stop() {
    if (!_running) return;
    _running = false;
    notifyListeners();
  }

  /// Called by the sheet when it reaches the bottom.
  void finished() {
    progress.value = 1;
    stop();
  }

  @override
  void dispose() {
    scrolled.dispose();
    seek.dispose();
    progress.dispose();
    super.dispose();
  }
}
