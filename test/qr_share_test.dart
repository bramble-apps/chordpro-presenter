import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/qr_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

String verse(int n) =>
    '{start_of_verse: Verse $n}\n'
    '[G]Amazing [C]grace, how [G]sweet the sound, that [D]saved a wretch like me\n'
    '[G]I once was [C]lost but [G]now am found, was [D]blind but [G]now I see\n'
    '{end_of_verse}';

void main() {
  test('a song fits one code, medium error correction when it can', () {
    final parts = qrParts('{title: Short}\n${verse(1)}\n', 'Short');
    expect(parts, hasLength(1));
    expect(parts.single.level, QrErrorCorrectLevel.M);
    expect(parts.single.text, contains('Amazing'));
  });

  test('accents survive', () {
    final parts = qrParts(
      '{title: Alléluia}\nÀ toi la gloire, ô Ressuscité\n',
      'Alléluia',
    );
    expect(parts.single.text, contains('Ressuscité'));
  });

  test('a very long song splits in two at a section break', () {
    final long = [
      '{title: Long}',
      for (var i = 1; i <= 26; i++) verse(i),
      '{footer: © Someone · CCLI 123}',
    ].join('\n\n');
    expect(long.length, greaterThan(3000));
    final parts = qrParts(long, 'Long');
    expect(parts, hasLength(2));
    expect(parts[0].text, contains('(part 1 of 2)'));
    expect(parts[1].text, startsWith('Long (part 2 of 2)'));
    // Nothing lost, nothing cut mid-section.
    for (var i = 1; i <= 26; i++) {
      expect(parts.where((p) => p.text.contains('Verse $i}')), hasLength(1));
    }
    expect(parts[1].text, contains('CCLI 123'));
    for (final p in parts) {
      expect(qrVersionFor(p.text, p.level), isNotNull);
    }
  });

  testWidgets('the song menu shows its code', (tester) async {
    KeyValueStore.memory.clear();
    final model = PresenterModel();
    await tester.runAsync(model.load);
    final song = Song(title: 'Test', raw: '{title: Test}\n${verse(1)}\n');
    model.addOrUpdate(song);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTextQr(context, song.title, song.raw),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scan with any phone camera'), findsOneWidget);
    expect(find.byTooltip('Print'), findsOneWidget);
  });
}
