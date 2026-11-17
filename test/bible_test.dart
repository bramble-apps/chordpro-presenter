import 'dart:convert';
import 'dart:typed_data';

import 'package:bilingual_projector/bible.dart';
import 'package:bilingual_projector/bible/bible_xml.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/bible_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const zefania = '''<?xml version="1.0" encoding="UTF-8"?>
<XMLBIBLE biblename="Test English">
  <BIBLEBOOK bnumber="43" bname="John">
    <CHAPTER cnumber="3">
      <VERS vnumber="16">For God so loved the world &amp; gave<NOTE>a note</NOTE> his Son.</VERS>
      <VERS vnumber="17">God didn't send his Son to judge the world:</VERS>
      <VERS vnumber="18">He who believes [in him] is not judged.</VERS>
    </CHAPTER>
  </BIBLEBOOK>
  <BIBLEBOOK bnumber="19" bname="Psalms">
    <CHAPTER cnumber="23"><VERS vnumber="1">The LORD is my shepherd.</VERS></CHAPTER>
  </BIBLEBOOK>
</XMLBIBLE>''';

const french = '''<?xml version="1.0" encoding="UTF-8"?>
<XMLBIBLE biblename="Louis Segond">
  <INFORMATION><language>FRE</language></INFORMATION>
  <BIBLEBOOK bnumber="43" bname="Jean">
    <CHAPTER cnumber="3">
      <VERS vnumber="16">Car Dieu a tant aimé le monde.</VERS>
      <VERS vnumber="17">Dieu n'a pas envoyé son Fils.</VERS>
      <VERS vnumber="18">Celui qui croit n'est point jugé.</VERS>
    </CHAPTER>
  </BIBLEBOOK>
