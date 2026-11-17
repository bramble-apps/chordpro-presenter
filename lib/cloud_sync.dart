// Backups and sync: the library saved where it's safe.
//
// Folder backup (the Linux app, and the web app with its local server):
// the backup zip (songs.json and the PDFs, the same file "Export" makes)
// written into a folder of your choice after changes, the newest few kept.
// Point it at a synced folder (Drime, Dropbox, Nextcloud, Syncthing…) and
// the backups go online too.
//
// WebDAV sync (every app): the library kept on a WebDAV service (Koofr,
// Nextcloud, a NAS…) and merged song by song with every device using the
// same account. On the server, in the chosen folder, one folder per
// library:
//   songs/<id>.json   {"song": {...}, "trash": bool}
//   meta.json         {"tags": [...], "setlists": [...]}
//   files/<id>        PDFs and pictures (they never change once added)
//   stamp.json        changed by every sync that changes something, so the
//                     regular checks read just this when all's quiet
// What was last in step is remembered per song (its local hash and the
// server's ETag), so each side's changes and deletions are told apart;
// when both changed the same song, the newer edit wins and the other is
// kept as a copy ("(other copy)").

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'browser.dart';
import 'pdfs.dart';
import 'state.dart';

/// A sync that doesn't merge: this device's library sent over the
/// service's ([push]), or the service's taken over this device's ([pull]).
enum SyncForce { none, push, pull }

// ---- Settings ----

class SyncSettings {
  bool backupOn = false;
  String backupFolder = '';
  int keep = 10;

  bool davOn = false;
  String davUrl = '';
  String davUser = '';
  String davPassword = '';
  String davFolder = 'ChordPro Presenter';

  Map<String, dynamic> toJson() => {
    'backupOn': backupOn,
    'backupFolder': backupFolder,
    'keep': keep,
    'davOn': davOn,
    'davUrl': davUrl,
    'davUser': davUser,
    'davPassword': davPassword,
    'davFolder': davFolder,
  };

  void updateFrom(Map<String, dynamic> j) {
    backupOn = j['backupOn'] == true;
    backupFolder = j['backupFolder'] as String? ?? '';
    keep = (j['keep'] as num?)?.toInt() ?? 10;
    davOn = j['davOn'] == true;
    davUrl = j['davUrl'] as String? ?? '';
    davUser = j['davUser'] as String? ?? '';
    davPassword = j['davPassword'] as String? ?? '';
    davFolder = j['davFolder'] as String? ?? 'ChordPro Presenter';
  }

  bool get davReady => davUrl.trim().isNotEmpty && davUser.trim().isNotEmpty;
}

/// Ready-made WebDAV addresses.
const davPresets = {
  'Koofr': 'https://app.koofr.net/dav/Koofr',
  'Nextcloud': 'https://YOUR-SERVER/remote.php/dav/files/YOUR-USERNAME',
};

// ---- WebDAV ----

class DavResponse {
  final int status;
  final Map<String, String> headers;
  final Uint8List body;
  const DavResponse(this.status, this.headers, this.body);

  bool get ok => status >= 200 && status < 300;
  String get text => utf8.decode(body, allowMalformed: true);
}

/// Sends one HTTP request (tests and other transports swap this).
typedef DavSend = Future<DavResponse> Function(
  String method,
  String url,
  Map<String, String> headers,
  Uint8List? body,
);

/// Browsers can't reach WebDAV services (other sites), so the web app
/// asks its local server to; the installed apps go directly.
Future<DavResponse> defaultDavSend(
  String method,
  String url,
  Map<String, String> headers,
  Uint8List? body,
) async {
  if (kIsWeb) {
    final j = await localServer(
      'dav',
      post: {
        'method': method,
        'url': url,
        'headers': headers,
        'body': body == null ? '' : base64Encode(body),
      },
    ) as Map;
    return DavResponse((j['status'] as num).toInt(), {
      for (final e in ((j['headers'] as Map?) ?? const {}).entries)
        '${e.key}'.toLowerCase(): '${e.value}',
    }, base64Decode(j['body'] as String? ?? ''));
  }
  final req = http.Request(method, Uri.parse(url))..headers.addAll(headers);
  if (body != null) req.bodyBytes = body;
  final res = await http.Response.fromStream(
    await req.send().timeout(const Duration(seconds: 60)),
  );
  return DavResponse(res.statusCode, res.headers, res.bodyBytes);
}

