import 'package:bilingual_projector/chords/chord_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ChordLibrary.load());

  ChordShape first(Instrument i, String name, {int transpose = 0}) {
    final c = ChordName.parse(name, transpose: transpose)!;
    final shapes = ChordLibrary.shapesFor(i, c);
    expect(shapes, isNotEmpty, reason: '$name on ${i.name}');
    return shapes.first;
  }

  test('chord names → chord types', () {
    expect(normalizeSuffix(false, ''), 'major');
    expect(normalizeSuffix(true, ''), 'minor');
    expect(normalizeSuffix(false, 'maj7'), 'maj7');
    expect(normalizeSuffix(false, 'M7'), 'maj7');
    expect(normalizeSuffix(false, 'Δ'), 'maj7');
    expect(normalizeSuffix(true, '7b5'), 'm7b5');
    expect(normalizeSuffix(false, 'ø'), 'm7b5');
    expect(normalizeSuffix(false, '°7'), 'dim7');
    expect(normalizeSuffix(false, 'sus'), 'sus4');
    expect(normalizeSuffix(false, '2'), 'sus2');
    expect(normalizeSuffix(false, 'add2'), 'add9');
    expect(normalizeSuffix(false, '7(b9)'), '7b9');
    expect(normalizeSuffix(true, 'M7'), 'mmaj7');
    expect(normalizeSuffix(false, '69'), '6/9');
    expect(normalizeSuffix(false, 'xyz'), isNull);
    expect(ChordName.parse('N.C.'), isNull);
  });

  test('guitar lookups (shapes, enharmonics, slash chords)', () {
    final c = first(Instrument.guitar, 'C');
    expect(c.frets, [-1, 3, 2, 0, 1, 0]);
    expect(c.midi(), [48, 52, 55, 60, 64]);
    for (final name in [
      'Cm',
      'C7',
      'Cmaj7',
      'C#m7b5',
      'Bb',
      'Ebsus4',
      'F#m',
      'Gb',
      'A#m',
    ]) {
      first(Instrument.guitar, name);
    }
    // D/F#: a real slash shape, with F# in the bass.
    final dfs = first(Instrument.guitar, 'D/F#');
    expect(dfs.midi().first % 12, 6);
    // No shape of its own: the plain chord.
    expect(first(Instrument.guitar, 'Cmaj7/A').bass, isNull);
    // Transposed: G + 2 = A.
    expect(first(Instrument.guitar, 'G', transpose: 2).root, 9);
    // Capo raises the notes.
    expect(c.midi(capo: 2).first, 50);
  });

  test('ukulele and piano', () {
    expect(first(Instrument.ukulele, 'C').frets, [0, 0, 0, 3]);
    expect(first(Instrument.ukulele, 'C').midi(), [67, 60, 64, 72]);
    expect(first(Instrument.piano, 'C').keys, [48, 52, 55]);
    // C/E: E in the bass, then C E G above it.
    final ce = first(Instrument.piano, 'C/E').keys;
    expect(ce.first % 12, 4);
    expect(ce.map((k) => k % 12).toSet(), {0, 4, 7});
  });
}
