import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/tuner/key_detect.dart';
import 'package:bilingual_projector/widgets/key_finder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const rate = 44100;
double hzOf(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// [notes] (MIDI) sounding together for [seconds], with piano-ish overtones
/// and a decay, plus a little noise.
Float32List tone(List<int> notes, double seconds, {double vibrato = 0, int seed = 1}) {
  final rnd = math.Random(seed);
  final n = (rate * seconds).round();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    var s = 0.0;
    for (final m in notes) {
      // the phase of a pitch wobbling ±vibrato around the note, 5.5 times a second
      final phase = hzOf(m) * (t - vibrato * math.cos(2 * math.pi * 5.5 * t) / (2 * math.pi * 5.5));
      for (var h = 1; h <= 5; h++) {
        s += math.sin(2 * math.pi * phase * h) / (h * h * .8 + .2);
      }
    }
    out[i] = (s / notes.length * .2 * math.exp(-t * .8) + (rnd.nextDouble() - .5) * .004).toDouble();
  }
  return out;
}

MusicKey? listenTo(List<Float32List> parts) {
  final k = KeyListener(sampleRate: rate);
  for (final p in parts) {
    for (var i = 0; i < p.length; i += 1024) {
      k.add(Float32List.sublistView(p, i, math.min(p.length, i + 1024)));
    }
  }
  return k.guess.value?.key;
}

void main() {
  test('clean note counts give the key', () {
    // the G major scale, G strongest
    final g = List<double>.filled(12, 0);
    for (final (n, w) in [(7, 5.0), (9, 2.0), (11, 3.0), (0, 2.0), (2, 4.0), (4, 2.0), (6, 1.5)]) {
      g[n] = w;
    }
    expect(rankKeys(g).first.key.name, 'G');
  });

  test('the FFT finds a pure tone', () {
    const n = 1024;
    final re = Float64List(n), im = Float64List(n);
    for (var i = 0; i < n; i++) {
      re[i] = math.sin(2 * math.pi * 37 * i / n);
    }
    fft(re, im);
    var best = 0;
    for (var b = 1; b < n ~/ 2; b++) {
      if (re[b] * re[b] + im[b] * im[b] > re[best] * re[best] + im[best] * im[best]) best = b;
    }
    expect(best, 37);
  });

  test('piano chords in G: G major', () {
    // G C D G, Em C D G (piano voicings)
    const g = [55, 59, 62, 67], c = [48, 55, 60, 64], d = [50, 54, 57, 62], em = [52, 55, 59, 64];
    final parts = [for (final ch in [g, c, d, g, em, c, d, g]) tone(ch, 1.5)];
    expect(listenTo(parts)?.name, 'G');
  });

  test('guitar chords in E minor: E minor', () {
    const em = [40, 47, 52, 55, 59, 64], am = [45, 52, 57, 60, 64], b7 = [47, 51, 57, 59, 63, 66];
    final parts = [for (final ch in [em, am, b7, em, am, b7, em, em]) tone(ch, 1.5, seed: 3)];
    expect(listenTo(parts)?.name, 'Em');
  });

  test('a sung melody (one note at a time, vibrato) in D major', () {
    // D E F# G A G F# E D … F# A B A F# E D (D4 = 62)
    const melody = [62, 64, 66, 67, 69, 67, 66, 64, 62, 66, 69, 71, 69, 66, 64, 62, 62, 69, 66, 62];
    final parts = [for (final m in melody) tone([m], .6, vibrato: .006, seed: m)];
    expect(listenTo(parts)?.name, 'D');
  });

  test('says nothing in silence', () {
    expect(listenTo([Float32List(rate * 5)]), isNull);
  });

  testWidgets('the key finder page: shows the key heard, offers to move the song there', (t) async {
    const g = [55, 59, 62, 67], c = [48, 55, 60, 64], d = [50, 54, 57, 62];
    final audio = [for (final ch in [g, c, d, g, c, d, g]) tone(ch, 1.0)];
    final used = <int>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KeyFinderView(
          size: 320,
          written: const MusicKey(4, false), // the song is in E
          transpose: 0,
          onUse: used.add,
          debugSamples: Stream.fromIterable([
            for (final p in audio)
              for (var i = 0; i < p.length; i += 4096) Float32List.sublistView(p, i, math.min(p.length, i + 4096)),
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('G'), findsWidgets);
    expect(find.text('major'), findsOneWidget);
    await t.tap(find.text('Use G'));
    expect(used, [3]); // E up 3 = G
  });

  testWidgets('the key menu: the mic opens the finder, the arrow goes back', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KeyMenu(
          frame: ({required title, required actions, required builder}) => Column(children: [Text(title), ...actions, builder(200)]),
          wheel: (_) => const Text('wheel'),
          finder: (_, back) => const Text('finder'),
        ),
      ),
    ));
    expect(find.text('wheel'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('key-finder-open')));
    await t.pump();
    expect(find.text('finder'), findsOneWidget);
    expect(find.text('Find the key'), findsOneWidget);
    await t.tap(find.byTooltip('Back to the key wheel'));
    await t.pump();
    expect(find.text('wheel'), findsOneWidget);
  });
}
