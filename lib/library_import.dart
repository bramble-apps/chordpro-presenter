// Reads a song-library backup (e.g. library_2026-10-05.json):
//   { songs: [{id, title, rawData, keyChord, transpose, tags, ...}],
//     playlists: [{id, title, arrangement: [...], separateSongSettings, ...}],
//     tags: [{id, name, color, hidden}], songsTrash: [...], ... }
// Dates are seconds since 2001-01-01 (Apple reference date). Song/playlist
// "transpose" values are target key names ("E"), converted to semitones here.

import 'dart:convert';

import 'chordpro.dart';
import 'music.dart';
import 'song_sources.dart' show pastedToChordPro;
import 'state.dart';

bool isLibraryBackup(Map<String, dynamic> json) {
  if (json['songs'] is! List) return false;
  if (json.containsKey('playlists') || json.containsKey('songsTrash')) {
    return true;
  }
  final songs = json['songs'] as List;
  return songs.isNotEmpty &&
      songs.first is Map &&
      (songs.first as Map).containsKey('rawData');
}

final _appleEpoch = DateTime.utc(2001, 1, 1);

DateTime? _appleDate(Object? seconds) => seconds is num
    ? _appleEpoch.add(Duration(milliseconds: (seconds * 1000).round()))
    : null;

String _s(Object? v) => v is String ? v.trim() : (v is num ? '$v' : '');

List<StructureItem> _sections(Object? arrangement) =>
    StructureItem.listFromJson(arrangement);

/// Semitones from [written] to the key named [target] (e.g. "E").
int _transposeTo(MusicKey? written, Object? target) {
  if (written == null || target is! String || target.isEmpty) return 0;
  final t = MusicKey.parse(target);
  if (t == null) return 0;
  return normalizeTranspose(t.root - written.root);
}

Map<String, dynamic> _extra(Map<String, dynamic> j, Set<String> known) => {
  for (final e in j.entries)
    if (!known.contains(e.key) && e.value != null) e.key: e.value,
};

const _songKeys = {
  'id', 'title', 'rawData', 'keyChord', 'transpose', 'capo', 'artist',
  'subtitle', 'tempo', 'timeSignature', 'duration', 'composer', 'lyricist',
  'copyright', 'ccli', 'ccliLicense', 'footer', 'notes', 'audioTrack',
  'sorttitle', 'tags', 'structure', 'date', 'customFields', //
};

const _playlistKeys = {
  'id', 'title', 'separateSongSettings', 'arrangement', 'eventDate', 'notes',
  'date', //
};

const _itemKeys = {
  'id', 'index', 'type', 'title', 'color', 'transpose', 'capo',
  'arrangement', //
};

Song _song(Map<String, dynamic> j) {
  MusicKey? key;
  final kc = j['keyChord'];
  if (kc is Map && kc['key'] is String) {
    key = MusicKey.parse('${kc['key']}${kc['minor'] == true ? 'm' : ''}');
  }
  final song = Song(
    id: j['id'] as String?,
    title: _s(j['title']),
    raw: j['rawData'] is String ? j['rawData'] as String : '',
    key: key,
    capo: (j['capo'] as num?)?.toInt() ?? 0,
    artist: _s(j['artist']),
    subtitle: _s(j['subtitle']),
    tempo: _s(j['tempo']),
    timeSignature: _s(j['timeSignature']),
    duration: _s(j['duration']),
    composer: _s(j['composer']),
    lyricist: _s(j['lyricist']),
    copyright: _s(j['copyright']),
    ccli: _s(j['ccli']),
    ccliLicense: _s(j['ccliLicense']),
    footer: _s(j['footer']),
    notes: _s(j['notes']),
    audioUrl: j['audioTrack'] is Map
        ? _s((j['audioTrack'] as Map)['identifier'])
        : '',
    sortTitle: _s(j['sorttitle']),
    tags: [
      for (final t in (j['tags'] as List?) ?? [])
        if (t is String) t,
    ],
    structure: _sections(j['structure']),
    date: _appleDate(j['date']),
    custom: {
      if (j['customFields'] is Map)
        for (final e in (j['customFields'] as Map).entries)
          '${e.key}': '${e.value}',
    },
    extra: {
      ..._extra(j, _songKeys),
      // As written (spelling such as C# / Db), for exporting back.
      if (j['keyChord'] is Map) '_keyChord': j['keyChord'],
      if (j['transpose'] is String) '_transpose': j['transpose'],
    },
  );
  song.transpose = _transposeTo(song.writtenKey, j['transpose']);
  return song;
}

