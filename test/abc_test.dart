import 'package:bilingual_projector/abc.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/scanner/engrave.dart';
import 'package:bilingual_projector/widgets/abc_view.dart';
import 'package:flutter/material.dart';
import 'package:bilingual_projector/scanner/score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a simple tune: header, lengths, key', () {
    final s = parseAbc(
      'X:1\nT:Amazing Grace\nM:3/4\nL:1/4\nQ:1/4=80\nK:G\n'
      'D | G2 B/G/ | B2 A | G2 E | D2 D |]',
    )!;
    expect(s.title, 'Amazing Grace');
    expect((s.beats, s.beatType, s.fifths, s.tempo), (3, 4, 1, 80));
    // The pickup, then four full bars.
    expect(s.measures.map((m) => m.length), [1, 3, 3, 3, 3]);
    final notes = s.notes.where((n) => !n.rest).toList();
    expect(notes.first.midi, 62); // D4
    expect(notes[1].midi, 67); // G4, a half note
    expect(notes[1].type, 'half');
    expect(notes[2].type, 'eighth'); // B/
    expect(notes[2].onset, 3); // after the pickup and the half note
  });

  test('accidentals, octaves, chords, ties, triplets, broken rhythm', () {
    final s = parseAbc(
      'M:4/4\nL:1/8\nK:F\n'
      "B ^F F c' C, [CEG]2 G-G | (3ABc d>e f4 |]",
    )!;
    final n = s.notes;
    expect(n[0].alter, -1); // B flat from the key
    expect(n[1].alter, 1); // ^F
    expect(n[2].alter, 1); // still sharp in the bar
    expect(n[3].diatonic, 42); // c' = C6
    expect(n[4].diatonic, 21); // C, = C3
    expect(n.where((x) => x.chord >= 0).length, 3);
    expect(n.firstWhere((x) => x.tie).diatonic, 32); // G4
    final trip = n.where((x) => x.triplet).toList();
    expect(trip, hasLength(3));
    expect(trip.first.duration, closeTo(1 / 3, 1e-9));
    final d = n.firstWhere((x) => x.diatonic == 36); // d (D5)
    expect(d.duration, 0.75); // d>e: dotted
    expect(n.firstWhere((x) => x.diatonic == 37).duration, 0.25);
  });

  test('repeats and endings play in order', () {
    final s = parseAbc('M:2/4\nL:1/4\nK:C\n|: C D | [1 E F :| [2 G A |]')!;
    expect(s.measures.first.repeatStart, isTrue);
    expect(s.measures[1].ending, [1]);
    expect(s.measures[1].repeatEnd, isTrue);
    expect(s.measures[2].ending, [2]);
    expect(s.playOrder, [0, 1, 0, 2]);
  });

  test('back to ABC and read again: the same music', () {
    const tune =
        'X:1\nT:Test\nM:3/4\nL:1/8\nK:D\n'
        "A2 | d2 f2 a2 | ^g4 e2 | [DFA]6 | (3def g>f e2 |]";
    final a = parseAbc(tune)!;
    final b = parseAbc(scoreToAbc(a))!;
    List<(int, double, double)> key(Score s) => [
      for (final n in s.notes)
        if (!n.rest) (n.midi, n.onset, n.duration),
    ];
    expect(key(b), key(a));
    expect(b.fifths, 2);
  });

  test('keys and modes', () {
    expect(abcKey('G').$1, 1);
    expect(abcKey('Dm').$1, -1);
    expect(abcKey('A dorian').$1, 1); // = G major
    expect(abcKey('Bb').$1, -2);
    expect(abcKey('none').$1, 0);
    expect(abcKey('C clef=bass').$2, Clef.bass);
    expect(parseAbc('X:1\nK:C\n'), isNull);
  });

  const song =
      '{title: Hymn}\nVerse 1:\n[G]Amazing grace\n\n'
      '{start_of_abc}\nX:1\nM:3/4\nL:1/4\nK:G\n\nD | G2 B |]\n'
      '{end_of_abc}\n\nChorus:\n[C]How sweet';

  test('in a song: one sheet line, never on slides, kept in one section', () {
    final sheet = ChordPro.sheetLines(song);
    final abc = sheet.where((l) => l.startsWith(abcMarker)).toList();
    expect(abc, hasLength(1));
    expect(abc.single.substring(abcMarker.length).split(tabLineBreak), [
      'X:1',
      'M:3/4',
      'L:1/4',
      'K:G',
      '',
      'D | G2 B |]',
    ]);
    // Nothing of it is read as lyrics or chords.
    expect(
      sheet.any((l) => !l.startsWith(abcMarker) && l.contains('G2 B')),
      isFalse,
    );
    final slides = ChordPro.parseToSlides(song);
    expect(slides.join('\n'), isNot(contains('G2')));
    expect(slides.join('\n'), isNot(contains('X:1')));
    // The blank line inside the tune doesn't split it.
    final parts = ChordPro.parts(song);
    expect(
      parts.where((p) => p.raw.contains('{start_of_abc}')).single.raw,
      contains('{end_of_abc}'),
    );
  });

  testWidgets('drawn as music with a play button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AbcView(
              lines: 'T:Tune\nM:4/4\nL:1/8\nK:D\nDEFG ABcd|]'.split('\n'),
              style: const TextStyle(fontSize: 16),
              ink: Colors.black,
              accent: Colors.blue,
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Play this tune'), findsOneWidget);
    expect(find.text('Tune'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ScorePainter,
      ),
      findsOneWidget,
    );
  });
}
