import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/tabs.dart';
import 'package:bilingual_projector/widgets/tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _riff = [
  'e|-----0-----|-----3-----|',
  'B|---1---1---|---0---0---|',
  'G|-2-------2-|-0-------0-|',
  'D|-----------|-----------|',
  'A|-3---------|-----------|',
  'E|-----------|-3---------|',
];

void main() {
  test('tab lines are recognised, words are not', () {
    expect(isTabLine('e|--0--3--|'), isTrue);
    expect(isTabLine('|---5h7---|'), isTrue);
    expect(isTabLine('D|-----'), isTrue);
    expect(isTabLine('E|------|-5-2-|---v-2->-|'), isTrue);
    expect(isTabLine('A|--7~~--PM----x-x-|'), isTrue);
    expect(isTabLine('Amazing grace'), isFalse);
    expect(isTabLine('[G]Here I am | to worship'), isFalse);
  });

  test('tabs stay on the sheet as one block, off the slides', () {
    const song =
        '{title: T}\n{start_of_tab}\nIntro riff\ne|---0---|\nB|---1---|\n'
        'G|---2---|\n{end_of_tab}\n[G]Words here';
    final sheet = ChordPro.sheetLines(song);
    final tab = sheet.where((l) => l.startsWith(tabMarker)).toList();
    expect(tab, hasLength(1));
    expect(tab.first.substring(tabMarker.length).split(tabLineBreak), [
      'Intro riff',
      'e|---0---|',
      'B|---1---|',
      'G|---2---|',
    ]);
    final slides = ChordPro.parseToSlides(song).join('\n');
    expect(slides, contains('Words here'));
    expect(slides, isNot(contains('|---')));
    expect(slides, isNot(contains('Intro riff')));
  });

  test('pasted tab lines without a block are collapsed too', () {
    final sheet = ChordPro.sheetLines(['Verse', ..._riff, 'More'].join('\n'));
    expect(sheet.where((l) => l.startsWith(tabMarker)), hasLength(1));
  });

  test('notes, bars and tuning', () {
    final b = parseTab(_riff);
    final s = b.systems.single;
    expect(s.strings.map((x) => x.open), [64, 59, 55, 50, 45, 40]);
    expect(s.bars, {11, 23});
    expect(s.notes.first.fret, anyOf(2, 3));
    expect(s.notes.where((n) => n.string == 0).map((n) => n.fret), [0, 3]);
    expect(tuningFor(['A', 'E', 'C', 'G']), [69, 64, 60, 67]);
    expect(tuningFor(['d', 'A', 'F', 'D', 'A', 'D']), [62, 57, 53, 50, 45, 38]);
  });

  test('a tab plays', () {
    final (samples, at) = renderTab(parseTab(_riff).systems.single, bpm: 100);
    expect(samples.length, greaterThan(tabSampleRate));
    expect(samples.any((v) => v.abs() > 0.1), isTrue);
    expect(at(5), greaterThan(at(1)));
  });

  testWidgets('modern and classic views, with a play button', (tester) async {
    for (final modern in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabView(
              lines: _riff,
              modern: modern,
              style: const TextStyle(fontSize: 16),
              ink: Colors.black,
              accent: Colors.blue,
            ),
          ),
        ),
      );
      expect(find.byTooltip('Play this tab'), findsOneWidget);
      if (!modern) expect(find.textContaining('e|-----0'), findsOneWidget);
    }
  });
}
