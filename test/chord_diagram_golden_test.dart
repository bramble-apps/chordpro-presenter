import 'package:bilingual_projector/chords/chord_db.dart';
import 'package:bilingual_projector/chords/chord_diagram.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chord diagrams', (tester) async {
    await tester.runAsync(ChordLibrary.load);
    tester.view.physicalSize = const Size(760, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget d(Instrument i, String name, {int pick = 0}) {
      final shapes = ChordLibrary.shapesFor(i, ChordName.parse(name)!);
      return ChordDiagram(
        name: name,
        shape: shapes[pick],
        instrument: i,
        selected: name == 'F',
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Wrap(
            children: [
              d(Instrument.guitar, 'C'),
              d(Instrument.guitar, 'F'),
              d(Instrument.guitar, 'C', pick: 1),
              d(Instrument.guitar, 'D/F#'),
              d(Instrument.guitar, 'F#m'),
              d(Instrument.ukulele, 'C'),
              d(Instrument.piano, 'C'),
              d(Instrument.piano, 'C/E'),
            ],
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chord_diagrams.png'),
    );
  });
}
