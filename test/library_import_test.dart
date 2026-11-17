import 'dart:convert';
import 'dart:io';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/library_import.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Small made-up backup in the same shape as library_YYYY-MM-DD.json.
final fixture = {
  'dataVersion': 'x',
  'identity': 'y',
  'tags': [
    {'id': 'T1', 'name': 'English', 'hidden': false, 'color': 'red'},
    {'id': 'T2', 'name': 'Christmas', 'hidden': true, 'color': 'green'},
  ],
  'songs': [
    {
      'id': 'S1',
      'title': 'Test Song',
      'rawData':
          'Verse 1:\n[G]Line one [D]here\n\nChorus:\n[C]Sing it [G]loud\n'
          '{section_break}\n[Em]Second half\n# private note\n~~:\n[G]End line',
      'keyChord': {'key': 'G', 'minor': false},
      'transpose': 'F',
      'tempo': '90',
      'timeSignature': '4/4',
      'ccli': '123',
      'tags': ['T1'],
      'date': 779938796.0,
      'audioTrack': {'identifier': 'https://youtu.be/x', 'source': 'youtube'},
      'structure': [
        {'sectionName': 'Chorus', 'type': 'section'},
        {'sectionName': 'Verse 1', 'type': 'section'},
      ],
      'preferencesPerDevice': [
        {'hideGuitarDiagrams': true},
      ],
    },
    {
      'id': 'S2',
      'title': 'Noel',
      'rawData': '[A]Noel',
      'keyChord': {'key': 'A', 'minor': false},
      'tags': ['T2'],
    },
  ],
  'songsTrash': [
    {'id': 'S3', 'title': 'Old', 'rawData': '[C]old'},
  ],
  'playlists': [
    {
      'id': 'P1',
      'title': 'Sunday',
      'separateSongSettings': true,
      'eventDate': 775315040.0,
      'notes': '',
      'date': 775315040.0,
      'hasImage': false,
      'arrangement': [
        {
          'id': 'S1',
          'index': 'E1',
          'type': 'song',
          'transpose': 'A',
          'capo': 2,
        },
        {
          'id': 'D1',
          'index': 'E2',
          'type': 'divider',
          'title': 'Cut',
          'color': 'red',
        },
        {
          'id': 'S2',
          'index': 'E3',
          'type': 'song',
          'arrangement': [
            {'type': 'section', 'sectionName': 'Chorus'},
          ],
        },
        {'id': 'L1', 'index': 'E4', 'type': 'sectionLabel', 'title': 'Maybe'},
        {'id': 'V1', 'index': 'E5', 'type': 'event', 'title': 'Prayer'},
      ],
    },
  ],
};

