// Export to JustChords (macOS / iPad), in its own library format (see
// ~/Downloads/instructions.txt, verified against JustChords 9.34):
//  * the whole library as a backup .json (Backup & Restore → "Restore from
//    file" replaces the JustChords library with it);
//  * one song or a setlist as a `.jcarchive`: a zip holding one data.json.
//    One song opens in JustChords' song editor; two or more songs open the
//    Import dialog, which adds the songs and the setlist. Tags aren't
//    imported from archives, so none are sent.
//
// Translations: JustChords can't link sections, so a linked "Verse 1" +
// "Verse 1 (FR)" becomes two sections one after the other in the song
// structure; JustChords shows them as consecutive slides.

import 'dart:convert';
import 'dart:typed_data';

import 'chordpro.dart';
import 'export.dart' show zipFiles;
import 'music.dart';
import 'pdfs.dart';
import 'gospelizer.dart';
import 'state.dart';

final _appleEpoch = DateTime.utc(2001, 1, 1);

/// Seconds since 2001-01-01 (JustChords' dates).
double _appleSeconds(DateTime? d) =>
    (d ?? DateTime.now()).toUtc().difference(_appleEpoch).inMilliseconds / 1000;

String _uuid() => newId().toUpperCase();

/// Key name as JustChords writes it: "G", "Bb", "F#" (minor is separate).
String _keyName(MusicKey k) => MusicKey(k.root, false).name;

Map<String, dynamic> _structureItem(StructureItem i) => i.isModulation
    ? {'type': 'transpose', 'transpo': i.semitones, 'sectionName': ''}
    : {'type': 'section', 'sectionName': i.name};

List<Map<String, dynamic>> _structure(List<StructureItem> items) =>
    items.map(_structureItem).toList();

/// The key [song] is played in after [semitones], or null.
String? _playedKey(Song song, int semitones) {
  final k = song.writtenKey;
  if (k == null || semitones == 0) return null;
  return _keyName(k.transposed(semitones));
}

bool _isYouTube(String url) =>
    RegExp(r'(youtube\.com|youtu\.be)/', caseSensitive: false).hasMatch(url);

Map<String, dynamic> justChordsSong(Song s, {bool withTags = false}) {
  final key = s.writtenKey;
  final played = _playedKey(s, s.transpose);
  void opt(Map<String, dynamic> m, String k, String v) {
    if (v.trim().isNotEmpty) m[k] = v.trim();
  }

  final m = <String, dynamic>{
    'id': s.id.toUpperCase(),
    'title': s.displayTitle,
    // (With the Gospelizer's chords while it's on.)
    'rawData': s.exportRaw,
    'date': _appleSeconds(s.date),
    'timeSignature': s.timeSignature.trim().isEmpty
        ? '4/4'
        : s.timeSignature.trim(),
  };
  opt(m, 'artist', s.artist);
  opt(m, 'subtitle', s.subtitle);
  opt(m, 'tempo', s.tempo);
  opt(m, 'duration', s.duration);
  opt(m, 'composer', s.composer);
  opt(m, 'lyricist', s.lyricist);
  opt(m, 'copyright', s.copyright);
  opt(m, 'ccli', s.ccli);
  opt(m, 'ccliLicense', s.ccliLicense);
  opt(m, 'footer', s.footer);
  opt(m, 'notes', s.notes);
  opt(m, 'sorttitle', s.sortTitle);
  if (key != null) m['keyChord'] = {'key': _keyName(key), 'minor': key.minor};
  if (played != null) m['transpose'] = played;
  if (s.capo != 0) m['capo'] = s.capo;
  if (_isYouTube(s.audioUrl)) {
    m['audioTrack'] = {'source': 'youtube', 'identifier': s.audioUrl.trim()};
  }
  if (s.structure.isNotEmpty) m['structure'] = _structure(s.structure);
  // The person's own fields: JustChords skips keys it doesn't know, and
  // this app reads them back from its own JustChords exports.
  if (s.custom.isNotEmpty) m['customFields'] = s.custom;
  if (withTags && s.tags.isNotEmpty) {
    m['tags'] = [for (final t in s.tags) t.toUpperCase()];
  }
  return m;
}

