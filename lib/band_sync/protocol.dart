// Band Sync: JustChords' PlayTogether protocol (verified against JustChords
// 9.34, 2026-10-13; see PlayTogether_Implementation.txt).
//
// Local network only. The leader advertises Bonjour service
// "_jcremote._tcp" (instance name = the leader's nickname, TXT record
// "playlist=<setlist title>") and listens on TCP. Followers connect.
// Every message both ways is a 4-byte big-endian length followed by that
// many bytes of UTF-8 JSON. Messages:
//
//   leader -> follower
//     {"type":"setlistData","setlistData":{<JustChords playlist> + "songs":[<songs>]}}
//         sent on connect and again whenever the setlist or a song changes
//         (key / capo / autoscroll speed...). The follower shows it as a
//         temporary setlist; nothing is saved to its library.
//     {"type":"ping"}                                   every 5 s
//     {"type":"command","command":{"command":{"<name>":{}},"data":[...],"id":"<UUID>"}}
//         gotoPlaylistIndexAndSection: data [setlistIndex], id = that song's id
//         nextSongSection / previousSongSection / firstSongSection /
//         lastSongSection / nextSong / previousSong: data [], id = a NEW UUID
//         (the follower ignores a command whose id equals the previous one)
//     {"type":"scrollTo","scrollOffset":0.42}           0..1 of the song
//     {"type":"startAutoscroll","autoscrollFromOffset":0,"autoscrollToOffset":1,
//      "autoscrollDuration":90}                         seconds for from->to
//     {"type":"stopAutoscroll","scrollOffset":0.15}
//     {"type":"kick"}                                   follower disconnects
//   follower -> leader
//     {"type":"nickname","nickname":"Mac"}              first message
//     {"type":"pong"}                                   reply to each ping
//
// Sections are counted the way JustChords shows them: each section of the
// song structure separately (a linked "Verse 1" + "Verse 1 (FR)" pair is two
// sections there, one slide here).

import 'dart:convert';
import 'dart:typed_data';

import '../chordpro.dart';
import '../justchords.dart';
import '../state.dart';

const bandSyncService = '_jcremote._tcp';

/// One length-prefixed JSON frame.
Uint8List ptFrame(Map<String, dynamic> message) {
  final body = utf8.encode(jsonEncode(message));
  final out = Uint8List(4 + body.length);
  ByteData.sublistView(out).setUint32(0, body.length);
  out.setRange(4, out.length, body);
  return out;
}

/// Splits a byte stream into JSON messages.
class PtDecoder {
  Uint8List _pending = Uint8List(0);

  List<Map<String, dynamic>> add(List<int> chunk) {
    final data = Uint8List(_pending.length + chunk.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + chunk.length, chunk);
    final out = <Map<String, dynamic>>[];
    var i = 0;
    while (data.length - i >= 4) {
      final n = ByteData.sublistView(data, i, i + 4).getUint32(0);
      if (data.length - i - 4 < n) break;
      try {
        final m = jsonDecode(utf8.decode(data.sublist(i + 4, i + 4 + n)));
        if (m is Map<String, dynamic>) out.add(m);
      } catch (_) {
        // A broken message: skip it.
      }
      i += 4 + n;
    }
    _pending = Uint8List.fromList(data.sublist(i));
    return out;
  }
}

/// The `setlistData` payload for [set]: the JustChords playlist plus its
/// songs.
Map<String, dynamic> ptSetlistData(Setlist set, Song? Function(String) song) {
  // (Songs nested under another: entries of their own.)
  set = set.flattened(song);
  final byId = <String, Song>{
    for (final e in set.entries)
      if (e.type == EntryType.song && e.songId != null)
        e.songId!: ?song(e.songId!),
  };
  final p = justChordsPlaylist(set, byId);
  final seen = <String>{};
  p['songs'] = [
    for (final e in set.entries)
      if (e.type == EntryType.song &&
          byId[e.songId] != null &&
          seen.add(e.songId!))
        justChordsSong(byId[e.songId]!),
  ];
  p['shared'] = true;
  return p;
}

/// A command message ([id]: a song's id, or a fresh UUID).
Map<String, dynamic> ptCommand(String name, List<int> data, String id) => {
  'type': 'command',
  'command': {
    'command': {name: <String, dynamic>{}},
    'data': data,
    'id': id,
  },
};

/// The command name in a `command` message ("nextSongSection"...).
String? ptCommandName(Map<String, dynamic> m) {
  final c = (m['command'] as Map?)?['command'];
  return c is Map && c.isNotEmpty ? c.keys.first as String : null;
}

/// The `data` list of a `command` message.
List<int> ptCommandData(Map<String, dynamic> m) => [
  for (final v in ((m['command'] as Map?)?['data'] as List?) ?? const [])
    if (v is num) v.toInt(),
];

/// The `id` of a `command` message.
String? ptCommandId(Map<String, dynamic> m) =>
    (m['command'] as Map?)?['id'] as String?;

/// For each part of a song (see [ChordPro.parts], structure applied), the
/// JustChords sections it shows: each labelled section counts once, in
/// order, so a linked pair (a verse and its translation) gives one part two
/// sections. Parts that continue a section (split at a blank line) share
/// its number; key-change markers have none.
List<List<int>> jcSectionsOfParts(List<SongPart> parts) {
  var section = -1;
  final out = <List<int>>[];
  for (final part in parts) {
    if (part.isMarker) {
      out.add(const []);
      continue;
    }
    final mine = <int>[];
    for (final piece in part.pieceLines) {
      if (_startsSection(piece)) {
        section++;
      } else if (section < 0) {
        section = 0; // words before the first label
      }
      if (!mine.contains(section)) mine.add(section);
    }
    out.add(mine);
  }
  return out;
}

bool _startsSection(List<String> lines) {
  for (final l in lines) {
    if (l.trim().isEmpty) continue;
    return ChordPro.isSectionLabel(l);
  }
  return false;
}

/// The part showing JustChords section [section] (or the nearest before).
int partOfSection(List<List<int>> sections, int section) {
  var best = -1;
  for (var p = 0; p < sections.length; p++) {
    if (sections[p].contains(section)) return p;
    if (sections[p].isNotEmpty && sections[p].first <= section) best = p;
  }
  return best < 0 ? 0 : best;
}

/// The number of JustChords sections in a song.
int jcSectionCount(List<List<int>> sections) {
  var n = 0;
  for (final s in sections) {
    for (final k in s) {
      if (k + 1 > n) n = k + 1;
    }
  }
  return n;
}
