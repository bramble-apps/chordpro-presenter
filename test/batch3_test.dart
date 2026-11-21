import 'package:bilingual_projector/bramble_icons.dart';

import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/inline_format.dart';
import 'package:bilingual_projector/library_import.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show pumpApp;

Future<PresenterModel> _model() async {
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final m = PresenterModel();
  await m.load();
  m.updateProjection(
    (p) => p
      ..blankSlide = false
      ..titleSlide = false,
  );
  return m;
}

void main() {
  test('several songs in one ChordPro file', () async {
    final m = await _model();
    final b = m.readImport([
      (
        'book.cho',
        '{title: One}\n[G]First\n{new_song}\n{title: Two}\n[C]Second\n{ns}\n{title: Three}\nThird',
      ),
    ]);
    expect(b.songs.map((s) => s.title), ['One', 'Two', 'Three']);
    expect(splitSongs('just one'), ['just one']);
  });

  test('OnSong files: header, metadata, chords over words', () {
    final s = onSongToSong(
      'Amazing Grace\nJohn Newton\nKey: G\nCapo: 2\nTempo: 80\nTime: 3/4\n\n'
      'Verse 1:\nG          C       G\nAmazing grace how sweet the sound',
      fileName: 'amazing.onsong',
    );
    expect(s.title, 'Amazing Grace');
    expect(s.artist, 'John Newton');
    expect(s.key?.name, 'G');
    expect(s.capo, 2);
    expect(s.tempo, '80');
    expect(s.timeSignature, '3/4');
    expect(s.raw, contains('[G]'));
    expect(s.raw, contains('Verse 1:'));
  });

  test('SongbookPro data: songs and sets', () async {
    final m = await _model();
    final data =
        '1.0\n${jsonEncode({
          'songs': [
            {'Id': 7, 'name': 'Hosanna', 'author': 'Brooke', 'content': '{title: Hosanna}\n[G]Praise', 'key': 7, 'capo': 1},
          ],
          'sets': [
            {
              'name': 'Sunday',
              'songs': [
                {'Id': 7},
              ],
            },
          ],
        })}';
    final b = m.readImport([('dataFile.txt', data)]);
    expect(b.songs.single.title, 'Hosanna');
    expect(b.songs.single.artist, 'Brooke');
    expect(b.songs.single.key?.name, 'G');
    expect(b.songs.single.capo, 1);
    expect(b.setlists.single.name, 'Sunday');
    expect(b.setlists.single.entries.single.songId, b.songs.single.id);
  });

  test('inline formatting: JustChords syntax, styles across chords', () {
    final runs = formatPieces([
      'Line with *bo',
      'ld* and <red>red<',
      ' _under_ **it**',
    ]);
    expect(runs.map((p) => p.map((r) => r.text).join()).toList(), [
      'Line with bo',
      'ld and red',
      ' under it',
    ]);
    expect(runs[0].last.style.bold, isTrue);
    expect(runs[1].first.style.bold, isTrue);
    expect(runs[1].last.style.color, isNotNull);
    expect(runs[2][1].style.underline, isTrue);
    expect(runs[2].last.style.italic, isTrue);
    expect(withoutInlineMarks('<red,@yellow,2>big<'), 'big');
    expect(
      formatPieces(['<@yellow>hi<']).first.first.style.highlight,
      isNotNull,
    );
    expect(formatPieces(['<2>hi<']).first.first.style.size, 2);
    // A lone mark is just a character.
    expect(withoutInlineMarks('Hosanna*'), 'Hosanna*');
    expect(withoutInlineMarks('3 < 4'), '3 < 4');
    // Slides never show the marks.
    expect(ChordPro.parseToSlides('[G]Sing *loud* <red>now<'), [
      'Sing loud now',
    ]);
  });

  testWidgets('the sheet shows formatted words without the marks', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(id: 'f', title: 'F', raw: 'Verse:\n[G]Sing *loud* now'),
    );
    model.selectSong('f');
    await tester.pumpAndSettle();
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join('|');
    expect(texts, isNot(contains('*loud*')));
  });

  test('remote control actions', () async {
    final m = await _model();
    m.addOrUpdate(
      Song(id: 'a', title: 'Amazing Grace', raw: 'V:\nOne\n\nC:\nTwo'),
    );
    m.addOrUpdate(
      Song(id: 'h', title: 'Hosanna', raw: 'V:\nPraise\n\nC:\nRising'),
    );
    expect(m.remote('song', 'hosanna'), isTrue);
    expect(m.currentSong!.id, 'h');
    expect(m.remote('slide', '2'), isTrue);
    expect(m.index, 1);
    m.remote('previous');
    expect(m.index, 0);
    m.remote('blackout', 'on');
    expect(m.blackout, isTrue);
    m.remote('blackout');
    expect(m.blackout, isFalse);
    expect(m.remote('dance'), isFalse);
  });

  testWidgets('chordpropresenter:// links run actions', (tester) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(id: 'h', title: 'Hosanna', raw: 'V:\nPraise\n\nC:\nRising'),
    );
    debugShareText('chordpropresenter://song?title=Hosanna');
    await tester.pumpAndSettle();
    expect(model.currentSong!.id, 'h');
    debugShareText('chordpropresenter://slide/2');
    await tester.pumpAndSettle();
    expect(model.index, 1);
  });

  testWidgets('⋯ on a song → Song icon… sets it without opening the song', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    final open = model.currentSong!.id;
    model.addOrUpdate(Song(id: 'z', title: 'Zebra Song', raw: '[G]Hi'));
    model.selectSong(open);
    await tester.pumpAndSettle();
    // The song's row (the tile, with its key and ⋯ beside it).
    final row = find.ancestor(
      of: find.text('Zebra Song'),
      matching: find.byWidgetPredicate(
        (w) => w is Material && w.child is InkWell,
      ),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song icon…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Christmas'));
    await tester.pumpAndSettle();
    expect(model.songById('z')!.extra['icon'], 'christmas');
    expect(model.currentSong!.id, open);
    expect(
      find.descendant(of: row, matching: find.byIcon(BrambleIcons.tree)),
      findsOneWidget,
    );
  });
}
