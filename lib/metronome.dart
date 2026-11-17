import 'dart:async';

import 'package:flutter/foundation.dart';

import 'browser.dart';

/// Click track: follows the song's tempo and time signature; can be
/// adjusted or set by tapping.
class Metronome extends ChangeNotifier {
  int bpm = 100;
  int beatsPerBar = 4;
  bool running = false;
  bool sound = true;

  /// Beat within the bar that just played (0 = first), -1 when stopped.
  int beat = -1;

  Timer? _timer;
  final List<DateTime> _taps = [];

  static const minBpm = 30;
  static const maxBpm = 280;

  /// Uses the song's tempo ("90", "90 bpm") and time ("6/8") when present.
  void setFromSong(String tempo, String timeSignature) {
    final t = int.tryParse(RegExp(r'\d+').stringMatch(tempo) ?? '');
    final n = int.tryParse(timeSignature.split('/').first.trim());
    var changed = false;
    if (t != null && t >= minBpm && t <= maxBpm && t != bpm) {
      bpm = t;
      changed = true;
    }
    if (n != null && n > 0 && n <= 16 && n != beatsPerBar) {
      beatsPerBar = n;
      changed = true;
    }
    if (changed) {
      if (running) _restart();
      notifyListeners();
    }
  }

  void toggle() => running ? stop() : start();

  void start() {
    running = true;
    beat = -1;
    _restart();
    _tick();
    notifyListeners();
  }

  void stop() {
    running = false;
    _timer?.cancel();
    _timer = null;
    beat = -1;
    notifyListeners();
  }

  void setBpm(int value) {
    bpm = value.clamp(minBpm, maxBpm);
    if (running) _restart();
    notifyListeners();
  }

  /// Tap tempo: averages the last few taps.
  void tap() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last).inSeconds >= 2) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);
    if (_taps.length >= 2) {
      final ms =
          now.difference(_taps.first).inMilliseconds / (_taps.length - 1);
      setBpm((60000 / ms).round());
    }
  }

  void setBeatsPerBar(int n) {
    beatsPerBar = n.clamp(1, 16);
    beat = beat.clamp(-1, beatsPerBar - 1);
    notifyListeners();
  }

  void setSound(bool on) {
    sound = on;
    notifyListeners();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(microseconds: (60000000 / bpm).round()),
      (_) => _tick(),
    );
  }

  void _tick() {
    beat = (beat + 1) % beatsPerBar;
    if (sound) playClick(accent: beat == 0);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
