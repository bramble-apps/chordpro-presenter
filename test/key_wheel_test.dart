import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/widgets/key_wheel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyWheelMath', () {
    test('positions on the circle of fifths', () {
      expect(KeyWheelMath.majorAt(0), 0); // C
      expect(KeyWheelMath.majorAt(7), 1); // G
      expect(KeyWheelMath.majorAt(4), 4); // E
      expect(KeyWheelMath.majorAt(5), 11); // F
      expect(KeyWheelMath.minorAt(9), 0); // Am inside C
      expect(KeyWheelMath.minorAt(1), 4); // C#m inside E
      expect(KeyWheelMath.positionOf(const MusicKey(4, false)), 4);
      expect(KeyWheelMath.positionOf(const MusicKey(9, true)), 0);
    });

    test('offsets as the key menu shows them', () {
      // from E: Bb is -6, A is +5, F# is +2
      expect(KeyWheelMath.offset(4, 10), -6);
      expect(KeyWheelMath.offset(4, 3), 5);
      expect(KeyWheelMath.offset(4, 6), 2);
      expect(KeyWheelMath.offset(4, 4), 0);
    });

    test("a song's chords land on the wheel, borrowed and extended ones too", () {
      final cs = ['E', 'A', 'B7', 'C#m7', 'Asus2', 'Cmaj7', 'D', 'G#dim', 'F#m7b5', 'E']
          .map(Chord.parse)
          .whereType<Chord>();
      final m = KeyWheelMath.marks(cs);
      expect(m[(false, 4)], 2); // E twice
      expect(m[(false, 3)], 2); // A and Asus2
      expect(m[(false, 5)], 1); // B7
      expect(m[(true, 4)], 1); // C#m7 inside E
      expect(m[(false, 0)], 1); // Cmaj7: borrowed (bVI)
      expect(m[(false, 2)], 1); // D: borrowed (bVII)
      expect(m[(true, 5)], 1); // G#dim: inside, where G#m sits (inside B)
      expect(m[(true, 3)], 1); // F#m7b5 inside, where F#m sits (inside A)
    });

    test('the chords of a key', () {
      final g = KeyWheelMath.degrees(1, false).map((d) => d.$2).toList();
      expect(g, ['G', 'Am', 'Bm', 'C', 'D', 'Em', 'F#°']);
      expect(KeyWheelMath.degrees(4, false).last.$2, 'D#°'); // E major's vii°
      expect(KeyWheelMath.degrees(6, false)[4].$2, 'C#'); // F# major's V
      final am = KeyWheelMath.degrees(0, true).map((d) => d.$2).toList();
      expect(am, ['Am', 'B°', 'C', 'Dm', 'Em', 'F', 'G']);
    });
  });

  testWidgets('tapping a key and the middle turns the wheel and reports the offset', (t) async {
    final got = <int>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: KeyWheel(
            original: const MusicKey(4, false), // E
            offset: 0,
            chords: [Chord.parse('E')!, Chord.parse('A')!],
            onChanged: got.add,
          ),
        ),
      ),
    ));
    expect(find.text('E'), findsWidgets);
    // the key one place clockwise of the top (B) is +7 semitones from E, shown as −5
    final wheel = t.getRect(find.byType(KeyWheel));
    final top = Offset(wheel.center.dx, wheel.top + 150 - 150 * .73);
    final right = Offset(top.dx + 150 * .73 * .5, wheel.top + 150 - 150 * .73 * .866);
    await t.tapAt(right);
    await t.pumpAndSettle();
    expect(got.last, -5);
    // the middle: back to the original
    await t.tapAt(Offset(wheel.center.dx, wheel.top + 150));
    await t.pumpAndSettle();
    expect(got.last, 0);
  });
}