void main() {
  test('recognises the library backup format', () {
    expect(isLibraryBackup(fixture), isTrue);
    expect(
      isLibraryBackup({
        'songs': [
          {'id': 'x', 'raw': ''},
        ],
      }),
      isFalse,
    );
  });

  test('maps songs, tags, trash and playlists', () {
    final lib = LibraryBackup.parse(fixture);
    final song = lib.songs.first;
    expect(song.writtenKey!.name, 'G');
    expect(song.transpose, -2, reason: 'G -> F');
    expect(song.tempo, '90');
    expect(song.ccli, '123');
    expect(song.tags, ['T1']);
    expect(song.audioUrl, 'https://youtu.be/x');
    expect(song.structure.map((i) => i.name), ['Chorus', 'Verse 1']);
    expect(song.date!.year, 2025);
    expect(song.extra.containsKey('preferencesPerDevice'), isTrue);

    expect(lib.tags.map((t) => t.name), ['English', 'Christmas']);
    expect(lib.tags[1].hidden, isTrue);
    expect(lib.trash.single.title, 'Old');

    final set = lib.setlists.single;
    expect(set.name, 'Sunday');
    expect(set.setSpecific, isTrue);
    expect(set.eventDate, isNotNull);
    expect(set.entries.map((e) => e.type), [
      EntryType.song,
      EntryType.divider,
      EntryType.song,
      EntryType.label,
      EntryType.event,
    ]);
    final first = set.entries.first;
    expect(first.songId, 'S1');
    expect(first.id, 'E1');
    expect(first.transpose, 2, reason: 'G -> A');
    expect(first.capo, 2);
    expect(set.entries[1].color, 'red');
    expect(set.entries[2].structure.single.name, 'Chorus');
  });

  test('parser handles section_break, # comments and ~~: markers', () {
    final raw = (fixture['songs'] as List).first['rawData'] as String;
    final slides = ChordPro.parseToSlides(raw);
    expect(slides, [
      'Line one here',
      'Sing it loud',
      'Second half',
      'End line',
    ]);
    final sheet = ChordPro.sheetLines(raw);
    expect(sheet.any((l) => l.contains('private note')), isFalse);
    expect(sheet.any((l) => l.contains('~~')), isFalse);
  });

  test('arrangement reorders sections', () {
    final raw = 'Verse 1:\nA\n\nChorus:\nB\n\nChorus:\n';
    final arranged = ChordPro.applyStructure(raw, const [
      StructureItem.section('Chorus'),
      StructureItem.section('Verse 1'),
      StructureItem.section('Chorus'),
    ]);
    expect(ChordPro.parseToSlides(arranged), ['B', 'A', 'B']);
  });

  testWidgets('import merges into the model and survives reload', (
    tester,
  ) async {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final model = PresenterModel();
    await model.load();
    final summary = model.importFiles([('library.json', jsonEncode(fixture))]);
    expect(
      summary.toString(),
      'Imported 2 songs, 1 setlist, 2 tags, 1 in Trash.',
    );
    expect(model.songs.length, 3, reason: 'sample + 2 imported');
    await model.flush();

    final reloaded = PresenterModel();
    await reloaded.load();
    // (Counts lyric slides: no blank / title slides.)
    reloaded.updateProjection(
      (p) => p
        ..blankSlide = false
        ..titleSlide = false,
    );
    expect(reloaded.songs.length, 3);
    expect(reloaded.tags.length, 2);
    expect(reloaded.trash.single.id, 'S3');
    expect(reloaded.setlists.single.entries.length, 5);
    expect(reloaded.songById('S1')!.transpose, -2);

    // Opening a setlist entry uses its key, capo and arrangement.
    final set = reloaded.setlists.single;
    reloaded.selectEntry(set, set.entries.first);
    expect(reloaded.currentKey!.name, 'A');
    expect(reloaded.currentCapo, 2);
    expect(reloaded.shapeKey!.name, 'G');
    expect(reloaded.slides.first, 'Sing it loud', reason: 'Chorus first');

    // Re-importing the same file updates instead of duplicating.
    reloaded.importFiles([('library.json', jsonEncode(fixture))]);
    expect(reloaded.songs.length, 3);
    expect(reloaded.setlists.length, 1);
  });

  // Runs against the real backup when it's been downloaded locally.
  final real = File('.backup-sample/library_2026-10-05.json');
  test('real library backup imports cleanly', () {
    final json = jsonDecode(real.readAsStringSync()) as Map<String, dynamic>;
    final lib = LibraryBackup.parse(json);
    expect(lib.songs.length, 725);
    expect(lib.trash.length, 175);
    expect(lib.tags.length, 10);
    expect(lib.setlists.length, 25);
    final ids = {for (final s in lib.songs) s.id};
    final refs = [
      for (final p in lib.setlists)
        for (final e in p.entries)
          if (e.type == EntryType.song) e.songId,
    ];
    expect(
      refs.where(ids.contains).length,
      refs.length - 1,
      reason: 'one playlist song was deleted from the library',
    );
    for (final s in lib.songs) {
      final raw = ChordPro.applyStructure(s.raw, s.structure);
      final slides = ChordPro.parseToSlides(raw);
      ChordPro.sheetLines(raw);
      for (final slide in slides) {
        expect(slide.contains('{'), isFalse, reason: '${s.title}: $slide');
        expect(slide.contains('&nbsp;'), isFalse, reason: s.title);
      }
    }
  }, skip: !real.existsSync() ? 'backup not downloaded' : false);
}
