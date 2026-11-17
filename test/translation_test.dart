import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/translation.dart';
import 'package:flutter_test/flutter_test.dart';

const song = '''{title: Grace}
Verse 1:
[G]Amazing grace how [C]sweet the sound
That saved a [D]wretch like me

Chorus:
[C]My chains are gone

Verse 2:
Twas grace that taught
''';

Future<String> fake(String text, String lang) async =>
    text.split('\n').map((l) => l.isEmpty ? l : '[$lang] $l').join('\n');

void main() {
  test('each section gets a linked translation after it', () async {
    final progress = <int>[];
    final r = await translateSong(
      raw: song,
      structure: const [],
      language: languageFor('fr')!,
      translate: fake,
      onProgress: (d, t) => progress.add(d),
    );
    expect(progress.last, 3);
    expect(ChordPro.sectionNames(r.raw), [
      'Verse 1',
      'Verse 1 (FR)',
      'Chorus',
      'Chorus (FR)',
      'Verse 2',
      'Verse 2 (FR)',
    ]);
    // Lyrics only: no chords in the translation.
    expect(
      ChordPro.sectionText(r.raw, 'Verse 1 (FR)'),
      'Verse 1 (FR):\n[fr] Amazing grace how sweet the sound\n'
      '[fr] That saved a wretch like me',
    );
    expect(
      [for (final i in r.structure) (i.name, i.linked)],
      [
        ('Verse 1', true),
        ('Verse 1 (FR)', false),
        ('Chorus', true),
        ('Chorus (FR)', false),
        ('Verse 2', true),
        ('Verse 2 (FR)', false),
      ],
    );
    // Shown together: original and translation make one slide.
    final parts = ChordPro.parts(ChordPro.applyStructure(r.raw, r.structure));
    expect(parts, hasLength(3));
    expect(parts.first.slide, contains(linkSeparator));
    expect(translatedLanguages(r.raw), ['FR']);
  });

  test('a second language, updating, and removing', () async {
    final fr = await translateSong(
      raw: song,
      structure: const [
        StructureItem.section('Verse 1'),
        StructureItem.section('Chorus'),
        StructureItem.section('Verse 2'),
        StructureItem.section('Chorus'),
      ],
      language: languageFor('fr')!,
      translate: fake,
    );
    final es = await translateSong(
      raw: fr.raw,
      structure: fr.structure,
      language: languageFor('es')!,
      translate: fake,
    );
    expect(
      [for (final i in es.structure) i.name],
      [
        'Verse 1', 'Verse 1 (FR)', 'Verse 1 (ES)', //
        'Chorus', 'Chorus (FR)', 'Chorus (ES)',
        'Verse 2', 'Verse 2 (FR)', 'Verse 2 (ES)',
        'Chorus', 'Chorus (FR)', 'Chorus (ES)',
      ],
    );
    expect(
      [for (final i in es.structure.take(3)) i.linked],
      [true, true, false],
    );
    expect(translatedLanguages(es.raw), ['FR', 'ES']);

    // Again: replaced, not doubled.
    final again = await translateSong(
      raw: es.raw,
      structure: es.structure,
      language: languageFor('fr')!,
      translate: (t, l) async => 'new',
    );
    expect(
      ChordPro.sectionNames(again.raw).where((n) => n == 'Verse 1 (FR)'),
      hasLength(1),
    );
    expect(ChordPro.sectionText(again.raw, 'Verse 1 (FR)'), contains('new'));
    expect(again.structure, hasLength(12));

    // Remove French: Spanish stays linked to the originals.
    final noFr = removeTranslation(again.raw, again.structure, tag: 'FR');
    expect(translatedLanguages(noFr.raw), ['ES']);
    expect(
      [for (final i in noFr.structure.take(3)) (i.name, i.linked)],
      [('Verse 1', true), ('Verse 1 (ES)', false), ('Chorus', true)],
    );
    // Remove all: back to the song.
    final none = removeTranslation(noFr.raw, noFr.structure);
    expect(ChordPro.sectionNames(none.raw), ['Verse 1', 'Chorus', 'Verse 2']);
    expect(none.structure.every((i) => !i.linked), isTrue);
  });

  test('tags', () {
    expect(translationOf('Verse 1 (FR)'), ('Verse 1', 'FR'));
    expect(translationOf('Chorus (ZH-CN)'), ('Chorus', 'ZH-CN'));
    expect(translationOf('Verse 1'), isNull);
    expect(translationOf('Bridge (XX)'), isNull, reason: 'not a language');
  });
}
