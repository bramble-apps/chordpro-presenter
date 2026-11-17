import 'package:bilingual_projector/chordpro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample song splits into lyrics-only slides', () {
    final slides = ChordPro.parseToSlides(sampleChordPro);
    expect(slides, [
      'Amazing grace, how sweet the sound\n'
          'That saved a wretch like me\n'
          'I once was lost, but now am found\n'
          'Was blind, but now I see',
      "'Twas grace that taught my heart to fear\n"
          'And grace my fears relieved\n'
          'How precious did that grace appear\n'
          'The hour I first believed',
    ]);
  });

  test('header reads title and artist', () {
    final h = ChordProHeader.parse(sampleChordPro);
    expect(h.titles, ['Amazing Grace']);
    expect(h.artist, 'John Newton');
  });

  test('chords attach to the following word', () {
    final segs = ChordPro.segments('[Em]Amazing [D]grace');
    expect(segs.map((s) => (s.chord, s.text)).toList(), [
      ('Em', 'Amazing '),
      ('D', 'grace'),
    ]);
  });

  test('sheet hides metadata and keeps labels', () {
    final lines = ChordPro.sheetLines(sampleChordPro);
    expect(lines.first, 'Verse 1:');
    expect(lines.any((l) => l.contains('{')), isFalse);
  });

  test('section label detection', () {
    expect(ChordPro.isSectionLabel('Chorus 2'), isTrue);
    expect(ChordPro.isSectionLabel('Pre-chorus:'), isTrue);
    expect(ChordPro.isSectionLabel('Amazing grace'), isFalse);
  });

  test('labels written as comments are real section labels', () {
    const raw =
        '{c: Verse 1:}\n[G]Line one\n{comment: CHORUS}\n[C]Sing it\n'
        '{c: Instrumental}\n[D] [G]\n{c: To Chorus}\n';
    final parts = ChordPro.parts(raw);
    expect(parts.map((p) => p.lines.first).toList(), [
      'Verse 1:',
      'CHORUS:',
      'Instrumental:',
    ]);
    // Projector shows lyrics only: no labels, no performer notes.
    final slides = parts.map((p) => p.slide).toList();
    expect(slides, ['Line one', 'Sing it', '']);
    expect(slides.join(), isNot(contains('To Chorus')));
  });

  test('a label with a blank line under it joins its section', () {
    const raw = 'Chorus:\n\n[G]Bless the Lord\n\nVerse 1:\n[D]The sun';
    final parts = ChordPro.parts(raw);
    expect(parts.length, 2, reason: 'one press per section');
    expect(parts.first.lines.first, 'Chorus:');
    expect(parts.first.slide, 'Bless the Lord');
  });

  test('more label words are recognised', () {
    for (final l in [
      'Instrumental',
      'Turnaround:',
      'Post-Chorus',
      'Pré-refrain',
      'Final Chorus',
      'Chorus x2',
      'Coda',
    ]) {
      expect(ChordPro.isSectionLabel(l), isTrue, reason: l);
      expect(ChordPro.parseToSlides('$l\nWords here'), [
        'Words here',
      ], reason: l);
    }
  });

  test('linked sections in a structure become one slide', () {
    const raw =
        'Verse 1:\nAmazing grace\nHow sweet the sound\n\n'
        'Couplet 1:\nGrâce infinie\nQuel doux son\n\n'
        'Chorus:\nMy chains are gone';
    final arranged = ChordPro.applyStructure(raw, const [
      StructureItem.section('Verse 1', linked: true),
      StructureItem.section('Couplet 1'),
      StructureItem.section('Chorus'),
    ]);
    final parts = ChordPro.parts(arranged);
    expect(parts.length, 2);
    expect(parts[0].slide, contains('Amazing grace'));
    expect(parts[0].slide, contains('Grâce infinie'));
    expect(parts[0].slide, isNot(contains('{link}')));
    expect(
      parts[0].slide,
      'Amazing grace\nHow sweet the sound${linkSeparator}Grâce infinie\n'
      'Quel doux son',
      reason: 'linked pieces kept apart',
    );
    expect(parts[1].slide, contains('My chains are gone'));

    // Unlinked: three separate slides.
    final plain = ChordPro.parts(
      ChordPro.applyStructure(raw, const [
        StructureItem.section('Verse 1'),
        StructureItem.section('Couplet 1'),
        StructureItem.section('Chorus'),
      ]),
    );
    expect(plain.length, 3);

    // Saved and loaded with the link.
    final json = const StructureItem.section('Verse 1', linked: true).toJson();
    expect(StructureItem.fromJson(json)!.linked, isTrue);
    expect(
      StructureItem.fromJson(const StructureItem.section('X').toJson())!.linked,
      isFalse,
    );
  });

  test('a divider ends a section (a translation pasted below)', () {
    const raw =
        'Verse 1:\nOne\n\nChorus:\nHo\n\nVerse 2:\nTwo\n\n----\n\n'
        '*Hosanna\nUn chant\n\n{c:Refrain}\nHo FR\n';
    final out = ChordPro.applyStructure(raw, [
      StructureItem.section('Verse 1'),
      StructureItem.section('Verse 2'),
      StructureItem.section('Chorus'),
    ]);
    expect(out, isNot(contains('Un chant')));
    expect(out.indexOf('Two'), lessThan(out.indexOf('Ho')));
    expect(ChordPro.sectionText(raw, 'Verse 2'), 'Verse 2:\nTwo');
  });

  test('syllables join however they are spaced; credits leave slides', () {
    expect(ChordPro.joinSyllables('all  mea  -  sure'), 'all  measure');
    expect(
      ChordPro.joinSyllables('glo  -ry and fin -  ished'),
      'glory and finished',
    );
    expect(ChordPro.joinSyllables('Ho - san - na'), 'Hosanna');
    expect(ChordPro.joinSyllables('HO - SAN - NA'), 'HOSANNA');
    expect(ChordPro.joinSyllables('Lord - You reign'), 'Lord - You reign');
    expect(ChordPro.joinSyllables('au-delà'), 'au-delà');
    expect(
      ChordPro.parseToSlides(
        'The pain of [Em]sea  -  [D/F#]ring   [G]loss\n'
        'Many sons to [A]glo  -[|]  [D]ry\n\nCCLI# 155810\n© 1995 Music',
      ),
      ['The pain of searing loss\nMany sons to glory'],
    );
  });

  test('unlabelled lyrics get labels; repeats of a label get numbers', () {
    const fr =
        'Mon titre\n\nPremier couplet\n\nRefrain:\nGloire\n\n'
        'Deuxième couplet\n\nPont:\nToi seul\n\n----\nautre';
    expect(
      ChordPro.sectionNames(ChordPro.labelSections(fr, title: 'Mon titre')),
      ['Couplet 1', 'Refrain', 'Couplet 2', 'Pont'],
    );
    // A verse over two paragraphs stays one; a repeated label with new
    // words is the next verse; one with no words is a repeat.
    const en =
        'Verse:\nOne\n\nmore one\n\nChorus:\nHo\n\nVerse:\nTwo\n\nChorus:\n';
    expect(ChordPro.sectionNames(ChordPro.labelSections(en)), [
      'Verse',
      'Chorus',
      'Verse 2',
      'Chorus',
    ]);
    // Lyrics after an intro become a verse, and join the structure where
    // they were shown (after the intro).
    const intro = 'Intro:\n[G] [C]\n\nWords here\n\nChorus:\nHey';
    final (raw, st) = ChordPro.relabel(intro, [
      StructureItem.section('Intro'),
      StructureItem.section('Chorus'),
      StructureItem.section('Intro'),
    ]);
    expect(raw, contains('Verse 1:\nWords here'));
    expect(st.map((s) => s.name), [
      'Intro',
      'Verse 1',
      'Chorus',
      'Intro',
      'Verse 1',
    ]);
  });

  test('linked sections pair paragraph by paragraph, past instrumentals', () {
    const raw =
        'Chorus:\nBreath in our lungs\n\n[|][C] [|][Em7] [|]\n\n'
        '[|][G] [|][G] [|]\n\nChorus (FR):\nSouffle dans nos poumons';
    final parts = ChordPro.parts(
      ChordPro.applyStructure(raw, [
        StructureItem.section('Chorus', linked: true),
        StructureItem.section('Chorus (FR)'),
      ]),
    );
    expect(parts.map((p) => p.slide), [
      'Breath in our lungs${linkSeparator}Souffle dans nos poumons',
      '', // one blank slide for the instrumental, not two
    ]);
  });
}