class DavEntry {
  final String name;
  final bool isDir;
  final String etag;
  const DavEntry(this.name, this.isDir, this.etag);
}

class DavError implements Exception {
  final String message;
  const DavError(this.message);
  @override
  String toString() => message;
}

/// A WebDAV folder: list, read, write and delete files under [base].
class WebDav {
  final String base;
  final String user, password;
  final DavSend send;

  WebDav(String base, this.user, this.password, {DavSend? send})
    : base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      send = send ?? defaultDavSend;

  Map<String, String> get _auth => {
    'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$password'))}',
  };

  String url(String path) => [
    base,
    for (final part in path.split('/'))
      if (part.isNotEmpty) Uri.encodeComponent(part),
  ].join('/');

  Future<DavResponse> _do(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Uint8List? body,
  }) async {
    final r = await send(method, url(path), {..._auth, ...headers}, body);
    if (r.status == 401 || r.status == 403) {
      throw const DavError(
        'The service refused the user name or password (use an app '
        'password where the service has them).',
      );
    }
    if (r.status == 0) {
      throw const DavError('Couldn’t reach the service (check the address).');
    }
    return r;
  }

  /// The files and folders in [path] (null: it doesn't exist).
  Future<List<DavEntry>?> list(String path) async {
    final r = await _do(
      'PROPFIND',
      '$path/',
      headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      body: utf8.encode(
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:getetag/><d:getlastmodified/><d:getcontentlength/>'
        '<d:resourcetype/></d:prop></d:propfind>',
      ),
    );
    if (r.status == 404) return null;
    if (r.status != 207 && !r.ok) {
      throw DavError('Listing $path failed (${r.status}).');
    }
    return parsePropfind(r.text, url('$path/'));
  }

  Future<Uint8List?> get(String path) async {
    final r = await _do('GET', path);
    if (r.status == 404) return null;
    if (!r.ok) throw DavError('Reading $path failed (${r.status}).');
    return r.body;
  }

  /// Writes [path]; returns its new ETag if the server says.
  Future<String?> put(String path, Uint8List bytes) async {
    final r = await _do(
      'PUT',
      path,
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    if (!r.ok) throw DavError('Saving $path failed (${r.status}).');
    return r.headers['etag'];
  }

  Future<void> delete(String path) async {
    final r = await _do('DELETE', path);
    if (!r.ok && r.status != 404) {
      throw DavError('Deleting $path failed (${r.status}).');
    }
  }

  /// Makes folder [path] (and its parents) if missing.
  Future<void> makeFolders(String path) async {
    var done = '';
    for (final part in path.split('/').where((p) => p.isNotEmpty)) {
      done = '$done/$part';
      final r = await _do('MKCOL', done);
      // 201 made; 405 already there; some servers answer 301 / 409.
      if (!r.ok && r.status != 405 && r.status != 301 && r.status != 409) {
        throw DavError('Making the folder $done failed (${r.status}).');
      }
    }
  }
}

