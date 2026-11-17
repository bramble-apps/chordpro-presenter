import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bilingual_projector/tuner/microphone.dart';
import 'package:bilingual_projector/tuner/pitch.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tone (with a few harmonics, like a string) at [hz].
Float32List tone(
  double hz, {
  int rate = 48000,
  int n = 4096,
  double noise = 0,
}) {
  final r = math.Random(1);
  return Float32List.fromList([
    for (var i = 0; i < n; i++)
      0.5 * math.sin(2 * math.pi * hz * i / rate) +
          0.25 * math.sin(4 * math.pi * hz * i / rate) +
          0.12 * math.sin(6 * math.pi * hz * i / rate) +
          noise * (r.nextDouble() * 2 - 1),
  ]);
}

void main() {
  const detector = PitchDetector();

  test('guitar strings, in tune', () {
    for (final (hz, name, octave) in [
      (82.41, 'E', 2),
      (110.0, 'A', 2),
      (146.83, 'D', 3),
      (196.0, 'G', 3),
      (246.94, 'B', 3),
      (329.63, 'E', 4),
      (440.0, 'A', 4),
    ]) {
      final p = detector.detect(tone(hz), 48000)!;
      expect(p.name(), name, reason: '$hz Hz');
      expect(p.octave, octave, reason: '$hz Hz');
      expect(p.cents.abs(), lessThan(3), reason: '$hz Hz');
    }
  });

  test('sharp and flat, at 44.1 kHz too', () {
    final sharp = detector.detect(tone(440 * 1.0058, rate: 44100), 44100)!;
    expect(sharp.name(), 'A');
    expect(sharp.cents, closeTo(10, 3));
    final flat = detector.detect(tone(440 / 1.0116), 48000)!;
    expect(flat.cents, closeTo(-20, 3));
  });

  test('silence is nothing; a little noise is fine', () {
    expect(detector.detect(Float32List(4096), 48000), isNull);
    final noisy = detector.detect(tone(196, noise: 0.05), 48000)!;
    expect(noisy.name(), 'G');
  });

  test('reference pitch and solfège', () {
    final p = detector.detect(tone(432), 48000, a4: 432)!;
    expect(p.name(), 'A');
    expect(p.cents.abs(), lessThan(3));
    expect(Pitch.fromHz(261.63).name(solfege: true), 'Do');
    expect(Pitch.fromHz(277.18).name(solfege: true), 'Do#');
  });

  test('controller: steady readings from a stream of samples', () {
    final tuner = TunerController(sampleRate: 44100);
    final sharpA = tone(440 * 1.0058, rate: 44100, n: 44100 ~/ 2);
    // Arrives in small chunks, like a microphone.
    for (var i = 0; i < sharpA.length; i += 512) {
      tuner.add(
        Float32List.sublistView(sharpA, i, math.min(i + 512, sharpA.length)),
      );
    }
    final r = tuner.reading.value!;
    expect(r.pitch.name(), 'A');
    expect(r.pitch.cents, closeTo(10, 3));
    // Silence: the note is held a few seconds, then clears.
    tuner.add(Float32List(44100));
    expect(tuner.reading.value, isNotNull, reason: 'held');
    tuner.add(Float32List(44100 * 6));
    expect(tuner.reading.value, isNull);

    // 48 kHz (halved to 24 kHz inside) reads the same.
    final at48 = TunerController(sampleRate: 48000);
    final g = tone(196, rate: 48000, n: 24000);
    for (var i = 0; i < g.length; i += 960) {
      at48.add(Float32List.sublistView(g, i, math.min(i + 960, g.length)));
    }
    expect(at48.reading.value!.pitch.name(), 'G');
    expect(at48.reading.value!.pitch.cents.abs(), lessThan(3));
  });
}
