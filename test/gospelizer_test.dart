import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/export.dart';
import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/gospelizer.dart';
import 'package:bilingual_projector/justchords.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/chord_line.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const body =
    'Verse 1:\n'
    '[C]Blessed assurance, [F]Jesus is [C]mine\n'
    'Oh what a foretaste of [G]glory di[G7]vine\n'
    '[C]Heir of salvation, [F]purchase of [C]God\n'
    '[F]Born of His Spirit, [C]washed in His [G7]blood [C]\n'
    '\n'
    'Chorus:\n'
    '[C]This is my story, this is my song\n'
    '[G]Praising my Savior all the day [C]long\n'
    '[C]This is my story, [F]this is my song\n'
    '[C]Praising my Savior [G]all the day [C]long';

const hymn = '{title: Blessed Assurance}\n{key: C}\n\n$body';

/// Only added chords: approaches into the changes, walk-ups, 1–4–1.
const keepBody =
    'Verse 1:\n'
    '[C]Blessed [C7]assurance, [F]Jesus [G7]is [C]mine\n'
    'Oh [F/C]what [C]a [Am7]foretaste [D7]of [G]glory di[G7]vine\n'
    '[C]Heir [Dm7]of [C/E]salvation, [F]purchase [G7]of [C]God\n'
    '[F]Born of [Dm7]His [G7]Spirit, [C]washed [Am7]in [D7]His [G7]blood [C]\n'
    '\n'
    'Chorus:\n'
    '[C]This is my [F/C]story, [C]this is [Am7]my [D7]song\n'
    '[G]Praising my Savior all the [G7]day [C]long\n'
    '[C]This is [Gm7]my [C7]story, [F]this is [Dm7]my [G7]song\n'
    '[C]Praising [Am7]my [D7]Savior [G]all the [G7]day [C]long';

/// Also reharmonizes the song's own chords: colours, I7 → IV, borrowed iv,
/// IV/V, the tritone at a section end, bVI–bVII–I at the very end.
const subBody =
    'Verse 1:\n'
    '[Cadd9]Blessed [C7]assurance, [Fmaj7]Jesus [Fm6]is [Cadd9]mine\n'
    'Oh [F/C]what [Cadd9]a [Am7]foretaste [D7]of [G]glory di[F/G]vine\n'
    '[Cadd9]Heir of [C7]salvation, [Fmaj7]purchase [Fm6]of [Cadd9]God\n'
    '[Fmaj7]Born of [Dm7]His [G7]Spirit, [Cadd9]washed in His [Db7]blood [Cadd9]\n'
    '\n'
    'Chorus:\n'
    '[Cadd9]This is my [F/C]story, [Cadd9]this is [Am7]my [D7]song\n'
    '[F/G]Praising my Savior all the [G7]day [Cadd9]long\n'
    '[Cadd9]This is my [C7]story, [Fmaj7]this is [Dm7]my [G7]song\n'
    '[Cadd9]Praising [Am7]my [D7]Savior [Abmaj7]all the [Bb]day [Cadd9]long';

/// A CCM-style chart (made-up words): slash chords, a chord every few words.
const ccm =
    'Verse:\n'
    '[A]Higher than [E/G#]mountains, [F#m]higher than [E]stars\n'
    '[D]Higher than [E]oceans and [A]all of the [E/G#]earth\n'
    '[F#m]Higher than [E]reason and [D]all of our [A/C#]plans\n'
    '[Bm]You were there be[Esus]fore it be[E]gan\n'
    '\n'
    'Chorus:\n'
    '[A]Taken a[E/G#]way and laid in a [F#m]tomb\n'
    '[D]You went to [E]die, a[A]lone in the [E/G#]gloom\n'
    '[F#m]Like a [E]flower [D]crushed on the [A/C#]ground\n'
    '[Bm]You took the [E]fall and thought of [A]me\n'
    '[D]Higher than [E]all [A]';

/// Kept: a passing chord or two into each change.
const ccmKeep =
    'Verse:\n'
    '[A]Higher [B7]than [E/G#]mountains, [F#m]higher [B7]than [E]stars\n'
    '[D]Higher [D#dim7]than [E]oceans [E7]and [A]all [F#m7]of [B7]the [E/G#]earth\n'
    '[F#m]Higher [B7]than [E]reason [A7]and [D]all [Bm7]of [E7]our [A/C#]plans\n'
    '[Bm]You were there [B7]be[Esus]fore it be[E]gan\n'
    '\n'
    'Chorus:\n'
    '[A]Taken [B7]a[E/G#]way and laid [G#m7b5]in [C#7]a [F#m]tomb\n'
    '[D]You went [D#dim7]to [E]die, [E7]a[A]lone [F#m7]in [B7]the [E/G#]gloom\n'
    '[F#m]Like [B7]a [E]flower [D]crushed [Bm7]on [E7]the [A/C#]ground\n'
    '[Bm]You took [B7]the [E]fall and thought [E7]of [A]me\n'
    '[D]Higher [D#dim7]than [E]all [A]';

