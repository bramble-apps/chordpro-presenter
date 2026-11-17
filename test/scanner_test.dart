import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/pads/sf2.dart';
import 'package:bilingual_projector/scanner/engrave.dart';
import 'package:bilingual_projector/scanner/harmony.dart';
import 'package:bilingual_projector/scanner/playback.dart';
import 'package:bilingual_projector/scanner/reader.dart';
import 'package:bilingual_projector/scanner/scan_store.dart';
import 'package:bilingual_projector/scanner/score.dart';
import 'package:bilingual_projector/scanner/score_export.dart';
import 'package:bilingual_projector/scanner/shapes.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A printed G major scale exercise (4 bars: quarters, halves, beamed
/// eighths, a whole note), as a grey picture.
PageImage _fixture() {
  final b = gzip.decode(
    File('test/fixtures/scale_in_g.pgm.gz').readAsBytesSync(),
  );
  final head = latin1.decode(b.sublist(0, 20)).split(RegExp(r'\s+'));
  final w = int.parse(head[1]), h = int.parse(head[2]);
  return PageImage(w, h, Uint8List.fromList(b.sublist(b.length - w * h)));
}

/// A score made by hand: C major chord in half notes, then G7.
Score _chords() {
  ScoreNote note(
    int m,
    double on,
    int diatonic, {
    int alter = 0,
    int staff = 0,
  }) => ScoreNote(
    page: 0,
    system: 0,
    staff: staff,
    measure: m,
    onset: on,
    duration: 2,
    diatonic: diatonic,
    alter: alter,
    type: 'half',
    box: Box(on * 50, 0, on * 50 + 10, 10),
  );
  return Score(
    pages: [(100, 100)],
    systems: [],
    clefs: [Clef.treble],
    measures: [
      ScoreMeasure(
        onset: 0,
        length: 4,
        page: 0,
        system: 0,
        box: const Box(0, 0, 200, 50),
      ),
      ScoreMeasure(
        onset: 4,
        length: 4,
        page: 0,
        system: 0,
        box: const Box(200, 0, 400, 50),
      ),
    ],
    notes: [
      // C E G
      for (final d in [28, 30, 32]) note(0, 0, d),
      for (final d in [28, 30, 32]) note(0, 2, d),
      // G B D F
      for (final d in [25, 27, 29, 31]) note(1, 4, d),
    ],
  );
}