</XMLBIBLE>''';

Future<PresenterModel> _model() async {
  KeyValueStore.memory.clear();
  KeyValueStore.bytes.clear();
  PresenterModel.saveDelay = Duration.zero;
  final m = PresenterModel();
  await m.load();
  m.updateProjection(
    (p) => p
      ..blankSlide = false
      ..titleSlide = false,
  );
  return m;
}

void _fakeVersions() {
  final lib = BibleLibrary.instance..resetForTest();
  lib.putForTest('WEB', parseBibleXml(zefania));
  lib.putForTest('LSG', parseBibleXml(french), name: 'Louis Segond');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bible XML', () {
    test('Zefania: books, verses, notes left out, entities', () {
      final b = parseBibleXml(zefania);
      expect(b.title, 'Test English');
      expect(b.books.map((x) => x.name), ['John', 'Psalms']);
      final v = b.book('43')!.chapter(3)!.verses;
      expect(v.map((x) => x.number), ['16', '17', '18']);
      expect(v.first.text, 'For God so loved the world & gave his Son.');
    });

    test('Beblia and OSIS milestones', () {
      final beblia = parseBibleXml(
        '<bible translation="B"><testament name="New"><book number="43">'
        '<chapter number="1"><verse number="1">In the beginning</verse>'
        '</chapter></book></testament></bible>',
      );
      expect(
        beblia.book('43')!.chapter(1)!.verses.single.text,
        'In the beginning',
      );
      final osis = parseBibleXml(
        '<osis><osisText xml:lang="en"><div type="book" osisID="John">'
        '<chapter osisID="John.1"><verse sID="John.1.1" osisID="John.1.1"/>'
        'In the <w lemma="x">beginning</w><note>n</note> was the Word.'
        '<verse eID="John.1.1"/></chapter></div></osisText></osis>',
      );
      expect(
        osis.book('43')!.chapter(1)!.verses.single.text,
        'In the beginning was the Word.',
      );
    });

    test('opened a book at a time: the same books and verses', () {
      final whole = parseBibleXml(zefania);
      final quick = openBibleXml(zefania);
      expect(quick.title, whole.title);
      expect(quick.books.map((b) => '${b.number} ${b.name}'), [
        '43 John',
        '19 Psalms',
      ]);
      expect(
        quick.book('43')!.chapter(3)!.verses.map((v) => v.text),
        whole.book('43')!.chapter(3)!.verses.map((v) => v.text),
      );
      expect(quick.verseCount, whole.verseCount);
    });

    test('not a Bible', () {
      expect(() => parseBibleXml('<songs/>'), throwsFormatException);
    });

    test('UTF-16 and Latin-1 files', () {
      final bytes = Uint8List.fromList([
        0xFF,
        0xFE,
        for (final c in '<a>é</a>'.codeUnits) ...[c & 0xFF, c >> 8],
      ]);
      expect(decodeXmlBytes(bytes), '<a>é</a>');
      final latin = Uint8List.fromList(
        latin1.encode('<?xml version="1.0" encoding="ISO-8859-1"?><a>é</a>'),
      );
      expect(decodeXmlBytes(latin), endsWith('<a>é</a>'));
    });
  });

  group('passages', () {
    final en = parseBibleXml(zefania);
    final fr = parseBibleXml(french);

    test('typed references', () {
      expect(parsePassage('John 3:16-18', en), (
        book: '43',
        chapter: 3,
        from: 16,
        to: 18,
      ));
      expect(parsePassage('Jn 3.17', en)?.to, 17);
      // A chapter alone: all of it; an end past the chapter: its last.
      expect(parsePassage('John 3', en)?.from, 16);
      expect(parsePassage('John 3:17–40', en)?.to, 18);
      expect(parsePassage('Ps 23:1', en)?.book, '19');
      // The version's own names.
      expect(parsePassage('Jean 3:16-17', fr)?.to, 17);
      expect(parsePassage('Romans 1:1', en), isNull);
      expect(parsePassage('', en), isNull);
    });

    test('slides: a few verses each, the second version linked beside', () {
      const p = BiblePassage(
        version: 'WEB',
        second: 'LSG',
        book: '43',
        chapter: 3,
        from: 16,
        to: 18,
      );
      final t = passageText(p, en, second: fr);
      expect(t.title, 'John 3:16–18');
      expect(ChordPro.sectionNames(t.raw), [
        'John 3:16–17 (WEB)',
        'John 3:16–17 (LSG)',
        'John 3:18 (WEB)',
        'John 3:18 (LSG)',
      ]);
      expect(t.structure.map((s) => s.linked), [true, false, true, false]);
      // Verse numbers, the reference in each version's names.
      expect(t.raw, contains('¹⁶ For God so loved'));
      expect(t.raw, contains('Jean 3:16–17 LSG'));
      // No chords from [brackets], no label from a colon at the end.
      expect(t.raw, isNot(contains('[')));
      expect(t.raw, contains('judge the world:​'));
      final one = passageText(p.copyWith(noSecond: true, perSlide: 3), en);
      expect(ChordPro.sectionNames(one.raw), ['John 3:16–18 (WEB)']);
    });

    test('JSON', () {
      const p = BiblePassage(
        version: 'KJV',
        book: '19',
        chapter: 23,
        from: 1,
        to: 6,
        perSlide: 3,
      );
      expect(BiblePassage.fromJson(jsonDecode(jsonEncode(p.toJson()))), p);
      expect(p.reference, 'Psalms 23:1–6');
      expect(BiblePassage.fromJson('nope'), isNull);
    });

    test('version tags', () {
      expect(versionIdFor('LSG', 'x.xml'), 'LSG');
      expect(versionIdFor('Louis Segond 1910', 'lsg1910'), 'LSG1910');
      expect(versionIdFor(null, 'French Darby Bible'), 'FDB');
    });
  });

  group('in the app', () {
    setUp(_fakeVersions);

    test('a passage shows as slides, never in the library', () async {
      final m = await _model();
      final songs = m.songs.length;
      // (No song open: the passage shows on its own.)
      m.selectSong(null);
      const p = BiblePassage(
        version: 'WEB',
        second: 'LSG',
        book: '43',
        chapter: 3,
        from: 16,
        to: 18,
      );
      await m.showPassage(p);
      expect(m.currentPassage, p);
      expect(m.currentSong?.title, 'John 3:16–18');
      expect(m.songs.length, songs);
      expect(m.songs.any((s) => s.title.contains('John')), isFalse);
      // Linked: two slides, each with both versions.
      expect(m.slides.length, 2);
      expect(m.slides.first, contains('For God so loved'));
      expect(m.slides.first, contains('Car Dieu'));
      // With a blank and a title slide first: it opens on the verses.
      m.updateProjection(
        (p) => p
          ..blankSlide = true
          ..titleSlide = true,
      );
      await m.showPassage(p);
      expect(m.slides.length, 4);
      expect(m.slides[m.selection.value], contains('For God so loved'));
    });

    test('with a song open: the song stays, scripture follows it', () async {
      final m = await _model();
      final song = Song(title: 'Grace', raw: 'Verse 1:\nAmazing grace');
      m.addOrUpdate(song);
      final own = m.slides.length;
      expect(m.scriptureStart, -1);
      const p = BiblePassage(
        version: 'WEB',
        book: '43',
        chapter: 3,
        from: 16,
        to: 18,
      );
      await m.showPassage(p);
      // Still the song; its slides, then the passage's two.
      expect(m.currentSong?.id, song.id);
      expect(m.currentPassage, p);
      expect(m.slides.length, own + 2);
      expect(m.scriptureStart, own);
      expect(m.scriptureNames, ['John 3:16–17 (WEB)', 'John 3:18 (WEB)']);
      expect(m.slides.first, contains('Amazing grace'));
      // It opens on the first verses.
      expect(m.selection.value, own);
      expect(m.slides[own], contains('For God so loved'));
      // Another passage replaces it; closing it leaves the song.
      await m.showPassage(p.copyWith(perSlide: 3));
      expect(m.slides.length, own + 1);
      m.closeScripture();
      expect(m.slides.length, own);
      expect(m.currentPassage, isNull);
      expect(m.selection.value, own - 1);
      // Opening another song ends it too.
      await m.showPassage(p);
      m.addOrUpdate(Song(title: 'Other', raw: 'Verse 1:\nHello'));
      expect(m.scriptureStart, -1);
      expect(m.currentPassage, isNull);
    });

    test('saved in a setlist: only there, and plays from it', () async {
      final m = await _model();
      final set = m.createSetlist('Sunday');
      const p = BiblePassage(
        version: 'WEB',
        book: '19',
        chapter: 23,
        from: 1,
        to: 1,
      );
      final entry = m.addPassageToSetlist(set, p);
      expect(entry.type, EntryType.bible);
      expect(m.savedPassages.single.$2.passage, p);
      expect(m.songs.any((s) => s.raw.contains('shepherd')), isFalse);

      // Survives saving (setlist JSON).
      final back = Setlist.fromJson(jsonDecode(jsonEncode(set.toJson())));
      expect(back.entries.single.passage, p);

      m.selectEntry(set, entry);
      await pumpEventQueue();
      expect(m.currentPassage, p);
      expect(m.activeSetlistId, set.id);
      expect(m.activeEntryId, entry.id);
      expect(m.slides.single, contains('shepherd'));

      // Swiping on from a song reaches the passage.
      final song = Song(title: 'Grace', raw: 'Verse 1:\nAmazing grace');
      m.addOrUpdate(song);
      set.entries.insert(0, SetEntry(songId: song.id));
      m.selectEntry(set, set.entries.first);
      expect(m.currentSong?.id, song.id);
      m.goSong(1);
      await pumpEventQueue();
      expect(m.currentPassage, p);
    });

    test('the queue keeps its order and is remembered', () async {
      final lib = BibleLibrary.instance;
      await lib.start();
      KeyValueStore.memory.clear();
      const a = BiblePassage(
        version: 'WEB',
        book: '43',
        chapter: 3,
        from: 16,
        to: 16,
      );
      final b = a.copyWith(perSlide: 1);
      const c = BiblePassage(
        version: 'WEB',
        book: '19',
        chapter: 23,
        from: 1,
        to: 1,
      );
      lib
        ..enqueue(a)
        ..enqueue(b)
        ..enqueue(c);
      lib.reorder(2, 0);
      expect(lib.queue, [c, a, b]);
      lib.dequeue(1);
      expect(lib.queue, [c, b]);
      await pumpEventQueue();
      lib.resetForTest();
      await lib.start();
      expect(lib.queue, [c, b]);
    });

    test('importing a Bible XML file', () async {
      final lib = BibleLibrary.instance;
      await lib.start();
      final info = await lib.importXml(
        'Louis Segond.xml',
        Uint8List.fromList(
          utf8.encode(french.replaceAll('Louis Segond', 'LSG')),
        ),
      );
      expect(info.id, 'LSG2'); // LSG is taken (the fake above)
      expect(lib.versionById('LSG2'), isNotNull);
      expect(KeyValueStore.bytes.keys, contains(endsWith('LSG2')));
      final b = await lib.load('LSG2');
      expect(b.book('43')!.name, 'Jean');
      await expectLater(
        lib.importXml('songs.xml', Uint8List.fromList(utf8.encode('<x/>'))),
        throwsFormatException,
      );
      await lib.remove('LSG2');
      expect(lib.versionById('LSG2'), isNull);
    });
  });

  test('the bundled WEB and KJV', () async {
    final lib = BibleLibrary.instance..resetForTest();
    for (final id in ['WEB', 'KJV']) {
      final b = await lib.load(id);
      expect(b.books.length, 66, reason: id);
      expect(b.verseCount, greaterThan(31000), reason: id);
      expect(
        b.book('43')!.chapter(3)!.verses[15].text,
        startsWith('For God so loved the world'),
        reason: id,
      );
    }
  });

  group('the Bible tool', () {
    for (final (name, size) in [
      ('phone', const Size(390, 844)),
      ('desktop', const Size(1280, 800)),
    ]) {
      testWidgets('on a $name: pick verses, show, queue', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final m = await tester.runAsync(_model);
        // (Made here: futures from setUp never finish in the test's zone.)
        _fakeVersions();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: BiblePane(model: m!)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('For God so loved the world & gave his Son.'),
          findsOneWidget,
        );
        // 16 is picked; tapping 17 makes it 16–17, tapping again starts
        // over at 17.
        await tester.tap(find.text('17'));
        await tester.pump();
        await tester.tap(find.text('17'));
        await tester.pump();
        await tester.tap(find.text('18'));
        await tester.pump();
        // Show sits evenly in its pill: the same gap above, below and
        // at the end.
        final show = tester.getRect(find.byKey(const Key('bible-show')));
        final bar = tester.getRect(
          find
              .ancestor(
                of: find.byKey(const Key('bible-show')),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(show.top - bar.top, closeTo(bar.right - show.right, 0.5));
        expect(bar.bottom - show.bottom, closeTo(bar.right - show.right, 0.5));
        await tester.tap(find.byKey(const Key('bible-show')));
        await tester.pumpAndSettle();
        expect(m.currentPassage?.from, 17);
        expect(m.currentPassage?.to, 18);
        // One version unless a second is added.
        expect(m.currentPassage?.second, isNull);
        expect(m.slides[m.scriptureStart], isNot(contains('Dieu')));
        expect(m.songs.any((s) => s.id.startsWith('bible:')), isFalse);

        // "Add version" puts the other one beside it, live.
        await tester.tap(find.byKey(const Key('bible-add-version')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('LSG · Louis Segond').last);
        await tester.pumpAndSettle();
        expect(BibleLibrary.instance.second, 'LSG');
        expect(m.currentPassage?.second, 'LSG');
        expect(m.slides[m.scriptureStart], contains('Dieu'));
        // Its × goes back to one version.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(BibleLibrary.instance.second, isNull);
        expect(m.currentPassage?.second, isNull);

        // The picker: a book, then a chapter.
        await tester.tap(find.byKey(const Key('bible-pick')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('bible-book-19')));
        await tester.pumpAndSettle();
        expect(find.text('The LORD is my shepherd.'), findsOneWidget);
        expect(find.text('Psalms 23:1'), findsOneWidget);

        await tester.tap(find.byKey(const Key('bible-queue-add')));
        await tester.pumpAndSettle();
        expect(BibleLibrary.instance.queue.length, 1);
        // (Narrow tools keep the queue in the options menu.)
        if (find.byKey(const Key('bible-queue')).evaluate().isEmpty) {
          await tester.tap(find.byTooltip('Options'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('bible-queue')));
        await tester.pumpAndSettle();
        expect(find.text('Show next'), findsOneWidget);
        expect(tester.takeException(), isNull);
        BibleLibrary.instance.clearQueue();
      });
    }
  });
}
