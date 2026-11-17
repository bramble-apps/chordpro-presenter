import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PresenterModel> _model() async {
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final m = PresenterModel();
  await m.load();
  m.songs.clear();
  return m;
}

String _backup(List<Song> songs, List<Setlist> sets) => jsonEncode({
  'songs': [for (final s in songs) s.toJson()],
  'setlists': [for (final s in sets) s.toJson()],
});

void main() {
  final old = DateTime(2025, 1, 1), later = DateTime(2026, 1, 1);

  test('songs already here: skip, if newer, replace', () async {
    for (final (mode, expected) in [
      (ImportSongs.skip, 'mine'),
      (ImportSongs.newer, 'theirs'),
      (ImportSongs.replace, 'theirs'),
    ]) {
      final m = await _model();
      m.songs.add(Song(id: 'a', title: 'A', raw: 'mine', date: old));
      final file = _backup([
        Song(id: 'a', title: 'A', raw: 'theirs', date: later),
        Song(title: 'New', raw: 'x'),
      ], []);
      m.importFiles([('b.json', file)], ImportOptions(songs: mode));
      expect(m.songById('a')!.raw, expected, reason: '$mode');
      expect(m.songs, hasLength(2));
    }
    // An older copy in the file: "if newer" keeps yours.
    final m = await _model();
    m.songs.add(Song(id: 'a', title: 'A', raw: 'mine', date: later));
    m.importFiles([
      (
        'b.json',
        _backup([Song(id: 'a', title: 'A', raw: 'old', date: old)], []),
      ),
    ], const ImportOptions(songs: ImportSongs.newer));
    expect(m.songById('a')!.raw, 'mine');
  });

  test('a ChordPro file with the same title matches, keeping the id', () async {
    final m = await _model();
    m.songs.add(Song(id: 'a', title: 'Amazing', raw: 'mine', date: old));
    m.importFiles([('x.cho', '{title: Amazing}\n[G]New')]);
    expect(m.songs.single.id, 'a');
    expect(m.songs.single.raw, contains('New'));
  });

  test('setlists already here: merge, replace, skip', () async {
    for (final (mode, expected) in [
      (ImportSetlists.merge, ['a', 'b']),
      (ImportSetlists.replace, ['b']),
      (ImportSetlists.skip, ['a']),
    ]) {
      final m = await _model();
      m.songs.addAll([
        Song(id: 'a', title: 'A', raw: ''),
        Song(id: 'b', title: 'B', raw: ''),
      ]);
      m.setlists.add(
        Setlist(
          id: 's',
          name: 'Sunday',
          entries: [SetEntry(songId: 'a')],
        ),
      );
      final file = _backup([], [
        Setlist(
          id: 'other',
          name: 'sunday',
          entries: [SetEntry(songId: 'b')],
        ),
      ]);
      m.importFiles([('b.json', file)], ImportOptions(setlists: mode));
      expect(m.setlists, hasLength(1), reason: '$mode');
      expect(m.setlists.single.id, 's');
      expect(m.setlists.single.entries.map((e) => e.songId), expected);
    }
  });

  test('restore replaces the whole library', () async {
    final m = await _model();
    m.songs.add(Song(title: 'Gone', raw: ''));
    m.setlists.add(Setlist(name: 'Gone too'));
    m.importFiles([
      ('b.json', _backup([Song(title: 'Kept', raw: '')], [])),
    ], const ImportOptions(restore: true));
    expect(m.songs.map((s) => s.title), ['Kept']);
    expect(m.setlists, isEmpty);
  });

  test('editing a song moves its date on', () async {
    final m = await _model();
    m.addOrUpdate(Song(id: 'a', title: 'A', raw: 'x', date: old));
    m.addOrUpdate(m.songById('a')!.copy());
    expect(m.songById('a')!.date, old);
    m.addOrUpdate(m.songById('a')!.copy()..raw = 'y');
    expect(m.songById('a')!.date!.isAfter(old), isTrue);
  });
}
