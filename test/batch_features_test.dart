import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/pdfs.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/song_icons.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show pumpApp;

final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0,
  0,
  0,
  0,
]);

void main() {
  test('dual chords: a second notation beside each chord', () {
    String r(String c, ChordNotation? dual) => renderDualChord(
      c,
      transpose: 0,
      key: const MusicKey(7, false),
      notation: ChordNotation.standard,
      dual: dual,
      minorStyle: MinorStyle.m,
      accidentals: Accidentals.auto,
    );
    expect(r('G', ChordNotation.numbers), 'G (1)');
    expect(r('Em', ChordNotation.roman), 'Em (VIm)');
    expect(r('G', null), 'G');
  });

  test('rewrite into key: chords and {key:} for good, comments kept', () {
    const raw = '{key: G}\n[G]Amazing [C/G]grace [D*soft]how [|] [Em]sweet';
    final out = rewriteIntoKey(raw, 3, const MusicKey(10, false));
    expect(
      out,
      '{key: Bb}\n[Bb]Amazing [Eb/Bb]grace [F*soft]how [|] [Gm]sweet',
    );
  });

  test('lyrics override: the projector shows it, the sheet the lyrics', () {
    const raw =
        'Verse 1:\n[G]Amazing grace\n{start_of_lyrics_override}\nGrâce infinie\n'
        '{end_of_lyrics_override}\n\nChorus:\nSing\n{start_of_lyrics_override}\n'
        '{end_of_lyrics_override}';
    final parts = ChordPro.parts(raw);
    expect(parts.map((p) => p.slide), ['Grâce infinie', 'Sing']);
    expect(parts.first.raw, contains('Amazing grace'));
    expect(ChordPro.sheetLines(raw).join('\n'), isNot(contains('Grâce')));
    expect(ChordPro.parseToSlides(raw).join(), isNot(contains('Grâce')));
  });

  test(
    'pictures are sheet music too, and keep their type in backups',
    () async {
      KeyValueStore.memory.clear();
      KeyValueStore.bytes.clear();
      PresenterModel.saveDelay = Duration.zero;
      final model = PresenterModel();
      await model.load();
      expect(PdfStore.looksLikeImage(_png), isTrue);
      expect(PdfStore.looksLikeSheetMusic(_png), isTrue);
      final song = await addPdfSong(model, 'Lead sheet.png', _png);
      final ref = pdfsOf(song).single;
      expect(ref.isImage, isTrue);
      expect(ref.title, 'Lead sheet');
      final zip = ZipDecoder().decodeBytes(await libraryBackupZip(model));
      expect(zip.files.map((f) => f.name), contains('pdfs/${ref.id}.png'));
      final named = ZipDecoder().decodeBytes(await pdfsZip(model));
      expect(named.files.single.name, 'Lead sheet.png');
    },
  );

  testWidgets('files dropped on the window are imported', (tester) async {
    final model = await pumpApp(tester);
    final before = model.songs.length;
    debugDropFiles([
      (
        'Dropped.cho',
        Uint8List.fromList(utf8.encode('{title: Dropped song}\n[G]Hi')),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(model.songs.length, before + 1);
    expect(model.songs.any((s) => s.displayTitle == 'Dropped song'), isTrue);
  });

  test('line spacing is a projection setting', () {
    final p = ProjectionSettings()..updateFrom({'textLineSpacing': 140});
    expect(p.textLineSpacing, 140);
    expect(ProjectionSettings().toJson()['textLineSpacing'], 100);
  });

  test('song icons are saved with the song', () {
    final song = Song(title: 'S', raw: '');
    expect(songIconOf(song), isNull);
    setSongIcon(song, 'hymn');
    expect(song.extra['icon'], 'hymn');
    expect(songIconOf(Song.fromJson(song.toJson())), isNotNull);
    setSongIcon(song, null);
    expect(song.extra.containsKey('icon'), isFalse);
  });

  test('strum patterns: strokes, accents and counts', () {
    final s = parseRhythm('D>-DU-UDU');
    expect(s.map((x) => x.symbol).join(), '↓·↓↑·↑↓↑');
    expect(s.first.accent, isTrue);
    expect(s[1].rest, isTrue);
    expect(rhythmCounts(8, 4), ['1', '+', '2', '+', '3', '+', '4', '+']);
    expect(rhythmCounts(4, 4), ['1', '2', '3', '4']);
    expect(rhythmCounts(16, 4).take(4), ['1', 'e', '+', 'a']);
    expect(rhythmCounts(6, 3), ['1', '+', '2', '+', '3', '+']);
    expect(
      parseRhythm('Dpm U< X b').map((x) => x.action).join(),
      'DUXb'.substring(0, 3),
    );
    // In the sheet: one rhythm line (never on the projector).
    const raw = 'Verse:\n{rhythm: D>-DU-UDU}\n[G]Hello';
    expect(ChordPro.sheetLines(raw), contains('${rhythmMarker}D>-DU-UDU'));
    expect(ChordPro.parseToSlides(raw), ['Hello']);
  });

  testWidgets('the sheet draws a strum pattern', (tester) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(id: 'r', title: 'R', raw: 'Verse:\n{rhythm: D-DU}\n[G]Hi'),
    );
    model.selectSong('r');
    await tester.pumpAndSettle();
    expect(find.byType(RhythmDiagram), findsWidgets);
    expect(find.text('↓'), findsWidgets);
  });

  testWidgets('text shared from another app becomes a song', (tester) async {
    final model = await pumpApp(tester);
    final before = model.songs.length;
    debugShareText(
      'Blessed Assurance\n\n[D]Blessed as[G]surance',
      'Blessed Assurance',
    );
    await tester.pumpAndSettle();
    expect(model.songs.length, before + 1);
    expect(model.songs.any((s) => s.title == 'Blessed Assurance'), isTrue);
    // A link to a site the app can't read: says so, adds nothing.
    debugShareText('https://example.com/song/123');
    await tester.pumpAndSettle();
    expect(model.songs.length, before + 1);
    expect(find.textContaining('can’t be read yet'), findsOneWidget);
  });
}
