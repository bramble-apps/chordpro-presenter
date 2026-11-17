import 'dart:async';

import 'package:bilingual_projector/bible.dart';
import 'package:bilingual_projector/bible/bible_xml.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/media_library.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Passes messages between two windows, like the local server's relay
/// does (each hears what the other sends).
class _Relay {
  final PresenterModel a, b;
  int _fromA = 0, _fromB = 0;
  Timer? _timer;
  _Relay(this.a, this.b) {
    _timer = Timer.periodic(const Duration(milliseconds: 5), (_) => pump());
  }

  void pump() {
    while (_fromA < a.sync.sent.length) {
      b.sync.receive(a.sync.sent[_fromA++]);
    }
    while (_fromB < b.sync.sent.length) {
      a.sync.receive(b.sync.sent[_fromB++]);
    }
  }

  void stop() => _timer?.cancel();
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
  });

  test('a browser on the Wi-Fi edits the computer\'s library', () async {
    final computer = PresenterModel();
    await computer.load();
    computer.addOrUpdate(Song(title: 'Grace', raw: '[G]Amazing grace'));
    final phone = PresenterModel()..remoteEdit = true;
    final relay = _Relay(computer, phone);
    addTearDown(relay.stop);
    await phone.load();
    expect(phone.remoteError, isNull);
    expect(phone.songs.map((s) => s.title), contains('Grace'));
    expect(phone.remoteLibraryName, computer.currentLibrary.name);

    // An edit on the phone reaches the computer…
    final grace = phone.songs.firstWhere((s) => s.title == 'Grace');
    phone.addOrUpdate(grace.copy()..raw = '[G]Amazing grace, how sweet');
    await _settle();
    expect(
      computer.songs.firstWhere((s) => s.id == grace.id).raw,
      '[G]Amazing grace, how sweet',
    );
    // …and a new song and a setlist too.
    phone.addOrUpdate(Song(title: 'New one', raw: 'Words'));
    phone.setlists.add(Setlist(name: 'Sunday'));
    phone.addSongsToSetlist(phone.setlists.last, [grace.id]);
    await _settle();
    expect(computer.songs.map((s) => s.title), contains('New one'));
    expect(computer.setlists.map((s) => s.name), contains('Sunday'));

    // Edits on the computer reach the phone; deleting goes both ways.
    computer.deleteSong(
      computer.songs.firstWhere((s) => s.title == 'New one').id,
    );
    await _settle();
    expect(phone.songs.map((s) => s.title), isNot(contains('New one')));
    expect(phone.trash.map((s) => s.title), contains('New one'));

    // The phone never drives the projector, and its own library (saved in
    // its browser) isn't touched.
    expect(
      phone.sync.sent.map((m) => m['type']).toSet(),
      everyElement(isIn(['libraryRequest', 'libraryEdit'])),
    );
  });

  test('no computer answering: says so', () async {
    final phone = PresenterModel()..remoteEdit = true;
    await phone.load().timeout(const Duration(seconds: 20));
    expect(phone.remoteError, isNotNull);
    expect(phone.songs, isEmpty); // not a sample song, not its own library
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'Remote: the phone picks the song and slide the computer shows',
    () async {
      const words = 'Verse 1:\nOne\n\nChorus:\nTwo\n\nVerse 2:\nThree';
      final computer = PresenterModel();
      await computer.load();
      computer.addOrUpdate(Song(title: 'Grace', raw: words));
      computer.addOrUpdate(Song(title: 'Other', raw: 'Verse 1:\nHello'));
      final phone = PresenterModel()..remoteEdit = true;
      final relay = _Relay(computer, phone);
      addTearDown(relay.stop);
      await phone.load();
      final grace = phone.songs.firstWhere((s) => s.title == 'Grace');
      final other = phone.songs.firstWhere((s) => s.title == 'Other');

      // Off: the phone only edits; the computer's screen is left alone.
      phone.selectSong(grace.id);
      phone.next();
      await _settle();
      expect(computer.currentSong?.title, 'Other');

      // On: the phone starts where the computer is…
      await phone.setRemoteControl(true);
      await _settle();
      expect(phone.currentSong?.title, 'Other');

      // …then what it opens and taps shows on the computer.
      phone.selectSong(grace.id);
      await _settle();
      expect(computer.currentSong?.title, 'Grace');
      phone.selectPart(2);
      await _settle();
      expect(computer.selectedPart, 2);
      expect(computer.slides[computer.selection.value], contains('Three'));
      phone.toggleBlackout();
      await _settle();
      expect(computer.blackout, isTrue);
      phone.toggleBlackout();
      await _settle();
      expect(computer.blackout, isFalse);

      // The phone follows the computer too.
      computer.selectSong(other.id);
      await _settle();
      expect(phone.currentSong?.title, 'Other');
      computer.selectSong(grace.id);
      computer.selectPart(1);
      await _settle();
      expect(phone.currentSong?.title, 'Grace');
      expect(phone.selectedPart, 1);

      // Off again: no more control.
      await phone.setRemoteControl(false);
      phone.selectSong(other.id);
      await _settle();
      expect(computer.currentSong?.title, 'Grace');
    },
  );

  test('Remote: every presentation control, both ways', () async {
    PresenterModel.remoteEchoWindow = Duration.zero;
    addTearDown(
      () => PresenterModel.remoteEchoWindow = const Duration(milliseconds: 700),
    );
    final lib = BibleLibrary.instance..resetForTest();
    lib.putForTest(
      'WEB',
      parseBibleXml(
        '<XMLBIBLE><BIBLEBOOK bnumber="43" bname="John"><CHAPTER cnumber="3">'
        '<VERS vnumber="16">For God so loved the world.</VERS>'
        '</CHAPTER></BIBLEBOOK></XMLBIBLE>',
      ),
    );
    final computer = PresenterModel();
    await computer.load();
    computer.addOrUpdate(Song(title: 'Grace', raw: 'Verse 1:\nOne'));
    final clip = MediaItem(
      name: 'Welcome',
      kind: MediaKind.youtube,
      url: 'https://youtu.be/abc',
    );
    computer.addMedia(clip);
    // Something only the computer has set: the phone takes it, never
    // the other way round, when its remote is turned on.
    computer.updateProjection((p) => p.underscanW = 77);
    final phone = PresenterModel()..remoteEdit = true;
    final relay = _Relay(computer, phone);
    addTearDown(relay.stop);
    await phone.load();
    await phone.setRemoteControl(true);
    await _settle();
    expect(phone.projection.underscanW, 77);
    expect(computer.projection.underscanW, 77);
    // The computer's media, to show from the phone.
    expect(phone.mediaItems.map((m) => m.name), ['Welcome']);

    // Underscan and the other projector settings.
    phone.updateProjection(
      (p) => p
        ..underscan = true
        ..underscanW = 80,
    );
    await _settle();
    expect(computer.projection.underscan, isTrue);
    expect(computer.projection.underscanW, 80);
    computer.updateProjection((p) => p.underscan = false);
    await _settle();
    expect(phone.projection.underscan, isFalse);

    // The timer: length, start, pause, stop.
    phone.timerSet(120);
    phone.timerToggle();
    await _settle();
    expect(computer.timerTotalSeconds, 120);
    expect(computer.timerRunning, isTrue);
    expect(computer.timerActive, isTrue);
    computer.timerToggle();
    await _settle();
    expect(phone.timerRunning, isFalse);
    phone.timerAdd(60);
    await _settle();
    expect(computer.timerTotalSeconds, 180);
    phone.timerStop();
    await _settle();
    expect(computer.timerActive, isFalse);

    // Media: show, pause, stop.
    phone.showMedia(phone.mediaItems.single, LiveMode.play);
    await _settle();
    expect(computer.live?.item.name, 'Welcome');
    phone.setLivePlaying(false);
    await _settle();
    expect(computer.live?.playing, isFalse);
    computer.stopLive();
    await _settle();
    expect(phone.live, isNull);

    // Scripture beside the song.
    const passage = BiblePassage(
      version: 'WEB',
      book: '43',
      chapter: 3,
      from: 16,
      to: 16,
    );
    await phone.showPassage(passage);
    await _settle();
    expect(computer.currentPassage, passage);
    expect(computer.currentSong?.title, 'Grace');
    expect(computer.slides[computer.selection.value], contains('For God'));
    phone.closeScripture();
    await _settle();
    expect(computer.currentPassage, isNull);
    await computer.showPassage(passage);
    await _settle();
    expect(phone.currentPassage, passage);

    // Blackout from the computer.
    computer.toggleBlackout();
    await _settle();
    expect(phone.blackout, isTrue);

    // Off: the phone's changes stay on the phone.
    await phone.setRemoteControl(false);
    phone.updateProjection((p) => p.underscanW = 50);
    phone.timerSet(30);
    await _settle();
    expect(computer.projection.underscanW, 80);
    expect(computer.timerTotalSeconds, 180);
  });
}
