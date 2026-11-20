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

/// A sung line: [notes] as (MIDI, beats), like a real voice: the note
/// itself quieter than its overtones, a formant boost, breath noise,
/// vibrato, and a slide from one note into the next.
Float32List voice(List<(int, double)> notes, {double beat = .42, int seed = 7}) {
  final rnd = math.Random(seed);
  final total = notes.fold(0.0, (a, n) => a + n.$2) * beat;
  final out = Float32List((total * rate).round());
  var phase = 0.0, t0 = 0.0, prev = hzOf(notes.first.$1);
  for (final (m, beats) in notes) {
    final len = beats * beat, target = hzOf(m);
    final n0 = (t0 * rate).round(), n1 = math.min(out.length, ((t0 + len) * rate).round());
    for (var i = n0; i < n1; i++) {
      final t = (i - n0) / rate;
      final slide = math.min(1.0, t / .07);
      final f = (prev + (target - prev) * slide) * (1 + .007 * math.sin(2 * math.pi * 5.3 * (i / rate)));
      phase += f / rate;
      var s = 0.0;
      for (var h = 1; h <= 14; h++) {
        final hz = f * h;
        // a weak fundamental, formants near 650 and 1150 Hz
        final formant = math.exp(-math.pow((hz - 650) / 250, 2)) + .7 * math.exp(-math.pow((hz - 1150) / 300, 2));
        final amp = (h == 1 ? .25 : 1 / h) * (.3 + 2.2 * formant);
        s += amp * math.sin(2 * math.pi * phase * h);
      }
      final env = math.min(1.0, t / .03) * math.min(1.0, (len - t) / .05);
      out[i] = (s * .06 * env + (rnd.nextDouble() - .5) * .02).toDouble();
    }
    prev = target;
    t0 += len;
  }
  return out;
}

/// A harsher voice: a phone in a room (hardly any fundamental, breath and
/// room noise, echoes).
Float32List hard(List<(int, double)> notes, {double beat = .42, int seed = 7, double h1 = .06, double noise = .06, double gain = .05}) {
  final rnd = math.Random(seed);
  final total = notes.fold(0.0, (a, n) => a + n.$2) * beat;
  final out = Float32List((total * rate).round() + rate);
  var phase = 0.0, t0 = 0.0, prev = hzOf(notes.first.$1);
  for (final (m, beats) in notes) {
    final len = beats * beat, target = hzOf(m);
    final n0 = (t0 * rate).round(), n1 = ((t0 + len) * rate).round();
    for (var i = n0; i < n1; i++) {
      final t = (i - n0) / rate;
      final slide = math.min(1.0, t / .12);
      final f = (prev + (target - prev) * slide) * (1 + .012 * math.sin(2 * math.pi * 5.3 * (i / rate)));
      phase += f / rate;
      var s = 0.0;
      for (var h = 1; h <= 20; h++) {
        final hz = f * h;
        final formant = math.exp(-math.pow((hz - 550) / 200, 2)) + math.exp(-math.pow((hz - 1700) / 350, 2)) + .6 * math.exp(-math.pow((hz - 2600) / 400, 2));
        final amp = (h == 1 ? h1 : 1 / math.sqrt(h)) * (.15 + 2.5 * formant);
        s += amp * math.sin(2 * math.pi * phase * h);
      }
      final env = math.min(1.0, t / .03) * math.min(1.0, (len - t) / .05);
      out[i] = (s * gain * env + (rnd.nextDouble() - .5) * noise * gain * 4).toDouble();
    }
    prev = target;
    t0 += len;
  }
  // a room: a few echoes
  for (final (delay, g) in [(.031, .35), (.047, .3), (.083, .25), (.121, .2)]) {
    final dly = (delay * rate).round();
    for (var i = out.length - 1; i >= dly; i--) {
      out[i] += out[i - dly] * g;
    }
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

  test('a voice alone: Amazing Grace in G (five notes only)', () {
    const d3 = 50, e3 = 52, g3 = 55, a3 = 57, b3 = 59, d4 = 62;
    final song = <(int, double)>[
      (d3, 1), (g3, 2), (b3, .5), (g3, .5), (b3, 2), (a3, 1), (g3, 2), (e3, 1), (d3, 2),
      (d3, 1), (g3, 2), (b3, .5), (g3, .5), (b3, 2), (a3, 1), (d4, 3),
      (b3, 1), (d4, 1.5), (b3, .5), (d4, .5), (b3, .5), (g3, 2), (d3, 1), (e3, 1.5), (g3, .5), (g3, .5), (e3, .5), (d3, 2),
      (d3, 1), (g3, 2), (b3, .5), (g3, .5), (b3, 2), (a3, 1), (g3, 3),
    ];
    expect(listenTo([voice(song)])?.name, 'G');
  });

  test('a voice alone: a tune in E minor', () {
    // (a higher voice: E4 = 64)
    const e = 64, fs = 66, g = 67, a = 69, b = 71, ds = 63, c5 = 72, b3 = 59;
    final song = <(int, double)>[
      (e, 1), (g, 1), (a, 1), (b, 2), (a, 1), (g, 1), (fs, 1), (e, 2),
      (ds, 1), (e, 1), (fs, 1), (g, 2), (fs, 1), (e, 1), (ds, 1), (b3, 2),
      (e, 1), (g, 1), (b, 1), (c5, 2), (b, 1), (a, 1), (g, 1), (fs, 1),
      (g, 1), (fs, 1), (e, 1), (ds, 1), (e, 3),
    ];
    expect(listenTo([voice(song, seed: 9)])?.name, 'Em');
  });

  test('a voice in a room, in four keys (the old spectrum-only way got 2 of 8)', () {
    const d3 = 50, e3 = 52, g3 = 55, a3 = 57, b3 = 59, d4 = 62;
    final grace = <(int, double)>[
      (d3, 1), (g3, 2), (b3, .5), (g3, .5), (b3, 2), (a3, 1), (g3, 2), (e3, 1), (d3, 2),
      (d3, 1), (g3, 2), (b3, .5), (g3, .5), (b3, 2), (a3, 1), (d4, 3),
      (b3, 1), (d4, 1.5), (b3, .5), (d4, .5), (b3, .5), (g3, 2), (d3, 1), (e3, 1.5), (g3, .5), (g3, .5), (e3, .5), (d3, 2),
    ];
    const e = 64, fs = 66, g = 67, a = 69, b = 71, ds = 63, c5 = 72, bl = 59;
    final minor = <(int, double)>[
      (e, 1), (g, 1), (a, 1), (b, 2), (a, 1), (g, 1), (fs, 1), (e, 2),
      (ds, 1), (e, 1), (fs, 1), (g, 2), (fs, 1), (e, 1), (ds, 1), (bl, 2),
      (e, 1), (g, 1), (b, 1), (c5, 2), (b, 1), (a, 1), (g, 1), (fs, 1),
      (g, 1), (fs, 1), (e, 1), (ds, 1), (e, 3),
    ];
    for (final shift in [0, 3, -2, 5]) {
      MusicKey? sung(List<(int, double)> song) =>
          listenTo([hard([for (final (m, b) in song) (m + shift, b)], seed: shift + 20)]);
      expect(sung(grace)?.name, const MusicKey(7, false).transposed(shift).name, reason: 'major, $shift');
      expect(sung(minor)?.name, const MusicKey(4, true).transposed(shift).name, reason: 'minor, $shift');
    }
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
