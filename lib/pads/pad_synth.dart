// Pad sounds rendered as seamless stereo loops: a held chord (root, fifth,
// octave) from the built-in synth or a SoundFont preset, then tone and
// reverb. The loop is played over and over (and crossfaded into the next
// key's), so it is made to join up with no click.

import 'dart:math' as math;
import 'dart:typed_data';

import 'sf2.dart';

/// Samples a second of the rendered loops.
const padRate = 32000;

/// The loop's length, in seconds.
const padLoopSeconds = 10;

/// The built-in sounds (no files needed).
enum BuiltInPad {
  warm('Warm'),
  shimmer('Shimmer'),
  soft('Soft');

  final String label;
  const BuiltInPad(this.label);
}

/// A rendered loop.
class PadLoop {
  final Float32List left, right;
  final int rate;
  const PadLoop(this.left, this.right, this.rate);
  int get length => left.length;
}

/// The notes held for [key] (0 = C … 11 = B) at [octave] (0: the root
/// between C2 and B2), with their levels.
List<(int, double)> padNotes(int key, int octave, {bool shimmer = false}) {
  final root = 36 + key + 12 * octave;
  return [
    (root, 1.0),
    (root + 7, 0.7),
    (root + 12, 0.6),
    if (shimmer) ...[(root + 19, 0.22), (root + 24, 0.25)],
  ];
}

