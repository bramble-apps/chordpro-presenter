import 'dart:convert';
import 'dart:typed_data';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/cloud_sync.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A WebDAV server in memory: files and folders, ETags that change on
/// every write, PROPFIND answers like real servers give.
class FakeDav {
  final files = <String, Uint8List>{};
  final folders = <String>{''};
  final etags = <String, String>{};
  var _n = 0;
  var user = 'me', password = 'secret';

  /// Every request, as "METHOD path" (to count them).
  final log = <String>[];

  String _path(String url) =>
      Uri.decodeComponent(Uri.parse(url).path.replaceFirst('/dav', ''))
          .replaceAll(RegExp(r'/+$'), '');

  Future<DavResponse> send(
    String method,
    String url,
    Map<String, String> headers,
    Uint8List? body,
  ) async {
    final auth = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
    if (headers['Authorization'] != auth) {
      return DavResponse(401, const {}, Uint8List(0));
    }
    final p = _path(url);
    log.add('$method $p');
    DavResponse r(int s, [List<int> b = const [], Map<String, String>? h]) =>
        DavResponse(s, h ?? const {}, Uint8List.fromList(b));
    switch (method) {
      case 'MKCOL':
        if (folders.contains(p)) return r(405);
        folders.add(p);
        return r(201);
      case 'PUT':
        files[p] = body ?? Uint8List(0);
        final tag = '"${++_n}"';
        etags[p] = tag;
        return r(201, const [], {'etag': tag});
      case 'GET':
        final f = files[p];
        return f == null ? r(404) : r(200, f);
      case 'DELETE':
        return files.remove(p) == null ? r(404) : r(204);
      case 'PROPFIND':
        if (!folders.contains(p)) return r(404);
        final b = StringBuffer(
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
          '<d:response><d:href>/dav$p/</d:href><d:propstat><d:prop>'
          '<d:resourcetype><d:collection/></d:resourcetype></d:prop>'
          '</d:propstat></d:response>',
        );
        for (final f in files.keys.where((f) => _parent(f) == p)) {
          b.write(
            '<d:response><d:href>/dav${Uri.encodeFull(f)}</d:href><d:propstat>'
            '<d:prop><d:getetag>${etags[f]}</d:getetag><d:resourcetype/>'
            '</d:prop></d:propstat></d:response>',
          );
        }
        for (final d in folders.where((d) => d.isNotEmpty && _parent(d) == p)) {
          b.write(
            '<d:response><d:href>/dav$d/</d:href><d:propstat><d:prop>'
            '<d:resourcetype><d:collection/></d:resourcetype></d:prop>'
            '</d:propstat></d:response>',
          );
        }
        b.write('</d:multistatus>');
        return r(207, utf8.encode(b.toString()));
    }
    return r(405);
  }

  String _parent(String p) => p.substring(0, p.lastIndexOf('/'));
}

Future<(PresenterModel, CloudSync)> _device(FakeDav server, String name) async {
  final m = PresenterModel();
  await m.load();
  final sync = CloudSync(m, davSend: server.send, storePrefix: '$name:');
  sync.settings
    ..davOn = true
    ..davUrl = 'https://example.test/dav'
    ..davUser = 'me'
    ..davPassword = 'secret';
  return (m, sync);
}

