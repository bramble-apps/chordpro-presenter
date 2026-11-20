// Finding a song's key by ear: the microphone's sound is split into its
// frequencies, each strong one counted toward its note (C, C♯ … B), and the
// running counts compared with how often each note is heard in each of the
// 24 keys (the Krumhansl–Kessler key profiles). A single voice (or any one
// note at a time) is followed with the tuner's pitch detector instead, and
// its notes matched to profiles made from melodies (Aarden–Essen): a voice's
// overtones are often louder than the note itself, so its spectrum misleads.
// Works for singing, piano or guitar, single notes or chords.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../music.dart';
import 'pitch.dart';

/// How much each note is heard in a major and a minor key, from the tonic
/// up (Krumhansl & Kessler's listening tests).
const _majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const _minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

/// How often each note comes in melodies in a major and a minor key, from
/// the tonic up (Aarden's counts from the Essen folk song collection).
const _majorMelody = [17.77, 0.15, 14.93, 0.16, 19.80, 11.36, 0.29, 22.06, 0.15, 8.15, 0.23, 4.95];
const _minorMelody = [18.26, 0.74, 14.05, 16.86, 0.70, 14.44, 0.70, 18.62, 4.57, 1.93, 7.38, 1.76];

/// One key's match with what was heard (Pearson correlation, −1…1).
class KeyScore {
  final MusicKey key;
  final double score;
  const KeyScore(this.key, this.score);
}