double _hz(num midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

// ---- Built-in synth ----

/// One cycle of a wave with [harmonics] amplitudes (up to below [maxHz]
/// for a note at [hz]), in a table of [size].
Float32List _table(List<double> harmonics, double hz, double maxHz) {
  const size = 2048;
  final t = Float32List(size);
  for (var k = 1; k <= harmonics.length; k++) {
    if (k * hz > maxHz) break;
    final a = harmonics[k - 1];
    if (a == 0) continue;
    for (var i = 0; i < size; i++) {
      t[i] += a * math.sin(2 * math.pi * k * i / size);
    }
  }
  return t;
}

List<double> _harmonics(BuiltInPad pad) => switch (pad) {
  // A soft sawtooth, darker up high.
  BuiltInPad.warm => [for (var k = 1; k <= 48; k++) math.exp(-(k - 1) / 5) / k],
  BuiltInPad.shimmer => [
    for (var k = 1; k <= 48; k++) math.exp(-(k - 1) / 9) / k,
  ],
  // Nearly a sine, like a flute stop.
  BuiltInPad.soft => [1, 0.22, 0.1, 0.04, 0.02],
};

/// The built-in pad: each note as three slightly detuned voices spread
/// left to right, slowly swelling. Every frequency fits a whole number of
/// cycles into the loop, so it joins up exactly.
PadLoop renderBuiltIn(BuiltInPad pad, List<(int, double)> notes) {
  final n = padRate * padLoopSeconds;
  final left = Float32List(n), right = Float32List(n);
  final random = math.Random(7);
  const detune = [-9.0, 0.0, 8.0];
  const pans = [-0.7, 0.0, 0.7];
  for (final (i, (note, level)) in notes.indexed) {
    // The top shimmer notes are soft sines.
    final soft = pad == BuiltInPad.shimmer && i >= 3;
    final wave = soft ? const [1.0] : _harmonics(pad);
    for (var v = 0; v < 3; v++) {
      final hz = _hz(note + detune[v] / 100);
      // Whole cycles in the loop.
      final fitted = (hz * padLoopSeconds).round() / padLoopSeconds;
      final table = _table(wave, fitted, padRate * 0.45);
      final size = table.length;
      final step = fitted * size / padRate;
      var phase = random.nextDouble() * size;
      // A slow swell: 1–3 times a loop.
      final swells = 1 + (i + v) % 3;
      final swellPhase = random.nextDouble() * 2 * math.pi;
      final angle = (pans[v] + 1) * math.pi / 4;
      final gl = math.cos(angle) * level / 3, gr = math.sin(angle) * level / 3;
      var swell = 1.0;
      for (var s = 0; s < n; s++) {
        // (Slow: worked out every 32 samples.)
        if (s & 31 == 0) {
          swell = 1 + 0.2 * math.sin(swellPhase + 2 * math.pi * swells * s / n);
        }
        final at = phase.floor();
        final f = phase - at;
        final a = table[at], b = table[at + 1 == size ? 0 : at + 1];
        final x = (a + (b - a) * f) * swell;
        left[s] += x * gl;
        right[s] += x * gr;
        phase += step;
        if (phase >= size) phase -= size;
      }
    }
  }
  return PadLoop(left, right, padRate);
}

// ---- SoundFont ----

/// A SoundFont preset holding [notes]. Rendered a little longer than the
/// loop and joined end to start with a crossfade (from past the attack).
PadLoop renderSoundFont(PadSound sound, List<(int, double)> notes) {
  final n = padRate * padLoopSeconds;
  final skip = padRate; // past the attack
  final fade = padRate * 2;
  final total = skip + n + fade;
  final left = Float32List(total), right = Float32List(total);
  final pcm = sound.pcm;
  for (final (note, level) in notes) {
    for (final z in sound.zonesFor(note)) {
      final semis = ((note - z.root) * z.scale + z.tune) / 100;
      final step = math.pow(2, semis / 12) * z.rate / padRate;
      final angle = (z.pan + 1) * math.pi / 4;
      final g = z.gain * level / 32768;
      final gl = math.cos(angle) * g * math.sqrt2;
      final gr = math.sin(angle) * g * math.sqrt2;
      final loopLength = z.loopEnd - z.loopStart;
      var p = 0.0;
      for (var s = 0; s < total; s++) {
        if (z.loop) {
          while (p >= z.loopEnd) {
            p -= loopLength;
          }
        } else if (p >= z.length - 1) {
          break;
        }
        final at = p.floor();
        final f = p - at;
        final a = pcm[z.offset + at];
        final next = z.loop && at + 1 >= z.loopEnd
            ? z.loopStart
            : math.min(at + 1, z.length - 1);
        final x = a + (pcm[z.offset + next] - a) * f;
        left[s] += x * gl;
        right[s] += x * gr;
        p += step;
      }
    }
  }
  // Loop it: the start fades in under the end.
  final outL = Float32List(n), outR = Float32List(n);
  for (var i = 0; i < n; i++) {
    var l = left[skip + i], r = right[skip + i];
    if (i < fade) {
      final t = i / fade;
      final a = math.sin(t * math.pi / 2), b = math.cos(t * math.pi / 2);
      l = l * a + left[skip + n + i] * b;
      r = r * a + right[skip + n + i] * b;
    }
    outL[i] = l;
    outR[i] = r;
  }
  return PadLoop(outL, outR, padRate);
}

// ---- Level, tone and reverb ----

/// Brings [loop] to a steady loudness (so every sound plays about as loud).
void normalize(PadLoop loop) {
  var sum = 0.0, peak = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final l = loop.left[i], r = loop.right[i];
    sum += l * l + r * r;
    peak = math.max(peak, math.max(l.abs(), r.abs()));
  }
  if (sum == 0) return;
  final rms = math.sqrt(sum / (2 * loop.length));
  final gain = math.min(0.14 / rms, 0.8 / peak);
  for (var i = 0; i < loop.length; i++) {
    loop.left[i] *= gain;
    loop.right[i] *= gain;
  }
}