/// The entries of a PROPFIND answer for folder [folderUrl] (the folder
/// itself left out).
List<DavEntry> parsePropfind(String xml, String folderUrl) {
  final folderPath = Uri.parse(folderUrl).path;
  String clean(String p) =>
      Uri.decodeComponent(p).replaceAll(RegExp(r'/+$'), '');
  final out = <DavEntry>[];
  final responses = RegExp(
    r'<(?:\w+:)?response\b[^>]*>(.*?)</(?:\w+:)?response>',
    dotAll: true,
  ).allMatches(xml);
  for (final m in responses) {
    final block = m[1]!;
    final href = RegExp(
      r'<(?:\w+:)?href[^>]*>(.*?)</(?:\w+:)?href>',
      dotAll: true,
    ).firstMatch(block)?[1]?.trim();
    if (href == null) continue;
    final path = Uri.tryParse(href)?.path ?? href;
    if (clean(path) == clean(folderPath)) continue;
    final name = clean(path).split('/').last;
    final isDir = RegExp(r'<(?:\w+:)?collection\s*/?>').hasMatch(block);
    final etag =
        RegExp(
          r'<(?:\w+:)?getetag[^>]*>(.*?)</(?:\w+:)?getetag>',
          dotAll: true,
        ).firstMatch(block)?[1]?.trim() ??
        // No ETag: when it changed and its size tell changes apart.
        [
          RegExp(r'<(?:\w+:)?getlastmodified[^>]*>(.*?)</')
              .firstMatch(block)?[1],
          RegExp(r'<(?:\w+:)?getcontentlength[^>]*>(.*?)</')
              .firstMatch(block)?[1],
        ].nonNulls.join('|');
    out.add(DavEntry(name, isDir, etag.replaceAll('&quot;', '"')));
  }
  return out;
}

// ---- Sync ----

/// A short fingerprint of [s] (to notice changes).
String fingerprint(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return '${h.toRadixString(36)}-${s.length}';
}

/// What was last in step with the server, per library.
class _State {
  final Map<String, (String, String)> songs; // id → (local hash, ETag)
  String metaHash, metaTag;
  final Set<String> files;

  /// The service's change marker when last in step (see [CloudSync]).
  String stamp;
  _State(
    this.songs,
    this.metaHash,
    this.metaTag,
    this.files, [
    this.stamp = '',
  ]);

  factory _State.fromJson(Map<String, dynamic> j) => _State(
    {
      for (final e in ((j['songs'] as Map?) ?? const {}).entries)
        '${e.key}': ('${(e.value as List)[0]}', '${(e.value as List)[1]}'),
    },
    j['metaHash'] as String? ?? '',
    j['metaTag'] as String? ?? '',
    {for (final f in (j['files'] as List?) ?? const []) '$f'},
    j['stamp'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'songs': {
      for (final e in songs.entries) e.key: [e.value.$1, e.value.$2],
    },
    'metaHash': metaHash,
    'metaTag': metaTag,
    'files': files.toList(),
    'stamp': stamp,
  };
}

/// Keeps the library backed up and in sync, as the settings say.
class CloudSync extends ChangeNotifier {
  final PresenterModel model;
  final DavSend? davSend;
  final KeyValueStore _store = KeyValueStore();

  /// Keeps this one's saved settings and state apart (tests run two).
  final String storePrefix;
  String get _settingsKey => '${storePrefix}cloudSync';

  final SyncSettings settings = SyncSettings();

  CloudSync(this.model, {this.davSend, this.storePrefix = ''});

  /// What happened last (for the settings page).
  String backupStatus = '', syncStatus = '';
  DateTime? lastBackup, lastSync;
  bool syncing = false, backingUp = false;
  bool syncFailed = false, backupFailed = false;

  Timer? _backupTimer, _syncTimer, _poll;
  String _lastBackedUp = '';
  bool _started = false;

