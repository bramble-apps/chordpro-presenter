import 'package:bilingual_projector/music.dart';
import 'package:flutter_test/flutter_test.dart';

String r(
  String c, {
  int t = 0,
  MusicKey? key,
  ChordNotation n = ChordNotation.standard,
  MinorStyle m = MinorStyle.m,
  Accidentals a = Accidentals.auto,
}) => renderChord(
  c,
  transpose: t,
  key: key,
  notation: n,
  minorStyle: m,
  accidentals: a,
);

void main() {
  const g = MusicKey(7, false);

  test('transposes with key-appropriate accidentals', () {
    expect(r('G', t: 3, key: g.transposed(3)), 'Bb');
    expect(r('D/F#', t: 2, key: g.transposed(2)), 'E/G#');
    expect(r('Em7', t: -2, key: g.transposed(-2)), 'Dm7');
    expect(r('Cmaj7', t: 2, key: g.transposed(2)), 'Dmaj7');
  });

  test('minor styles', () {
    expect(r('Em7', m: MinorStyle.mi), 'Emi7');
    expect(r('Em', m: MinorStyle.min), 'Emin');
    expect(r('Em', m: MinorStyle.dash), 'E-');
    expect(r('Em7', m: MinorStyle.lower), 'e7');
    expect(r('F#m', m: MinorStyle.lower), 'f#');
  });

  test('notations', () {
    expect(r('Bb', n: ChordNotation.solfege), 'Sib');
    expect(r('Em', n: ChordNotation.solfege), 'Mim');
    expect(r('C', key: g, n: ChordNotation.roman), 'IV');
    expect(r('Em', key: g, n: ChordNotation.roman, m: MinorStyle.lower), 'vi');
    expect(r('D/F#', key: g, n: ChordNotation.numbers), '5/7');
    expect(
      r('Em', key: g, n: ChordNotation.numbers, m: MinorStyle.lower),
      '6-',
    );
    expect(r('F', key: g, n: ChordNotation.numbers), 'b7');
  });

  test('non-chords are untouched', () {
    expect(r('N.C.', t: 2), 'N.C.');
  });

  test('key detection', () {
    expect(
      detectKey('[Em]a [D]b [G]c [D]d [G]e [Em]f [D]g [G]h [D]i', null)!.name,
      'G',
    );
    expect(detectKey('[Am]a [Dm]b [E7]c [Am]d', null)!.name, 'Am');
    expect(detectKey('', 'Bb')!.name, 'Bb');
    expect(MusicKey.parse('F# minor')!.name, 'F#m');
  });

  test('accidentals override', () {
    // Key of G prefers sharps
    const g = MusicKey(7, false);
    // Auto: uses key preference (sharps for G)
    expect(r('F', t: 1, key: g, a: Accidentals.auto), 'F#');
    // Sharps: always sharps
    expect(r('F', t: 1, key: g, a: Accidentals.sharps), 'F#');
    // Flats: always flats
    expect(r('F', t: 1, key: g, a: Accidentals.flats), 'Gb');

    // Key of F prefers flats
    const f = MusicKey(5, false);
    // Auto: uses key preference (flats for F)
    expect(r('G', t: -1, key: f, a: Accidentals.auto), 'Gb');
    // Sharps: always sharps
    expect(r('G', t: -1, key: f, a: Accidentals.sharps), 'F#');
    // Flats: always flats
    expect(r('G', t: -1, key: f, a: Accidentals.flats), 'Gb');

    // Bass notes also affected
    expect(r('D/F#', t: 2, key: g, a: Accidentals.flats), 'E/Ab');
    expect(r('D/F#', t: 2, key: g, a: Accidentals.sharps), 'E/G#');
    expect(r('D/F#', t: 2, key: g, a: Accidentals.auto), 'E/G#');

    // Without a key, auto falls back to original spelling
    expect(r('F', t: 1, a: Accidentals.auto), 'F#');
    expect(r('Gb', t: 1, a: Accidentals.auto), 'G');
    expect(r('F', t: 1, a: Accidentals.sharps), 'F#');
    expect(r('F', t: 1, a: Accidentals.flats), 'Gb');

    // Without transposing, auto keeps the author's spelling; an explicit
    // choice still respells
    expect(r('Gb', t: 0, key: g, a: Accidentals.auto), 'Gb');
    expect(r('F#', t: 0, a: Accidentals.flats), 'Gb');
    expect(r('Gb', t: 0, a: Accidentals.sharps), 'F#');
    expect(r('D/F#', t: 0, a: Accidentals.flats), 'D/Gb');
  });
}