void main() {
  setUp(() {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
  });

  test(
    'two devices: new songs, edits, deletions and setlists go across',
    () async {
      final server = FakeDav();
      final (a, syncA) = await _device(server, 'a');
      a.addOrUpdate(Song(title: 'Grace', raw: '[G]Amazing grace'));
      await syncA.syncNow();
      expect(syncA.syncFailed, isFalse, reason: syncA.syncStatus);
      expect(server.files.keys.where((f) => f.contains('/songs/')), isNotEmpty);

      final (b, syncB) = await _device(server, 'b');
      await syncB.syncNow();
      expect(b.songs.map((s) => s.title), contains('Grace'));

      // An edit on B reaches A.
      final grace = b.songs.firstWhere((s) => s.title == 'Grace');
      b.addOrUpdate(grace.copy()..raw = '[G]Amazing grace, how sweet');
      await syncB.syncNow();
      await syncA.syncNow();
      expect(
        a.songs.firstWhere((s) => s.id == grace.id).raw,
        '[G]Amazing grace, how sweet',
      );

      // A setlist made on A reaches B.
      a.setlists.add(Setlist(name: 'Sunday'));
      a.addSongsToSetlist(a.setlists.last, [grace.id]);
      await syncA.syncNow();
      await syncB.syncNow();
      expect(b.setlists.map((s) => s.name), contains('Sunday'));

      // To the Trash on A: in B's Trash too; gone for good: gone on B.
      a.deleteSong(grace.id);
      await syncA.syncNow();
      await syncB.syncNow();
      expect(b.trash.map((s) => s.id), contains(grace.id));
      a.deleteForever(a.trash.firstWhere((s) => s.id == grace.id));
      await syncA.syncNow();
      await syncB.syncNow();
      expect(
        [...b.songs, ...b.trash].map((s) => s.id),
        isNot(contains(grace.id)),
      );
      expect(server.files.keys, isNot(contains(contains(grace.id))));

      // Nothing changed: nothing sent.
      await syncA.syncNow();
      expect(syncA.syncStatus, 'Up to date');
    },
  );

  test('the same song edited on both: newer wins, the other is kept', () async {
    final server = FakeDav();
    final (a, syncA) = await _device(server, 'a');
    a.addOrUpdate(Song(title: 'Hymn', raw: 'one'));
    await syncA.syncNow();
    final (b, syncB) = await _device(server, 'b');
    await syncB.syncNow();
    final id = a.songs.firstWhere((s) => s.title == 'Hymn').id;

    a.addOrUpdate(a.songById(id)!.copy()..raw = 'from A');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    b.addOrUpdate(b.songById(id)!.copy()..raw = 'from B'); // newer
    await syncA.syncNow();
    await syncB.syncNow();
    await syncA.syncNow();
    expect(b.songById(id)!.raw, 'from B');
    expect(a.songById(id)!.raw, 'from B');
    expect(
      b.songs.where((s) => s.title == 'Hymn (other copy)').single.raw,
      'from A',
    );
    expect(syncB.syncStatus, contains('other copy'));
  });

  test('first sync on a second device keeps both devices\' setlists', () async {
    final server = FakeDav();
    final (a, syncA) = await _device(server, 'a');
    a.createSetlist('Made on the computer');
    await syncA.syncNow();
    // A device that already had its own setlist before syncing.
    final b = PresenterModel()
      ..setlists.add(Setlist(name: 'Made on the phone'));
    final syncB = CloudSync(b, davSend: server.send, storePrefix: 'b:');
    syncB.settings
      ..davOn = true
      ..davUrl = 'https://example.test/dav'
      ..davUser = 'me'
      ..davPassword = 'secret';
    await syncB.syncNow();
    expect(b.setlists.map((s) => s.name).toSet(), {
      'Made on the computer',
      'Made on the phone',
    });
    await syncA.syncNow();
    expect(a.setlists.map((s) => s.name), contains('Made on the phone'));
    // A new one on the phone shows up on the computer next sync.
    b.createSetlist('Test setlist');
    await syncB.syncNow();
    await syncA.syncNow();
    expect(a.setlists.map((s) => s.name), contains('Test setlist'));
  });

  test(
    'forcing: re-upload sends ours over, re-download takes theirs',
    () async {
      final server = FakeDav();
      final (a, syncA) = await _device(server, 'a');
      a.addOrUpdate(Song(title: 'Psalm', raw: 'original'));
      a.createSetlist('Sunday');
      await syncA.syncNow();
      final (b, syncB) = await _device(server, 'b');
      await syncB.syncNow();
      final id = a.songs.firstWhere((s) => s.title == 'Psalm').id;

      // Both edit; A re-uploads: A's version is everywhere.
      a.addOrUpdate(a.songById(id)!.copy()..raw = 'A version');
      b.addOrUpdate(b.songById(id)!.copy()..raw = 'B version');
      await syncA.syncNow(force: SyncForce.push);
      await syncB.syncNow(force: SyncForce.pull);
      expect(b.songById(id)!.raw, 'A version');
      expect(b.songs.where((s) => s.title.contains('other copy')), isEmpty);

      // B renames the setlist; A re-downloads: A has B's setlist.
      b.updateSetlist(
        b.setlists.firstWhere((s) => s.name == 'Sunday'),
        name: 'Sunday AM',
      );
      await syncB.syncNow();
      a.updateSetlist(
        a.setlists.firstWhere((s) => s.name == 'Sunday'),
        name: 'Local name',
      );
      await syncA.syncNow(force: SyncForce.pull);
      expect(a.setlists.map((s) => s.name), contains('Sunday AM'));
      expect(a.setlists.map((s) => s.name), isNot(contains('Local name')));
    },
  );

  test('when nothing changed, a check is one tiny request', () async {
    final server = FakeDav();
    final (a, syncA) = await _device(server, 'a');
    for (var i = 0; i < 30; i++) {
      a.addOrUpdate(Song(title: 'Song $i', raw: 'words $i'));
    }
    await syncA.syncNow();
    final (b, syncB) = await _device(server, 'b');
    await syncB.syncNow();

    server.log.clear();
    await syncA.syncNow();
    expect(syncA.syncStatus, 'Up to date');
    expect(server.log, hasLength(1)); // GET stamp.json
    expect(server.log.single, endsWith('/stamp.json'));

    // A change on B: A's next check notices and fetches just that song.
    final s3 = b.songs.firstWhere((s) => s.title == 'Song 3');
    b.addOrUpdate(s3.copy()..raw = 'changed');
    await syncB.syncNow();
    server.log.clear();
    await syncA.syncNow();
    expect(a.songById(s3.id)!.raw, 'changed');
    expect(
      server.log.where((l) => l.startsWith('GET') && l.contains('/songs/')),
      hasLength(1),
    );
  });

  test('a wrong password says so', () async {
    final server = FakeDav();
    final (_, sync) = await _device(server, 'a');
    sync.settings.davPassword = 'nope';
    expect(await sync.testConnection(), contains('refused'));
    await sync.syncNow();
    expect(sync.syncFailed, isTrue);
  });

  test('reads PROPFIND answers from other servers', () {
    const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
 <D:response><D:href>/dav/Koofr/ChordPro%20Presenter/</D:href>
  <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
 <D:response><D:href>/dav/Koofr/ChordPro%20Presenter/a%20b.json</D:href>
  <D:propstat><D:prop><D:getetag>&quot;abc&quot;</D:getetag><D:resourcetype/></D:prop></D:propstat></D:response>
 <D:response><D:href>/dav/Koofr/ChordPro%20Presenter/files/</D:href>
  <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
</D:multistatus>''';
    final entries = parsePropfind(
      xml,
      'https://app.koofr.net/dav/Koofr/ChordPro%20Presenter/',
    );
    expect(entries.map((e) => (e.name, e.isDir, e.etag)), [
      ('a b.json', false, '"abc"'),
      ('files', true, ''),
    ]);
  });
}