  Future<void> start() async {
    if (_started || model.remoteEdit) return;
    _started = true;
    try {
      final raw = await _store.read(_settingsKey);
      if (raw != null) {
        settings.updateFrom(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    model.saves.addListener(_changed);
    // Others' changes come in now and then, and at the start.
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      if (settings.davOn) syncNow(quiet: true);
    });
    if (settings.davOn) unawaited(syncNow(quiet: true));
    if (settings.backupOn) _scheduleBackup();
  }

  @override
  void dispose() {
    model.saves.removeListener(_changed);
    _backupTimer?.cancel();
    _syncTimer?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> saveSettings() async {
    await _store.write(_settingsKey, jsonEncode(settings.toJson()));
    notifyListeners();
  }

  /// The library changed: back up and sync a little later (edits come in
  /// bursts).
  void _changed() {
    if (settings.davOn) {
      _syncTimer?.cancel();
      _syncTimer = Timer(
        const Duration(seconds: 5),
        () => syncNow(quiet: true),
      );
    }
    if (settings.backupOn) _scheduleBackup();
  }

  void _scheduleBackup() {
    _backupTimer?.cancel();
    _backupTimer = Timer(const Duration(minutes: 2), backupNow);
  }

  // ---- Folder backup ----

  /// Whether this app can save backups to a folder (it needs the local
  /// server: the Linux app, or the web app run with run.sh).
  static Future<bool> folderBackupAvailable() async =>
      await relayDetails() != null;

  /// Checks the folder (made if missing); returns (full path, error).
  Future<(String, String?)> checkFolder(String path) async {
    try {
      final j = await localServer(
        'backup/folder?path=${Uri.encodeQueryComponent(path)}',
      ) as Map;
      return ('${j['path']}', j['ok'] == true ? null : '${j['error']}');
    } catch (e) {
      return (path, 'Folder backups need the computer app ($e).');
    }
  }

  Future<void> backupNow() async {
    if (backingUp) return;
    final json = model.toJsonString();
    // Nothing new since the last one.
    if (json == _lastBackedUp && lastBackup != null) return;
    backingUp = true;
    notifyListeners();
    try {
      final zip = await libraryBackupZip(model);
      final d = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'ChordPro Presenter ${d.year}-${two(d.month)}-${two(d.day)} '
          '${two(d.hour)}${two(d.minute)}.zip';
      final q =
          'backup/save?path=${Uri.encodeQueryComponent(settings.backupFolder)}'
          '&name=${Uri.encodeQueryComponent(name)}&keep=${settings.keep}';
      final j = await postBytesToServer(q, zip) as Map;
      if (j['ok'] != true) throw StateError('${j['error']}');
      _lastBackedUp = json;
      lastBackup = d;
      backupFailed = false;
      backupStatus = 'Saved ${j['file']}';
    } catch (e) {
      backupFailed = true;
      backupStatus = 'Backup failed: $e';
    } finally {
      backingUp = false;
      notifyListeners();
    }
  }

  // ---- WebDAV sync ----

  WebDav get _dav => WebDav(
    settings.davUrl.trim(),
    settings.davUser.trim(),
    settings.davPassword,
    send: davSend,
  );

  String get _root =>
      '${settings.davFolder.trim().isEmpty ? 'ChordPro Presenter' : settings.davFolder.trim()}'
      '/${model.libraryId}';

  /// Tries the address and sign-in; null when fine, else what's wrong.
  Future<String?> testConnection() async {
    try {
      await _dav.makeFolders(settings.davFolder.trim());
      await _dav.list(settings.davFolder.trim());
      return null;
    } catch (e) {
      return '$e';
    }
  }

  String get _stateKey => '${storePrefix}cloudSyncState:${model.libraryId}';

  Future<_State> _loadState() async {
    try {
      final raw = await _store.read(_stateKey);
      if (raw != null) {
        return _State.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _State({}, '', '', {});
  }

  bool _again = false;

  /// Brings the library and the server in step ([force]: one side's
  /// version wins everywhere instead of merging).
  Future<void> syncNow({
    bool quiet = false,
    SyncForce force = SyncForce.none,
  }) async {
    if (!settings.davReady) return;
    if (syncing) {
      if (force != SyncForce.none) return; // (the button waits for it)
      _again = true; // once this one's done
      return;
    }
    syncing = true;
    if (!quiet) syncStatus = 'Syncing…';
    notifyListeners();
    try {
      final summary = await _sync(force);
      lastSync = DateTime.now();
      syncFailed = false;
      syncStatus = summary;
    } catch (e) {
      syncFailed = true;
      syncStatus = 'Sync failed: $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      await syncNow(quiet: true);
    }
  }

  static String _songJson(Song s, bool trash) =>
      jsonEncode({'song': s.toJson(), 'trash': trash});

  /// Shows how far the sync has got (in the settings window).
  void _progress(String text) {
    syncStatus = text;
    notifyListeners();
  }

  /// Runs [jobs] a few at a time (much faster than one by one).
  static Future<void> _pool(List<Future<void> Function()> jobs) async {
    var next = 0;
    Future<void> worker() async {
      while (next < jobs.length) {
        await jobs[next++]();
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  }

  Future<void> _saveState(_State state) =>
      _store.write(_stateKey, jsonEncode(state.toJson()));

  /// The library's save count when last in step (nothing saved since: no
  /// need to look for changes here).
  int? _syncedSaves;

  Future<String> _sync([SyncForce force = SyncForce.none]) async {
    final dav = _dav;
    final root = _root;
    final state = await _loadState();
    final saves = model.saves.value;
    // All quiet: nothing saved here since, and the service's marker is
    // the same: done, after reading one tiny file.
    if (force == SyncForce.none &&
        _syncedSaves == saves &&
        state.stamp.isNotEmpty) {
      final stamp = await dav.get('$root/stamp.json');
      if (stamp != null && utf8.decode(stamp) == state.stamp) {
        return 'Up to date';
      }
    }
    await dav.makeFolders('$root/songs');
    await dav.makeFolders('$root/files');
    var up = 0, down = 0, gone = 0, copies = 0;

    // ---- Tags and setlists first (small, and what people wait for) ----
    String metaOf(List<Tag> tags, List<Setlist> sets) => jsonEncode({
      'tags': [for (final t in tags) t.toJson()],
      'setlists': [for (final s in sets) s.toJson()],
    });
    final metaRemote = (await dav.list(root) ?? const <DavEntry>[])
        .where((e) => e.name == 'meta.json')
        .firstOrNull;
    switch (force) {
      case SyncForce.push: // ours changed, theirs not: ours goes up
        state.metaHash = '';
        state.metaTag = metaRemote?.etag ?? '';
      case SyncForce.pull: // theirs changed, ours not: theirs comes down
        state.metaHash = fingerprint(metaOf(model.tags, model.setlists));
        state.metaTag = '';
      case SyncForce.none:
    }
    final metaMineChanged =
        fingerprint(metaOf(model.tags, model.setlists)) != state.metaHash;
    if (metaRemote != null && metaRemote.etag != state.metaTag) {
      final bytes = await dav.get('$root/meta.json');
      if (bytes != null) {
        final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final tags = [
          for (final t in (j['tags'] as List?) ?? const [])
            Tag.fromJson(Map<String, dynamic>.from(t as Map)),
        ];
        final sets = [
          for (final s in (j['setlists'] as List?) ?? const [])
            Setlist.fromJson(Map<String, dynamic>.from(s as Map)),
        ];
        List<Tag> newTags;
        List<Setlist> newSets;
        if (metaMineChanged) {
          // Both sides have changes (or this is the first sync here): ours
          // where both have it, plus what's only there.
          final myTags = {for (final t in model.tags) t.id};
          final mySets = {for (final s in model.setlists) s.id};
          newTags = [
            ...model.tags,
            ...tags.where((t) => !myTags.contains(t.id)),
          ];
          newSets = [
            ...model.setlists,
            ...sets.where((s) => !mySets.contains(s.id)),
          ];
        } else {
          newTags = tags;
          newSets = sets;
        }
        model.applySynced(tags: newTags, setlists: newSets);
        state.metaTag = metaRemote.etag;
        state.metaHash = fingerprint(metaOf(tags, sets));
        down++;
      }
    }
    Future<void> sendMeta() async {
      final metaNow = metaOf(model.tags, model.setlists);
      if (fingerprint(metaNow) == state.metaHash && metaRemote != null) {
        return;
      }
      final tag = await dav.put('$root/meta.json', utf8.encode(metaNow));
      state.metaHash = fingerprint(metaNow);
      state.metaTag =
          tag ??
          (await dav.list(root) ?? const <DavEntry>[])
              .where((e) => e.name == 'meta.json')
              .firstOrNull
              ?.etag ??
          '';
      up++;
    }

    await sendMeta();
    await _saveState(state);

    // ---- Songs ----
    final remote = {
      for (final e in await dav.list('$root/songs') ?? const <DavEntry>[])
        if (!e.isDir && e.name.endsWith('.json'))
          e.name.substring(0, e.name.length - 5): e.etag,
    };
    final local = <String, (Song, bool, String)>{
      for (final s in model.songs) s.id: (s, false, _songJson(s, false)),
      for (final s in model.trash) s.id: (s, true, _songJson(s, true)),
    };
    switch (force) {
      case SyncForce.push: // every song here counts as changed here only
        for (final id in local.keys) {
          state.songs[id] = ('', remote[id] ?? '');
        }
      case SyncForce.pull: // every song there counts as changed there only
        for (final id in remote.keys) {
          final mine = local[id];
          state.songs[id] = (mine == null ? '' : fingerprint(mine.$3), '');
        }
      case SyncForce.none:
    }
    final upserts = <(Song, bool)>[];
    final removed = <String>[];

    Future<void> upload(String id, String json) async {
      final tag = await dav.put('$root/songs/$id.json', utf8.encode(json));
      state.songs[id] = (fingerprint(json), tag ?? '');
      up++;
    }

    Future<(Song, bool)?> download(String id) async {
      final bytes = await dav.get('$root/songs/$id.json');
      if (bytes == null) return null;
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return (
        Song.fromJson(Map<String, dynamic>.from(j['song'] as Map)),
        j['trash'] == true,
      );
    }

    Future<void> one(String id) async {
      final known = state.songs[id];
      final mine = local[id];
      final theirs = remote[id];
      final mineChanged = mine != null && fingerprint(mine.$3) != known?.$1;
      final theirsChanged = theirs != null && theirs != known?.$2;

      if (theirsChanged) {
        final got = await download(id);
        if (got == null) return;
        final (song, trash) = got;
        final json = _songJson(song, trash);
        if (mineChanged && known != null && mine.$3 != json) {
          // Both changed: the newer edit wins, the other is kept as a copy.
          final mineNewer = (mine.$1.date ?? DateTime(0)).isAfter(
            song.date ?? DateTime(0),
          );
          final loser = mineNewer ? song : mine.$1;
          upserts.add((
            Song.fromJson({
              ...loser.copy().toJson(),
              'id': newId(),
              'title': '${loser.title} (other copy)',
            }),
            false,
          ));
          copies++;
          if (mineNewer) {
            await upload(id, mine.$3);
          } else {
            upserts.add((song, trash));
            state.songs[id] = (fingerprint(json), theirs);
            down++;
          }
          return;
        }
        if (mine == null || mine.$3 != json) {
          upserts.add((song, trash));
          down++;
        }
        state.songs[id] = (fingerprint(json), theirs);
        return;
      }
      if (theirs == null && known != null) {
        // Deleted on the server (by another device).
        if (mine != null && !mineChanged) {
          removed.add(id);
          gone++;
          state.songs.remove(id);
          return;
        }
        if (mine == null) {
          state.songs.remove(id);
          return;
        }
        // Changed here meanwhile: the edit wins over the deletion.
      }
      if (mine == null && theirs != null && known != null) {
        // Deleted here for good: off the server too.
        await dav.delete('$root/songs/$id.json');
        state.songs.remove(id);
        gone++;
        return;
      }
      if (mine != null && (mineChanged || theirs == null)) {
        await upload(id, mine.$3);
      }
    }

    // Only the songs with something to do (most have nothing).
    bool needsWork(String id) {
      final known = state.songs[id];
      final mine = local[id];
      final theirs = remote[id];
      if (theirs != null && theirs != known?.$2) return true; // changed there
      if (theirs == null && known != null) return true; // deleted there
      if (mine == null) return known != null; // deleted here
      return fingerprint(mine.$3) != known?.$1 || theirs == null;
    }

    final ids = [
      for (final id in {...remote.keys, ...local.keys, ...state.songs.keys})
        if (needsWork(id)) id,
    ];
    if (ids.isNotEmpty) _progress('Songs: 0 of ${ids.length}');
    var done = 0;
    final jobs = [
      for (final id in ids)
        () async {
          await one(id);
          done++;
          if (done % 10 == 0 || done == ids.length) {
            _progress('Songs: $done of ${ids.length}');
          }
          // Kept as it goes, so a long first sync picks up where it
          // stopped if the app closes.
          if (done % 25 == 0) await _saveState(state);
        },
    ];
    await _pool(jobs);

    if (upserts.isNotEmpty || removed.isNotEmpty) {
      model.applySynced(upserts: upserts, removed: removed);
    }
    // Copies made for edits on two devices, setlists that changed with
    // them: up now.
    await sendMeta();
    await _saveState(state);

    // ---- PDFs and pictures (they never change once added) ----
    final onServer = {
      for (final e in await dav.list('$root/files') ?? const <DavEntry>[])
        if (!e.isDir) e.name,
    };
    final pdfs = libraryPdfs(model);
    var fileDone = 0;
    final fileJobs = <Future<void> Function()>[];
    for (final p in pdfs) {
      // Known to be on the service already: nothing to read or send.
      if (onServer.contains(p.id) && state.files.contains(p.id)) continue;
      fileJobs.add(() async {
        if (onServer.contains(p.id)) {
          // There: fetched if missing here (it came with others' songs).
          final have = await PdfStore.bytes(p.id);
          if (have == null || have.isEmpty) {
            final bytes = await dav.get('$root/files/${p.id}');
            if (bytes != null) {
              await PdfStore.put(p.id, bytes);
              down++;
            }
          }
          state.files.add(p.id);
        } else {
          final bytes = await PdfStore.bytes(p.id);
          if (bytes != null && bytes.isNotEmpty) {
            await dav.put('$root/files/${p.id}', bytes);
            state.files.add(p.id);
            up++;
          }
        }
        fileDone++;
        if (fileDone % 5 == 0 || fileDone == fileJobs.length) {
          _progress('PDFs and pictures: $fileDone of ${fileJobs.length}');
        }
      });
    }
    await _pool(fileJobs);

    // Songs saved without an ETag in the answer: read them from a listing,
    // so the next round doesn't take them for others' changes.
    if (state.songs.values.any((v) => v.$2.isEmpty)) {
      final tags = {
        for (final e in await dav.list('$root/songs') ?? const <DavEntry>[])
          if (e.name.endsWith('.json'))
            e.name.substring(0, e.name.length - 5): e.etag,
      };
      for (final id in [...state.songs.keys]) {
        final v = state.songs[id]!;
        if (v.$2.isEmpty && tags[id] != null) {
          state.songs[id] = (v.$1, tags[id]!);
        }
      }
    }

    // Something changed on the service: a new marker, so the other
    // devices' next quick check notices.
    final stampNow = await dav.get('$root/stamp.json');
    if (up > 0 || gone > 0 || stampNow == null) {
      final fresh = newId();
      await dav.put('$root/stamp.json', utf8.encode(fresh));
      state.stamp = fresh;
    } else {
      state.stamp = utf8.decode(stampNow);
    }
    await _saveState(state);
    _syncedSaves = saves;
    final parts = [
      if (up > 0) '$up sent',
      if (down > 0) '$down received',
      if (gone > 0) '$gone removed',
      if (copies > 0)
        '$copies edited on two devices (kept both: “(other copy)”)',
    ];
    return parts.isEmpty ? 'Up to date' : parts.join(', ');
  }
}
