import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/widgets/chordpro_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suggestions: chords from the song, first-seen order, no words', () {
    const raw =
        "[G]'Tis so sweet to [C]trust in [C/G]Je - [G]sus\n"
        '[G]Just to take Him [D/F#]at [A7/E]His [D]word\n'
        '[D] [(][To Instrumental][)]';
    expect(chordSuggestions(raw), ['G', 'C', 'C/G', 'D/F#', 'A7/E', 'D']);
  });

  test('suggestions for a new song come from its key', () {
    expect(chordSuggestions('', key: const MusicKey(7, false)), [
      'G',
      'Am',
      'Bm',
      'C',
      'D',
      'Em',
    ]);
    expect(chordSuggestions('', key: const MusicKey(9, true)), [
      'Am',
      'C',
      'Dm',
      'Em',
      'F',
      'G',
    ]);
  });

  testWidgets('shortcut bar inserts at the cursor', (tester) async {
    final c = ChordProController(text: 'Amazing grace');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChordProField(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    // Chords suggested from the key of C (no chords yet).
    c.selection = const TextSelection.collapsed(offset: 8); // before "grace"
    await tester.tap(find.text('F'));
    await tester.pump();
    expect(c.text, 'Amazing [F]grace');

    // Now the song has F; [chord] wraps a selection.
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.tap(find.text('[chord]'));
    await tester.pump();
    expect(c.text, '[Amazing] [F]grace');

    c.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.text('[chord]'));
    await tester.pump();
    expect(c.text, '[][Amazing] [F]grace');
    expect(c.selection.baseOffset, 1, reason: 'cursor inside the brackets');
    await tester.tap(find.text('/'));
    await tester.pump();
    expect(c.text, '[/][Amazing] [F]grace');

    // Highlighting never changes the text.
    final span = c.buildTextSpan(
      context: tester.element(find.byType(TextField).first),
      withComposing: false,
    );
    expect(span.toPlainText(), c.text);
  });
}