/// All 24 keys for a note profile ([chroma]: how much of C, C♯ … B was
/// heard), best match first. [melody]: the notes were sung or played one
/// at a time (compared with melodies' profiles, not chords').
List<KeyScore> rankKeys(List<double> chroma, {bool melody = false}) {
  double corr(List<double> a, List<double> b) {
    final ma = a.reduce((x, y) => x + y) / 12;
    final mb = b.reduce((x, y) => x + y) / 12;
    var num = 0.0, da = 0.0, db = 0.0;
    for (var i = 0; i < 12; i++) {
      num += (a[i] - ma) * (b[i] - mb);
      da += (a[i] - ma) * (a[i] - ma);
      db += (b[i] - mb) * (b[i] - mb);
    }
    return da == 0 || db == 0 ? 0 : num / math.sqrt(da * db);
  }

  final out = <KeyScore>[];
  for (var root = 0; root < 12; root++) {
    for (final minor in [false, true]) {
      final p = melody
          ? (minor ? _minorMelody : _majorMelody)
          : (minor ? _minorProfile : _majorProfile);
      // the profile turned to start on this root
      final turned = [for (var i = 0; i < 12; i++) p[(i - root + 12) % 12]];
      out.add(KeyScore(MusicKey(root, minor), corr(chroma, turned)));
    }
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// What the key finder shows: its best guess, the runner-up, how sure it
/// is (0…1), how long it has heard sound, and the notes heard (0…1 each).
class KeyGuess {
  final MusicKey key;
  final MusicKey runnerUp;
  final double sure;
  final Duration heard;
  final List<double> notes;
  const KeyGuess({
    required this.key,
    required this.runnerUp,
    required this.sure,
    required this.heard,
    required this.notes,
  });
}

/// In-place radix-2 FFT of [re] / [im] (length a power of two).
void fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final a = -2 * math.pi / len;
    final wr = math.cos(a), wi = math.sin(a);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final ur = re[i + k], ui = im[i + k];
        final xr = re[i + k + len ~/ 2], xi = im[i + k + len ~/ 2];
        final vr = xr * cr - xi * ci, vi = xr * ci + xi * cr;
        re[i + k] = ur + vr;
        im[i + k] = ui + vi;
        re[i + k + len ~/ 2] = ur - vr;
        im[i + k + len ~/ 2] = ui - vi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

/// Turns the microphone's samples into a running key guess: about eight
/// looks a second, each adding the notes it hears (older ones slowly
/// fading, so a key change is followed within half a minute or so).
class KeyListener {
  /// Samples per second of what's fed in (set once the mic is open).
  int sampleRate;
  double a4;

  /// The latest guess (null until a few seconds of sound have been heard).
  final guess = ValueNotifier<KeyGuess?>(null);

  /// How loud the sound is right now (0…1, for the listening light).
  final level = ValueNotifier<double>(0);

  KeyListener({required this.sampleRate, this.a4 = 440});

  static const _size = 8192;
  final _buffer = Float32List(_size);
  var _filled = 0;
  var _sinceLast = 0;
  var _half = false;
  double? _pending;
  final _chroma = List<double>.filled(12, 0);
  // notes heard one at a time (a voice), and how much of each kind there's
  // been (fading like the counts)
  final _melody = List<double>.filled(12, 0);
  var _chordWeight = 0.0, _melodyWeight = 0.0;
  static const _voice = PitchDetector(minHz: 70, maxHz: 1100, threshold: .12);
  var _heardSamples = 0;
  late final _window = Float64List.fromList([
    for (var i = 0; i < _size; i++) .5 - .5 * math.cos(2 * math.pi * i / (_size - 1)),
  ]);

  StreamSubscription<Float32List>? _sub;

  void listen(Stream<Float32List> samples) {
    _sub?.cancel();
    _sub = samples.listen(add);
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
    level.value = 0;
  }

  /// Forgets everything heard (start over).
  void reset() {
    _chroma.fillRange(0, 12, 0);
    _melody.fillRange(0, 12, 0);
    _chordWeight = _melodyWeight = 0;
    _heardSamples = 0;
    guess.value = null;
  }

  int get _rate => sampleRate > 30000 ? sampleRate ~/ 2 : sampleRate;

  void _push(double s) {
    _buffer[_filled % _size] = s;
    _filled++;
    _sinceLast++;
  }

  /// Feeds samples in.
  void add(Float32List chunk) {
    final halve = sampleRate > 30000;
    for (final s in chunk) {
      if (!halve) {
        _push(s);
      } else if (_half) {
        _push((_pending! + s) / 2);
        _half = false;
      } else {
        _pending = s;
        _half = true;
      }
      if (_filled >= _size && _sinceLast >= _rate ~/ 8) {
        final hop = _sinceLast;
        _sinceLast = 0;
        _analyse(hop);
      }
    }
  }

  void _analyse(int hop) {
    final rate = _rate;
    final start = _filled % _size;
    final re = Float64List(_size), im = Float64List(_size);
    var energy = 0.0;
    for (var i = 0; i < _size; i++) {
      final s = _buffer[(start + i) % _size];
      energy += s * s;
      re[i] = s * _window[i];
    }
    final rms = math.sqrt(energy / _size);
    // (about −60 dB full scale is silence; −20 dB loud)
    level.value = ((20 * math.log(rms + 1e-9) / math.ln10 + 60) / 40).clamp(0.0, 1.0);
    if (rms < 0.004) return; // too quiet: nothing to count
    // one clear note (a voice, a single line)? Then that note is what's
    // counted (the latest tenth of a second, read like the tuner does)
    const fade = .995; // older sound fades: about 25 s for most of it to go
    final recent = Float32List(2048);
    for (var i = 0; i < 2048; i++) {
      recent[i] = _buffer[(start + _size - 2048 + i) % _size];
    }
    final sung = _voice.detect(recent, rate, a4: a4);
    if (sung != null && sung.clarity > .85 && sung.cents.abs() < 35) {
      for (var i = 0; i < 12; i++) {
        _melody[i] *= fade;
        _chroma[i] *= fade;
      }
      _melody[sung.midi % 12] += 1;
      _melodyWeight = _melodyWeight * fade + 1;
      _chordWeight *= fade;
      _heard(hop);
      return;
    }
    fft(re, im);
    final binHz = rate / _size;
    final lo = (60 / binHz).floor(), hi = math.min(_size ~/ 2 - 2, (2100 / binHz).ceil());
    final mag = Float64List(hi + 2);
    var top = 0.0;
    for (var b = lo - 1; b <= hi + 1; b++) {
      mag[b] = math.sqrt(re[b] * re[b] + im[b] * im[b]);
      if (b >= lo && b <= hi && mag[b] > top) top = mag[b];
    }
    if (top == 0) return;
    final peaks = <(double hz, double mag)>[];
    for (var b = lo; b <= hi; b++) {
      final m = mag[b];
      // spectral peaks only, and not the faint ones
      if (m < top * .06 || m < mag[b - 1] || m < mag[b + 1]) continue;
      // the peak's true place between bins (parabolic)
      final a = mag[b - 1], c = mag[b + 1];
      final d = (a - 2 * m + c) == 0 ? 0.0 : .5 * (a - c) / (a - 2 * m + c);
      peaks.add(((b + d) * binHz, m));
    }
    final frame = List<double>.filled(12, 0);
    for (final (hz, m) in peaks) {
      // an overtone (2, 3, 4, 5 or 6 times a lower note that's sounding):
      // it's that note's colour, not a note of its own; counted, it would
      // pull every note toward its fifth and third
      final overtone = peaks.any((q) {
        if (q.$1 >= hz * .97 || q.$2 < m * .15) return false;
        final k = hz / q.$1;
        return k > 1.9 && k < 6.2 && (k - k.roundToDouble()).abs() < .03 * k;
      });
      if (overtone) continue;
      final midi = 69 + 12 * math.log(hz / a4) / math.ln2;
      final near = midi.roundToDouble();
      if ((midi - near).abs() > .35) continue; // between notes: noise
      frame[near.toInt() % 12] += math.sqrt(m / top);
    }
    final sum = frame.reduce((x, y) => x + y);
    if (sum == 0) return;
    for (var i = 0; i < 12; i++) {
      _chroma[i] = _chroma[i] * fade + frame[i] / sum;
      _melody[i] *= fade;
    }
    _chordWeight = _chordWeight * fade + 1;
    _melodyWeight *= fade;
    _heard(hop);
  }

  /// After each look: the guess from all that's been heard so far.
  void _heard(int hop) {
    final rate = _rate;
    _heardSamples += hop;
    final heard = Duration(milliseconds: _heardSamples * 1000 ~/ rate);
    if (heard < const Duration(seconds: 2)) return;
    // chords' and single notes' matches, mixed by how much of each
    final total = _chordWeight + _melodyWeight;
    final score = <String, double>{};
    final keys = <String, MusicKey>{};
    void mix(List<KeyScore> ranked, double weight) {
      if (weight == 0) return;
      for (final k in ranked) {
        final id = '${k.key.root}${k.key.minor}';
        keys[id] = k.key;
        score[id] = (score[id] ?? 0) + k.score * weight / total;
      }
    }

    mix(rankKeys(_chroma), _chordWeight);
    mix(rankKeys(_melody, melody: true), _melodyWeight);
    final ranked = [for (final e in score.entries) KeyScore(keys[e.key]!, e.value)]
      ..sort((a, b) => b.score.compareTo(a.score));
    final best = ranked[0], second = ranked[1];
    // sure: a clear lead over the runner-up, and long enough listening
    final lead = ((best.score - second.score) / .12).clamp(0.0, 1.0);
    final time = (heard.inMilliseconds / 12000).clamp(0.0, 1.0);
    final fit = ((best.score - .3) / .5).clamp(0.0, 1.0);
    // the notes heard, both kinds together
    final cSum = _chroma.reduce((x, y) => x + y), mSum = _melody.reduce((x, y) => x + y);
    final notes = [
      for (var i = 0; i < 12; i++)
        (cSum == 0 ? 0 : _chroma[i] / cSum * _chordWeight) + (mSum == 0 ? 0 : _melody[i] / mSum * _melodyWeight),
    ];
    final peak = notes.reduce(math.max);
    guess.value = KeyGuess(
      key: best.key,
      runnerUp: second.key,
      sure: (.5 * lead + .5 * fit) * (.35 + .65 * time),
      heard: heard,
      notes: [for (final v in notes) peak == 0 ? 0.0 : v / peak],
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    guess.dispose();
    level.dispose();
  }
}
