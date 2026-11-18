// OpenChords (https://openchords.net): an open protocol for sharing song
// folders and setlists between apps (JustChords, OpenSongApp…). A folder
// lives on the OpenChords server under a UUID; anyone with its link
// (https://openchords.net/?fld=<UUID>) can import it, and pull or push
// later edits.
//
// API v2 (OpenAPI 1.0.7, MIT, https://openchords.net/api/v2/swagger.json):
//   POST /login                     {username, password (its SHA-256, lower-
//                                   case hex), deviceId} → {token}, an hour
//   GET  /folder/{id}?userID=       the whole folder (Folder JSON)
//   POST /folder/{id}?userID=       saves the whole folder
// Each app has its own login (given by the OpenChords maintainer); this
// build takes it from --dart-define=OPENCHORDS_USER / OPENCHORDS_PASSWORD
// (GitHub secrets of the same names in CI) and leaves OpenChords out when
// there is none.
//
// A Folder: {title, type: folder|setlist, readonly, isOwner, songs,
// setlists, tags}. A Song: {id, title, rawData (ChordPro), artist,
// duration, tempo, timeSignature, key, keyIsMinor, transpose, notes,
// copyright, ccli, lastUpdated, tags (tag ids), structure, metadata}.
//
// Here a link joins a folder to one setlist (shared from this app, or a
// "setlist" folder from another app) or to a tag (a song folder: its
// songs get the tag). Syncing merges song by song (the newer edit wins, by
// lastUpdated); the setlist goes the way of the side that changed it since
// the last sync (both: this device's).

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'chordpro.dart';
import 'gospelizer.dart';
import 'music.dart';
import 'pdfs.dart';
import 'state.dart';

/// The server (another can be given with --dart-define=OPENCHORDS_API).
const openChordsApi = String.fromEnvironment(
  'OPENCHORDS_API',
  defaultValue: 'https://openchords.net/api/v2',
);
const openChordsShareBase = 'https://openchords.net/?fld=';

const _user = String.fromEnvironment('OPENCHORDS_USER');
const _password = String.fromEnvironment('OPENCHORDS_PASSWORD');

/// This build has an OpenChords login (see the top of this file).
bool get openChordsAvailable =>
    openChordsTestClient != null || (_user.isNotEmpty && _password.isNotEmpty);

/// Tests: the client the app uses instead of the real server's.
@visibleForTesting
OpenChordsClient? openChordsTestClient;

OpenChordsClient? _appClient;

/// The app's client (one login for the whole session).
OpenChordsClient openChordsClient({String deviceId = ''}) =>
    openChordsTestClient ??
    (_appClient ??= OpenChordsClient(deviceId: deviceId));

final _uuidPattern = RegExp(
  r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}',
);

/// The folder id in an OpenChords link (or a bare id), upper case; null if
/// [text] holds none.
String? openChordsFolderId(String text) {
  final t = text.trim();
  final fld = RegExp(r'[?&]fld=([^&#\s]+)').firstMatch(t);
  final m = _uuidPattern.firstMatch(fld?.group(1) ?? t);
  return m?.group(0)!.toUpperCase();
}

/// The link others open to import the folder.
String openChordsLink(String folderId) => '$openChordsShareBase$folderId';

String _up(String id) => id.toUpperCase();

/// A fresh OpenChords id (UUID v4, upper case).
String newOpenChordsId() => _up(newId());

// ---- Songs ----

/// Song fields this file reads and writes; the rest of a song from the
/// server is kept (in [Song.extra]) and sent back as it came.
const _songFields = {
  'id', 'title', 'rawData', 'artist', 'duration', 'tempo', 'timeSignature',
  'key', 'keyIsMinor', 'transpose', 'notes', 'copyright', 'ccli',
  'lastUpdated', 'tags', 'structure', 'metadata', //
};

const _extraKey = 'openchords';

final _keyPattern = RegExp(r'^[A-G][#b]?$');
final _timePattern = RegExp(r'^[1-9]{1,2}/[1-9]$');

bool _isYouTube(String url) =>
    RegExp(r'(youtube\.com|youtu\.be)/', caseSensitive: false).hasMatch(url);