void main() {
  test('music symbols become filled shapes', () {
    final m = glyphMask('noteheadBlack', 12, 10);
    final ink = m.px.where((v) => v == 1).length;
    expect(ink, greaterThan(60)); // mostly filled, an oval
    expect(m.at(0, 0), isFalse); // corners empty
    expect(pathPolygons('M0 0L10 0L10 10Z'), hasLength(1));
  });

  test('reads a printed exercise: key, time, pitches and rhythm', () {
    final score = readScore([_fixture()]);
    expect(score.fifths, 1);
    expect((score.beats, score.beatType), (4, 4));
    expect(score.clefs, [Clef.treble]);
    expect(score.measures, hasLength(4));
    final notes = score.ordered.where((n) => !n.rest).toList();
    expect(
      [for (final n in notes) n.midi],
      [
        67, 69, 71, 72, // G A B C
        74, 71, // D B
        67, 69, 71, 72, 74, 76, 78, 79, // G … F# G (key signature)
        79,
      ],
    );
    expect(
      [for (final n in notes) n.onset],
      [0, 1, 2, 3, 4, 6, 8, 8.5, 9, 9.5, 10, 10.5, 11, 11.5, 12],
    );
    expect(notes.last.type, 'whole');
  });

  test('playing: repeats, ties, swing, transposition', () {
    final s = _chords();
    s.measures[1].repeatEnd = true;
    final perf = perform(s, PlaySettings());
    // Bars 1, 2, then 1, 2 again.
    expect([for (final (m, _) in perf.measures) m], [0, 1, 0, 1]);
    expect(perf.length, 16);
    final up = perform(
      s,
      PlaySettings(transpose: 2, written: Transposing.bFlat),
    );
    expect(up.notes.first.midi, perf.notes.first.midi); // +2 −2
    // Tied notes sound once, for both lengths.
    final t = _chords()..measures[1].repeatEnd = false;
    t.notes.first.tie = true;
    final tied = perform(t, PlaySettings());
    final c4 = tied.notes.where((n) => n.midi == 60).toList();
    expect(c4, hasLength(1));
    expect(c4.single.length, 4);
    final audio = render(t, tied, PlaySettings(metronome: true));
    expect(audio.length, greaterThan(playbackRate * 4));
    expect(audio.any((v) => v.abs() > 0.05), isTrue);
  });

  test('every instrument makes a sound', () {
    final s = _chords();
    for (final i in Instrument.values) {
      final play = PlaySettings(parts: [PartMix(instrument: i)]);
      final audio = render(s, perform(s, play), play);
      expect(audio.any((v) => v.abs() > 0.01), isTrue, reason: i.name);
    }
  });

  test('chords from the notes', () {
    final g = guessChords(_chords());
    expect([for (final c in g) c.name], ['C', 'G7']);
    expect(chordsToChordPro(g, 2), '| [C] | [G7] |');
    // Played a tone higher.
    expect(guessChords(_chords(), shift: 2).map((c) => c.name), ['D', 'A7']);
  });

  test('exports: MusicXML, MIDI, WAV', () {
    final s = _chords()..title = 'Test';
    final xml = scoreToMusicXml(s);
    expect(xml, contains('<work-title>Test</work-title>'));
    expect('<step>C</step>'.allMatches(xml).length, 2);
    expect(xml, contains('<chord/>'));
    final midi = scoreToMidi(s, PlaySettings());
    expect(ascii.decode(midi.sublist(0, 4)), 'MThd');
    expect(midi.length, greaterThan(60));
    final wav = samplesToWav(Float32List.fromList([0, 0.5, -0.5]), 32000);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(wav.length, 44 + 6);
  });

  test('a score survives being kept', () async {
    KeyValueStore.memory.clear();
    KeyValueStore.bytes.clear();
    final s = _chords();
    final id = await ScanStore.add(
      'Kept',
      [ScanPage(Uint8List(4), 100, 100)],
      s,
      PlaySettings(tempo: 77),
    );
    final list = await ScanStore.list();
    expect(list.single.title, 'Kept');
    final (back, play, pages) = (await ScanStore.load(id))!;
    expect(back.notes, hasLength(s.notes.length));
    expect(play.tempo, 77);
    expect(pages, hasLength(1));
    await ScanStore.delete(id);
    expect(await ScanStore.list(), isEmpty);
  });

  testWidgets('scanner opens on its start page', (tester) async {
    KeyValueStore.memory.clear();
    final model = PresenterModel();
    await tester.pumpWidget(MaterialApp(home: ScannerScreen(model: model)));
    await tester.pump();
    expect(find.text('Read printed sheet music'), findsOneWidget);
    expect(find.text('Open photo, picture or PDF…'), findsOneWidget);
  });

  testWidgets('a kept scan: open it, see the notes, correct one', (
    tester,
  ) async {
    KeyValueStore.memory.clear();
    KeyValueStore.bytes.clear();
    final png = base64.decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    await tester.runAsync(
      () => ScanStore.add(
        'Hymn',
        [ScanPage(png, 100, 100)],
        _chords(),
        PlaySettings(),
      ),
    );
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ScannerScreen(model: PresenterModel())),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.tap(find.text('Hymn'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scan'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Correct notes (tap one)'));
    await tester.pumpAndSettle();
    // Tap the first note drawn.
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ScorePainter,
      ),
    );
    final layout = (paint.painter! as ScorePainter).layout;
    final origin = tester.getTopLeft(find.byWidget(paint));
    final first = layout.drawn.firstWhere((d) => d.note == 0);
    await tester.tapAt(origin + first.rect.center);
    await tester.pumpAndSettle();
    expect(find.text('C4'), findsOneWidget);
    await tester.tap(find.byTooltip('Higher'));
    await tester.pumpAndSettle();
    expect(find.text('D4'), findsOneWidget);
  });

  test('first and second endings, and time changes', () {
    ScoreMeasure bar(
      int i, {
      bool start = false,
      bool end = false,
      List<int>? ending,
    }) => ScoreMeasure(
      onset: 0,
      length: 4,
      page: 0,
      system: 0,
      box: Box(i * 100.0, 0, i * 100.0 + 100, 50),
      repeatStart: start,
      repeatEnd: end,
      ending: ending,
    );
    Score score(List<ScoreMeasure> ms) => Score(
      pages: [(10, 10)],
      systems: [],
      clefs: [Clef.treble],
      measures: ms,
      notes: [],
    );
    // |: 0 1 |1, 2. 2 :| 3. 3 | 4
    expect(
      score([
        bar(0, start: true),
        bar(1),
        bar(2, end: true, ending: [1, 2]),
        bar(3, ending: [3]),
        bar(4),
      ]).playOrder,
      [0, 1, 2, 0, 1, 2, 0, 1, 3, 4],
    );
    // A plain repeat, then another one later.
    expect(
      score([bar(0), bar(1, end: true), bar(2, start: true), bar(3, end: true)])
          .playOrder,
      [0, 1, 0, 1, 2, 3, 2, 3],
    );
    // |: 0 |1. 1 :| 2. 2 |
    expect(
      score([
        bar(0, start: true),
        bar(1, end: true, ending: [1]),
        bar(2, ending: [2]),
      ]).playOrder,
      [0, 1, 0, 2],
    );
    // 4/4, then a 2/4 bar.
    final s = _chords();
    s.measures.add(
      ScoreMeasure(
        onset: 8,
        length: 2,
        page: 0,
        system: 0,
        box: const Box(400, 0, 500, 50),
        time: (2, 4),
      ),
    );
    s.retime();
    expect(s.lengthOf(2), 2);
    expect(s.length, 10);
  });

  test('key changes and part names', () {
    final s = _chords();
    // Bar 2 changes to one flat: its B is B flat.
    s.measures[1].fifths = -1;
    s.retime();
    expect(s.fifthsAt(0), 0);
    expect(s.fifthsAt(1), -1);
    final b = s.notes.firstWhere((n) => n.measure == 1 && n.diatonic == 27);
    expect(b.midi, 58);
    // Voices over a piano.
    s.clefs = [Clef.treble, Clef.bass, Clef.treble, Clef.bass];
    expect(s.partNames, [
      'Voices (treble staff)',
      'Voices (bass staff)',
      'Piano right hand',
      'Piano left hand',
    ]);
    // Muting a part leaves it out of the sound.
    final quiet = PlaySettings(parts: [PartMix(muted: true)]);
    final one = _chords();
    expect(
      render(one, perform(one, quiet), quiet).every((v) => v == 0),
      isTrue,
    );
  });

  test('grand piano, sustain and reverb', () {
    final piano = PadSound.decode(
      File('assets/sounds/piano.pad').readAsBytesSync(),
    );
    expect(piano.zones.length, 30);
    final s = _chords();
    final dry = PlaySettings();
    final wet = PlaySettings(sustain: true, reverb: true);
    final a = render(s, perform(s, dry), dry, sounds: {grandPiano: piano});
    final b = render(s, perform(s, wet), wet, sounds: {grandPiano: piano});
    expect(a.any((v) => v.abs() > 0.05), isTrue);
    // Sustain and reverb carry the sound on after the last note.
    double tail(Float32List x) {
      final from = (8 * 60 / 100 * playbackRate).round() + playbackRate ~/ 4;
      var e = 0.0;
      for (
        var i = from;
        i < math.min(x.length, from + playbackRate ~/ 2);
        i++
      ) {
        e += x[i] * x[i];
      }
      return e;
    }

    expect(tail(b), greaterThan(tail(a)));
    expect(PlaySettings.fromJson(wet.toJson()).reverb, isTrue);
  });
}
