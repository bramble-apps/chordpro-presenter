import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/chord_line.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:bilingual_projector/widgets/song_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _sheet(WidgetTester tester, double width, Song song) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChordSheet(
          song: song,
          raw: song.raw,
          format: SheetFormat(),
          transpose: 0,
          displayKey: null,
          soundingKey: MusicKey.parse('G'),
          parts: ChordPro.parts(song.raw),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('tempo and time read as printed music', () {
    expect(SongMarks.tempoText('73'), '73');
    expect(SongMarks.tempoText('73 BPM'), '73');
    expect(SongMarks.tempoText('Slow'), 'Slow');
    expect(SongMarks.timeParts('4/4'), ('4', '4'));
    expect(SongMarks.timeParts(' 6 / 8 '), ('6', '8'));
    expect(SongMarks.timeParts('cut'), isNull);
  });

  testWidgets('tempo, then time, then key; missing ones left out', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SongMarks(tempo: '73 BPM', time: '4/4', keyName: 'G'),
        ),
      ),
    );
    final tempo = tester.getCenter(find.text('= 73'));
    final four = tester.getCenter(find.text('4').first);
    final key = tester.getCenter(find.text('G'));
    expect(tempo.dx, lessThan(four.dx));
    expect(four.dx, lessThan(key.dx));
    // the time signature stacked: 4 over 4
    final fours = find.text('4').evaluate().toList();
    expect(fours, hasLength(2));
    expect(
      tester.getCenter(find.text('4').first).dy,
      lessThan(tester.getCenter(find.text('4').last).dy),
    );
    // the key no taller than a little over the numbers
    expect(
      tester.getSize(find.text('G')).height,
      lessThan(tester.getSize(find.text('= 73')).height * 1.2),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SongMarks(tempo: '', time: '', keyName: 'Em'),
        ),
      ),
    );
    expect(find.text('Em'), findsOneWidget);
    expect(find.textContaining('='), findsNothing);
  });

  final song = Song(
    title: '10 000 Reasons',
    artist: 'Matt Redman',
    raw: 'Chorus:\n[G]Bless the [D]Lord',
    tempo: '73',
    timeSignature: '4/4',
  );

  testWidgets('beside the title when wide, under the artist when narrow', (
    tester,
  ) async {
    await _sheet(tester, 1000, song);
    var title = tester.getRect(find.text('10 000 Reasons'));
    var marks = tester.getRect(find.byType(SongMarks));
    expect(marks.left, greaterThan(title.right), reason: 'at its right');
    expect(marks.top, lessThan(title.bottom), reason: 'level with it');

    await _sheet(tester, 360, song);
    final artist = tester.getRect(find.text('Matt Redman'));
    marks = tester.getRect(find.byType(SongMarks));
    title = tester.getRect(find.text('10 000 Reasons'));
    expect(marks.top, greaterThanOrEqualTo(artist.bottom));
    expect(marks.left, closeTo(title.left, .5));
    // nothing written out again in the details line
    expect(find.textContaining('BPM'), findsNothing);
    expect(find.textContaining('Key G'), findsNothing);
  });

  // The words start in line with the title (the selection's highlight and
  // bar reach out past them, into the margin).
  testWidgets('the parts\' words are in line with the title', (tester) async {
    await _sheet(tester, 1000, song);
    final title = tester.getRect(find.text('10 000 Reasons'));
    final words = tester.getRect(find.byType(ChordLine).first);
    expect(words.left, closeTo(title.left, .5));
  });
}
