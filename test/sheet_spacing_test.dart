import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/chord_line.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _song = Song(
  title: 'Spacing',
  raw: 'Verse 1:\n[G]One line\n[D]Two line\n[C]Three line',
);

Future<(Rect, Rect, Rect)> _sheet(WidgetTester tester, SheetFormat f) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChordSheet(
          song: _song,
          raw: _song.raw,
          format: f,
          transpose: 0,
          displayKey: null,
          parts: ChordPro.parts(_song.raw),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final lines = find.byType(ChordLine);
  return (
    tester.getRect(find.text('Spacing')),
    tester.getRect(lines.at(0)),
    tester.getRect(lines.at(1)),
  );
}

void main() {
  test('line spacing and margins are kept with the format', () {
    final f = SheetFormat()
      ..lineSpacing = 1.5
      ..margin = 40;
    final g = SheetFormat()..updateFrom(f.toJson());
    expect(g.lineSpacing, 1.5);
    expect(g.margin, 40);
    final old = SheetFormat()..updateFrom(const {});
    expect(old.lineSpacing, 1.0);
    expect(old.margin, 16);
  });

  testWidgets('margins move the sheet in; spacing spreads the lines', (
    tester,
  ) async {
    final (title, a, b) = await _sheet(tester, SheetFormat());
    final (wideTitle, wa, wb) = await _sheet(
      tester,
      SheetFormat()
        ..margin = 56
        ..lineSpacing = 2,
    );
    expect(wideTitle.left - title.left, closeTo(40, .5), reason: '16 → 56');
    expect(wa.left - a.left, closeTo(40, .5));
    expect(wb.top - wa.bottom, greaterThan(b.top - a.bottom + 10));
  });
}
