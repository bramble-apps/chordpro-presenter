import 'package:bilingual_projector/bidi.dart';
import 'package:bilingual_projector/widgets/chord_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('which lines are right to left', () {
    expect(isRightToLeft('[G]שלום [D]עולם'), isTrue); // Hebrew
    expect(isRightToLeft('[Am]السلام عليكم'), isTrue); // Arabic
    expect(isRightToLeft('Amazing grace'), isFalse);
    expect(isRightToLeft('[G]Amazing'), isFalse); // chords don't count
    // Mostly English with one Hebrew word: left to right.
    expect(isRightToLeft('Hallelujah means הללויה in Hebrew'), isFalse);
    expect(directionOf('ברוך'), TextDirection.rtl);
  });

  testWidgets('a chord line laid out from the right', (tester) async {
    const pieces = [
      (chord: 'G ', lyric: 'שלום ', runs: null),
      (chord: 'D ', lyric: 'עולם', runs: null),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ChordLine(
              pieces: pieces,
              chordStyle: TextStyle(fontSize: 14),
              lyricStyle: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    final box = tester.renderObject<RenderChordLine>(find.byType(ChordLine));
    // The line sits at the right of the screen.
    final topLeft = box.localToGlobal(Offset.zero);
    expect(topLeft.dx + box.size.width, closeTo(800, 1));
    // The first words (and their chord) are on the right, the second on
    // their left; each chord over the right-hand end (the start) of its
    // words.
    final [(c1, l1), (c2, l2)] = box.placed;
    expect(c1.dx, greaterThan(c2.dx));
    expect(l1.dx, greaterThan(l2.dx));
    final words = box.size.width;
    expect(l1.dx, lessThan(words));
    expect(c1.dx, greaterThan(l1.dx)); // the chord's right edge = the words'
  });
}
