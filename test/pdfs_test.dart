import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/justchords.dart';
import 'package:bilingual_projector/pdfs.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/pdf_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 fake'));

Future<PresenterModel> _model() async {
  KeyValueStore.memory.clear();
  KeyValueStore.bytes.clear();
  PresenterModel.saveDelay = Duration.zero;
  final m = PresenterModel();
  await m.load();
  return m;
}

void main() {
  test('PDF songs and attachments are stored and listed', () async {
    final m = await _model();
    final only = await addPdfSong(m, 'Hymn sheet.pdf', _pdf);
    expect(only.title, 'Hymn sheet');
    expect(isPdfOnly(only), isTrue);
    expect(await PdfStore.bytes(pdfsOf(only).single.id), _pdf);

    final song = m.songs.firstWhere((s) => s.raw.isNotEmpty);
    setPdfs(song, [await PdfStore.add('Lead.pdf', _pdf)]);
    expect(isPdfOnly(song), isFalse);
    expect(libraryPdfs(m), hasLength(2));
    expect(PdfStore.looksLikePdf(_pdf), isTrue);
  });

  test('backup zip round-trips songs with their PDFs', () async {
    final m = await _model();
    final only = await addPdfSong(m, 'Sheet.pdf', _pdf);
    final id = pdfsOf(only).single.id;
    final zip = await libraryBackupZip(m);
    expect(looksLikeZip(zip), isTrue);
    final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name);
    expect(names, containsAll(['songs.json', 'pdfs/$id.pdf']));

    final other = await _model();
    await importBackupZip(other, zip);
    final back = other.songs.firstWhere((s) => s.title == 'Sheet');
    expect(await PdfStore.bytes(pdfsOf(back).single.id), _pdf);
  });

  test('JustChords export leaves PDF-only songs out', () async {
    final m = await _model();
    await addPdfSong(m, 'Only a PDF.pdf', _pdf);
    final json = jsonDecode(justChordsLibraryJson(m)) as Map;
    final titles = [for (final s in json['songs'] as List) '${s['title']}'];
    expect(titles, isNot(contains('Only a PDF')));
    final zip = ZipDecoder().decodeBytes(await pdfsZip(m));
    expect(zip.files.single.name, 'Only a PDF.pdf');
  });

  testWidgets('a song with a PDF shows ChordPro | PDF tabs', (tester) async {
    final song = Song(title: 'A', raw: '[G]Hi');
    final pdfs = [const PdfRef('x', 'A.pdf')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongDocTabs(
            song: song,
            chordPro: const Text('sheet'),
            pdfs: pdfs,
          ),
        ),
      ),
    );
    expect(find.text('ChordPro'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('sheet'), findsOneWidget);
  });

  testWidgets('a song can have ChordPro and two PDFs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongDocTabs(
            song: Song(title: 'A', raw: '[G]Hi'),
            chordPro: const Text('sheet'),
            pdfs: const [PdfRef('x', 'Lead.pdf'), PdfRef('y', 'Bass.pdf')],
          ),
        ),
      ),
    );
    expect(find.text('ChordPro'), findsOneWidget);
    expect(find.text('Lead'), findsOneWidget);
    expect(find.text('Bass'), findsOneWidget);
  });
}