/// Reharmonized: borrowed iv into the I/3, the backdoor bVII9 ending.
const ccmSub =
    'Verse:\n'
    '[Aadd9]Higher [B7]than [E/G#]mountains, [F#m7]higher [B7]than [E]stars\n'
    '[Dmaj7]Higher than [E7]oceans and [Aadd9]all [F#m7]of [B7]the [E/G#]earth\n'
    '[F#m7]Higher [B7]than [E]reason [A7]and [Dmaj7]all of [Dm6]our [A2/C#]plans\n'
    '[Bm9]You were there [B7]be[Esus]fore it be[E]gan\n'
    '\n'
    'Chorus:\n'
    '[Aadd9]Taken [B7]a[E/G#]way and laid [G#m7b5]in [C#7]a [F#m7]tomb\n'
    '[Dmaj7]You went to [E7]die, a[Aadd9]lone [F#m7]in [B7]the [E/G#]gloom\n'
    '[F#m7]Like [B7]a [E]flower [Dmaj7]crushed on [Dm6]the [A2/C#]ground\n'
    '[Bm9]You took [B7]the [D/E]fall and thought [E7]of [Aadd9]me\n'
    '[Dmaj7]Higher than [G9]all [Aadd9]';

const c = MusicKey(0, false);

String merged(String raw, MusicKey key, {bool keep = true}) =>
    mergePassing(raw, gospelize(raw, key, keep: keep));

Future<PresenterModel> model(String raw) async {
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final m = PresenterModel();
  await m.load();
  m.addOrUpdate(Song(title: 'Blessed Assurance', raw: raw));
  return m;
}

