import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('section names shorten for a margin badge', () {
    final got = {
      for (final n in [
        'Verse 1', 'Chorus', 'Pre-Chorus 2', 'Bridge', 'Intro', 'Outro', 'Tag',
        'Couplet 2', 'Refrain', 'Pont', 'Verse 1 (FR)', 'Chorus 2', 'Interlude', 'Something',
      ])
        n: ChordPro.sectionAbbreviation(n),
    };
    expect(got, {
      'Verse 1': 'V1', 'Chorus': 'C', 'Pre-Chorus 2': 'PC2', 'Bridge': 'B', 'Intro': 'I',
      'Outro': 'O', 'Tag': 'T', 'Couplet 2': 'V2', 'Refrain': 'C', 'Pont': 'B',
      'Verse 1 (FR)': 'V1', 'Chorus 2': 'C2', 'Interlude': 'In', 'Something': 'So',
    });
  });

  test('the setting is saved, off by default', () {
    expect(SheetFormat().marginLabels, '');
    final f = SheetFormat()..marginLabels = 'right';
    expect((SheetFormat()..updateFrom(f.toJson())).marginLabels, 'right');
  });

  for (final side in ['left', 'right']) {
    testWidgets('labels in the $side margin: badges, not label lines', (t) async {
      const raw = 'Verse 1:\n[G]Amazing [C]grace\n\nChorus:\n[D]How sweet the [G]sound';
      final song = Song(title: 'T', raw: raw);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChordSheet(
            song: song,
            raw: raw,
            format: SheetFormat()..marginLabels = side,
            transpose: 0,
            displayKey: null,
            parts: ChordPro.parts(raw),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('V1'), findsOneWidget);
      expect(find.text('C'), findsWidgets);
      expect(find.textContaining('Verse 1'), findsNothing);
      // the badge is on the chosen side of the words
      final badge = t.getCenter(find.text('V1'));
      final mid = t.getCenter(find.byType(ChordSheet)).dx;
      expect(side == 'left' ? badge.dx < mid : badge.dx > mid, isTrue);
    });
  }
}