Setlist _setlist(Map<String, dynamic> j, Map<String, Song> songsById) {
  final entries = <SetEntry>[];
  for (final a
      in ((j['arrangement'] as List?) ?? []).cast<Map<String, dynamic>>()) {
    final type = switch (a['type']) {
      'song' => EntryType.song,
      'divider' => EntryType.divider,
      'sectionLabel' => EntryType.label,
      'event' => EntryType.event,
      _ => null,
    };
    if (type == null) continue;
    final isSong = type == EntryType.song;
    // For songs, "id" is the song's ID and "index" is the item's own ID.
    final songId = isSong ? a['id'] as String? : null;
    entries.add(
      SetEntry(
        id: (a['index'] ?? a['id']) as String?,
        type: type,
        songId: songId,
        title: _s(a['title']),
        color: a['color'] as String?,
        transpose: isSong
            ? _transposeTo(songsById[songId]?.writtenKey, a['transpose'])
            : 0,
        capo: (a['capo'] as num?)?.toInt() ?? 0,
        structure: _sections(a['arrangement']),
        extra: {
          ..._extra(a, _itemKeys),
          // Non-song items have their own "id" too (kept for exporting).
          if (!isSong && a['id'] is String) '_itemId': a['id'],
          if (a['transpose'] is String) '_transpose': a['transpose'],
          if (a.containsKey('capo')) '_hasCapo': true,
          if (a.containsKey('arrangement')) '_hasArrangement': true,
        },
      ),
    );
  }
  return Setlist(
    id: j['id'] as String?,
    name: _s(j['title']).isEmpty ? 'Setlist' : _s(j['title']),
    setSpecific: j['separateSongSettings'] == true,
    entries: entries,
    eventDate: _appleDate(j['eventDate']),
    notes: _s(j['notes']),
    date: _appleDate(j['date']),
    extra: _extra(j, _playlistKeys),
  );
}

class LibraryBackup {
  final List<Song> songs;
  final List<Song> trash;
  final List<Tag> tags;
  final List<Setlist> setlists;

  LibraryBackup(this.songs, this.trash, this.tags, this.setlists);

