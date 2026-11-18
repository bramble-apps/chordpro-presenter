import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/openchords.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/openchords_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An OpenChords server in memory, as the API describes it: a login
/// handing out tokens, folders saved whole, owners, read-only folders.
class FakeServer {
  final folders = <String, Map<String, dynamic>>{};
  final owners = <String, String>{};
  var logins = 0;
  var token = 'token-1';

  late final client = MockClient((r) async {
    final path = r.url.path.replaceFirst('/api/v2', '');
    if (path == '/login') {
      final b = jsonDecode(r.body) as Map;
      if (b['username'] != 'app' || b['password'] != sha256Hex('secret')) {
        return http.Response('{"error":"Invalid credentials"}', 401);
      }
      logins++;
      return http.Response(jsonEncode({'token': token}), 200);
    }
    if (r.headers['Authorization'] != 'Bearer $token') {
      return http.Response('Invalid token', 401);
    }
    final m = RegExp(r'^/folder/([0-9A-F-]+)$').firstMatch(path);
    if (m == null) return http.Response('', 404);
    final id = m.group(1)!;
    final user = r.url.queryParameters['userID'] ?? '';
    if (r.method == 'GET') {
      final f = folders[id];
      if (f == null) return http.Response('', 404);
      return http.Response(
        jsonEncode({...f, 'isOwner': owners[id] == user}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    final f = folders[id];
    if (f != null && f['readonly'] == true && owners[id] != user) {
      return http.Response('{"error":"read-only"}', 403);
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body.containsKey('songs'), isTrue);
    expect(body.containsKey('setlists'), isTrue);
    expect(body['title'], isA<String>());
    folders[id] = body;
    owners.putIfAbsent(id, () => user);
    return http.Response('', 200);
  });

  OpenChordsClient api() =>
      OpenChordsClient(client: client, user: 'app', password: 'secret');
}

Future<PresenterModel> device(String userId) async {
  final m = PresenterModel();
  await m.load();
  m.openChordsUserId = userId;
  return m;
}

void main() {
  setUp(() {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
  });

  test('SHA-256 (the login sends the password\'s)', () {
    expect(
      sha256Hex(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      sha256Hex('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    // Longer than one block, and not ASCII.
    expect(
      sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
    expect(
      sha256Hex('Grâce étonnante ♪'),
      'b9693d8b3da264d52172649b0f19cdb3a106d4f00d29829323f607e2c07630e9',
    );
  });

  test('folder id from a link or a bare id', () {
    const id = '93E5D3EF-8B1E-4B35-851E-16A0859315E3';
    expect(openChordsFolderId('https://openchords.net/?fld=$id'), id);
    expect(
      openChordsFolderId(
        'Join: https://openchords.net/?x=1&fld=${id.toLowerCase()} thanks',
      ),
      id,
    );
    expect(openChordsFolderId(id.toLowerCase()), id);
    expect(openChordsFolderId('https://openchords.net/'), isNull);
    expect(openChordsLink(id), 'https://openchords.net/?fld=$id');
  });

  test('song to OpenChords and back', () {
    final song = Song(
      title: 'Morning Light',
      raw: '{title: Morning Light}\nVerse 1:\n[G]Light\n\nChorus:\n[C]Rise',
      key: const MusicKey(7, false),
      transpose: 2,
      capo: 3,
      tempo: '72',
      timeSignature: '6/8',
      duration: '4:28',
      artist: 'Someone',
      copyright: '2024 Someone',
      ccli: '1234567',
      notes: 'Slow intro',
      audioUrl: 'https://youtu.be/NO5b8Ry-VIM',
      structure: const [
        StructureItem.section('Verse 1'),
        StructureItem.keyChange(2),
        StructureItem.section('Chorus'),
      ],
      date: DateTime.utc(2026, 11, 1, 12),
      extra: {
        'openchords': {
          'futureField': 7,
          'metadata': [
            {'key': 'spotifyId', 'value': 'abc'},
          ],
        },
      },
    );
    final j = openChordsSong(song);
    expect(j['id'], song.id.toUpperCase());
    expect(j['rawData'], song.raw);
    expect(j['key'], 'G');
    expect(j['keyIsMinor'], false);
    expect(j['transpose'], 'A');
    expect(j['tempo'], 72);
    expect(j['timeSignature'], '6/8');
    expect(j['duration'], '4:28');
    expect(j['ccli'], '1234567');
    expect(j['lastUpdated'], '2026-11-01T12:00:00.000Z');
    expect(j['structure'], [
      {'sectionName': 'Verse 1'},
      {'sectionName': 'Chorus', 'transposeSteps': 2},
    ]);
    expect(j['metadata'], [
      {'key': 'youtubeUrl', 'value': 'https://youtu.be/NO5b8Ry-VIM'},
      {'key': 'spotifyId', 'value': 'abc'},
    ]);
    // Fields this app doesn't know go back as they came.
    expect(j['futureField'], 7);

    final back = songFromOpenChords(jsonDecode(jsonEncode(j)));
    expect(back.id, song.id.toUpperCase());
    expect(back.title, 'Morning Light');
    expect((back.key!.root, back.key!.minor), (7, false));
    expect(back.transpose, 2);
    expect(back.tempo, '72');
    expect(back.timeSignature, '6/8');
    expect(back.artist, 'Someone');
    expect(back.audioUrl, 'https://youtu.be/NO5b8Ry-VIM');
    expect(back.structure.map((i) => i.toJson()).toList(), [
      {'type': 'section', 'name': 'Verse 1'},
      {'type': 'modulation', 'semitones': 2},
      {'type': 'section', 'name': 'Chorus'},
    ]);
    expect(back.date, DateTime.utc(2026, 11, 1, 12));
    expect(openChordsSong(back)['futureField'], 7);
  });

  test('a minor key and a song from another app', () {
    final s = songFromOpenChords({
      'id': 'AAAAAAAA-1111-4111-8111-000000000001',
      'title': 'From JustChords',
      'rawData': '[Am]Hello',
      'key': 'A',
      'keyIsMinor': true,
      'tempo': 90,
      'tags': ['TAG-1'],
    }, tagOf: (id) => id == 'TAG-1' ? 'local-tag' : null);
    expect((s.key!.root, s.key!.minor), (9, true));
    expect(s.tempo, '90');
    expect(s.tags, ['local-tag']);
    expect(openChordsSong(s)['key'], 'A');
    expect(openChordsSong(s)['keyIsMinor'], true);
  });

  test('setlist to OpenChords and back', () {
    final a = Song(
      title: 'A',
      raw: '{key: G}\n[G]a',
      key: const MusicKey(7, false),
    );
    final b = Song(title: 'B', raw: '[D]b');
    final set = Setlist(
      name: 'Sunday',
      setSpecific: true,
      entries: [
        SetEntry(songId: a.id, transpose: 2),
        SetEntry(type: EntryType.divider, title: 'Offering'),
        SetEntry(type: EntryType.label, title: 'Prayer', color: '#ff0000'),
        SetEntry(songId: b.id),
      ],
    );
    final byId = {a.id: a, b.id: b};
    final j = openChordsSetlist(set, byId);
    final items = j['items'] as List;
    expect(items.map((i) => i['type']), ['song', 'divider', 'slide', 'song']);
    expect(items[0]['songItem'], {
      'songId': a.id.toUpperCase(),
      'transpose': 'A',
    });
    expect(items[1]['title'], 'Offering');

    final back = setlistFromOpenChords(jsonDecode(jsonEncode(j)), {
      a.id.toUpperCase(): a,
      b.id.toUpperCase(): b,
    });
    expect(back.name, 'Sunday');
    expect(back.setSpecific, isTrue);
    expect(back.entries.map((e) => e.type), [
      EntryType.song,
      EntryType.divider,
      EntryType.label,
      EntryType.song,
    ]);
    expect(back.entries[0].transpose, 2);
    expect(back.entries[2].title, 'Prayer');
    expect(back.entries[2].color, '#ff0000');
  });

  test('two devices share a setlist and sync both ways', () async {
    final server = FakeServer();
    final alice = await device('A1111111-1111-4111-8111-111111111111');
    final song1 = Song(title: 'One', raw: '{key: C}\n[C]one');
    final song2 = Song(title: 'Two', raw: '[G]two');
    alice
      ..addOrUpdate(song1)
      ..addOrUpdate(song2);
    final set = alice.createSetlist('Sunday');
    alice.addSongsToSetlist(set, [song1.id, song2.id]);

    final link = await shareSetlistOnOpenChords(
      alice,
      set,
      client: server.api(),
    );
    expect(server.folders[link.folderId]!['type'], 'setlist');
    expect((server.folders[link.folderId]!['songs'] as List).length, 2);
    expect(alice.openChordsLinkFor(set.id), same(link));

    // Bob opens the link.
    final bob = await device('B2222222-2222-4222-8222-222222222222');
    final folder = await server.api().getFolder(
      link.folderId,
      bob.openChordsUserId,
    );
    expect(folder!['isOwner'], false);
    final bobLink = bob.importOpenChords(link.folderId, folder, isOwner: false);
    final bobSet = bob.setlistById(bobLink.localId)!;
    expect(bobSet.name, 'Sunday');
    expect(bobSet.entries.length, 2);
    expect(bob.songs.map((s) => s.title), containsAll(['One', 'Two']));

    // A sync with nothing changed sends nothing.
    final quiet = await syncOpenChords(bob, bobLink, client: server.api());
    expect(quiet.upload, isNull);
    expect(quiet.summary, 'Up to date');

    // Bob edits a song: it reaches Alice.
    final bobOne = bob.songs.firstWhere((s) => s.title == 'One').copy()
      ..raw = '{key: C}\n[C]one, edited by Bob';
    bob.addOrUpdate(bobOne);
    bob.songById(bobOne.id)!.date = DateTime.now().add(
      const Duration(seconds: 5),
    );
    final sent = await syncOpenChords(bob, bobLink, client: server.api());
    expect(sent.pushedSongs, 1);
    final got = await syncOpenChords(alice, link, client: server.api());
    expect(got.pulled.length, 1);
    expect(alice.songById(song1.id)!.raw, contains('edited by Bob'));
    // (Alice's own copy keeps its id.)
    expect(alice.songs.where((s) => s.title == 'One').length, 1);

    // Alice reorders the setlist and adds a divider: Bob gets it.
    final aSet = alice.setlistById(set.id)!;
    aSet.entries.insert(0, aSet.entries.removeAt(1));
    aSet.entries.add(SetEntry(type: EntryType.divider, title: 'End'));
    final pushed = await syncOpenChords(alice, link, client: server.api());
    expect(pushed.pushedSetlist, isTrue);
    final pulled = await syncOpenChords(bob, bobLink, client: server.api());
    expect(pulled.setlist, isNotNull);
    final names = [
      for (final e in bob.setlistById(bobLink.localId)!.entries)
        e.type == EntryType.song ? bob.songById(e.songId)!.title : e.title,
    ];
    expect(names, ['Two', 'One', 'End']);
    // Bob's setlist keeps its own id.
    expect(bob.setlistById(bobLink.localId), same(bobSet));
  });

  test('a read-only folder: only its owner sends changes', () async {
    final server = FakeServer();
    final alice = await device('A1111111-1111-4111-8111-111111111111');
    final song = Song(title: 'One', raw: '[C]one');
    alice.addOrUpdate(song);
    final set = alice.createSetlist('Locked');
    alice.addSongsToSetlist(set, [song.id]);
    final link = await shareSetlistOnOpenChords(
      alice,
      set,
      readonly: true,
      client: server.api(),
    );
    expect(server.folders[link.folderId]!['readonly'], true);

    final bob = await device('B2222222-2222-4222-8222-222222222222');
    final folder = await server.api().getFolder(
      link.folderId,
      bob.openChordsUserId,
    );
    final bobLink = bob.importOpenChords(
      link.folderId,
      folder!,
      isOwner: false,
    );
    expect(bobLink.canPush, isFalse);

    // Bob's edit stays his; the server's copy is untouched.
    final mine = bob.songs.firstWhere((s) => s.title == 'One').copy()
      ..raw = '[C]changed';
    bob.addOrUpdate(mine);
    bob.songById(mine.id)!.date = DateTime.now().add(
      const Duration(seconds: 5),
    );
    final r = await syncOpenChords(bob, bobLink, client: server.api());
    expect(r.upload, isNull);
    expect(
      (server.folders[link.folderId]!['songs'] as List).single['rawData'],
      '[C]one',
    );

    // The owner unlocks it.
    await syncOpenChords(alice, link, client: server.api(), readonly: false);
    expect(server.folders[link.folderId]!['readonly'], false);
  });

  test('a song folder from another app becomes a tag', () async {
    final server = FakeServer();
    const id = 'F0000000-0000-4000-8000-000000000001';
    server.folders[id] = {
      'title': 'Band',
      'type': 'folder',
      'songs': [
        {
          'id': 'S0000000-0000-4000-8000-000000000001',
          'title': 'First',
          'rawData': '[G]first',
          'lastUpdated': '2026-11-01T10:00:00Z',
          'tags': ['T0000000-0000-4000-8000-000000000001'],
        },
        {
          'id': 'S0000000-0000-4000-8000-000000000002',
          'title': 'Second',
          'rawData': '[D]second',
          'lastUpdated': '2026-11-01T10:00:00Z',
        },
      ],
      'setlists': [],
      'tags': [
        {'id': 'T0000000-0000-4000-8000-000000000001', 'title': 'Fast'},
      ],
    };
    server.owners[id] = 'SOMEONE-ELSE';
    final m = await device('C3333333-3333-4333-8333-333333333333');
    final folder = await server.api().getFolder(id, m.openChordsUserId);
    final link = m.importOpenChords(id, folder!, isOwner: false);
    expect(link.kind, OpenChordsKind.folder);
    final band = m.tagById(link.localId)!;
    expect(band.name, 'Band');
    expect(m.songs.where((s) => s.tags.contains(band.id)).length, 2);
    final fast = m.tags.firstWhere((t) => t.name == 'Fast');
    expect(
      m.songs.firstWhere((s) => s.title == 'First').tags,
      contains(fast.id),
    );

    // The other app takes "Second" out of the folder: it leaves the tag
    // here (the song stays in the library).
    (server.folders[id]!['songs'] as List).removeLast();
    final r = await syncOpenChords(m, link, client: server.api());
    expect(r.removedHere.length, 1);
    final second = m.songs.firstWhere((s) => s.title == 'Second');
    expect(second.tags, isNot(contains(band.id)));

    // A song tagged here goes to the folder.
    m.addOrUpdate(Song(title: 'Third', raw: '[A]third', tags: [band.id]));
    final up = await syncOpenChords(m, link, client: server.api());
    expect(up.pushedSongs, 1);
    expect(
      (server.folders[id]!['songs'] as List).map((s) => s['title']),
      containsAll(['First', 'Third']),
    );
    // The folder keeps its own tags.
    expect((server.folders[id]!['tags'] as List).single['title'], 'Fast');
  });

  test('logs in again when the token runs out', () async {
    final server = FakeServer();
    final api = server.api();
    const id = 'F0000000-0000-4000-8000-000000000009';
    expect(await api.getFolder(id, ''), isNull);
    expect(server.logins, 1);
    server.token = 'token-2';
    expect(await api.getFolder(id, ''), isNull);
    expect(server.logins, 2);
    final bad = OpenChordsClient(
      client: server.client,
      user: 'x',
      password: 'y',
    );
    expect(() => bad.getFolder(id, ''), throwsA(isA<OpenChordsException>()));
  });

  group('dialogs', () {
    late FakeServer server;
    setUp(() {
      server = FakeServer();
      openChordsTestClient = server.api();
    });
    tearDown(() => openChordsTestClient = null);

    Widget app(void Function(BuildContext) open) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context),
            child: const Text('go'),
          ),
        ),
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('share a setlist, then sync it', (tester) async {
      final m = await tester.runAsync(
        () => device('A1111111-1111-4111-8111-111111111111'),
      );
      final song = Song(title: 'One', raw: '[C]one');
      m!.addOrUpdate(song);
      final set = m.createSetlist('Sunday');
      m.addSongsToSetlist(set, [song.id]);

      await tester.pumpWidget(app((c) => showOpenChordsShare(c, m, set)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Share with OpenChords'), findsOneWidget);
      await tester.tap(find.text('Share'));
      await settle(tester);

      final link = m.openChordsLinkFor(set.id)!;
      expect(server.folders.keys, [link.folderId]);
      expect(find.text('Shared on OpenChords'), findsOneWidget);
      expect(find.text(link.link), findsOneWidget);

      // The owner locks it.
      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(server.folders[link.folderId]!['readonly'], isTrue);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('open a link someone sent', (tester) async {
      const id = 'F0000000-0000-4000-8000-000000000002';
      server.folders[id] = {
        'title': 'Youth band',
        'type': 'setlist',
        'songs': [
          {
            'id': 'S0000000-0000-4000-8000-000000000001',
            'title': 'Morning Light',
            'rawData': '[G]light',
            'lastUpdated': '2026-11-10T10:00:00Z',
          },
        ],
        'setlists': [
          {
            'id': 'L0000000-0000-4000-8000-000000000001',
            'title': 'Youth band',
            'items': [
              {
                'id': 'I0000000-0000-4000-8000-000000000001',
                'type': 'song',
                'songItem': {'songId': 'S0000000-0000-4000-8000-000000000001'},
              },
            ],
          },
        ],
      };
      final m = await tester.runAsync(
        () => device('B2222222-2222-4222-8222-222222222222'),
      );
      Setlist? made;
      await tester.pumpWidget(
        app((c) async => made = await showOpenChordsOpen(c, m!)),
      );
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField),
        'https://openchords.net/?fld=$id',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('Youth band'), findsOneWidget);
      expect(find.text('Setlist · 1 song'), findsOneWidget);
      await tester.tap(find.text('Add to library'));
      await settle(tester);
      expect(made?.name, 'Youth band');
      expect(m!.songById(made!.entries.single.songId)!.title, 'Morning Light');
    });
  });
}