Map<String, dynamic> justChordsPlaylist(
  Setlist set,
  Map<String, Song> songsById,
) {
  // (Songs nested under another: entries of their own, as JustChords has.)
  set = set.flattened((id) => songsById[id]);
  final items = <Map<String, dynamic>>[];
  for (final e in set.entries) {
    if (e.type == EntryType.song) {
      final song = songsById[e.songId];
      if (song == null) continue;
      final played = set.setSpecific ? _playedKey(song, e.transpose) : null;
      items.add({
        'type': 'song',
        'id': song.id.toUpperCase(), // the song
        'index': e.id.toUpperCase(), // this item
        'capo': set.setSpecific ? e.capo : 0,
        'transpose': ?played,
        'arrangement': _structure(e.structure),
        'notesAndDrawing': <Object>[],
      });
    } else {
      items.add({
        'type': switch (e.type) {
          EntryType.label => 'sectionLabel',
          // Media and Bible passages (ours only): an event with its name,
          // in JustChords.
          EntryType.event || EntryType.media || EntryType.bible => 'event',
          _ => 'divider',
        },
        // Its own id (as it came from JustChords, else a steady one).
        'id': ((e.extra['_itemId'] as String?) ?? e.id).toUpperCase(),
        'index': e.id.toUpperCase(),
        'title': e.title,
        'color': ?e.color,
        'notesAndDrawing': <Object>[],
      });
    }
  }
  return {
    'id': set.id.toUpperCase(),
    'title': set.name,
    'date': _appleSeconds(set.date),
    'eventDate': set.eventDate == null ? null : _appleSeconds(set.eventDate),
    'notes': set.notes,
    'shared': false,
    'hasImage': false,
    'separateSongSettings': set.setSpecific,
    'deletedEntities': null,
    'lastPushDate': null,
    'arrangement': items,
  };
}

Uint8List _archive(List<Song> songs, List<Map<String, dynamic>> playlists) {
  final data = {
    'dataVersion': _uuid(),
    'identity': _uuid(),
    'songs': songs.map(justChordsSong).toList(),
    'playlists': playlists,
    'tags': <Object>[],
  };
  return zipFiles({'data.json': utf8.encode(jsonEncode(data))});
}

/// One song as a `.jcarchive`.
Uint8List justChordsSongArchive(Song song) => _archive([song], const []);

/// A setlist and its songs as a `.jcarchive`.
Uint8List justChordsSetlistArchive(Setlist set, List<Song> library) {
  final byId = {for (final s in library) s.id: s};
  final songs = <Song>[];
  final seen = <String>{};
  for (final e in set.flattened((id) => byId[id]).entries) {
    final s = byId[e.songId];
    if (e.type == EntryType.song && s != null && seen.add(s.id)) songs.add(s);
  }
  return _archive(songs, [justChordsPlaylist(set, byId)]);
}

/// The whole library as a JustChords backup `.json` (Backup & Restore →
/// "Restore from file" replaces the JustChords library with it).
String justChordsLibraryJson(PresenterModel m) {
  final byId = {for (final s in m.songs) s.id: s};
  return jsonEncode({
    'dataVersion': _uuid(),
    'identity': _uuid(),
    // JustChords takes ChordPro songs only (PDF-only songs are left out).
    'songs': [
      for (final s in m.songs)
        if (!isPdfOnly(s)) justChordsSong(s, withTags: true),
    ],
    'songsTrash': [
      for (final s in m.trash)
        if (!isPdfOnly(s)) justChordsSong(s, withTags: true),
    ],
    'playlists': [for (final p in m.setlists) justChordsPlaylist(p, byId)],
    'tags': [
      for (final t in m.tags)
        {
          'id': t.id.toUpperCase(),
          'name': t.name,
          'color': ?t.color,
          'hidden': t.hidden,
        },
    ],
  });
}
