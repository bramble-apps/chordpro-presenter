// Plays a chord: strummed low → high for guitar / ukulele (a plucked
// string, Karplus–Strong), all keys together for piano. Made here, no sound
// files needed.

import 'dart:math' as math;
import 'dart:typed_data';

import '../browser.dart';
import 'chord_db.dart';

/// How fast a strum goes: the gap between strings.
enum ChordPlaySpeed {
  fast('Fast', 15),
  medium('Medium', 40),
  slow('Slow', 90);

  final String label;
  final int gapMs;
  const ChordPlaySpeed(this.label, this.gapMs);
}

const _rate = 22050;

/// The chord as sound: mono samples (−1…1) at [_rate].
Float32List renderChord(
  List<int> midi, {
  required Instrument instrument,
  ChordPlaySpeed speed = ChordPlaySpeed.medium,
  double seconds = 2.2,
}) {
  final n = (_rate * seconds).round();
  final out = Float32List(n);
  final random = math.Random(7);
  final piano = instrument == Instrument.piano;
  for (var k = 0; k < midi.length; k++) {
    final hz = 440 * math.pow(2, (midi[k] - 69) / 12).toDouble();
    final start = (k * (piano ? 8 : speed.gapMs) * _rate / 1000).round();
    if (piano) {
      _piano(out, start, hz);
    } else {
      _pluck(out, start, hz, random, bright: instrument == Instrument.ukulele);
    }
  }
  // Even loudness; a short fade at the end.
  var peak = 0.0;
  for (final v in out) {
    if (v.abs() > peak) peak = v.abs();
  }
  final gain = peak == 0 ? 0.0 : 0.8 / peak;
  final fade = (_rate * 0.3).round();
  for (var i = 0; i < n; i++) {
    final tail = n - i < fade ? (n - i) / fade : 1.0;
    out[i] *= gain * tail;
  }
  return out;
}

/// A plucked string: a burst of noise ringing around a delay line that
/// softens and fades it.
void _pluck(
  Float32List out,
  int start,
  double hz,
  math.Random random, {
  bool bright = false,
}) {
  final period = math.max(2, (_rate / hz).round());
  final line = Float32List(period);
  // The pick: noise, smoothed a little (less for the brighter ukulele).
  var prev = 0.0;
  for (var i = 0; i < period; i++) {
    final noise = random.nextDouble() * 2 - 1;
    prev = bright ? noise : (noise + prev) / 2;
    line[i] = prev;
  }
  final decay = bright ? 0.994 : 0.996;
  var p = 0;
  for (var i = start; i < out.length; i++) {
    final next = (p + 1) % period;
    final v = line[p];
    line[p] = decay * 0.5 * (line[p] + line[next]);
    out[i] += v * 0.5;
    p = next;
  }
}

/// A piano-ish note: a few harmonics, struck and fading.
void _piano(Float32List out, int start, double hz) {
  const partials = [1.0, 0.5, 0.25, 0.12, 0.06];
  for (var i = start; i < out.length; i++) {
    final t = (i - start) / _rate;
    final attack = math.min(1.0, t / 0.005);
    var v = 0.0;
    for (var h = 0; h < partials.length; h++) {
      v +=
          partials[h] *
          math.exp(-t * (1.2 + h * 0.8)) *
          math.sin(2 * math.pi * hz * (h + 1) * t);
    }
    out[i] += 0.3 * attack * v;
  }
}

/// Plays [shape] ([capo] raises it, as on the instrument).
void playChord(
  ChordShape shape, {
  int capo = 0,
  ChordPlaySpeed speed = ChordPlaySpeed.medium,
}) {
  final midi = shape.midi(capo: capo);
  if (midi.isEmpty) return;
  playSound(
    renderChord(midi, instrument: shape.instrument, speed: speed),
    _rate,
  );
}
