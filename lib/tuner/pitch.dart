import 'dart:math' as math;
import 'dart:typed_data';

/// A detected note: [hz] heard, the nearest note, and how far off it is.
class Pitch {
  final double hz;

  /// MIDI note number of the nearest note (69 = A4).
  final int midi;

  /// −50…+50: how sharp (+) or flat (−) [hz] is from [midi].
  final double cents;

  /// 0…1: how clearly pitched the sound was.
  final double clarity;

  const Pitch(this.hz, this.midi, this.cents, this.clarity);

  int get octave => midi ~/ 12 - 1;

  /// "A", "C#" … (or "La", "Do#" … in solfège).
  String name({bool solfege = false}) {
    final n = _names[midi % 12];
    if (!solfege) return n;
    return _solfege[n[0]]! + n.substring(1);
  }

  static Pitch fromHz(double hz, {double a4 = 440, double clarity = 1}) {
    final exact = 69 + 12 * math.log(hz / a4) / math.ln2;
    final midi = exact.round();
    return Pitch(hz, midi, (exact - midi) * 100, clarity);
  }
}

const _names = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
const _solfege = {
  'C': 'Do',
  'D': 'Re',
  'E': 'Mi',
  'F': 'Fa',
  'G': 'Sol',
  'A': 'La',
  'B': 'Si',
};

/// Finds the pitch of a sound with the YIN method (de Cheveigné & Kawahara,
/// 2002): compares the sound with delayed copies of itself; the smallest
/// delay that lines it up again is one period of the note. Plain Dart, so it
/// is the same on every platform.
class PitchDetector {
  final double minHz;
  final double maxHz;

  /// Lower = stricter (fewer, surer readings).
  final double threshold;

  /// Quieter than this (RMS, 0…1) counts as silence.
  final double silence;

  const PitchDetector({
    this.minHz = 40,
    this.maxHz = 1500,
    this.threshold = 0.15,
    this.silence = 0.01,
  });

  /// The pitch in [samples] (−1…1, mono), or null for silence / noise.
  Pitch? detect(Float32List samples, int sampleRate, {double a4 = 440}) {
    final n = samples.length;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += samples[i] * samples[i];
    }
    if (math.sqrt(sum / n) < silence) return null;

    final tauMin = (sampleRate / maxHz).floor().clamp(2, n ~/ 2);
    final tauMax = (sampleRate / minHz).ceil().clamp(tauMin + 2, n ~/ 2);
    final window = n - tauMax;
    if (window < tauMax ~/ 2) return null;

    // Difference of the sound with itself delayed by tau, normalised by
    // its running mean (so the first dip below the threshold wins).
    final d = Float64List(tauMax + 1);
    for (var tau = 1; tau <= tauMax; tau++) {
      var s = 0.0;
      for (var i = 0; i < window; i++) {
        final diff = samples[i] - samples[i + tau];
        s += diff * diff;
      }
      d[tau] = s;
    }
    final cmnd = Float64List(tauMax + 1)..[0] = 1;
    var running = 0.0;
    for (var tau = 1; tau <= tauMax; tau++) {
      running += d[tau];
      cmnd[tau] = running == 0 ? 1 : d[tau] * tau / running;
    }

    var best = -1;
    for (var tau = tauMin; tau <= tauMax; tau++) {
      if (cmnd[tau] < threshold) {
        // Walk down to the bottom of this dip.
        while (tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        best = tau;
        break;
      }
    }
    if (best < 0) return null;

    // Between samples: fit a parabola through the dip.
    var period = best.toDouble();
    if (best > 1 && best < tauMax) {
      final a = cmnd[best - 1], b = cmnd[best], c = cmnd[best + 1];
      final denom = a + c - 2 * b;
      if (denom != 0) period += (a - c) / (2 * denom);
    }
    final hz = sampleRate / period;
    if (hz < minHz || hz > maxHz) return null;
    return Pitch.fromHz(hz, a4: a4, clarity: (1 - cmnd[best]).clamp(0, 1));
  }
}
