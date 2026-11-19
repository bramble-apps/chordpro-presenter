import 'package:bilingual_projector/widgets/capo_neck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CapoNeckMath', () {
    test('frets close up along the neck, and back again', () {
      const l = 560.0;
      expect(CapoNeckMath.fretAt(0, l), 0);
      final gaps = [for (var n = 1; n <= 12; n++) CapoNeckMath.fretAt(n.toDouble(), l) - CapoNeckMath.fretAt(n - 1.0, l)];
      for (var i = 1; i < gaps.length; i++) {
        expect(gaps[i], lessThan(gaps[i - 1]));
      }
      // each fret's gap is 2^(-1/12) of the last: the 12th's is 2^(-11/12) of the 1st's
      expect(gaps[11] / gaps[0], closeTo(0.5297, 0.001));
      for (final n in [1.0, 4.5, 11.0]) {
        expect(CapoNeckMath.fretOf(CapoNeckMath.fretAt(n, l), l), closeTo(n, 1e-9));
      }
    });

    test('the capo sits just behind its fret, parked above the nut at 0', () {
      const l = 560.0;
      expect(CapoNeckMath.capoAt(0, l), lessThan(0));
      for (var n = 1; n <= capoMax; n++) {
        final at = CapoNeckMath.capoAt(n.toDouble(), l);
        expect(at, lessThan(CapoNeckMath.fretAt(n.toDouble(), l)));
        expect(at, greaterThan(CapoNeckMath.fretAt(n - 1.0, l)));
      }
    });
  });

  testWidgets('tapping a fret moves the capo there and reports it', (t) async {
    final got = <int>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: CapoNeck(capo: 0, height: 430, onChanged: got.add),
        ),
      ),
    ));
    final box = t.getRect(find.byType(CapoNeck));
    // the middle of fret 3's space: 26 above the nut, the neck 560 long
    final y = 26 + (CapoNeckMath.fretAt(2, 560) + CapoNeckMath.fretAt(3, 560)) / 2;
    await t.tapAt(box.topLeft + Offset(60, y));
    await t.pumpAndSettle();
    expect(got.last, 3);
    // the arrow keys step it
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(got.last, 4);
  });
}
