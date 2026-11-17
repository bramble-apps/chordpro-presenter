import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/justchords.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final song = Song(
    title: 'ZZ Morning Light',
    raw: 'Verse 1:\n[G]Light\n\nVerse 1 (FR):\nLumière',
    key: const MusicKey(7, false),
    transpose: 2,
    tempo: '72',
    audioUrl: 'https://youtu.be/NO5b8Ry-VIM',
    structure: [
      const StructureItem.section('Verse 1'),
      const StructureItem.section('Verse 1 (FR)', linked: true),
      const StructureItem.keyChange(2),
    ],
  );

  test('song in JustChords format', () {
    final j = justChordsSong(song);
    expect(j['rawData'], song.raw);
    expect(j['timeSignature'], '4/4');
    expect(j['keyChord'], {'key': 'G', 'minor': false});
    expect(j['transpose'], 'A');
    expect(j['tempo'], '72');
    expect(j['audioTrack'], {
      'source': 'youtube',
      'identifier': 'https://youtu.be/NO5b8Ry-VIM',
    });
    expect(j['structure'], [
      {'type': 'section', 'sectionName': 'Verse 1'},
      {'type': 'section', 'sectionName': 'Verse 1 (FR)'},
      {'type': 'transpose', 'transpo': 2, 'sectionName': ''},
    ]);
    expect(j['id'], j['id'].toString().toUpperCase());
    // Key changes read back from JustChords.
    expect(StructureItem.fromJson((j['structure'] as List).last)!.semitones, 2);
  });

  test('song archive is a zip with one data.json', () {
    final zip = ZipDecoder().decodeBytes(justChordsSongArchive(song));
    expect(zip.files.map((f) => f.name), ['data.json']);
    final data =
        jsonDecode(utf8.decode(zip.files.single.content as List<int>)) as Map;
    expect((data['songs'] as List).length, 1);
    expect(data['playlists'], isEmpty);
    expect(data['tags'], isEmpty);
  });
}
