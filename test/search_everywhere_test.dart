import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/chordpro_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show pumpApp;

void main() {
  test('editor Find: accents don\'t matter, unless Match case', () {
    final c = ChordProController(text: 'Alléluia, [G]alleluia, ALLÉLUIA');
    c.setFind('alleluia');
    expect(c.matches.length, 3);
    // The places are the places in the text (replace swaps just those).
    expect(
      c.text.substring(c.matches.first.start, c.matches.first.end),
      'Alléluia',
    );
    c.setFind('Alléluia', matchCase: true);
    expect(c.matches.length, 1);
  });

  testWidgets('Add songs finds songs by their lyrics, like the side pane', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(title: 'Psalm 23', raw: 'The Lord is my shepherd, I shall not want'),
    );
    final set = model.createSetlist('Sunday');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Setlists ('), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text(set.name));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add songs to "Sunday"'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'shepherd');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Psalm 23'), findsOneWidget);
    expect(
      find.widgetWithText(CheckboxListTile, 'Amazing Grace'),
      findsNothing,
    );
    // Where it was found, under the title.
    expect(find.textContaining('shepherd'), findsWidgets);
  });
}
