import 'dart:convert';
import 'dart:typed_data';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/export.dart';
import 'package:bilingual_projector/justchords.dart';
import 'package:bilingual_projector/library_import.dart';
import 'package:bilingual_projector/pdfs.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/sheet_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PresenterModel> _model() async {
  KeyValueStore.memory.clear();
  KeyValueStore.bytes.clear();
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
  test(
    'custom fields: kept, shown in search, through JustChords and ChordPro',
    () async {
      final m = await _model();
      final song = Song(
        title: 'Grace',
        raw: '[G]Amazing grace',
        custom: {'Theme': 'Mercy', 'Season': 'Lent'},
      );
      m.addOrUpdate(song);
      expect(Song.fromJson(song.toJson()).custom, {
        'Theme': 'Mercy',
        'Season': 'Lent',
      });
      expect(song.searchRank('mercy'), isNotNull);
      // JustChords: an extra key JustChords skips, read back by this app.
      final jc = justChordsSong(song);
      expect(jc['customFields'], {'Theme': 'Mercy', 'Season': 'Lent'});
      final back = m.readImport([('library.json', justChordsLibraryJson(m))]);
      final grace = back.songs.firstWhere((s) => s.title == 'Grace');
      expect(grace.custom['Season'], 'Lent');
      expect(grace.extra.containsKey('customFields'), isFalse);
      // ChordPro: {meta: …}.
      m.selectSong(song.id);
      final cho = exportChordPro(ExportSource.from(m), includeChords: true);
      expect(cho, contains('{meta: Theme Mercy}'));
    },
  );

  test('OnSong: other header lines become custom fields', () {
    final s = onSongToSong(
      'Hosanna\nKey: E\nTheme: Praise\nSeason: Easter\n\nVerse 1:\n[E]Hosanna',
    );
    expect(s.custom, {'Theme': 'Praise', 'Season': 'Easter'});
    expect(s.key?.name, 'E');
  });

  test(
    'song usage: counted when the words are projected, once a service',
    () async {
      final m = await _model();
      final song = Song(
        title: 'Blessed',
        raw: '{start_of_verse}\nOne\n{end_of_verse}\n\n{start_of_verse}\nTwo\n{end_of_verse}',
        ccli: '123',
      );
      m.addOrUpdate(song);
      m.selectSong(song.id);
      // Not projecting: nothing.
      m.goTo(1);
      m.goTo(0);
      await Future<void>.delayed(Duration.zero);
      await m.loadUsage();
      expect(m.usage, isEmpty);
      m.debugProjecting(true);
      m.goTo(1);
      m.goTo(0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(m.usage, hasLength(1));
      expect(m.usage.single.ccli, '123');
      expect(SongUse.fromJson(m.usage.single.toJson()).title, 'Blessed');
      await m.clearUsage();
      expect(m.usage, isEmpty);
      m.debugProjecting(false);
    },
  );

  testWidgets(
    'a picture on the sheet: select, mask, resize keeping its shape',
    (tester) async {
      late PresenterModel m;
      await tester.runAsync(() async => m = await _model());
      m.addOrUpdate(Song(id: 'PIC', title: 'Pic', raw: 'Words'));
      final song = m.songById('PIC')!;
      final png = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      late PdfRef ref;
      await tester.runAsync(
        () async =>
            ref = await PdfStore.add('logo.png', Uint8List.fromList(png)),
      );
      m.setSheetImages(song, [
        SheetImage(
          file: ref.id,
          name: 'logo.png',
          x: 50,
          y: 80,
          width: 200,
          aspect: 0.5,
        ).toJson(),
      ]);
      // Backups carry it.
      expect(libraryPdfs(m).map((p) => p.id), contains(ref.id));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SheetImageLayer(model: m, song: song),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.byTooltip('Crop'), findsNothing);
      await tester.tapAt(const Offset(150, 100));
      await tester.pump();
      expect(find.byTooltip('Crop'), findsOneWidget);
      await tester.tap(find.byTooltip('Mask (remove the white background)'));
      await tester.pump();
      expect(sheetImages(m, song).single.mask, isTrue);
      // Drag the bottom-right corner: wider and taller together.
      await tester.dragFrom(const Offset(250, 180), const Offset(100, 10));
      await tester.pump();
      final img = sheetImages(m, song).single;
      expect(img.width, greaterThan(250));
      expect(img.height / img.width, closeTo(0.5, 0.001));
      SheetImageLayer.select(null);
    },
  );
}
