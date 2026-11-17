import 'dart:async';
import 'dart:convert';

import 'package:bilingual_projector/band_sync/band_sync.dart';
import 'package:bilingual_projector/band_sync/protocol.dart';
import 'package:bilingual_projector/band_sync/transport.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frames: 4-byte big-endian length + JSON, split across chunks', () {
    final f = ptFrame({'type': 'ping'});
    expect(f.sublist(0, 4), [0, 0, 0, 15]);
    expect(utf8.decode(f.sublist(4)), '{"type":"ping"}');
    final d = PtDecoder();
    final two = [
      ...f,
      ...ptFrame({'type': 'pong'}),
    ];
    expect(d.add(two.sublist(0, 7)), isEmpty);
    expect(d.add(two.sublist(7)).map((m) => m['type']), ['ping', 'pong']);
  });

  test('sections: a linked verse + translation is two JustChords sections', () {
    const raw = 'Verse 1:\nA\n\nVerse 1 (FR):\nB\n\nChorus:\nC\n\nmore chorus';
    final applied = ChordPro.applyStructure(raw, const [
      StructureItem.section('Verse 1', linked: true),
      StructureItem.section('Verse 1 (FR)'),
      StructureItem.section('Chorus'),
    ]);
    final parts = ChordPro.parts(applied);
    final s = jcSectionsOfParts(parts);
    expect(s.first, [0, 1]);
    expect(s.expand((e) => e).toSet(), {0, 1, 2});
    expect(partOfSection(s, 1), 0);
    expect(partOfSection(s, 2), s.indexWhere((p) => p.contains(2)));
    expect(jcSectionCount(s), 3);
  });

  test('leader and follower talk over a socket', () async {
    final a = Song(title: 'A', raw: 'Verse 1:\nx', key: MusicKey.parse('G'));
    final b = Song(title: 'B', raw: 'Verse 1:\ny');
    final set = Setlist(
      name: 'Set',
      entries: [
        SetEntry(songId: a.id),
        SetEntry(type: EntryType.divider, title: '—'),
        SetEntry(songId: b.id),
      ],
    );
    final songs = {a.id: a, b.id: b};
    final leader = createBandSyncTransport();
    await leader.lead('Leader', ptSetlistData(set, (id) => songs[id]));
    final port = (leader as dynamic).port as int;
    final follower = createBandSyncTransport();
    final got = <Map<String, dynamic>>[];
    follower.messages.listen(got.add);
    final joined = leader.followers.firstWhere((f) => f.contains('Phone'));
    await follower.join('127.0.0.1', port, 'Phone');
    await joined;
    leader.send(ptCommand('gotoPlaylistIndexAndSection', [2], b.id));
    final repeat = ptCommand('nextSongSection', const [], 'SAME');
    leader.send(repeat);
    leader.send(repeat); // the same id twice: dropped
    leader.send({'type': 'scrollTo', 'scrollOffset': 0.5});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final lost = follower.connected.firstWhere((c) => !c);
    await leader.stopLeading();
    await lost.timeout(const Duration(seconds: 2));

    expect(got.first['type'], 'setlistData');
    final data = got.first['setlistData'] as Map;
    expect(data['title'], 'Set');
    expect(data['shared'], isTrue);
    expect((data['songs'] as List).length, 2);
    // Dividers count in the setlist index.
    expect((data['arrangement'] as List)[2]['id'], b.id.toUpperCase());
    final cmds = got.where((m) => m['type'] == 'command').toList();
    expect(cmds.map(ptCommandName), [
      'gotoPlaylistIndexAndSection',
      'nextSongSection',
    ]);
    expect(ptCommandData(cmds.first), [2]);
    expect(got.any((m) => m['scrollOffset'] == 0.5), isTrue);
    expect(got.last['type'], 'kick');
  });

  group('controller', () {
    late PresenterModel model;
    late _FakeTransport net;
    late BandSync band;

    // A bilingual song: Verse 1 linked to its French translation.
    final bilingual = Song(
      title: 'Bilingual',
      raw:
          'Verse 1:\n[G]Light\n\nVerse 1 (FR):\n[G]Lumière\n\n'
          'Chorus:\n[C]Sing',
      key: MusicKey.parse('G'),
      structure: const [
        StructureItem.section('Verse 1', linked: true),
        StructureItem.section('Verse 1 (FR)'),
        StructureItem.section('Chorus'),
      ],
    );
    final other = Song(title: 'Other', raw: 'Verse 1:\n[D]x');

    setUp(() async {
      KeyValueStore.memory.clear();
      PresenterModel.saveDelay = Duration.zero;
      model = PresenterModel();
      await model.load();
      // (Counts lyric slides: no blank / title slides.)
      model.updateProjection(
        (p) => p
          ..blankSlide = false
          ..titleSlide = false,
      );
      model.addOrUpdate(other);
      model.addOrUpdate(bilingual);
      net = _FakeTransport();
      band = BandSync(model, transport: net);
    });

    test('leading: songs, sections (a linked pair = 2), key changes', () async {
      final set = model.createSetlist('Sunday');
      model.addSongsToSetlist(set, [other.id]);
      model.addMarker(set, EntryType.divider, 'Offering');
      model.addSongsToSetlist(set, [bilingual.id]);
      await band.lead(set);
      expect(net.leading?['title'], 'Sunday');

      net.sent.clear();
      model.selectEntry(set, set.entries[2]);
      final go = net.sent.single;
      expect(ptCommandName(go), 'gotoPlaylistIndexAndSection');
      expect(ptCommandData(go), [2]); // the divider counts
      expect(ptCommandId(go), bilingual.id.toUpperCase());

      // Next slide: past Verse 1 AND Verse 1 (FR) in JustChords.
      net.sent.clear();
      model.goTo(1);
      expect(net.sent.map(ptCommandName), [
        'nextSongSection',
        'nextSongSection',
      ]);
      expect(
        net.sent.map(ptCommandId).toSet(),
        hasLength(2),
        reason: 'every command has a fresh id',
      );

      // A key change goes out as new setlist data.
      net.sent.clear();
      model.setTranspose(2);
      final data = net.sent.singleWhere((m) => m['type'] == 'setlistData');
      final song = ((data['setlistData'] as Map)['songs'] as List)
          .cast<Map>()
          .firstWhere((s) => s['title'] == 'Bilingual');
      expect(song['transpose'], 'A');

      await band.stopLeading();
      expect(net.leading, isNull);
    });

    test('following: the leader’s setlist, songs and sections', () async {
      // The leader's setlist, as JustChords sends it.
      final set = Setlist(
        name: 'Leader set',
        entries: [
          SetEntry(songId: other.id),
          SetEntry(type: EntryType.divider, title: '—'),
          SetEntry(songId: bilingual.id),
        ],
      );
      final songs = {other.id: other, bilingual.id: bilingual};
      await band.join(
        const BandSyncSession(
          leader: 'iPad',
          title: 'Leader set',
          host: 'h',
          port: 1,
        ),
      );
      net.receive({
        'type': 'setlistData',
        'setlistData': ptSetlistData(set, (id) => songs[id]),
      });
      await pumpEventQueue();
      final band0 = model.bandSetlist!;
      expect(band0.name, 'Leader set');
      // Kept apart from the library (and not saved).
      expect(model.songs.where((s) => s.title == 'Bilingual'), hasLength(1));
      expect(jsonEncode(model.toJson()), isNot(contains('Leader set')));

      net.receive(ptCommand('gotoPlaylistIndexAndSection', [2], bilingual.id));
      await pumpEventQueue();
      expect(model.activeSetlistId, band0.id);
      expect(model.currentSong!.title, 'Bilingual');
      expect(model.index, 0);

      // The JustChords format has no linked sections, so here too Verse 1
      // and its translation are two slides, like on the leader.
      net.receive(ptCommand('nextSongSection', const [], 'A'));
      await pumpEventQueue();
      expect(model.index, 1);
      net.receive(ptCommand('nextSongSection', const [], 'B'));
      await pumpEventQueue();
      expect(model.index, 2);
      net.receive(ptCommand('firstSongSection', const [], 'D'));
      await pumpEventQueue();
      expect(model.index, 0);
      net.receive(ptCommand('previousSong', const [], 'C'));
      await pumpEventQueue();
      expect(model.currentSong!.title, 'Other');

      net.receive({'type': 'kick'});
      await pumpEventQueue();
      expect(band.role, BandSyncRole.idle);
      expect(band.status, 'Disconnected by leader');
      expect(model.bandSetlist, isNull);
      expect(model.currentSong!.id.startsWith('band:'), isFalse);
    });
  });
}

/// A pretend network.
class _FakeTransport implements BandSyncTransport {
  Map<String, dynamic>? leading;
  final sent = <Map<String, dynamic>>[];
  final _messages = StreamController<Map<String, dynamic>>.broadcast();

  void receive(Map<String, dynamic> m) => _messages.add(m);

  @override
  Stream<List<BandSyncSession>> get sessions => const Stream.empty();
  @override
  Future<void> scan() async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> lead(String nickname, Map<String, dynamic> data) async =>
      leading = data;
  @override
  void send(Map<String, dynamic> message) => sent.add(message);
  @override
  Stream<List<String>> get followers => const Stream.empty();
  @override
  Future<void> stopLeading() async => leading = null;
  @override
  Future<void> join(String host, int port, String nickname) async {}
  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<bool> get connected => const Stream.empty();
  @override
  Future<void> leave() async {}
}
