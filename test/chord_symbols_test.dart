import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/music.dart';
import 'package:flutter_test/flutter_test.dart';

String r(String chord, ChordSymbols s, {MinorStyle minor = MinorStyle.m}) =>
    renderChord(
      chord,
      transpose: 0,
      key: null,
      notation: ChordNotation.standard,
      minorStyle: minor,
      accidentals: Accidentals.auto,
      symbols: s,
    );

void main() {
  test('as written by default', () {
    for (final c in ['Cmaj7', 'CM7', 'Cm7b5', 'Cø7', 'Cdim7', 'C°', 'Cma7']) {
      expect(r(c, const ChordSymbols()), c);
    }
  });

  test('major sevenths one way', () {
    const tri = ChordSymbols(major: MajorSymbol.triangle);
    expect(r('Cmaj7', tri), 'C∆7');
    expect(r('CM9', tri), 'C∆9');
    expect(r('Cma7/E', tri), 'C∆7/E');
    expect(r('Cmaj7', const ChordSymbols(major: MajorSymbol.ma)), 'Cma7');
    expect(r('C∆7', const ChordSymbols(major: MajorSymbol.maj)), 'Cmaj7');
    // (minor chords and plain M are left alone)
    expect(r('Cm7', tri), 'Cm7');
    expect(r('Cma7', const ChordSymbols()), 'Cma7', reason: 'not minor');
  });

  test('half-diminished and diminished', () {
    const o = ChordSymbols(halfDim: HalfDimSymbol.slashedO);
    expect(r('Cm7b5', o), 'Cø7');
    expect(r('Cm7(b5)', o), 'Cø7');
    expect(r('Cø7', const ChordSymbols(halfDim: HalfDimSymbol.m7b5)), 'Cm7♭5');
    expect(
      r(
        'Cø7',
        const ChordSymbols(halfDim: HalfDimSymbol.m7b5),
        minor: MinorStyle.dash,
      ),
      'C-7♭5',
    );
    const circle = ChordSymbols(dim: DimSymbol.circle);
    expect(r('Cdim7', circle), 'C°7');
    expect(r('Cdim', circle), 'C°');
    expect(r('Co7', const ChordSymbols(dim: DimSymbol.dim)), 'Cdim7');
  });

  test('extension split for raising or lowering', () {
    expect(splitChordExtension('Cmaj7/E'), ('C', 'maj7', '/E'));
    expect(splitChordExtension('Am7'), ('Am', '7', ''));
    expect(splitChordExtension('F#m7b5'), ('F#m', '7b5', ''));
    expect(splitChordExtension('Gsus4'), ('G', 'sus4', ''));
    expect(splitChordExtension('C6/9'), ('C', '6/9', ''));
    expect(splitChordExtension('G7 (5)'), ('G', '7', ' (5)'));
    expect(splitChordExtension('C'), isNull);
    expect(splitChordExtension('Am'), isNull);
    expect(splitChordExtension('G/B'), isNull);
    expect(splitChordExtension('N.C.'), isNull);
  });

  test('the choices are kept with the format', () {
    final f = SheetFormat()
      ..majorSymbol = MajorSymbol.triangle
      ..halfDimSymbol = HalfDimSymbol.slashedO
      ..dimSymbol = DimSymbol.circle
      ..chordExtensions = ChordExtensions.lowered;
    final g = SheetFormat()..updateFrom(f.toJson());
    expect(g.majorSymbol, MajorSymbol.triangle);
    expect(g.halfDimSymbol, HalfDimSymbol.slashedO);
    expect(g.dimSymbol, DimSymbol.circle);
    expect(g.chordExtensions, ChordExtensions.lowered);
    // (older saved formats: as written, on the line)
    final old = SheetFormat()..updateFrom(const {});
    expect(old.majorSymbol, MajorSymbol.asWritten);
    expect(old.chordExtensions, ChordExtensions.inline);
  });
}
