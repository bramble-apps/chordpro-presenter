import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/justchords.dart';
import 'package:bilingual_projector/media_library.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/live_media.dart';
import 'package:bilingual_projector/youtube_handle.dart';
import 'package:bilingual_projector/widgets/media_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PresenterModel> _model() async {
  KeyValueStore.memory.clear();
  KeyValueStore.bytes.clear();
  PresenterModel.saveDelay = Duration.zero;
  final m = PresenterModel();
  await m.load();
  await m.loadMedia();
  return m;
}

MediaItem _picture(String name) =>
    MediaItem.fromFile(MediaRef('m-$name', '$name.jpg', 'image/jpeg'));

void main() {
  test('links and files get the right kind and name', () {
    final yt = MediaItem.fromUrl('https://youtu.be/dQw4w9WgXcQ');
    expect(yt.kind, MediaKind.youtube);
    expect(yt.youtube, 'dQw4w9WgXcQ');
    expect(yt.thumbnailUrl, contains('dQw4w9WgXcQ'));
    final mp4 = MediaItem.fromUrl('https://example.com/clips/Intro%20loop.mp4');
    expect((mp4.kind, mp4.name), (MediaKind.video, 'Intro loop'));
    expect(MediaItem.fromUrl('https://example.com/').kind, MediaKind.link);
    final song = MediaItem.fromFile(MediaRef('a', 'Hymn.mp3', 'audio/mpeg'));
    expect((song.kind, song.name), (MediaKind.audio, 'Hymn'));
    expect(song.canBeBackground, isFalse);
    expect(_picture('Sky').canBeBackground, isTrue);
    // Through JSON.
    final back = MediaItem.fromJson(jsonDecode(jsonEncode(yt.toJson())))!;
    expect((back.id, back.kind, back.url), (yt.id, yt.kind, yt.url));
  });

  test('folders: add, move, rename and delete keep items', () async {
    final m = await _model();
    final sky = _picture('Sky');
    m.addMedia(sky);
    m.addMediaFolder('Easter/Backgrounds');
    expect(m.mediaFolders, ['Easter', 'Easter/Backgrounds']);
    m.moveMedia(sky, 'Easter/Backgrounds');
    m.renameMediaFolder('Easter', 'Spring');
    expect(m.mediaFolders, ['Spring', 'Spring/Backgrounds']);
    expect(sky.folder, 'Spring/Backgrounds');
    m.deleteMediaFolder('Spring');
    expect(m.mediaFolders, ['Backgrounds']);
    expect(sky.folder, 'Backgrounds');
    m.renameMedia(sky, 'Blue sky');
    // Kept: a fresh model reads it back.
    final again = PresenterModel();
    await again.load();
    await again.loadMedia();
    expect(again.mediaItems.single.name, 'Blue sky');
    expect(again.mediaFolders, ['Backgrounds']);
  });

  test('play, overlay and background on the projector', () async {
    final m = await _model();
    final sky = _picture('Sky');
    final yt = MediaItem.fromUrl('https://www.youtube.com/watch?v=abcdefghijk');
    m.showMedia(yt, LiveMode.play);
    expect(m.live?.item.youtube, 'abcdefghijk');
    expect(m.projectionData.live, isNotNull);
    expect(m.projectionData.preview, isTrue);
    // What the projector windows are sent, read back as they read it.
    final sent = LiveMedia.fromJson(jsonDecode(jsonEncode(m.live!.toJson())))!;
    expect((sent.mode, sent.item.youtube), (LiveMode.play, 'abcdefghijk'));
    m.setLivePlaying(false);
    expect(m.live!.playing, isFalse);
    m.stopLive();
    expect(m.live, isNull);
    m.showMedia(sky, LiveMode.background);
    expect(m.projection.bgType, BackgroundType.media);
    expect(m.projection.bgMedia?.id, 'm-Sky');
    expect(m.live, isNull);
  });

  test('setlists: media plays in turn, songs can have their own '
      'background', () async {
    final m = await _model();
    final song = Song(title: 'Song', raw: '[G]Words');
    m.addOrUpdate(song);
    final set = Setlist(name: 'Sunday');
    m.setlists.add(set);
    m.addSongsToSetlist(set, [song.id]);
    final yt = MediaItem.fromUrl('https://youtu.be/abcdefghijk');
    m.addMediaToSetlist(set, yt);
    final sky = _picture('Sky');
    m.setEntryBackground(set.entries.first, sky);

    m.selectEntry(set, set.entries.first);
    expect(m.shownProjection.bgMedia?.id, 'm-Sky');
    expect(m.projection.bgMedia, isNull); // the usual one is untouched
    expect(m.live, isNull);

    // Next "song" is the video: it plays.
    expect(m.canGoSong(1), isTrue);
    m.goSong(1);
    expect(m.live?.item.youtube, 'abcdefghijk');
    expect(m.activeEntryId, set.entries[1].id);
    // Back to the song: the video stops.
    m.goSong(-1);
    expect(m.live, isNull);

    // Through saving, and out to JustChords as an event.
    final again = Setlist.fromJson(jsonDecode(jsonEncode(set.toJson())));
    expect(again.entries[1].type, EntryType.media);
    expect(again.entries[1].media?.youtube, 'abcdefghijk');
    expect(again.entries.first.background?.name, 'Sky');
    final items =
        justChordsPlaylist(set, {song.id: song})['arrangement'] as List? ??
        const [];
    expect(
      items.whereType<Map>().any(
        (i) => i['type'] == 'event' && i['title'] == 'YouTube video',
      ),
      isTrue,
    );
  });

  test('dropped files: type from the name', () {
    expect(mimeOfName('Intro.MP4'), 'video/mp4');
    expect(mimeOfName('hymn.mp3'), 'audio/mpeg');
    expect(mimeOfName('sky.jpeg'), 'image/jpeg');
    expect(mimeOfName('song.cho'), '');
  });

  test('YouTube progress is read from the player\'s messages', () {
    final h = YouTubeHandle();
    final seen = <(double, double, bool)>[];
    h.onInfo = (p, d, playing) => seen.add((p, d, playing));
    final sent = <(String, List<Object?>)>[];
    h.send = (f, a) => sent.add((f, a));
    // Not started yet: still counts as playing (it's about to).
    h.receive('{"event":"infoDelivery","info":{"playerState":-1}}', jsonDecode);
    h.receive(
      '{"event":"infoDelivery","info":{"currentTime":12.5,"duration":200}}',
      jsonDecode,
    );
    h.receive('{"event":"infoDelivery","info":{"playerState":2}}', jsonDecode);
    expect(seen.last, (12.5, 200.0, false));
    expect(seen.first.$3, isTrue);
    h.seekTo(30);
    h.play();
    expect(
      [for (final (f, a) in sent) '$f $a'],
      ['seekTo [30.0, true]', 'playVideo []'],
    );
    h.receive('not json', (_) => throw const FormatException());
  });

  test('the scrubber: seeks go to the screens, progress comes back', () async {
    final m = await _model();
    final yt = MediaItem.fromUrl('https://youtu.be/abcdefghijk');
    m.showMedia(yt, LiveMode.play);
    final seeks = <double>[];
    final sub = LiveControl.seeks.stream.listen(seeks.add);
    m.seekLive(42);
    await Future<void>.delayed(Duration.zero);
    expect(seeks, [42.0]);
    expect(m.liveTime.value.$1, 42);
    m.restartLive();
    await Future<void>.delayed(Duration.zero);
    expect(seeks.last, 0);
    expect(m.live!.playing, isTrue);
    await sub.cancel();
  });

  testWidgets('tiles keep their own picture after a delete or a filter', (
    tester,
  ) async {
    final m = await _model();
    // A picture first (alphabetically), then a YouTube link.
    KeyValueStore.bytes['media:m-Aaa'] = _png;
    final pic = _picture('Aaa');
    final yt = MediaItem.fromUrl('https://youtu.be/abcdefghijk', name: 'Bbb');
    m.addMedia(pic);
    m.addMedia(yt);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaPane(model: m)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2)); // the picture, YouTube's
    expect(find.text('Picture'), findsNothing); // the kind is a badge
    expect(find.text('Aaa'), findsOneWidget);

    await m.deleteMedia(pic);
    await tester.pumpAndSettle();
    expect(find.text('Aaa'), findsNothing);
    expect(find.text('Bbb'), findsOneWidget);
    // The YouTube tile shows YouTube's still, not the deleted picture.
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1));
    expect(images.single.image, isA<NetworkImage>());

    // Filtering to pictures: none left.
    m.addMedia(_picture('Ccc'));
    await tester.pumpAndSettle();
    mediaPaneFilter.value = MediaKind.youtube;
    await tester.pumpAndSettle();
    expect(find.text('Ccc'), findsNothing);
    expect(find.text('Bbb'), findsOneWidget);
    mediaPaneFilter.value = null;
  });
  _filterTest();

  test(
    'items added together get their own ids; old clashes are repaired',
    () async {
      // Many at once: all different.
      final ids = {
        for (var i = 0; i < 50; i++)
          MediaItem(name: '$i', kind: MediaKind.image).id,
      };
      expect(ids, hasLength(50));

      // A library saved by an earlier version, six pictures with one id.
      KeyValueStore.memory.clear();
      KeyValueStore.bytes.clear();
      PresenterModel.saveDelay = Duration.zero;
      KeyValueStore.memory['mediaLibrary'] = jsonEncode({
        'items': [
          for (var n = 1; n <= 6; n++)
            {
              'id': 'mi1793118999662000',
              'name': 'Jubilee $n',
              'kind': 'image',
              'file': {
                'id': 'm$n',
                'name': 'j$n.jpg',
                'mime': 'image/jpeg',
                'server': true,
              },
            },
        ],
        'folders': [],
      });
      final m = PresenterModel();
      await m.load();
      await m.loadMedia();
      expect({for (final i in m.mediaItems) i.id}, hasLength(6));
      // Deleting one deletes that one only.
      await m.deleteMedia(
        m.mediaItems.firstWhere((i) => i.name == 'Jubilee 3'),
      );
      expect(m.mediaItems.map((i) => i.name), [
        'Jubilee 1',
        'Jubilee 2',
        'Jubilee 4',
        'Jubilee 5',
        'Jubilee 6',
      ]);
      // The repair was saved.
      final again = PresenterModel();
      await again.load();
      await again.loadMedia();
      expect({for (final i in again.mediaItems) i.id}, hasLength(5));
    },
  );
}

void _filterTest() {
  testWidgets('a filter shows only that kind (nothing left over)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final m = await _model();
    for (final n in ['Jubilee 1', 'Jubilee 2', 'Jubilee 3', 'Jubilee 4']) {
      m.addMedia(_picture(n));
    }
    m.addMedia(MediaItem.fromUrl('https://youtu.be/abcdefghijk', name: 'Clip'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaPane(model: m, horizontal: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Jubilee 4'), findsOneWidget);
    mediaPaneFilter.value = MediaKind.youtube;
    await tester.pumpAndSettle();
    for (final n in ['Jubilee 1', 'Jubilee 2', 'Jubilee 3', 'Jubilee 4']) {
      expect(find.text(n), findsNothing, reason: n);
    }
    expect(find.text('Clip'), findsOneWidget);
    mediaPaneFilter.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Jubilee 4'), findsOneWidget);
    // Deleting one: it goes, the rest stay.
    await m.deleteMedia(m.mediaItems.firstWhere((i) => i.name == 'Jubilee 2'));
    await tester.pumpAndSettle();
    expect(find.text('Jubilee 2'), findsNothing);
    expect(find.text('Jubilee 3'), findsOneWidget);
  });
}

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9Q'
  'DwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