  static LibraryBackup parse(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String k) =>
        ((json[k] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
    final songs = list('songs').map(_song).toList();
    final trash = list('songsTrash').map(_song).toList();
    final byId = {
      for (final s in [...songs, ...trash]) s.id: s,
    };
    final tags = list('tags')
        .map(
          (t) => Tag(
            id: t['id'] as String?,
            name: _s(t['name']),
            color: t['color'] as String?,
            hidden: t['hidden'] == true,
          ),
        )
        .toList();
    final setlists = list('playlists').map((p) => _setlist(p, byId)).toList();
    return LibraryBackup(songs, trash, tags, setlists);
  }
}

/// A JustChords playlist with its songs (Band Sync's `setlistData`): the
/// setlist and the songs, as this app's.
(Setlist, List<Song>) parseJustChordsSetlist(Map<String, dynamic> json) {
  final songs = ((json['songs'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(_song)
      .toList();
  final set = _setlist(json, {for (final s in songs) s.id: s});
  return (set, songs);
}

// ---- Other apps' songs ----

/// Splits ChordPro text holding several songs at each `{new_song}` / `{ns}`
/// (JustChords and others put a whole songbook in one file).
List<String> splitSongs(String text) {
  final parts = text.split(
    RegExp(
      r'^[ \t]*\{\s*(?:new_song|ns)\s*\}[ \t]*$',
      multiLine: true,
      caseSensitive: false,
    ),
  );
  return [
    for (final p in parts)
      if (p.trim().isNotEmpty) p.trim(),
  ];
}

/// An OnSong song file (.onsong / OnSong text): the title and artist on
/// the first lines, then `Key:`, `Capo:`, `Tempo:`… lines, then the
/// sections, with chords in brackets or over the words.
Song onSongToSong(String text, {String? fileName}) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final meta = <String, String>{};
  final loose = <String>[];
  var i = 0;
  final metaLine = RegExp(r'^\s*([A-Za-z][A-Za-z ]{0,20}):\s*(.*)$');
  // The header: up to the first blank line or section.
  for (; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.isEmpty) {
      if (meta.isNotEmpty || loose.isNotEmpty) break;
      continue;
    }
    final m = metaLine.firstMatch(t);
    if (m != null && m.group(2)!.isNotEmpty) {
      meta[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();
    } else if (ChordPro.sectionName(t) != null) {
      break;
    } else if (loose.length < 2 && !t.contains('[')) {
      loose.add(t);
    } else {
      break;
    }
  }
  final body = lines.sublist(i).join('\n').trim();
  final fallback = (fileName ?? 'Untitled').replaceAll(RegExp(r'\.[^.]+$'), '');
  final title = meta['title'] ?? (loose.isNotEmpty ? loose.first : fallback);
  final artist =
      meta['artist'] ?? meta['author'] ?? (loose.length > 1 ? loose[1] : '');
  return Song(
    title: title,
    artist: artist,
    raw: pastedToChordPro(body),
    key: meta['key'] == null ? null : MusicKey.parse(meta['key']!),
    capo: int.tryParse(meta['capo'] ?? '') ?? 0,
    tempo: meta['tempo'] ?? meta['bpm'] ?? '',
    timeSignature: meta['time'] ?? meta['time signature'] ?? '',
    copyright: meta['copyright'] ?? '',
    ccli: meta['ccli'] ?? '',
    duration: meta['duration'] ?? '',
    date: DateTime.now(),
    // Any other "Name: value" in the header is the person's own field,
    // as OnSong keeps it.
    custom: {
      for (final e in meta.entries)
        if (!_onSongKnown.contains(e.key)) _capitalized(e.key): e.value,
    },
  );
}

const _onSongKnown = {
  'title', 'artist', 'author', 'key', 'capo', 'tempo', 'bpm', 'time',
  'time signature', 'copyright', 'ccli', 'duration', //
};

String _capitalized(String name) => name
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// The JSON in a SongbookPro file's data (it can start with a version line
/// before the JSON), or null.
Map<String, dynamic>? songbookProData(String text) {
  for (final candidate in [text, text.substring(text.indexOf('\n') + 1)]) {
    try {
      final j = jsonDecode(candidate.trim());
      if (j is Map<String, dynamic> && isSongbookPro(j)) return j;
    } catch (_) {}
  }
  return null;
}

/// SongbookPro's data: songs with their words in `content` (ChordPro), a
/// `name` and an `author`, rather than this app's or JustChords' fields.
bool isSongbookPro(Map<String, dynamic> j) {
  final songs = j['songs'];
  if (songs is! List || songs.isEmpty || songs.first is! Map) return false;
  final s = songs.first as Map;
  return s.containsKey('content') &&
      !s.containsKey('raw') &&
      !s.containsKey('rawData');
}

const _sbpKeys = [
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

/// SongbookPro's songs and sets.
({List<Song> songs, List<Setlist> sets}) parseSongbookPro(
  Map<String, dynamic> j,
) {
  String str(Object? v) => v == null ? '' : '$v';
  final ids = <String, String>{};
  final songs = <Song>[];
  for (final e in (j['songs'] as List).whereType<Map>()) {
    final raw = str(e['content'] ?? e['lyrics']);
    MusicKey? key;
    final k = e['key'];
    if (k is num && k >= 0 && k < 12) {
      key = MusicKey(
        k.toInt(),
        raw.contains(RegExp(r'\{\s*key\s*:\s*[A-G][#b]?m\b')),
      );
    } else if (k is String && k.isNotEmpty) {
      final n = int.tryParse(k);
      key =
          MusicKey.parse(k) ??
          (n != null && n >= 0 && n < 12 ? MusicKey.parse(_sbpKeys[n]) : null);
    }
    final song = Song(
      title: str(e['name'] ?? e['title']).isEmpty
          ? 'Untitled'
          : str(e['name'] ?? e['title']),
      artist: str(e['author'] ?? e['artist']),
      raw: raw,
      key: key,
      capo: (e['capo'] is num)
          ? (e['capo'] as num).toInt()
          : int.tryParse(str(e['capo'])) ?? 0,
      tempo: str(e['tempo']) == '0' ? '' : str(e['tempo']),
      timeSignature: str(e['timeSig'] ?? e['time']),
      copyright: str(e['copyright']),
      notes: str(e['notes']),
      date: DateTime.now(),
    );
    final id = str(e['Id'] ?? e['id']);
    if (id.isNotEmpty) ids[id] = song.id;
    songs.add(song);
  }
  final sets = <Setlist>[];
  for (final e in ((j['sets'] as List?) ?? const []).whereType<Map>()) {
    final entries = <SetEntry>[];
    for (final item in (e['songs'] as List?) ?? const []) {
      final ref = item is Map
          ? str(item['Id'] ?? item['id'] ?? item['songId'])
          : str(item);
      final songId = ids[ref];
      if (songId != null) entries.add(SetEntry(songId: songId));
    }
    if (entries.isNotEmpty) {
      sets.add(
        Setlist(
          name: str(e['name']).isEmpty ? 'Set' : str(e['name']),
          entries: entries,
        ),
      );
    }
  }
  return (songs: songs, sets: sets);
}