String _stamp(DateTime? d) =>
    (d ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .toUtc()
        .toIso8601String();

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

String _s(Object? v) => v is String ? v.trim() : (v is num ? '$v' : '');

/// Key name for OpenChords: "G", "Bb", "F#" (minor goes in keyIsMinor).
String _keyName(MusicKey k) => MusicKey(k.root, false).name;

/// [items] as OpenChords structure: sections, a key change becoming the
/// next section's transposeSteps.
List<Map<String, dynamic>> _structureOut(List<StructureItem> items) {
  final out = <Map<String, dynamic>>[];
  int? steps;
  for (final i in items) {
    if (i.isModulation) {
      steps = i.semitones;
    } else {
      out.add({'sectionName': i.name, 'transposeSteps': ?steps});
      steps = null;
    }
  }
  return out;
}

List<StructureItem> _structureIn(Object? list) => [
  if (list is List)
    for (final i in list.whereType<Map>())
      if (_s(i['sectionName']).isNotEmpty) ...[
        if (i['transposeSteps'] is num)
          StructureItem.keyChange((i['transposeSteps'] as num).toInt()),
        StructureItem.section(_s(i['sectionName'])),
      ],
];

/// [s] as an OpenChords Song. [tagIds]: this app's tag id → the folder's
/// (songs keep only the folder's tags).
Map<String, dynamic> openChordsSong(Song s, {Map<String, String>? tagIds}) {
  final kept = s.extra[_extraKey];
  final key = s.writtenKey;
  final m = <String, dynamic>{
    if (kept is Map) ...Map<String, dynamic>.from(kept),
    'id': _up(s.id),
    'title': s.displayTitle,
    // (With the Gospelizer's chords while it's on.)
    'rawData': s.exportRaw,
    'lastUpdated': _stamp(s.date),
  };
  void opt(String k, Object? v) {
    if (v == null || (v is String && v.isEmpty)) {
      m.remove(k);
    } else {
      m[k] = v;
    }
  }

  opt('artist', s.displayArtist);
  opt('duration', s.duration.trim());
  final tempo = int.tryParse(s.tempo.trim());
  opt('tempo', tempo != null && tempo > 0 ? tempo : null);
  final time = s.timeSignature.trim();
  opt('timeSignature', _timePattern.hasMatch(time) ? time : null);
  opt('key', key == null ? null : _keyName(key));
  opt('keyIsMinor', key?.minor);
  opt(
    'transpose',
    key == null || s.transpose == 0
        ? null
        : _keyName(key.transposed(s.transpose)),
  );
  opt('notes', s.notes.trim());
  opt('copyright', s.copyright.trim());
  opt('ccli', s.ccli.trim());
  opt('structure', s.structure.isEmpty ? null : _structureOut(s.structure));
  if (tagIds != null) {
    opt(
      'tags',
      [
        for (final t in s.tags)
          if (tagIds[t] != null) tagIds[t]!,
      ].nullIfEmpty,
    );
  }
  // Recording links: ours in front; any others the song had stay.
  final url = s.audioUrl.trim();
  final meta = [
    if (url.isNotEmpty)
      {'key': _isYouTube(url) ? 'youtubeUrl' : 'audioUrl', 'value': url},
    if (kept is Map && kept['metadata'] is List)
      for (final i in (kept['metadata'] as List).whereType<Map>())
        if (i['key'] != 'youtubeUrl' && i['key'] != 'audioUrl')
          Map<String, dynamic>.from(i),
  ];
  opt('metadata', meta.nullIfEmpty);
  return m;
}

extension<T> on List<T> {
  List<T>? get nullIfEmpty => isEmpty ? null : this;
}

/// An OpenChords Song as this app's. [tagOf]: the folder's tag id → this
/// app's tag id (null to leave it off).
Song songFromOpenChords(
  Map<String, dynamic> j, {
  String? Function(String ocTagId)? tagOf,
}) {
  final raw = j['rawData'] is String ? j['rawData'] as String : '';
  final keyText = _s(j['key']);
  MusicKey? key = _keyPattern.hasMatch(keyText)
      ? MusicKey.parse('$keyText${j['keyIsMinor'] == true ? 'm' : ''}')
      : null;
  var transpose = 0;
  final played = MusicKey.parse(_s(j['transpose']));
  if (played != null) {
    key ??= ChordProHeader.parse(raw).key == null
        ? null
        : MusicKey.parse(ChordProHeader.parse(raw).key!);
    if (key != null) transpose = normalizeTranspose(played.root - key.root);
  }
  var audio = '';
  if (j['metadata'] is List) {
    for (final i in (j['metadata'] as List).whereType<Map>()) {
      if ((i['key'] == 'youtubeUrl' || i['key'] == 'audioUrl') &&
          _s(i['value']).isNotEmpty) {
        audio = _s(i['value']);
        break;
      }
    }
  }
  final tempo = j['tempo'];
  return Song(
    id: _s(j['id']).isEmpty ? null : _s(j['id']),
    title: _s(j['title']),
    raw: raw,
    key: _keyPattern.hasMatch(keyText) ? key : null,
    transpose: transpose,
    artist: _s(j['artist']),
    duration: _s(j['duration']),
    tempo: tempo is num && tempo > 0 ? '${tempo.toInt()}' : '',
    timeSignature: _s(j['timeSignature']),
    notes: _s(j['notes']),
    copyright: _s(j['copyright']),
    ccli: _s(j['ccli']),
    audioUrl: audio,
    structure: _structureIn(j['structure']),
    tags: [
      if (tagOf != null && j['tags'] is List)
        for (final t in (j['tags'] as List).whereType<String>()) ?tagOf(_up(t)),
    ],
    date: _date(j['lastUpdated']),
    extra: {
      _extraKey: {
        for (final e in j.entries)
          if (!_songFields.contains(e.key) && e.value != null) e.key: e.value,
        if (j['metadata'] is List) 'metadata': j['metadata'],
      },
    },
  );
}

// ---- Setlists ----

/// [set] as an OpenChords Setlist. Songs nested under another become
/// entries of their own; labels and events become slides (with what they
/// were in customData), media and Bible passages too.
Map<String, dynamic> openChordsSetlist(Setlist set, Map<String, Song> byId) {
  final flat = set.flattened((id) => byId[id]);
  final kept = set.extra[_extraKey];
  final items = <Map<String, dynamic>>[];
  for (final e in flat.entries) {
    final keptItem = e.extra[_extraKey];
    final base = <String, dynamic>{
      if (keptItem is Map) ...Map<String, dynamic>.from(keptItem),
      'id': _up(e.id),
    };
    if (e.type == EntryType.song) {
      final song = byId[e.songId];
      if (song == null) continue;
      final key = song.writtenKey;
      final t = set.setSpecific ? e.transpose : song.transpose;
      items.add({
        ...base,
        'type': 'song',
        'songItem': {
          'songId': _up(song.id),
          if (key != null && t != 0) 'transpose': _keyName(key.transposed(t)),
          if (e.structure.isNotEmpty) 'structure': _structureOut(e.structure),
        },
      });
    } else if (e.type == EntryType.divider) {
      items.add({...base, 'type': 'divider', 'title': e.title});
    } else {
      items.add({
        ...base,
        'type': 'slide',
        'title': e.title,
        'customData': jsonEncode({
          'chordproPresenter': e.type.name,
          'color': ?e.color,
        }),
      });
    }
  }
  return {
    if (kept is Map) ...Map<String, dynamic>.from(kept),
    'id': _up(set.id),
    'title': set.name,
    'items': items,
    'lastUpdated': _stamp(
      set.extra['openchordsUpdated'] is String
          ? DateTime.tryParse(set.extra['openchordsUpdated'] as String)
          : set.date,
    ),
  };
}

/// An OpenChords Setlist as this app's (songs looked up in [byId], by
/// upper-case id).
Setlist setlistFromOpenChords(Map<String, dynamic> j, Map<String, Song> byId) {
  final entries = <SetEntry>[];
  var anyTranspose = false;
  for (final i in ((j['items'] as List?) ?? const []).whereType<Map>()) {
    final item = Map<String, dynamic>.from(i);
    final id = _s(item['id']).isEmpty ? null : _s(item['id']);
    final keep = {
      _extraKey: {
        for (final e in item.entries)
          if (!const {
                'id',
                'type',
                'title',
                'songItem',
                'customData',
              }.contains(e.key) &&
              e.value != null)
            e.key: e.value,
      },
    };
    switch (item['type']) {
      case 'song':
        final si = item['songItem'];
        if (si is! Map) continue;
        final song = byId[_up(_s(si['songId']))];
        if (song == null) continue;
        final played = MusicKey.parse(_s(si['transpose']));
        final key = song.writtenKey;
        final t = played != null && key != null
            ? normalizeTranspose(played.root - key.root)
            : song.transpose;
        if (t != song.transpose) anyTranspose = true;
        entries.add(
          SetEntry(
            id: id,
            songId: song.id,
            transpose: t,
            capo: song.capo,
            structure: _structureIn(si['structure']),
            extra: keep,
          ),
        );
      case 'divider':
        entries.add(
          SetEntry(
            id: id,
            type: EntryType.divider,
            title: _s(item['title']),
            extra: keep,
          ),
        );
      default:
        // A slide: what it was here, if it came from this app.
        var type = EntryType.event;
        String? color;
        try {
          final c = jsonDecode(_s(item['customData']));
          if (c is Map) {
            final t = EntryType.values.asNameMap()[c['chordproPresenter']];
            if (t == EntryType.label || t == EntryType.event) type = t!;
            color = c['color'] as String?;
          }
        } catch (_) {}
        entries.add(
          SetEntry(
            id: id,
            type: type,
            title: _s(item['title']),
            color: color,
            extra: keep,
          ),
        );
    }
  }
  return Setlist(
    id: _s(j['id']).isEmpty ? null : _s(j['id']),
    name: _s(j['title']).isEmpty ? 'Setlist' : _s(j['title']),
    setSpecific: anyTranspose,
    entries: entries,
    date: _date(j['lastUpdated']),
    extra: {
      _extraKey: {
        for (final e in j.entries)
          if (!const {'id', 'title', 'items', 'lastUpdated'}.contains(e.key) &&
              e.value != null)
            e.key: e.value,
      },
    },
  );
}

// ---- Links ----

enum OpenChordsKind { setlist, folder }

/// A folder on the OpenChords server joined to a setlist or a tag here,
/// with what was in step at the last sync.
class OpenChordsLink {
  final String folderId;
  final OpenChordsKind kind;

  /// The setlist ([OpenChordsKind.setlist]) or tag ([OpenChordsKind.folder]).
  final String localId;
  String title;

  /// Only the owner can change it ([readonly] set by the owner).
  bool readonly;
  bool isOwner;

  /// Song ids (upper case) in the folder after the last sync: a song gone
  /// from one side since was removed there.
  Set<String> songIds;

  /// The setlist as it was at the last sync, here and on the server.
  String? localSetHash;
  String? remoteSetHash;
  DateTime? lastSync;

  OpenChordsLink({
    required this.folderId,
    required this.kind,
    required this.localId,
    this.title = '',
    this.readonly = false,
    this.isOwner = true,
    Set<String>? songIds,
    this.localSetHash,
    this.remoteSetHash,
    this.lastSync,
  }) : songIds = songIds ?? {};

  String get link => openChordsLink(folderId);

  /// This device may send changes.
  bool get canPush => isOwner || !readonly;

  Map<String, dynamic> toJson() => {
    'folderId': folderId,
    'kind': kind.name,
    'localId': localId,
    'title': title,
    'readonly': readonly,
    'isOwner': isOwner,
    'songIds': songIds.toList(),
    'localSetHash': ?localSetHash,
    'remoteSetHash': ?remoteSetHash,
    'lastSync': ?lastSync?.toIso8601String(),
  };

  static OpenChordsLink? fromJson(Object? v) {
    if (v is! Map) return null;
    final kind = OpenChordsKind.values.asNameMap()[v['kind']];
    final id = v['folderId'], local = v['localId'];
    if (kind == null || id is! String || local is! String) return null;
    return OpenChordsLink(
      folderId: id,
      kind: kind,
      localId: local,
      title: _s(v['title']),
      readonly: v['readonly'] == true,
      isOwner: v['isOwner'] != false,
      songIds: {
        for (final s in (v['songIds'] as List?) ?? const [])
          if (s is String) s,
      },
      localSetHash: v['localSetHash'] as String?,
      remoteSetHash: v['remoteSetHash'] as String?,
      lastSync: v['lastSync'] is String
          ? DateTime.tryParse(v['lastSync'] as String)
          : null,
    );
  }
}

/// The setlist's content as a short fingerprint, for telling whether it
/// changed (its date and what only this app keeps left out).
String openChordsSetHash(Map<String, dynamic> set) {
  final items = [
    for (final i in (set['items'] as List?) ?? const [])
      if (i is Map) {...i}..remove('notes'),
  ];
  // FNV-1a (the same on every platform, unlike String.hashCode).
  var h = 0x811c9dc5;
  for (final c in utf8.encode(
    jsonEncode({'title': set['title'], 'items': items}),
  )) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

// ---- Merging ----

/// What a sync does: songs to save here (new or newer on the server), the
/// setlist to take (if the server's won), the folder to send (if this
/// device's side changed), and what moved, for telling the person.
class OpenChordsMerge {
  final List<Song> pulled;

  /// Songs (ids as here) that left the folder on the server: a song
  /// folder's lose its tag here.
  final List<String> removedHere;
  final Setlist? setlist;
  final Map<String, dynamic>? upload;
  final int pushedSongs;
  final bool pushedSetlist;
  final Set<String> songIds;
  final String? localSetHash;
  final String? remoteSetHash;

  OpenChordsMerge({
    required this.pulled,
    required this.removedHere,
    required this.setlist,
    required this.upload,
    required this.pushedSongs,
    required this.pushedSetlist,
    required this.songIds,
    required this.localSetHash,
    required this.remoteSetHash,
  });

  bool get changedHere =>
      pulled.isNotEmpty || removedHere.isNotEmpty || setlist != null;

  String get summary {
    final parts = [
      if (pulled.isNotEmpty)
        '${pulled.length} song${pulled.length == 1 ? '' : 's'} updated here',
      if (setlist != null) 'setlist updated here',
      if (removedHere.isNotEmpty)
        '${removedHere.length} song${removedHere.length == 1 ? '' : 's'} '
            'removed from the folder',
      if (pushedSongs > 0)
        '$pushedSongs song${pushedSongs == 1 ? '' : 's'} sent',
      if (pushedSetlist) 'setlist sent',
    ];
    return parts.isEmpty ? 'Up to date' : parts.join(', ');
  }
}

/// Merges [remote] (the folder from the server; null when it isn't there
/// yet) with this device's side: [localSongs] (the setlist's songs, or the
/// tag's) and [localSet] (a setlist link's setlist). [tags]: this app's
/// tags, for the folder's tag list.
OpenChordsMerge mergeOpenChords({
  required OpenChordsLink link,
  required Map<String, dynamic>? remote,
  required List<Song> localSongs,
  Setlist? localSet,
  List<Tag> tags = const [],
  Map<String, String> remoteTagNames = const {},
  String? Function(String ocTagId)? tagOf,
}) {
  final canPush = remote == null || link.canPush;
  final remoteSongs = <String, Map<String, dynamic>>{
    for (final s
        in ((remote?['songs'] as List?) ?? const []).whereType<Map>().map(
          (m) => Map<String, dynamic>.from(m),
        ))
      if (_s(s['id']).isNotEmpty) _up(_s(s['id'])): s,
  };
  final local = {
    for (final s in localSongs)
      if (!isPdfOnly(s)) _up(s.id): s,
  };

  final pulled = <Song>[];
  final removedHere = <String>[];
  final upload = <String, Map<String, dynamic>>{};
  var pushed = 0;

  // The folder's tags: its own, plus ours on the songs sent.
  final tagIds = <String, String>{};
  final folderTags = <String, Map<String, dynamic>>{
    for (final t in ((remote?['tags'] as List?) ?? const []).whereType<Map>())
      if (_s(t['id']).isNotEmpty) _up(_s(t['id'])): Map.from(t),
  };
  if (link.kind == OpenChordsKind.setlist) {
    for (final t in tags) {
      final same = folderTags.entries
          .where((e) => _s(e.value['title']) == t.name)
          .firstOrNull;
      tagIds[t.id] = same?.key ?? _up(t.id);
    }
  }
  final usedTags = <String>{};

  Map<String, dynamic> out(Song s) {
    final j = openChordsSong(
      s,
      tagIds: link.kind == OpenChordsKind.setlist ? tagIds : null,
    );
    if (link.kind == OpenChordsKind.folder) {
      // A song folder keeps the tags its songs had there.
      final was = remoteSongs[_up(s.id)]?['tags'];
      if (was is List && was.isNotEmpty) j['tags'] = was;
    }
    for (final t in (j['tags'] as List?) ?? const []) {
      usedTags.add('$t');
    }
    return j;
  }

  for (final id in {...local.keys, ...remoteSongs.keys}) {
    final l = local[id], r = remoteSongs[id];
    if (l != null && r != null) {
      final lt = l.date?.toUtc(), rt = _date(r['lastUpdated']);
      final remoteNewer =
          rt != null && (lt == null || rt.difference(lt).inSeconds >= 1);
      final localNewer =
          lt != null && (rt == null || lt.difference(rt).inSeconds >= 1);
      if (remoteNewer || (!canPush && localNewer)) {
        final s = songFromOpenChords(r, tagOf: tagOf);
        pulled.add(_keepHere(s, l));
        upload[id] = r;
      } else if (localNewer) {
        upload[id] = out(l);
        pushed++;
      } else {
        upload[id] = r;
      }
    } else if (r != null) {
      if (link.kind == OpenChordsKind.folder &&
          link.songIds.contains(id) &&
          canPush) {
        // Taken out of the folder here (untagged or deleted): out there too.
        continue;
      }
      pulled.add(songFromOpenChords(r, tagOf: tagOf));
      upload[id] = r;
    } else if (l != null) {
      if (link.kind == OpenChordsKind.folder && link.songIds.contains(id)) {
        // Gone from the folder on the server.
        removedHere.add(l.id);
        continue;
      }
      if (!canPush) continue;
      upload[id] = out(l);
      pushed++;
    }
  }

  // The setlist (a setlist link's only).
  Setlist? takeSet;
  var pushedSet = false;
  String? localHash = link.localSetHash, remoteHash = link.remoteSetHash;
  final remoteSets = [
    for (final s
        in ((remote?['setlists'] as List?) ?? const []).whereType<Map>())
      Map<String, dynamic>.from(s),
  ];
  List<Map<String, dynamic>> setsOut = remoteSets;
  if (link.kind == OpenChordsKind.setlist && localSet != null) {
    final songsNow = <String, Song>{
      for (final s in localSongs) s.id: s,
      for (final s in pulled) s.id: s,
    };
    final mine = openChordsSetlist(localSet, songsNow);
    final theirs = remoteSets.firstOrNull;
    final mineHash = openChordsSetHash(mine);
    final theirsHash = theirs == null ? null : openChordsSetHash(theirs);
    final localChanged = mineHash != link.localSetHash;
    final remoteChanged =
        theirsHash != null && theirsHash != link.remoteSetHash;
    if (theirs != null && remoteChanged && (!localChanged || !canPush)) {
      final byId = {
        for (final s in localSongs) _up(s.id): s,
        for (final s in pulled) _up(s.id): s,
      };
      takeSet = setlistFromOpenChords(theirs, byId);
      // The server's songs not here yet come with it.
      for (final i
          in ((theirs['items'] as List?) ?? const []).whereType<Map>()) {
        final si = i['songItem'];
        if (si is Map) {
          final id = _up(_s(si['songId']));
          if (!byId.containsKey(id) && remoteSongs[id] != null) {
            final s = songFromOpenChords(remoteSongs[id]!, tagOf: tagOf);
            pulled.add(s);
            byId[id] = s;
          }
        }
      }
      if (byId.length > songsNow.length) {
        takeSet = setlistFromOpenChords(theirs, byId);
      }
      setsOut = [theirs];
      localHash = openChordsSetHash(
        openChordsSetlist(takeSet, {for (final s in byId.values) s.id: s}),
      );
      remoteHash = theirsHash;
    } else if (canPush && (localChanged || theirs == null)) {
      setsOut = [mine];
      pushedSet = theirs == null || mineHash != theirsHash;
      localHash = mineHash;
      remoteHash = mineHash;
    } else {
      localHash = mineHash;
      remoteHash = theirsHash;
    }
    // Songs that left the setlist leave the folder.
    final inSet = {
      for (final i in (setsOut.first['items'] as List).whereType<Map>())
        if (i['songItem'] is Map) _up(_s((i['songItem'] as Map)['songId'])),
    };
    upload.removeWhere((id, _) => !inSet.contains(id));
  }

  final sendSongs = upload.values.toList();
  for (final s in sendSongs) {
    for (final t in (s['tags'] as List?) ?? const []) {
      usedTags.add('$t');
    }
  }
  final changedThere =
      remote == null ||
      pushed > 0 ||
      pushedSet ||
      upload.length != remoteSongs.length;
  Map<String, dynamic>? folder;
  if (canPush && changedThere) {
    final names = {for (final t in tags) tagIds[t.id] ?? _up(t.id): t};
    folder = {
      ...?remote,
      // (A shared setlist's folder goes by the setlist's name.)
      'title': link.kind == OpenChordsKind.setlist && setsOut.isNotEmpty
          ? setsOut.first['title'] ?? link.title
          : link.title,
      'type': link.kind == OpenChordsKind.setlist ? 'setlist' : 'folder',
      'readonly': link.readonly,
      'songs': sendSongs,
      'setlists': setsOut,
      'tags': [
        for (final id in usedTags)
          folderTags[id] ??
              {
                'id': id,
                'title': names[id]?.name ?? remoteTagNames[id] ?? 'Tag',
                'color': ?names[id]?.color,
              },
      ],
    }..remove('isOwner');
  }
  return OpenChordsMerge(
    pulled: pulled,
    removedHere: removedHere,
    setlist: takeSet,
    upload: folder,
    pushedSongs: pushed,
    pushedSetlist: pushedSet,
    songIds: upload.keys.toSet(),
    localSetHash: localHash,
    remoteSetHash: remoteHash,
  );
}

/// A song from the server replacing [here]: what only this app keeps
/// (capo, its own fields, the parts of the song OpenChords has no place
/// for) stays.
Song _keepHere(Song s, Song here) => Song.fromJson({
  ...here.toJson(),
  ...{
    for (final e in s.toJson().entries)
      if (const {
        'title', 'raw', 'key', 'transpose', 'artist', 'tempo',
        'timeSignature', 'duration', 'notes', 'copyright', 'ccli',
        'audioUrl', 'structure', 'date', 'extra', //
      }.contains(e.key))
        e.key: e.value,
  },
  'id': here.id,
  'tags': here.tags,
  'extra': {...here.extra, ...s.extra},
});

// ---- The server ----

class OpenChordsException implements Exception {
  final String message;
  final int? status;
  OpenChordsException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Talks to the OpenChords server (this app's login; a token kept until
/// the server turns it down).
class OpenChordsClient {
  final http.Client _http;
  final String user, password, deviceId;
  final String base;
  String? _token;
  DateTime? _tokenTime;

  /// Tokens last an hour; a new login a little before that.
  static const tokenLife = Duration(minutes: 55);

  OpenChordsClient({
    http.Client? client,
    this.user = _user,
    this.password = _password,
    this.deviceId = '',
    this.base = openChordsApi,
  }) : _http = client ?? http.Client();

  Future<String> _login() async {
    final r = await _http.post(
      Uri.parse('$base/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': user,
        // (The server takes the password's SHA-256, never the password.)
        'password': sha256Hex(password),
        if (deviceId.isNotEmpty) 'deviceId': deviceId,
      }),
    );
    if (r.statusCode != 200) {
      throw OpenChordsException(
        'OpenChords turned down this app\'s login (${r.statusCode}).',
        r.statusCode,
      );
    }
    final token = (jsonDecode(r.body) as Map)['token'];
    if (token is! String || token.isEmpty) {
      throw OpenChordsException('OpenChords sent no login token.');
    }
    _tokenTime = DateTime.now();
    return _token = token;
  }

  Future<http.Response> _call(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final fresh =
          _tokenTime != null &&
          DateTime.now().difference(_tokenTime!) < tokenLife;
      final token = (fresh ? _token : null) ?? await _login();
      final r = await send({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });
      if (r.statusCode == 401 && attempt == 0) {
        _token = null;
        continue;
      }
      return r;
    }
    throw OpenChordsException('OpenChords login failed.');
  }

  Uri _folder(String id, String userId) =>
      Uri.parse('$base/folder/$id${userId.isEmpty ? '' : '?userID=$userId'}');

  /// The folder, or null if the server has none with that id.
  Future<Map<String, dynamic>?> getFolder(String id, String userId) async {
    final r = await _call((h) => _http.get(_folder(id, userId), headers: h));
    if (r.statusCode == 404 || (r.statusCode == 200 && r.body.trim().isEmpty)) {
      return null;
    }
    if (r.statusCode != 200) {
      throw OpenChordsException(
        'OpenChords couldn\'t open the folder (${r.statusCode}).',
        r.statusCode,
      );
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map<String, dynamic>) return null;
    // (No songs and no title: a folder nobody saved.)
    if (j['title'] == null && (j['songs'] as List?)?.isEmpty != false) {
      return null;
    }
    return j;
  }

  Future<void> saveFolder(
    String id,
    String userId,
    Map<String, dynamic> folder,
  ) async {
    final r = await _call(
      (h) =>
          _http.post(_folder(id, userId), headers: h, body: jsonEncode(folder)),
    );
    if (r.statusCode == 403) {
      throw OpenChordsException(
        'This folder is read-only: only its owner can change it.',
        403,
      );
    }
    if (r.statusCode != 200) {
      throw OpenChordsException(
        'OpenChords couldn\'t save the folder (${r.statusCode}).',
        r.statusCode,
      );
    }
  }
}

// ---- Syncing a link ----

/// The songs a link covers here: the setlist's (nested ones too), or the
/// tag's.
List<Song> openChordsSongsHere(PresenterModel m, OpenChordsLink link) {
  if (link.kind == OpenChordsKind.folder) {
    return [
      for (final s in m.songs)
        if (s.tags.contains(link.localId)) s,
    ];
  }
  final set = m.setlistById(link.localId);
  if (set == null) return const [];
  final seen = <String>{};
  return [
    for (final e in set.flattened(m.songById).entries)
      if (e.type == EntryType.song)
        if (m.songById(e.songId) case final s? when seen.add(s.id)) s,
  ];
}

/// Syncs [link] with its folder: the server's changes taken here, this
/// device's sent there. Throws [OpenChordsException] when the server
/// can't be reached or says no.
///
/// [readonly] (the owner only): locks the folder (true) or lets anyone
/// with the link edit it (false).
Future<OpenChordsMerge> syncOpenChords(
  PresenterModel m,
  OpenChordsLink link, {
  OpenChordsClient? client,
  bool? readonly,
}) async {
  final api = client ?? openChordsClient(deviceId: m.openChordsUserId);
  final user = m.openChordsUserId;
  final remote = await api.getFolder(link.folderId, user);
  if (remote != null) {
    link.readonly = remote['readonly'] == true;
    if (remote['isOwner'] is bool) link.isOwner = remote['isOwner'] as bool;
    final title = remote['title'];
    if (title is String && title.trim().isNotEmpty) link.title = title.trim();
  }
  // The folder's tags, matched here by name (made if missing).
  final tagMap = <String, String>{};
  for (final t in ((remote?['tags'] as List?) ?? const []).whereType<Map>()) {
    final id = t['id'], name = t['title'];
    if (id is! String || name is! String || name.trim().isEmpty) continue;
    final here =
        m.tags.where((x) => x.name == name.trim()).firstOrNull ??
        m.addTag(name.trim(), color: t['color'] as String?);
    tagMap[id.toUpperCase()] = here.id;
  }
  final merge = mergeOpenChords(
    link: link,
    remote: remote,
    localSongs: openChordsSongsHere(m, link),
    localSet: link.kind == OpenChordsKind.setlist
        ? m.setlistById(link.localId)
        : null,
    tags: m.tags,
    tagOf: (id) => tagMap[id],
  );
  var upload = merge.upload;
  if (readonly != null && link.isOwner) {
    link.readonly = readonly;
    if (remote != null && upload == null) {
      upload = {...remote}..remove('isOwner');
    }
    upload?['readonly'] = readonly;
  }
  if (upload != null) await api.saveFolder(link.folderId, user, upload);
  m.applyOpenChords(link, merge);
  return merge;
}

/// Shares [set] as a new OpenChords folder (this device its owner).
Future<OpenChordsLink> shareSetlistOnOpenChords(
  PresenterModel m,
  Setlist set, {
  bool readonly = false,
  OpenChordsClient? client,
}) async {
  final link = OpenChordsLink(
    folderId: newOpenChordsId(),
    kind: OpenChordsKind.setlist,
    localId: set.id,
    title: set.name,
    readonly: readonly,
  );
  await syncOpenChords(m, link, client: client);
  m.addOpenChordsLink(link);
  return link;
}

/// SHA-256 of [text] (UTF-8) as lower-case hex.
String sha256Hex(String text) {
  const k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, //
  ];
  final h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
    0x1f83d9ab, 0x5be0cd19, //
  ];
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
  final bytes = [...utf8.encode(text), 0x80];
  final bits = (bytes.length - 1) * 8;
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    // (Lengths past 2^32 bits never happen here.)
    bytes.add(i >= 4 ? 0 : (bits >> (8 * i)) & 0xff);
  }
  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < bytes.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final j = chunk + i * 4;
      w[i] =
          (bytes[j] << 24) |
          (bytes[j + 1] << 16) |
          (bytes[j + 2] << 8) |
          bytes[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    final add = [a, b, c, d, e, f, g, hh];
    for (var i = 0; i < 8; i++) {
      h[i] = (h[i] + add[i]) & 0xffffffff;
    }
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}