void main() {
  // (Shelved in the app; the tests still cover it.)
  setUpAll(() => gospelizerEnabled = true);
  tearDownAll(() => gospelizerEnabled = false);

  group('reharmonization', () {
    test('keeping the song’s chords: a few approaches, at phrase ends', () {
      expect(merged(body, c), keepBody);
      // Added chords only: the song's own are untouched.
      expect(gospelize(body, c).where((p) => p.isSubstitute), isEmpty);
    });

    test('allowed to change them: a real reharmonization', () {
      expect(merged(body, c, keep: false), subBody);
    });

    test('CCM songs with busy, slash-chord lines', () {
      const a = MusicKey(9, false);
      expect(merged(ccm, a), ccmKeep);
      expect(merged(ccm, a, keep: false), ccmSub);
    });

    test('the tonic is never replaced, only turns I7 later', () {
      final moves = gospelize('[C]Sing [F]out', c, keep: false);
      expect(moves.map((p) => p.chord), isNot(contains('C7')));
    });

    test('target chords get their own ii–V (as in the reference video)', () {
      expect(
        merged('[C]Sing it out loud [F]now', c),
        '[C]Sing it [Gm7]out [C7]loud [F]now',
      );
      expect(
        merged('[F]Sing it out loud [Am7]now', c),
        '[F]Sing it [Bm7b5]out [E7]loud [Am7]now',
      );
      // After the target's ii already: only its V.
      expect(
        merged('[Dm]Lord you are good to [C]me', c),
        '[Dm]Lord you are good [G7]to [C]me',
      );
    });

    test('walk-ups and the "Amen" ending', () {
      // IV → V through #iv°7, I → ii through #i°7.
      expect(
        merged('[F]Sing praise to the Lord on [G]high', c),
        '[F]Sing praise to the Lord [F#dim7]on [G]high',
      );
      expect(
        merged('[C]Lord you are good to [Dm]me', c),
        '[C]Lord you [F/C]are [C]good [C#dim7]to [Dm]me',
      );
      // IV → I at the end of a section: the minor plagal.
      expect(
        merged('[F]Praise Him all creatures, a[C]men', c),
        '[F]Praise Him all creatures, [Fm6]a[C]men',
      );
      // … but not in the middle of one.
      expect(
        merged('[F]Praise Him all creatures, a[C]men\n[G]and [C]more', c),
        isNot(contains('Fm6')),
      );
    });

    test('minor keys', () {
      expect(
        merged(
          '[Am]Lord I lift your name on [Dm]high',
          const MusicKey(9, true),
        ),
        '[Am]Lord I lift your name [A7]on [Dm]high',
      );
    });

    test('flat keys are spelled with flats', () {
      expect(
        merged('[F]Sing to the Lord a new [Bb]song', const MusicKey(5, false)),
        '[F]Sing to [Bb/F]the [F]Lord [Cm7]a [F7]new [Bb]song',
      );
    });

    test('leaves alone what already leads there, or has no room', () {
      expect(gospelize('[G7]Sing it out loud [C]now', c), isEmpty);
      expect(gospelize('[Db7]Sing it out loud [C]now', c), isEmpty);
      expect(
        gospelize('[C]Sing it out loud [C/E]now', c).map((p) => p.why),
        isNot(contains(startsWith('V7'))),
      );
      // Held too briefly.
      expect(gospelize('[C]Hal[F]le[G]lu[C]jah', c), isEmpty);
      expect(gospelize('[C] [F] [G] [C]', c), isEmpty);
      // One word each: one chord into each change.
      expect(
        merged('[C]Sing it [F]out and [G]then go [C]home', c),
        '[C]Sing [C7]it [F]out [F#dim7]and [G]then [G7]go [C]home',
      );
      expect(merged('[C]Sing it [F]out', c), '[C]Sing [C7]it [F]out');
      // A chord outside the key isn't approached.
      expect(gospelize('[F]Sing it out loud [Bb]now', c), isEmpty);
    });

    test('the bass walks down into vi, the ii–V goes into IV', () {
      expect(
        merged('[C]We will sing it [Am]out and we will sing it [F]now', c),
        '[C]We will [C/B]sing [E7/G#]it [Am]out and we will [Gm7]sing [C7]it '
        '[F]now',
      );
    });

    test('an approach into every change there’s room for', () {
      final moves = gospelize(
        '[C]Sing it out loud and [F]sing it out loud and [G]now',
        c,
      );
      expect(moves.map((p) => p.why), ['ii/IV', 'V7/IV', '#°7 (walk-up)']);
    });

    test('a turnaround at the end of a section going back home', () {
      expect(
        merged(
          'Verse:\n[G]Sing it [C]out, we sing it all\n\nChorus:\n[C]Now',
          c,
        ),
        'Verse:\n[G]Sing [G7]it [C]out, we [Am7]sing [Dm7]it [G7]all\n\n'
        'Chorus:\n[C]Now',
      );
    });

    test('never across sections, N.C., tabs or directives', () {
      const raw =
          'Verse:\n[C]Sing it out loud now\n\nChorus:\n[G7]Sing again\n'
          '[C]Hold on now and [N.C.]then and [F]then\n'
          '{start_of_tab}\n[C]e|--0--| one two three four [F]x\n{end_of_tab}\n'
          '{comment: [C]note}';
      expect(gospelize(raw, c), isEmpty);
    });

    test('bar lines don’t break the run', () {
      expect(
        merged('[C]Sing it [|] out loud [F]now', c),
        '[C]Sing it [|] [Gm7]out [C7]loud [F]now',
      );
    });
  });

  group('layer and round trip', () {
    for (final keep in [true, false]) {
      test('on then off gives back the song exactly (keep: $keep)', () {
        final song = Song(title: 'Blessed Assurance', raw: hymn);
        final before = jsonEncode(song.toJson());
        song.setGospel(true, keep: keep);
        expect(song.gospelOn, isTrue);
        expect(song.raw, hymn, reason: 'the text itself is never changed');
        expect(song.gospelRaw(), endsWith(keep ? keepBody : subBody));
        // Kept with the song (a save and load keeps it).
        final again = Song.fromJson(jsonDecode(jsonEncode(song.toJson())));
        expect(again.gospelOn, isTrue);
        expect(again.passingChords, song.passingChords);
        song.setGospel(false);
        expect(jsonEncode(song.toJson()), before);
        expect(song.gospelRaw(), hymn);
      });
    }

    test('an edited text gets its chords worked out again', () {
      final song = Song(title: 'B', raw: hymn)..setGospel(true);
      song.raw = '{key: C}\n[C]Sing it out loud [F]now';
      expect(song.gospelRaw(), '{key: C}\n[C]Sing it [Gm7]out [C7]loud [F]now');
    });

    test('a layer from older rules is worked out again', () {
      final song = Song(title: 'B', raw: hymn)..setGospel(true);
      (song.extra['gospel'] as Map)
        ..['v'] = 1
        ..['chords'] = [
          {'at': 0, 'chord': 'X', 'why': ''},
        ];
      expect(song.gospelRaw(), endsWith(keepBody));
    });

    test('marked chords: added and changed, plain when rendered', () {
      final segs = ChordPro.segments(
        mergePassing('[C]Sing it [F]out', const [
          PassingChord(0, 'Cadd9', 'colour', replace: 3),
          PassingChord(8, 'C7', 'V7/IV'),
        ], mark: true),
      );
      expect(segs.firstWhere((s) => s.changed).chord, 'Cadd9');
      expect(segs.firstWhere((s) => s.passing).chord, 'C7');
      for (final m in [passingMark, changedMark]) {
        expect(
          renderChord(
            '${m}C7',
            transpose: 2,
            key: const MusicKey(2, false),
            notation: ChordNotation.standard,
            minorStyle: MinorStyle.m,
            accidentals: Accidentals.auto,
          ),
          'D7',
        );
      }
      // Rewriting into a key keeps the marks.
      expect(
        rewriteIntoKey('[${changedMark}C]x', 2, const MusicKey(2, false)),
        '[${changedMark}D]x',
      );
    });

    test('shelved: songs show as written, whatever the layer', () {
      final song = Song(title: 'B', raw: hymn)..setGospel(true);
      gospelizerEnabled = false;
      expect(song.gospelRaw(), hymn);
      expect(song.exportRaw, hymn);
      gospelizerEnabled = true;
      expect(song.gospelRaw(), isNot(hymn));
    });

    test('model toggles follow transposing; off restores the sheet', () async {
      final m = await model(hymn);
      m.setTranspose(2); // C -> D
      m.setGospel(true);
      expect(m.currentSpec!.raw, contains('[${passingMark}Am7]my'));
      expect(m.currentSong!.raw, hymn);
      m.setGospelKeep(false);
      expect(m.currentSpec!.raw, contains('[${changedMark}F/G]Praising'));
      m.setGospel(false);
      expect(m.currentSpec!.raw, isNot(contains(passingMark)));
      expect(m.currentSpec!.raw, isNot(contains(changedMark)));
      expect(m.currentSong!.extra.containsKey('gospel'), isFalse);
    });
  });

  group('exports', () {
    test(
      'ChordPro and text exports include the changes only while on',
      () async {
        final m = await model(hymn);
        m.setTranspose(2); // C -> D
        final off = exportChordPro(ExportSource.from(m), includeChords: true);
        expect(off, isNot(contains('Bm7')));
        m.setGospel(true);
        final on = exportChordPro(ExportSource.from(m), includeChords: true);
        expect(
          on,
          contains('[D]This is my [G/D]story, [D]this is [Bm7]my [E7]song'),
        );
        expect(on, isNot(contains(passingMark)));
        m.setGospelKeep(false);
        final sub = exportChordPro(ExportSource.from(m), includeChords: true);
        expect(
          sub,
          contains('[G/A]Praising my Savior all the [A7]day [Dadd9]long'),
        );
        expect(sub, isNot(contains(changedMark)));
        final text = exportText(ExportSource.from(m), includeChords: true);
        expect(text, contains('G/A'));
        expect(text, isNot(contains(changedMark)));
        m.setGospel(false);
        expect(exportChordPro(ExportSource.from(m), includeChords: true), off);
      },
    );

    test('JustChords rawData has the changes while on, plain', () async {
      final song = Song(title: 'Blessed Assurance', raw: hymn);
      expect(justChordsSong(song)['rawData'], hymn);
      song.setGospel(true, keep: false);
      final raw = justChordsSong(song)['rawData'] as String;
      expect(raw, endsWith(subBody));
      expect(raw, isNot(contains(passingMark)));
      expect(raw, isNot(contains(changedMark)));
      song.setGospel(false);
      expect(justChordsSong(song)['rawData'], hymn);
    });
  });

  group('sheet', () {
    Future<ChordLine> line(
      WidgetTester tester, {
      required bool glow,
      bool keep = true,
    }) async {
      final song = Song(title: 'T', raw: '{key: C}\n[C]Sing it out loud [F]now')
        ..setGospel(true, keep: keep);
      final raw = song.gospelRaw(mark: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChordSheet(
              song: song,
              raw: raw,
              format: SheetFormat(),
              transpose: 0,
              displayKey: c,
              parts: ChordPro.parts(raw),
              animate: false,
              passingGlow: glow,
            ),
          ),
        ),
      );
      return tester.widget<ChordLine>(find.byType(ChordLine).first);
    }

    int at(ChordLine l, String chord) =>
        l.pieces.indexWhere((p) => p.chord.startsWith(chord));

    testWidgets('added chords glow, the song’s own don’t', (tester) async {
      final l = await line(tester, glow: true);
      expect(l.glowing, {at(l, 'Gm7'), at(l, 'C7')});
    });

    testWidgets('changed chords glow too, without brackets', (tester) async {
      final l = await line(tester, glow: true, keep: false);
      expect(l.glowing, contains(at(l, 'Cadd9')));
      final plain = await line(tester, glow: false, keep: false);
      expect(at(plain, 'Cadd9'), isNot(-1));
      expect(at(plain, '(C7)'), isNot(-1));
      expect(plain.glowing, isEmpty);
    });

    testWidgets('without the glow added chords are in brackets', (
      tester,
    ) async {
      final l = await line(tester, glow: false);
      expect(at(l, '(C7)'), isNot(-1));
      expect(l.glowing, isEmpty);
    });
  });
}
