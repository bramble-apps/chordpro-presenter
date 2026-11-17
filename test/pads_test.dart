import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/pads/pad_synth.dart';
import 'package:bilingual_projector/pads/sf2.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/pad_panel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show pumpApp;

/// A tiny SoundFont: one looped sine sample (A4) in a preset "Test Pad",
/// and an unlooped one in "Pluck".
Uint8List tinySf2() {
  final b = BytesBuilder();
  void chunk(BytesBuilder to, String id, List<int> body) {
    to.add(ascii.encode(id));
    to.add(
      (ByteData(
        4,
      )..setUint32(0, body.length, Endian.little)).buffer.asUint8List(),
    );
    to.add(body);
    if (body.length.isOdd) to.addByte(0);
  }

  List<int> list(String type, List<int> body) => [
    ...ascii.encode(type),
    ...body,
  ];
  List<int> le(int v, int bytes) => [
    for (var i = 0; i < bytes; i++) (v >> (8 * i)) & 0xFF,
  ];
  List<int> name(String n) => [
    ...ascii.encode(n),
    ...List.filled(20 - n.length, 0),
  ];

  // 1000 samples of a 440 Hz sine at 44 kHz (exactly 10 cycles).
  final pcm = <int>[];
  for (var i = 0; i < 1000; i++) {
    pcm.addAll(
      le((math.sin(2 * math.pi * 10 * i / 1000) * 12000).round() & 0xFFFF, 2),
    );
  }
  pcm.addAll(List.filled(92, 0)); // 46 zero samples after, as the spec asks
  final sdta = BytesBuilder();
  chunk(sdta, 'smpl', pcm);

  final pdta = BytesBuilder();
  chunk(pdta, 'phdr', [
    ...name('Test Pad'),
    ...le(0, 2),
    ...le(0, 2),
    ...le(0, 2),
    ...le(0, 12),
    ...name('Pluck'),
    ...le(1, 2),
    ...le(0, 2),
    ...le(1, 2),
    ...le(0, 12),
    ...name('EOP'),
    ...le(0, 2),
    ...le(0, 2),
    ...le(2, 2),
    ...le(0, 12),
  ]);
  chunk(pdta, 'pbag', [
    ...le(0, 2),
    ...le(0, 2),
    ...le(1, 2),
    ...le(0, 2),
    ...le(2, 2),
    ...le(0, 2),
  ]);
  chunk(pdta, 'pmod', List.filled(10, 0));
  chunk(pdta, 'pgen', [
    ...le(41, 2), ...le(0, 2), // instrument 0
    ...le(41, 2), ...le(1, 2), // instrument 1
    ...le(0, 4),
  ]);
  chunk(pdta, 'inst', [
    ...name('Sine'),
    ...le(0, 2),
    ...name('Sine once'),
    ...le(1, 2),
    ...name('EOI'),
    ...le(2, 2),
  ]);
  chunk(pdta, 'ibag', [
    ...le(0, 2),
    ...le(0, 2),
    ...le(2, 2),
    ...le(0, 2),
    ...le(3, 2),
    ...le(0, 2),
  ]);
  chunk(pdta, 'imod', List.filled(10, 0));
  chunk(pdta, 'igen', [
    ...le(54, 2), ...le(1, 2), // loops
    ...le(53, 2), ...le(0, 2), // sample 0
    ...le(53, 2), ...le(0, 2), // sample 0, no loop
    ...le(0, 4),
  ]);
  chunk(pdta, 'shdr', [
    ...name('sine'),
    ...le(0, 4),
    ...le(1000, 4),
    ...le(0, 4),
    ...le(1000, 4),
    ...le(44000, 4),
    69,
    0,
    ...le(0, 2),
    ...le(1, 2),
    ...name('EOS'),
    ...List.filled(26, 0),
  ]);

  final riff = BytesBuilder();
  riff.add(ascii.encode('sfbk'));
  chunk(riff, 'LIST', list('sdta', sdta.toBytes()));
  chunk(riff, 'LIST', list('pdta', pdta.toBytes()));
  chunk(b, 'RIFF', riff.toBytes());
  return b.toBytes();
}

double _rms(Float32List x) =>
    math.sqrt(x.fold<double>(0, (s, v) => s + v * v) / x.length);

void main() {
  test('reads a SoundFont and keeps one preset as a pad sound', () {
    final f = Sf2File.parse(tinySf2());
    final presets = f.presets;
    expect(presets.map((p) => p.name), ['Test Pad', 'Pluck']);
    expect(presets.first.sustains, isTrue);
    expect(presets.last.sustains, isFalse);

    final sound = f.extract(presets.first.index, 'Test Pad');
    expect(sound.zones.single.root, 69);
    expect(sound.pcm.length, 1000);
    final back = PadSound.decode(sound.encode());
    expect(back.name, 'Test Pad');
    expect(back.zones.single.loopEnd, 1000);
    expect(back.pcm, sound.pcm);

    // Rendered and looped: it holds for the whole loop.
    final loop = renderSoundFont(back, padNotes(9, 0));
    expect(loop.length, padRate * padLoopSeconds);
    expect(_rms(loop.left.sublist(loop.length - 1000)), greaterThan(0.01));

    expect(
      () => Sf2File.parse(Uint8List.fromList(utf8.encode('<!DOCTYPE html>'))),
      throwsA(isA<Sf2Error>()),
    );
  });

  test('built-in pads loop without a click', () {
    for (final pad in BuiltInPad.values) {
      final dry = renderBuiltIn(pad, padNotes(7, 0));
      normalize(dry);
      final wet = applyEffects(dry, tone: 0.6, reverb: 0.4);
      var biggest = 0.0;
      for (var i = 1; i < wet.length; i++) {
        biggest = math.max(biggest, (wet.left[i] - wet.left[i - 1]).abs());
      }
      final join = (wet.left.first - wet.left.last).abs();
      expect(join, lessThan(biggest), reason: pad.name);
      expect(_rms(wet.left), greaterThan(0.05), reason: pad.name);
    }
  });

  testWidgets('pads follow the song key and crossfade between keys', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    padLog.clear();
    model.addOrUpdate(
      Song(id: 'g', title: 'In G', raw: '[G]Hi', key: const MusicKey(7, false)),
    );
    model.addOrUpdate(
      Song(id: 'd', title: 'In D', raw: '[D]Hi', key: const MusicKey(2, false)),
    );
    model.selectSong('g');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Pads'));
    await tester.pumpAndSettle();
    expect(find.byType(PadPanel), findsOneWidget);
    expect(model.pads.key, 7);

    // Play (the power button), in the song's key.
    await tester.tap(find.byTooltip('Play the pad'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(padLog.where((l) => l.startsWith('play')), hasLength(1));

    // Next song: the pad moves to D.
    model.selectSong('d');
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(model.pads.key, 2);
    expect(padLog.where((l) => l.startsWith('play')), hasLength(2));

    // Tapping the key playing stops it.
    await tester.tap(find.text('D').last);
    await tester.pump();
    expect(model.pads.playing, isFalse);
    expect(padLog.last, 'stop');
    await tester.pumpAndSettle();
  });
}