/// Darkens ([tone] 0, about 400 Hz) or opens ([tone] 1, all of it) the
/// sound, and adds a hall's [reverb] (0–1). Run over the loop's end first
/// so it joins up.
PadLoop applyEffects(
  PadLoop dry, {
  required double tone,
  required double reverb,
}) {
  final n = dry.length, rate = dry.rate;
  final warm = math.min(n, rate * 3); // settles the filter / reverb
  final outL = Float32List(n), outR = Float32List(n);
  final cutoff = 400 * math.pow(2, tone.clamp(0, 1) * 5.4).toDouble();
  final lpL = _Biquad.lowPass(cutoff, rate),
      lpR = _Biquad.lowPass(cutoff, rate);
  final hpL = _Biquad.highPass(40, rate), hpR = _Biquad.highPass(40, rate);
  final wet = reverb.clamp(0.0, 1.0);
  final hall = wet > 0 ? _Reverb(rate) : null;
  for (var s = 0; s < warm + n; s++) {
    final i = (s - warm) % n;
    var l = hpL.run(lpL.run(dry.left[i]));
    var r = hpR.run(lpR.run(dry.right[i]));
    if (hall != null) {
      final (wl, wr) = hall.run(l, r);
      l = l * (1 - wet * 0.5) + wl * wet * 1.2;
      r = r * (1 - wet * 0.5) + wr * wet * 1.2;
    }
    if (s >= warm) {
      outL[i] = l.clamp(-1.0, 1.0);
      outR[i] = r.clamp(-1.0, 1.0);
    }
  }
  return PadLoop(outL, outR, rate);
}

class _Biquad {
  final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.lowPass(double hz, int rate) {
    final w = 2 * math.pi * math.min(hz, rate * 0.45) / rate;
    final alpha = math.sin(w) / (2 * math.sqrt1_2);
    final c = math.cos(w), a0 = 1 + alpha;
    return _Biquad(
      (1 - c) / 2 / a0,
      (1 - c) / a0,
      (1 - c) / 2 / a0,
      -2 * c / a0,
      (1 - alpha) / a0,
    );
  }

  factory _Biquad.highPass(double hz, int rate) {
    final w = 2 * math.pi * hz / rate;
    final alpha = math.sin(w) / (2 * math.sqrt1_2);
    final c = math.cos(w), a0 = 1 + alpha;
    return _Biquad(
      (1 + c) / 2 / a0,
      -(1 + c) / a0,
      (1 + c) / 2 / a0,
      -2 * c / a0,
      (1 - alpha) / a0,
    );
  }

  double run(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// A Freeverb-style hall: parallel damped combs, then allpasses; the right
/// side's delays a little longer, for width.
class _Reverb {
  final List<_Comb> _combsL, _combsR;
  final List<_Allpass> _allL, _allR;

  static const _combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const _alls = [556, 441, 341, 225];

  _Reverb(int rate)
    : _combsL = [for (final d in _combs) _Comb(_scaled(d, rate))],
      _combsR = [for (final d in _combs) _Comb(_scaled(d + 23, rate))],
      _allL = [for (final d in _alls) _Allpass(_scaled(d, rate))],
      _allR = [for (final d in _alls) _Allpass(_scaled(d + 23, rate))];

  // Long room: the delays stretched for a big, slow hall.
  static int _scaled(int d, int rate) => (d * 1.6 * rate / 44100).round();

  (double, double) run(double l, double r) {
    final x = (l + r) * 0.015;
    var wl = 0.0, wr = 0.0;
    for (final c in _combsL) {
      wl += c.run(x);
    }
    for (final c in _combsR) {
      wr += c.run(x);
    }
    for (final a in _allL) {
      wl = a.run(wl);
    }
    for (final a in _allR) {
      wr = a.run(wr);
    }
    return (wl, wr);
  }
}

class _Comb {
  final Float32List _buf;
  int _i = 0;
  double _low = 0;
  _Comb(int size) : _buf = Float32List(size);

  double run(double x) {
    final y = _buf[_i];
    _low = y * 0.65 + _low * 0.35; // damping
    _buf[_i] = x + _low * 0.88;
    if (++_i == _buf.length) _i = 0;
    return y;
  }
}

class _Allpass {
  final Float32List _buf;
  int _i = 0;
  _Allpass(int size) : _buf = Float32List(size);

  double run(double x) {
    final b = _buf[_i];
    _buf[_i] = x + b * 0.5;
    if (++_i == _buf.length) _i = 0;
    return b - x;
  }
}
