import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/translation.dart';
import 'package:bilingual_projector/widgets/presentation_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show pumpApp;

void main() {
  test('footer items on the first, last or every slide', () {
    expect(OnSlides.first.shows(0, 3), isTrue);
    expect(OnSlides.first.shows(1, 3), isFalse);
    expect(OnSlides.last.shows(2, 3), isTrue);
    expect(OnSlides.every.shows(1, 3), isTrue);
    expect(OnSlides.off.shows(0, 3), isFalse);
    // Older settings (true / false) still read.
    final p = ProjectionSettings()
      ..updateFrom({'footerTitle': false, 'footerCcli': 'last'});
    expect(p.footerTitle, OnSlides.off);
    expect(p.footerCcli, OnSlides.last);
  });

  test('an empty order keeps translations with their sections', () {
    final model = PresenterModel();
    final song = Song(
      title: 'S',
      raw: 'Verse 1:\nHello\n\nVerse 1 (FR):\nBonjour',
    );
    final st = model.structureFor(song, null);
    expect(st.map((s) => s.name), ['Verse 1', 'Verse 1 (FR)']);
    expect(st.first.linked, isTrue);
    expect(translatedLanguages(song.raw), ['FR']);
  });

  testWidgets('underscan: size, and drag the picture to a corner', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.updateSettings((s) => s.presentationMode = true);
    await tester.pumpAndSettle();
    final panel = find.byType(UnderscanPanel);
    expect(panel, findsOneWidget);
    await tester.ensureVisible(panel);
    await tester.tap(find.descendant(of: panel, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(model.projection.underscan, isTrue);

    // Drag the box up and left past the corner: it snaps there.
    final box = find.byKey(const ValueKey('underscan-box'));
    await tester.ensureVisible(box);
    await tester.drag(box, const Offset(-200, -200));
    await tester.pumpAndSettle();
    expect(model.projection.underscanX, -1);
    expect(model.projection.underscanY, -1);
    expect(
      find.descendant(of: panel, matching: find.textContaining('Top left')),
      findsOneWidget,
    );

    // Or tap one of the dots on the screen's edges.
    await tester.tap(find.bySemanticsLabel('Bottom right'));
    await tester.pumpAndSettle();
    expect(model.projection.underscanX, 1);
    expect(model.projection.underscanY, 1);
  });
}
