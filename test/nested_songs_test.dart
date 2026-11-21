import 'package:bilingual_projector/bramble_icons.dart';
import 'package:bilingual_projector/band_sync/protocol.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/justchords.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PresenterModel model;
  late Song a, b, c;
  late Setlist set;

  setUp(() async {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    model = PresenterModel();
    await model.load();
    a = Song(
      title: 'Song A',
      raw:
          '{title: Song A}\n{key: G}\nVerse 1:\n[G]Alpha words\n\n'
          'Chorus:\n[C]Alpha chorus',
    );
    b = Song(
      title: 'Song B',
      raw:
          '{title: Song B}\n{key: D}\nVerse 1:\n[D]Bravo words\n\n'
          'Bridge:\n[A]Bravo bridge',
    );
    c = Song(title: 'Song C', raw: 'Tag:\n[E]Charlie');
    for (final s in [a, b, c]) {
      model.addOrUpdate(s);
    }
    // (The model's own copies.)
    a = model.songById(a.id)!;
    b = model.songById(b.id)!;
    c = model.songById(c.id)!;
    set = model.createSetlist('Sunday');
    model.addSongsToSetlist(set, [a.id, b.id, c.id]);
  });

  test('a song dropped on another is nested under it, and out again', () {
    final [ea, eb, ec] = set.entries;
    model.nestEntry(set, eb, ea);
    model.nestEntry(set, ec, ea);
    expect(set.entries, [ea]);
    expect(ea.subSongIds, [b.id, c.id]);

    model.moveSubSong(ea, 1, -1);
    expect(ea.subSongIds, [c.id, b.id]);

    model.unnestSong(set, ea, 0);
    expect(ea.subSongIds, [b.id]);
    expect(set.entries.map((e) => e.songId), [a.id, c.id]);

    // The nesting survives a save and reload (our own format).
    final again = Setlist.fromJson(set.toJson());
    expect(again.entries.first.subSongIds, [b.id]);
  });

  test('nested songs play after it as one song; no arrangement: in order', () {
    final [ea, eb, ec] = set.entries;
    model.nestEntry(set, eb, ea);
    model.nestEntry(set, ec, ea);
    final played = model.playedSong(a, ea, set: set);
    final names = ChordPro.sectionNames(played.raw);
    expect(names, ['Verse 1', 'Chorus', 'Verse 1 (Song B)', 'Bridge', 'Tag']);
    expect(played.structure, isEmpty);
    // The nested songs' own title / key lines aren't in it.
    expect(played.raw, isNot(contains('{title: Song B}')));
    expect(played.raw, isNot(contains('{key: D}')));
    // The saved songs are untouched.
    expect(a.raw, isNot(contains('Bravo')));
    expect(model.songById(a.id)!.raw, a.raw);

    final spec = model.specFor(a, set: set, entry: ea);
    expect(spec.raw, contains('Bravo bridge'));
    expect(spec.raw, contains('Charlie'));
  });

  test('an arrangement can pick parts from either song', () {
    final [ea, eb, _] = set.entries;
    b.structure = [
      StructureItem.section('Bridge'),
      StructureItem.section('Verse 1'),
    ];
    model.nestEntry(set, eb, ea);
    final played = model.playedSong(a, ea, set: set);
    // Each song's own order (A has none: its sections as written).
    expect(played.structure.map((i) => i.name), [
      'Verse 1',
      'Chorus',
      'Bridge',
      'Verse 1 (Song B)',
    ]);
    // A custom order for the setlist mixing them.
    model.selectEntry(set, ea);
    model.setStructure([
      StructureItem.section('Verse 1 (Song B)'),
      StructureItem.section('Chorus'),
    ]);
    expect(ea.structure.map((i) => i.name), ['Verse 1 (Song B)', 'Chorus']);
    expect(model.currentSong!.raw, a.raw);
    final spec = model.specFor(a, set: set, entry: ea);
    expect(spec.parts.first.raw, contains('Bravo words'));
  });

  test('each nested song keeps its own key', () {
    final [ea, eb, _] = set.entries;
    b.transpose = 2; // D -> E
    model.nestEntry(set, eb, ea);
    final played = model.playedSong(a, ea, set: set);
    expect(played.raw, contains('[E]Bravo words'));
    expect(played.raw, contains('[G]Alpha words'));
  });

  test('JustChords and Band Sync get each song as its own entry', () {
    final [ea, eb, ec] = set.entries;
    model.nestEntry(set, eb, ea);
    model.nestEntry(set, ec, ea);
    model.selectEntry(set, ea);
    model.setStructure([
      StructureItem.section('Chorus'),
      StructureItem.section('Bridge'),
    ]);
    final byId = {
      for (final s in [a, b, c]) s.id: s,
    };

    final flat = set.flattened((id) => byId[id]);
    expect(flat.entries.map((e) => e.songId), [a.id, b.id, c.id]);
    expect(flat.entries.first.extra.containsKey('subSongs'), isFalse);
    // Only the parent's own parts stay in its arrangement.
    expect(flat.entries.first.structure.map((i) => i.name), ['Chorus']);
    // The setlist itself still has the nesting.
    expect(set.entries.single.subSongIds, [b.id, c.id]);

    final playlist = justChordsPlaylist(set, byId);
    expect(playlist.toString(), isNot(contains('subSongs')));
    expect((playlist.values.whereType<List>().first).length, 3);

    final data = ptSetlistData(set, (id) => byId[id]);
    expect((data['songs'] as List).length, 3);
    expect(data.toString(), isNot(contains('subSongs')));
  });

  test('rows move as Keydeck slides: right nests, left brings out', () {
    final [ea, eb, ec] = set.entries;
    // C dragged right, under B: nested in B.
    model.moveSetlistRow(set, 2, 3, 1);
    expect(set.entries, [ea, eb]);
    expect(eb.subSongIds, [c.id]);
    // B (with C) dragged right, under A: both nested in A.
    model.moveSetlistRow(set, 1, 3, 1);
    expect(set.entries, [ea]);
    expect(ea.subSongIds, [b.id, c.id]);
    // Rows: A, B, C. C moved above B (still nested).
    model.moveSetlistRow(set, 2, 1, 1);
    expect(ea.subSongIds, [c.id, b.id]);
    // B dragged left, to the end: its own entry again.
    model.moveSetlistRow(set, 2, 3, 0);
    expect(set.entries.map((e) => e.songId), [a.id, b.id]);
    expect(ea.subSongIds, [c.id]);
    // A (with C) moved below B: C goes along.
    model.moveSetlistRow(set, 0, 3, 0);
    expect(set.entries.map((e) => e.songId), [b.id, a.id]);
    expect(set.entries.last.subSongIds, [c.id]);
  });

  testWidgets('drag a song right by its handle to nest it; lines join them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    model.setUi('sidebar.mode', 'setlists');
    model.setUi('sidebar.setlist', set.id);
    await tester.pumpWidget(
      BilingualProjectorApp(
        model: model,
        home: OperatorScreen(model: model),
      ),
    );
    await tester.pumpAndSettle();
    if (find.text('1. Song A').evaluate().isEmpty) {
      await tester.tap(find.byTooltip('Show sidebar'));
      await tester.pumpAndSettle();
    }
    Finder rowOf(String text) => find.ancestor(
      of: find.descendant(of: find.byType(Sidebar), matching: find.text(text)),
      matching: find.byWidgetPredicate(
        (w) => w is Material && w.child is InkWell,
      ),
    );
    Finder handleOf(String text) => find.descendant(
      of: rowOf(text).first,
      matching: find.byIcon(BrambleIcons.dotsSixVertical),
    );
    // C: up over B's lower half and right one step.
    var g = await tester.startGesture(tester.getCenter(handleOf('3. Song C')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(set.entries.map((e) => e.songId), [a.id, b.id]);
    expect(set.entries.last.subSongIds, [c.id]);
    // The nested row keeps its handle.
    expect(handleOf('Song C'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // B (with C) right, under A.
    g = await tester.startGesture(tester.getCenter(handleOf('2. Song B')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(set.entries.single.subSongIds, [b.id, c.id]);

    // C dragged left, out again (to the end).
    g = await tester.startGesture(tester.getCenter(handleOf('Song C')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-6, 15));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(set.entries.map((e) => e.songId), [a.id, c.id]);
    expect(set.entries.first.subSongIds, [b.id]);
  });
}
