import 'package:bilingual_projector/bramble_icons.dart';
import 'package:bilingual_projector/widgets/motion_icon.dart';
import 'package:bilingual_projector/widgets/song_marks.dart';
import 'dart:math' as math;
import 'dart:async';

import 'package:bilingual_projector/widgets/edit_song_icon.dart';
import 'package:bilingual_projector/widgets/sidebar_icon.dart';
import 'package:bilingual_projector/widgets/toolbar_editor.dart';
import 'package:bilingual_projector/widgets/translate_dialog.dart';
import 'package:bilingual_projector/translation.dart';
import 'package:bilingual_projector/chord_beats.dart';
import 'package:bilingual_projector/chords/chord_db.dart';
import 'package:bilingual_projector/chords/chord_diagram.dart';
import 'package:bilingual_projector/chords/chord_strip.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/music.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/song_sources.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/media_pip.dart';
import 'package:bilingual_projector/widgets/metronome_icon.dart';
import 'package:bilingual_projector/widgets/paged_sheet.dart';
import 'package:bilingual_projector/widgets/presentation_view.dart';
import 'package:bilingual_projector/widgets/media_pane.dart';
import 'package:bilingual_projector/widgets/projection_view.dart';
import 'package:bilingual_projector/widgets/sidebar.dart';
import 'package:bilingual_projector/widgets/song_swipe.dart';
import 'package:bilingual_projector/widgets/sticky_note.dart';
import 'package:bilingual_projector/widgets/tuner_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bilingual_projector/widgets/find_songs.dart';
import 'package:bilingual_projector/widgets/fitting_slide.dart';
import 'package:bilingual_projector/widgets/key_wheel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilingual_projector/widgets/chord_line.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/widgets/alpha_scrubber.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:bilingual_projector/widgets/chordpro_field.dart';
import 'package:bilingual_projector/widgets/floating_panel.dart';
import 'package:bilingual_projector/widgets/format_pane.dart';
import 'package:bilingual_projector/themes.dart';

Future<PresenterModel> pumpApp(
  WidgetTester tester, {
  bool intro = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final model = PresenterModel();
  await model.load();
  // (These tests count lyric slides; the blank / title slides before each
  // song are tested on their own, in intro_slides_test.dart.)
  if (!intro) {
    model.updateProjection(
      (p) => p
        ..blankSlide = false
        ..titleSlide = false,
    );
  }
  await tester.pumpWidget(
    BilingualProjectorApp(
      model: model,
      home: OperatorScreen(model: model),
    ),
  );
  await tester.pumpAndSettle();
  return model;
}

Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(Dialog), matching: f);

bool hasRichText(WidgetTester tester, String text) => tester
    .widgetList<RichText>(find.byType(RichText))
    .any((w) => w.text.toPlainText().contains(text));

/// A chord shown above the words (chord lines are drawn as one element).
Finder chordText(String chord) => find.byWidgetPredicate(
  (w) => w is ChordLine && w.pieces.any((p) => p.chord == chord),
  description: 'chord "$chord"',
);

/// The toolbar's key button, showing key [k].
Finder keyButton(String k) => find.byWidgetPredicate(
  (w) => w is Text && w.key == const ValueKey('key-button-label') && w.data == k,
);

void main() {
  _toolbarMenuColourTests();
  // Chord shapes, loaded for real once (screens use them as they open).
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ChordLibrary.load();
  });
  testWidgets('key button transposes the chord sheet', (tester) async {
    final model = await pumpApp(tester);
    expect(keyButton('G'), findsOneWidget);
    expect(chordText('Em '), findsWidgets);

    // (the key list: a long press; a tap opens the key wheel)
    await tester.longPress(keyButton('G'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A').last);
    await tester.pumpAndSettle();

    expect(keyButton('A'), findsOneWidget);
    expect(chordText('F#m '), findsWidgets);
    expect(chordText('Em '), findsNothing);
    expect(model.currentSong!.transpose, 2);
  });

  testWidgets('key button opens the key wheel, its chips change the key', (tester) async {
    final model = await pumpApp(tester);
    await tester.tap(keyButton('G'));
    await tester.pumpAndSettle();
    expect(find.byType(KeyWheel), findsOneWidget);
    // G major's V chip: D, which is −5 from G
    await tester.tap(find.widgetWithText(InkWell, 'D'));
    await tester.pumpAndSettle();
    expect(model.currentSong!.transpose, -5);
    expect(keyButton('D'), findsOneWidget);
  });

  testWidgets('format: inline, roman, minor style, caps, hide', (tester) async {
    final model = await pumpApp(tester);

    // Inline chords via the Format panel.
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Inline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    expect(hasRichText(tester, 'Em Amazing'), isTrue);

    // Minor style chip "a" (lowercase).
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, 'a'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(FormatPane),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'a'));
    await tester.pumpAndSettle();
    expect(hasRichText(tester, 'e Amazing'), isTrue);

    // Roman numerals relative to G.
    model.updateFormat((f) => f.notation = ChordNotation.roman);
    await tester.pumpAndSettle();
    expect(hasRichText(tester, 'vi Amazing'), isTrue);
    expect(hasRichText(tester, 'V grace'), isTrue);

    // All caps lyrics, hidden chords, highlighted title.
    model.updateFormat((f) {
      f[SheetElement.lyrics].caps = true;
      f[SheetElement.chords].hidden = true;
      f[SheetElement.title].highlight = 1;
    });
    await tester.pumpAndSettle();
    expect(find.text('AMAZING GRACE, HOW SWEET THE SOUND'), findsOneWidget);
    expect(hasRichText(tester, 'vi '), isFalse);
    final title = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(ChordSheet),
            matching: find.text('Amazing Grace'),
          )
          .first,
    );
    expect(title.style?.backgroundColor, highlightColors[1]);
  });

  testWidgets('pin header keeps title outside the scrolling body', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.updateFormat((f) => f.pinHeader = true);
    await tester.pumpAndSettle();
    final titleScroll = find.ancestor(
      of: find.text('John Newton'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(titleScroll, findsNothing);
  });

  testWidgets('setlist with set-specific key', (tester) async {
    final model = await pumpApp(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Setlists ('), warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New setlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Sunday');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Sunday'), findsOneWidget);

    await tester.tap(find.byTooltip('New…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add songs to "Sunday"'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Amazing Grace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set-specific edits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1. Amazing Grace'));
    await tester.pumpAndSettle();

    // (the key list: a long press; a tap opens the key wheel)
    await tester.longPress(keyButton('G'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A').last);
    await tester.pumpAndSettle();

    final set = model.setlists.single;
    expect(set.entries.single.transpose, 2);
    expect(model.currentSong!.transpose, 0, reason: 'song itself unchanged');
    expect(keyButton('A'), findsOneWidget);

    // Opening the song from the library shows its own key again.
    model.selectSong(model.currentSong!.id);
    await tester.pumpAndSettle();
    expect(keyButton('G'), findsOneWidget);

    // Survives a save/load round trip.
    await model.flush();
    final reloaded = PresenterModel();
    await reloaded.load();
    expect(reloaded.setlists.single.name, 'Sunday');
    expect(reloaded.setlists.single.setSpecific, isTrue);
    expect(reloaded.setlists.single.entries.single.transpose, 2);
  });

  testWidgets('hidden tags, tag filter and trash', (tester) async {
    final model = await pumpApp(tester);
    final english = model.addTag('English', color: 'red');
    final xmas = model.addTag('Christmas', color: 'green');
    model.updateTag(xmas, hidden: true);
    model.addOrUpdate(
      Song(title: 'Joy to the World', raw: '[D]Joy', tags: [xmas.id]),
    );
    model.addOrUpdate(
      Song(title: 'Blessed Be', raw: '[A]Blessed', tags: [english.id]),
    );
    await tester.pumpAndSettle();

    // Christmas song is hidden from the list.
    expect(find.widgetWithText(ListTile, 'Joy to the World'), findsNothing);
    // (No notice about it: the user hid the tag, so they know.)
    expect(find.textContaining('hidden from All Songs'), findsNothing);

    // Filtering by the hidden tag shows it.
    await tester.tap(find.widgetWithText(FilterChip, 'Christmas'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Joy to the World'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Blessed Be'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'Christmas'));
    await tester.pumpAndSettle();

    // Move to Trash, then restore.
    final blessed = model.songs.firstWhere((s) => s.title == 'Blessed Be');
    model.deleteSong(blessed.id);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Blessed Be'), findsNothing);
    expect(model.trash.single.title, 'Blessed Be');

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Trash ('), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Blessed Be'), findsOneWidget);
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(model.trash, isEmpty);
    expect(model.songById(blessed.id), isNotNull);
  });

  testWidgets('details line, footer and capo shapes', (tester) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(
        title: 'Capo Song',
        raw: 'Verse 1:\n[A]Hello [E]there [A]friend',
        tempo: '72',
        timeSignature: '6/8',
        ccli: '555',
        copyright: 'Public Domain',
      ),
    );
    model.setCapo(2);
    await tester.pumpAndSettle();
    // Key, tempo and time beside the title, as on printed music…
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SongMarks &&
            w.keyName == 'A' &&
            w.tempo == '72' &&
            w.time == '6/8',
      ),
      findsOneWidget,
    );
    expect(find.text('= 72'), findsOneWidget);
    // …so the details line keeps only the rest.
    expect(find.textContaining('Key A'), findsNothing);
    expect(find.textContaining('72 BPM'), findsNothing);
    expect(find.textContaining('Capo 2 (G shapes)'), findsOneWidget);
    expect(find.textContaining('CCLI Song # 555'), findsOneWidget);
    // Only the open song (its neighbours are drawn beside it for swiping).
    Finder inSong(Finder f) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is ChordSheet && w.song.title == 'Capo Song',
      ),
      matching: f,
    );
    expect(inSong(chordText('G ')), findsWidgets, reason: 'A shown as G');
    expect(inSong(chordText('D ')), findsOneWidget, reason: 'E shown as D');
  });

  testWidgets('slide arrows only while the projector is open', (tester) async {
    final model = await pumpApp(tester);
    expect(find.byTooltip('Next part (↓ → PgDn Space)'), findsNothing);
    (model.sync as dynamic).receive({'type': 'hello'});
    await tester.pumpAndSettle();
    expect(find.byTooltip('Next part (↓ → PgDn Space)'), findsOneWidget);
    (model.sync as dynamic).receive({'type': 'bye'});
    await tester.pumpAndSettle();
    expect(find.byTooltip('Next part (↓ → PgDn Space)'), findsNothing);
  });

  testWidgets('screen menu: open window, copy link, stop', (tester) async {
    final model = await pumpApp(tester);
    expect(find.byTooltip('Project'), findsOneWidget);
    expect(find.byIcon(BrambleIcons.play), findsNothing);
    expect(find.byIcon(BrambleIcons.screencast), findsNothing, reason: 'one button now');

    await tester.tap(find.byTooltip('Project'));
    await tester.pumpAndSettle();
    expect(find.text('Open projector window'), findsOneWidget);
    expect(find.text('Cast to a TV or display…'), findsOneWidget);
    expect(find.text('Copy projection link'), findsOneWidget);
    expect(find.text('Stop projecting'), findsNothing);
    await tester.tap(find.text('Open projector window'));
    await tester.pumpAndSettle();
    final sent = (model.sync as dynamic).sent as List<Map<String, dynamic>>;
    expect(sent.any((m) => m['type'] == 'start'), isTrue);

    // Projecting: the button lights up and the menu can stop everything.
    (model.sync as dynamic).receive({'type': 'hello'});
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Projecting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop projecting'));
    await tester.pumpAndSettle();
    expect(sent.any((m) => m['type'] == 'stop'), isTrue);
    expect(find.byTooltip('Project'), findsOneWidget);

    // No local server in tests: copying explains how to get a link.
    await tester.tap(find.byTooltip('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy projection link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('run.sh'), findsOneWidget);
  });

  testWidgets('presentation mode: tiles, tap to show, pinch columns', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Presentation mode (slide grid)'));
    await tester.pumpAndSettle();
    expect(model.settings.presentationMode, isTrue);
    expect(find.byType(PresentationView), findsOneWidget);
    // Section headers on the tiles, and the docked controls.
    expect(find.text('Verse 1'), findsWidgets);
    expect(find.byTooltip('Next slide'), findsOneWidget);
    expect(find.text('1 / ${model.slides.length}'), findsOneWidget);

    // Tiles use the projector's look (alignment, position, dim…).
    model.updateProjection((p) {
      p.textAlign = HAlign.left;
      p.bgDim = 40;
    });
    await tester.pumpAndSettle();
    final tileSlide = tester.widget<FittingSlide>(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(FittingSlide),
          )
          .first,
    );
    expect(tileSlide.align, TextAlign.left);
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color.a > 0.3 && w.color.a < 0.5,
        ),
      ),
      findsWidgets,
      reason: 'dim layer on the tiles',
    );

    // Tap the second tile: it goes to the projector.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Slide 2')));
    await tester.pumpAndSettle();
    expect(model.selection.value, 1);
    final sent = (model.sync as dynamic).sent as List<Map<String, dynamic>>;
    expect(sent.last['index'], 1);

    // Ctrl + scroll (and trackpad pinch) changes the columns.
    expect(model.settings.presentColumns, 3);
    final grid = tester.getCenter(find.byType(GridView));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: grid, scrollDelta: const Offset(0, -120)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(model.settings.presentColumns, lessThan(3));

    // A trackpad pinch: many small steps. One short pinch goes all the
    // way to the most columns and back to one; every tile is still there.
    Future<void> pinchSteps(double dy, int n) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      for (var i = 0; i < n; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: grid, scrollDelta: Offset(0, dy)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    await pinchSteps(4, 15); // fingers together
    final most0 = model.settings.presentColumns;
    expect(most0, greaterThan(2));
    await pinchSteps(-4, 15); // fingers apart
    expect(model.settings.presentColumns, 1);
    await pinchSteps(4, 15);
    expect(model.settings.presentColumns, most0);
    expect(
      find.bySemanticsLabel(RegExp('^Slide ${model.slides.length}')),
      findsOneWidget,
      reason: 'no tiles lost after zooming back',
    );
    await pinchSteps(-4, 15);

    // Two-finger touch pinch together: more, smaller tiles.
    final a = await tester.startGesture(grid - const Offset(150, 0));
    final b = await tester.startGesture(grid + const Offset(150, 0));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(13, 0));
      await b.moveBy(const Offset(-13, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    // As many as fit (tiles stay at least ~160 px wide).
    final most = model.settings.presentColumns;
    expect(most, greaterThan(2));

    // Zoom buttons, limited to what fits.
    await tester.tap(find.byTooltip('Smaller tiles (more columns)'));
    await tester.pump();
    expect(model.settings.presentColumns, most);
    await tester.tap(find.byTooltip('Bigger tiles (fewer columns)'));
    await tester.pump();
    expect(model.settings.presentColumns, most - 1);

    // Phone: like YouTube — preview on top, controls under it, then
    // Slides / Functions tabs.
    tester.view.physicalSize = const Size(420, 900);
    await tester.pumpAndSettle();
    final previewTop = tester
        .getTopLeft(find.byType(ProjectorDisplay).first)
        .dy;
    expect(previewTop, lessThan(tester.getTopLeft(find.byTooltip('Slides')).dy));
    expect(
      tester.getTopLeft(find.byTooltip('Next slide')).dy,
      lessThan(tester.getTopLeft(find.byTooltip('Slides')).dy),
    );
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('+1 min'), findsNothing);
    await tester.tap(find.byTooltip('Functions'));
    await tester.pumpAndSettle();
    expect(find.text('+1 min'), findsOneWidget, reason: 'the timer');

    // Medium width: the dock stays beside the grid, its tools in tabs.
    tester.view.physicalSize = const Size(1000, 900);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Slides'), findsNothing);
    expect(find.byTooltip('Functions'), findsOneWidget);
    expect(find.byTooltip('Scripture'), findsOneWidget);
    expect(find.text('+1 min'), findsOneWidget, reason: 'the timer');
    expect(
      tester.getTopLeft(find.byTooltip('Next slide')).dx,
      greaterThan(tester.getTopRight(find.byType(GridView)).dx - 1),
    );
  });

  testWidgets('page mode: all songs or one, columns, tap parts', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    final grace = model.currentSong!;
    model.addOrUpdate(Song(title: 'Other', raw: 'Verse 1:\n[C]Hello'));
    model.selectSong(grace.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    Finder pane(Finder f) =>
        find.descendant(of: find.byType(FormatPane), matching: f);
    final paneScroll = find
        .descendant(
          of: find.byType(FormatPane),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      pane(find.text('Pages')),
      200,
      scrollable: paneScroll,
    );
    await tester.pumpAndSettle();

    // Columns for both views (the scroll view runs into columns too);
    // paper only for pages.
    expect(pane(find.text('Columns')), findsOneWidget);
    expect(pane(find.text('A4')), findsNothing);

    // Pages for every song, in two columns.
    await tester.tap(pane(find.text('Pages')));
    await tester.pumpAndSettle();
    expect(pane(find.text('Columns')), findsOneWidget);
    expect(pane(find.text('A4')), findsOneWidget);
    await tester.tap(pane(find.byTooltip('2 columns')));
    await tester.pumpAndSettle();
    expect(model.format.pageMode, isTrue);
    expect(model.format.columns, 2);
    final sheet = tester.widget<PagedSheet>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ChordSheet && w.song.id == grace.id,
        ),
        matching: find.byType(PagedSheet),
      ),
    );
    expect(sheet.columns, 2);

    // Tapping a part on the page still selects it.
    await tester.tap(find.textContaining("'Twas grace").first);
    await tester.pumpAndSettle();
    expect(model.selection.value, 1);

    // Just this song back to scrolling; the other song keeps pages.
    await tester.tap(pane(find.text('Only this song')).first);
    await tester.pumpAndSettle();
    await tester.tap(pane(find.text('Scroll')));
    await tester.pumpAndSettle();
    expect(model.layoutFor(grace).pageMode, isFalse);
    expect(model.layoutFor(grace).own, isTrue);
    final other = model.songs.firstWhere((s) => s.title == 'Other');
    expect(model.layoutFor(other).pageMode, isTrue);
    expect(model.format.pageMode, isTrue);
    // …and back to following all songs.
    await tester.tap(pane(find.text('Only this song')).first);
    await tester.pumpAndSettle();
    expect(model.layoutFor(grace).own, isFalse);
    expect(model.layoutFor(grace).pageMode, isTrue);

    // Share starts from the song's columns.
    await tester.tap(find.byTooltip('Share / export'));
    // The PDF preview's spinner never settles in tests, so pump frames.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 columns'), findsOneWidget);
    // Leave the dialog via Choose ChordPro (no PDF spinner left behind).
    await tester.tap(find.text('ChordPro'));
    await tester.pumpAndSettle();
  });

  testWidgets('tuner: quick button and reading a note', (tester) async {
    final model = await pumpApp(tester);
    // On by default in the installed apps (tests run like one); hideable.
    expect(find.byTooltip('Tuner'), findsOneWidget);
    model.updateSettings((s) => s.showTuner = false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tuner'), findsNothing);
    model.updateSettings((s) => s.showTuner = true);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tuner'), findsOneWidget);

    // The panel, listening to a played D (146.83 Hz) instead of a mic
    // (a source it can listen to again after being switched off and on).
    final samples = StreamController<Float32List>.broadcast();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TunerPanel(model: model, debugSamples: samples.stream),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Play a note'), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      samples.add(
        Float32List.fromList([
          for (var j = 0; j < 512; j++)
            0.5 * math.sin(2 * math.pi * 146.83 * (i * 512 + j) / 44100),
        ]),
      );
      await tester.pump();
    }
    expect(find.text('D'), findsOneWidget);
    expect(find.textContaining('In tune'), findsOneWidget);

    // Reference pitch is a setting.
    await tester.tap(find.byTooltip('Raise reference'));
    await tester.pump();
    expect(model.settings.tunerA4, 441);

    // The power button stops listening; on again, it listens again.
    await tester.tap(find.byTooltip('Turn the tuner off').first);
    await tester.pump();
    expect(find.text('Tuner off'), findsOneWidget);
    await tester.tap(find.byTooltip('Turn the tuner on').first);
    await tester.pump();
    expect(find.text('Tuner off'), findsNothing);
    await samples.close();
    await tester.pumpWidget(const SizedBox());
  });

  test('YouTube links of every kind', () {
    for (final url in [
      'https://www.youtube.com/watch?v=abc123XYZ_-',
      'https://youtu.be/abc123XYZ_-?si=x',
      'https://m.youtube.com/watch?v=abc123XYZ_-&t=30',
      'https://www.youtube.com/shorts/abc123XYZ_-',
      'https://music.youtube.com/watch?v=abc123XYZ_-',
      'https://www.youtube.com/embed/abc123XYZ_-',
    ]) {
      expect(youtubeId(url), 'abc123XYZ_-', reason: url);
    }
    expect(youtubeId('https://example.com/watch?v=x'), isNull);
    expect(isMediaFile('https://x.org/song.mp3'), isTrue);
    expect(canPlayInApp('https://open.spotify.com/track/1'), isFalse);
  });

  testWidgets('reference recording: quick play button and floating player', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    expect(find.byTooltip('Play reference recording'), findsNothing);
    model.addOrUpdate(
      Song(
        title: 'With video',
        raw: '[C]x',
        audioUrl: 'https://www.youtube.com/watch?v=abc123',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play reference recording'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPip), findsOneWidget);
    expect(lastEmbed, contains('youtube-nocookie.com/embed/abc123'));

    // Drag it by its bar.
    final before = tester.getTopLeft(find.byType(MediaPip));
    await tester.drag(find.text('With video').last, const Offset(200, -150));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byType(MediaPip));
    expect(after.dx, greaterThan(before.dx + 100));
    expect(after.dy, lessThan(before.dy - 100));

    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPip), findsNothing);

    // A web page the app can't show: opens it instead.
    model.addOrUpdate(
      Song(title: 'Page', raw: '[C]x', audioUrl: 'https://open.spotify.com/x'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open reference recording'));
    await tester.pumpAndSettle();
    expect(lastOpenedUrl, 'https://open.spotify.com/x');
    expect(find.byType(MediaPip), findsNothing);

    // Hidden from Settings → Quick buttons.
    model.updateSettings((s) => s.showPlayer = false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open reference recording'), findsNothing);
  });

  test('accents fold to their plain letters', () {
    expect(foldAccents('Élevé'), 'eleve');
    expect(foldAccents('Ô Seigneur, Œuvre'), 'o seigneur, oeuvre');
    expect(foldAccents('Niño · Straße · Æther'), 'nino · strasse · aether');
  });

  testWidgets('accented titles sort, group and search with their letter', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    for (final t in ['Élevé', 'Ecce Homo', 'Zion', 'Ô Seigneur', 'Oasis']) {
      model.addOrUpdate(Song(title: t, raw: 'words'));
    }
    await tester.pumpAndSettle();
    final sidebar = find.byType(Sidebar);
    Finder inList(String t) =>
        find.descendant(of: sidebar, matching: find.text(t));
    // One E group: Ecce Homo, then Élevé (not after Z).
    expect(inList('E'), findsOneWidget);
    double y(String t) => tester.getTopLeft(inList(t)).dy;
    expect(y('Ecce Homo'), lessThan(y('Élevé')));
    expect(y('Élevé'), lessThan(y('Zion')));
    // "o seigneur" before "oasis" (space before letters).
    expect(y('Ô Seigneur'), lessThan(y('Oasis')));
    expect(y('Ô Seigneur'), lessThan(y('Zion')));
    expect(inList('O'), findsOneWidget);

    // Searching without accents finds accented titles.
    await tester.enterText(
      find.descendant(of: sidebar, matching: find.byType(TextField)).first,
      'eleve',
    );
    await tester.pumpAndSettle();
    expect(inList('Élevé'), findsOneWidget);
    expect(inList('Zion'), findsNothing);
  });

  testWidgets('A–Z scrubber jumps the song list', (tester) async {
    final model = await pumpApp(tester);
    for (var c = 65; c <= 90; c++) {
      for (var n = 1; n <= 3; n++) {
        model.addOrUpdate(
          Song(
            title: '${String.fromCharCode(c)}song $n',
            raw: 'just words',
            artist: n.isEven ? 'Someone' : '',
          ),
        );
      }
    }
    await tester.pumpAndSettle();
    final strip = tester.getRect(find.byType(AlphaScrubber));
    final slot = strip.height / 27; // # A … Z
    Future<void> tapLetter(int i) async {
      await tester.tapAt(Offset(strip.center.dx, strip.top + (i + 0.5) * slot));
      await tester.pumpAndSettle();
    }

    double headerTop(String letter) => tester
        .getTopLeft(
          find.descendant(
            of: find.byType(Sidebar),
            matching: find.text(letter),
          ),
        )
        .dy;
    final listTop = tester.getTopLeft(find.byType(AlphaScrubber)).dy;

    await tapLetter(20); // T
    expect(headerTop('T'), closeTo(listTop, 30));
    await tapLetter(3); // C
    expect(headerTop('C'), closeTo(listTop, 30));

    // Dragging down the strip moves through the letters.
    final g = await tester.startGesture(
      Offset(strip.center.dx, strip.top + 5.5 * slot),
    );
    for (var i = 0; i < 10; i++) {
      await g.moveBy(Offset(0, slot));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(headerTop('O'), closeTo(listTop, 30));
  });

  testWidgets('timer panel copes with a narrow dock and large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final model = await pumpApp(tester);
    tester.view.physicalSize = const Size(1000, 900);
    model.updateSettings((s) => s.presentationMode = true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Timer format'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Bold'), findsOneWidget);
    // Stacked: the style buttons sit below the placement picker.
    expect(
      tester.getTopLeft(find.byTooltip('Bold')).dy,
      greaterThan(tester.getTopLeft(find.byTooltip('Top left')).dy + 40),
    );
  });

  testWidgets('sticky notes: add, type, hover toolbar, move, resize', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    final song = model.currentSong!;
    await tester.tap(find.byTooltip('Add sticky note'));
    await tester.pumpAndSettle();
    expect(find.byType(StickyCard), findsOneWidget);
    expect(model.stickiesOf(song), hasLength(1));

    // Typing is saved (shortly after).
    await tester.enterText(
      find.descendant(
        of: find.byType(StickyCard),
        matching: find.byType(TextField),
      ),
      'Capo 2 for the band',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(model.stickiesOf(song).single.text, 'Capo 2 for the band');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // The toolbar fades in on hover only.
    double toolbarOpacity() => tester
        .widget<AnimatedOpacity>(find.byKey(const Key('sticky-toolbar')))
        .opacity;
    expect(toolbarOpacity(), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final card = tester.getRect(find.byType(StickyCard));
    await mouse.moveTo(card.center + const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(toolbarOpacity(), 1);
    await tester.tap(find.byTooltip('Bold'));
    await tester.pumpAndSettle();
    expect(model.stickiesOf(song).single.bold, isTrue);

    // With text selected, bold applies to just that.
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(StickyCard),
        matching: find.byType(TextField),
      ),
    );
    final c = field.controller!;
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();
    await mouse.moveTo(tester.getRect(find.byType(StickyCard)).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Italic'));
    await tester.pumpAndSettle();
    final runs = model.stickiesOf(song).single.runs ?? const [];
    await tester.pump(const Duration(milliseconds: 500));
    final saved1 = model.stickiesOf(song).single.runs!;
    expect(saved1.first['t'], 'Capo');
    expect(saved1.first['i'], isTrue);
    expect(saved1[1]['i'], isFalse, reason: 'rest not italic ($runs)');
    expect(c.selection.start, 0, reason: 'selection kept');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // Colour from the classic sticky colours.
    await tester.tap(find.byTooltip('Note colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pink'));
    await tester.pumpAndSettle();
    expect(model.stickiesOf(song).single.colour, 0xFFFFB3D1);

    // Moving it hides the toolbar; where it lands is saved.
    final strip = find.byIcon(BrambleIcons.equals).last;
    final g = await tester.startGesture(tester.getCenter(strip));
    await g.moveBy(const Offset(60, 40));
    await tester.pump(const Duration(milliseconds: 300));
    expect(toolbarOpacity(), 0, reason: 'hidden while moving');
    await g.moveBy(const Offset(60, 40));
    await g.up();
    await tester.pumpAndSettle();
    final saved = model.stickiesOf(song).single;
    expect(saved.x, greaterThan(150));

    // Resizing from the top-left corner: bigger, and it moves up/left.
    final before = model.stickiesOf(song).single;
    final grip = find.byTooltip('Drag to resize').first;
    await tester.drag(grip, const Offset(-50, -40));
    await tester.pumpAndSettle();
    final after = model.stickiesOf(song).single;
    expect(after.width, greaterThan(before.width + 20));
    expect(after.height, greaterThan(before.height + 15));
    // The opposite corner stays put.
    expect(after.x + after.width, closeTo(before.x + before.width, 1));
    expect(after.y + after.height, closeTo(before.y + before.height, 1));

    // Notes belong to their song.
    model.addOrUpdate(Song(title: 'Other', raw: 'x'));
    await tester.pumpAndSettle();
    expect(find.byType(StickyCard), findsNothing);
    model.selectSong(song.id);
    await tester.pumpAndSettle();
    expect(find.byType(StickyCard), findsOneWidget);

    // Delete.
    await mouse.moveTo(tester.getRect(find.byType(StickyCard)).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();
    expect(find.byType(StickyCard), findsNothing);
    expect(model.stickiesOf(song), isEmpty);
  });

  testWidgets('autoscroll: time from the song, adjust, type, scrolls', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(
        title: 'Long',
        duration: '0:20',
        raw: [
          '{title: Long}',
          for (var i = 0; i < 80; i++) 'Line [G]number $i of the song',
        ].join('\n'),
      ),
    );
    await tester.pumpAndSettle();
    final song = model.currentSong!;
    expect(song.title, 'Long');

    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is ChordSheet && w.song.id == song.id,
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.pixels, 0);
    expect(model.autoscroll.seconds, 20, reason: "song's duration");
    expect(find.byKey(const Key('autoscroll-time')), findsNothing);

    // One tap starts it, and the time shows above with − / +.
    await tester.tap(find.byTooltip('Autoscroll'));
    await tester.pump();
    expect(model.autoscroll.running, isTrue);
    await tester.pump(const Duration(milliseconds: 250)); // opens out
    expect(find.byKey(const Key('autoscroll-time')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('autoscroll-time')),
        matching: find.text('0:20'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('30 seconds more'));
    await tester.pump();
    expect(model.autoscroll.seconds, 50);
    await tester.tap(find.byTooltip('30 seconds less'));
    await tester.pump();
    expect(model.autoscroll.seconds, 20);
    await tester.enterText(find.byKey(const Key('autoscroll-time')), '0:12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(model.autoscroll.seconds, 12);
    await tester.enterText(find.byKey(const Key('autoscroll-time')), 'soon');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(model.autoscroll.seconds, 12, reason: 'bad input ignored');
    expect(find.text('0:12'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();

    // Runs down the sheet at a steady pace, then stops at the end.
    scroll.position.jumpTo(0);
    model.autoscroll.progress.value = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final end = scroll.position.maxScrollExtent;
    final half = scroll.position.pixels;
    expect(model.autoscroll.progress.value, closeTo(0.5, 0.06));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            ['0:05', '0:06', '0:07'].contains(w.controller.text),
      ),
      findsOneWidget,
      reason: 'live time left',
    );
    // Scrolling by hand: the time left follows the page.
    scroll.position.jumpTo(end * 0.1);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EditableText && ['0:10', '0:11'].contains(w.controller.text),
      ),
      findsOneWidget,
    );
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(model.autoscroll.running, isFalse);
    expect(scroll.position.pixels, greaterThan(half));
    expect(scroll.position.pixels, lessThan(end), reason: 'stops at the song');
    expect(find.byKey(const Key('autoscroll-time')), findsNothing);

    // Starting again at the bottom goes from the top; pause hides the time.
    await tester.tap(find.byTooltip('Autoscroll'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.position.pixels, lessThan(half));
    await tester.tap(find.byTooltip('Pause autoscroll'));
    await tester.pumpAndSettle();
    expect(model.autoscroll.running, isFalse);
    expect(find.byKey(const Key('autoscroll-time')), findsNothing);

    // Hideable in Settings › Quick buttons.
    model.updateSettings((s) => s.showAutoscroll = false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Autoscroll'), findsNothing);
  });

  testWidgets('translate slides: globe in presentation view and structure', (
    tester,
  ) async {
    TranslateDialog.translator = (text, lang) async =>
        text.split('\n').map((l) => l.isEmpty ? l : '<$lang> $l').join('\n');
    addTearDown(() => TranslateDialog.translator = googleTranslate);
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(
        title: 'Grace',
        raw: 'Verse 1:\n[G]Amazing grace\n\nChorus:\n[C]My chains are gone',
      ),
    );
    await tester.pumpAndSettle();
    final slides = model.slides.length;

    model.updateSettings((s) => s.presentationMode = true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Translate slides'));
    await tester.pumpAndSettle();
    expect(find.text('Translate slides'), findsWidgets);

    // Pick Spanish (type to filter), then translate.
    await tester.tap(find.byKey(const Key('translate-language')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('translate-language')),
        matching: find.byType(TextField),
      ),
      'Span',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spanish · Español').last);
    await tester.pumpAndSettle();
    expect(model.settings.translateTo, 'es', reason: 'remembered');
    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pumpAndSettle();

    final song = model.currentSong!;
    expect(ChordPro.sectionNames(song.raw), [
      'Verse 1',
      'Verse 1 (ES)',
      'Chorus',
      'Chorus (ES)',
    ]);
    expect(model.slides.length, slides, reason: 'shown with the original');
    expect(model.slides.first, contains('<es> Amazing grace'));
    expect(find.widgetWithText(FilledButton, 'Update Spanish'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The same globe in Song structure: add French, then remove Spanish.
    model.updateSettings((s) => s.presentationMode = false);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Song structure'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Translate slides'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('translate-language')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('translate-language')),
        matching: find.byType(TextField),
      ),
      'Fren',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('French · Français').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add French'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Spanish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Verse 1 (FR)'), findsWidgets, reason: 'in the editor');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(ChordPro.sectionNames(model.currentSong!.raw), [
      'Verse 1',
      'Verse 1 (FR)',
      'Chorus',
      'Chorus (FR)',
    ]);
    expect(model.slides.length, slides);
    expect(model.slides.first, contains('<fr> Amazing grace'));
  });

  testWidgets('format pane opens on projection in presentation view', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    // The Page / Projection switch at the top of the pane.
    bool projectionTab() {
      final tabs = tester.widget<SegmentedButton>(
        find.byWidgetPredicate(
          (w) =>
              w is SegmentedButton &&
              w.segments.any(
                (seg) =>
                    seg.label is Text && (seg.label as Text).data == 'Page',
              ),
        ),
      );
      return tabs.selected.single.toString().contains('projection');
    }

    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    expect(projectionTab(), isFalse, reason: 'chord sheet: page');
    model.updateSettings((s) => s.presentationMode = true);
    await tester.pumpAndSettle();
    expect(projectionTab(), isTrue, reason: 'follows into presentation');
    model.updateSettings((s) => s.presentationMode = false);
    await tester.pumpAndSettle();
    expect(projectionTab(), isFalse);
  });

  testWidgets('presentation mode: slides run under the toolbar, media '
      'pane along the bottom', (tester) async {
    final model = await pumpApp(tester);
    model.updateSettings((s) => s.presentationMode = true);
    await tester.pumpAndSettle();
    // The slides reach the bottom of the window, with room at the end to
    // scroll the last ones out from behind the floating toolbar.
    final grid = find.descendant(
      of: find.byType(PresentationView),
      matching: find.byType(GridView),
    );
    final bottom = tester.getBottomLeft(grid).dy;
    expect(bottom, closeTo(900, 1));
    final pad = tester.widget<GridView>(grid).padding! as EdgeInsets;
    expect(pad.bottom, greaterThan(50));

    // The media pane: edge to edge along the bottom; the slides stop
    // above it.
    await tester.tap(find.byTooltip('Media'));
    await tester.pumpAndSettle();
    final pane = find.byType(MediaPane);
    expect(pane, findsOneWidget);
    expect(tester.getBottomRight(pane).dy, closeTo(900, 1));
    expect(tester.getBottomRight(pane).dx, closeTo(1400, 1));
    expect(
      tester.getBottomLeft(grid).dy,
      closeTo(tester.getTopLeft(pane).dy, 1),
    );
    await tester.tap(find.byTooltip('Close media'));
    await tester.pumpAndSettle();
    expect(pane, findsNothing);
  });

  for (final desktop in [false, true]) {
    testWidgets(
      'song editor (${desktop ? 'desktop dialog' : 'phone sheet'}): find, '
      '< >, replace and replace all',
      (tester) async {
        if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final model = await pumpApp(tester);
        model.addOrUpdate(
          Song(
            title: 'Find me',
            raw:
                'Verse 1:\n[G]Grace and grace\nAmazing GRACE\n\nChorus:\ngrace',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit song'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(
          find.byWidgetPredicate(
            (w) => w is TextField && w.controller is ChordProController,
          ),
        );
        final c = field.controller! as ChordProController;
        bool shows(String label) => tester
            .widgetList<Text>(find.byType(Text, skipOffstage: false))
            .any((w) => w.data == label);

        // Hidden until asked for.
        expect(find.byKey(const Key('find-text')), findsNothing);
        await tester.tap(find.byTooltip('Find & replace'));
        await tester.pumpAndSettle();

        // Find (any case): 4 matches; < > step through and wrap round.
        await tester.enterText(find.byKey(const Key('find-text')), 'grace');
        await tester.pump();
        expect(c.matches, hasLength(4));
        expect(shows('1 of 4'), isTrue);
        await tester.tap(find.byTooltip('Next match (Enter)'));
        await tester.pump();
        expect(shows('2 of 4'), isTrue);
        await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
        await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
        await tester.pump();
        expect(shows('4 of 4'), isTrue, reason: 'wraps round');

        // Replace: shown when wanted.
        await tester.tap(find.byTooltip('Replace…'));
        await tester.pumpAndSettle();

        // Match case: only the two lower-case "grace"s.
        await tester.tap(find.byTooltip('Match case'));
        await tester.pump();
        expect(c.matches, hasLength(2));
        await tester.tap(find.byTooltip('Match case'));
        await tester.pump();
        expect(c.matches, hasLength(4));

        // Replace the current one, then all the rest.
        expect(shows('1 of 4'), isTrue, reason: 'a new search starts over');
        await tester.enterText(find.byKey(const Key('replace-text')), 'mercy');
        await tester.tap(find.widgetWithText(TextButton, 'Replace'));
        await tester.pump();
        expect(c.text, startsWith('Verse 1:\n[G]mercy and grace'));
        expect(c.matches, hasLength(3));
        expect(shows('1 of 3'), isTrue, reason: 'on to the next');
        await tester.tap(find.widgetWithText(TextButton, 'All'));
        await tester.pump();
        expect(c.text, isNot(contains(RegExp('grace', caseSensitive: false))));
        expect(c.text, contains('Amazing mercy'));
        expect(shows('Replaced 3'), isTrue);

        // Closed, then ⌘F / Ctrl+F: back, with the selection in it.
        await tester.tap(find.byTooltip('Close (Esc)'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('find-text')), findsNothing);
        c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('find-text')))
              .controller!
              .text,
          'Verse',
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('share: this song or the whole setlist, every format', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    final a = Song(title: 'Alpha', raw: 'Verse 1:\n[G]One');
    final b = Song(title: 'Beta', raw: 'Chorus:\n[C]Two');
    model
      ..addOrUpdate(a)
      ..addOrUpdate(b);
    final set = model.createSetlist('Sunday');
    set.entries
      ..add(SetEntry(songId: a.id, title: a.title))
      ..add(SetEntry(songId: b.id, title: b.title));
    model.selectEntry(set, set.entries.first);
    await tester.pumpAndSettle();
    // The PDF preview's printing plugin isn't there in tests.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('net.nfet.printing'),
      (call) async =>
          throw PlatformException(code: 'unavailable', message: 'test'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('net.nfet.printing'),
        null,
      ),
    );
    // The PDF preview's spinner never settles in tests: step the clock.
    Future<void> step() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.tap(find.byTooltip('Share / export'));
    await step();
    expect(find.text('This song'), findsOneWidget);
    await tester.tap(find.text('Whole setlist (2)'));
    await step();
    expect(find.text('Share setlist "Sunday"'), findsOneWidget);

    Future<void> download(String format, String label) async {
      await tester.ensureVisible(find.text(format).first);
      await step();
      await tester.tap(find.text(format).first);
      await step();
      await tester.tap(find.widgetWithText(FilledButton, label));
      await step();
      await tester.tap(find.byTooltip('Share / export'));
      await step();
      await tester.tap(find.text('Whole setlist (2)'));
      await step();
    }

    // Text: one file with every song.
    await tester.tap(find.text('Text').first);
    await step();
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(text, startsWith('Sunday'));
    expect(text, contains('1. Alpha'));
    expect(text, contains('2. Beta'));
    await download('Text', 'Download .txt');
    expect(lastDownload?.$1, 'Sunday.txt');

    await download('ChordPro', 'Download .zip');
    expect(lastDownload?.$1, 'Sunday (ChordPro).zip');
    await download('FreeShow', 'Download .zip');
    expect(lastDownload?.$1, 'Sunday (FreeShow).zip');
    await download('JustChords', 'Download .jcarchive');
    expect(lastDownload?.$1, 'Sunday.jcarchive');

    // PDF: one, or one per song in a zip.
    await tester.tap(find.text('PDF').first);
    await step();
    await tester.tap(find.text('A PDF per song (.zip)'));
    await step();
    await tester.runAsync(() async {
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download PDFs (.zip)'),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await step();
    expect(lastDownload?.$1, 'Sunday (PDFs).zip');

    // The song on its own, as FreeShow.
    await tester.tap(find.byTooltip('Share / export'));
    await step();
    await tester.ensureVisible(find.text('FreeShow').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('FreeShow').first);
    await step();
    await tester.tap(find.widgetWithText(FilledButton, 'Download .show'));
    await step();
    expect(lastDownload?.$1, 'Alpha.show');

    // From the setlist's ⋯ menu it starts on the whole setlist.
    await tester.tap(find.byTooltip('Share / export'));
    await step();
    expect(find.text('Share "Alpha"'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await step();
  });

  testWidgets('sticky notes: smaller than the toolbar, which stays on screen', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Add sticky note'));
    await tester.pumpAndSettle();
    final song = model.currentSong!;
    // Shrink it from the bottom-right corner well below toolbar width.
    final grip = find.byTooltip('Drag to resize').last;
    await tester.drag(grip, const Offset(-200, -80));
    await tester.pumpAndSettle();
    final note = model.stickiesOf(song).single;
    expect(note.width, lessThan(_StickyWidths.toolbar));
    expect(note.width, greaterThanOrEqualTo(110));

    // Move it against the right edge; the toolbar stays on screen.
    final strip = find.byIcon(BrambleIcons.equals).last;
    await tester.drag(strip, const Offset(600, 0));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getRect(find.byType(StickyCard)).center);
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize.width;
    final bar = tester.getRect(find.byTooltip('Delete note'));
    expect(bar.right, lessThanOrEqualTo(screen - 8 + 0.5));
    expect(
      tester.getRect(find.byTooltip('Bold')).left,
      lessThan(tester.getRect(find.byType(StickyCard)).left),
      reason: 'wider than the note',
    );
    // Buttons beyond the note's edges still work.
    await tester.tap(find.byTooltip('Bold'));
    await tester.pumpAndSettle();
    expect(model.stickiesOf(song).single.bold, isTrue);
  });

  testWidgets('sticky notes: pinning lowers it onto the page', (tester) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Add sticky note'));
    await tester.pumpAndSettle();
    // The note's paper (the toolbar is a Material too).
    double elevation() {
      final paper = Color(model.stickiesOf(model.currentSong!).single.colour);
      return tester
          .widget<Material>(
            find.descendant(
              of: find.byType(StickyCard),
              matching: find.byWidgetPredicate(
                (w) => w is Material && w.color == paper,
              ),
            ),
          )
          .elevation;
    }

    expect(elevation(), 5, reason: 'floating: lifted');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getRect(find.byType(StickyCard)).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin to the page (scrolls with it)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final paper = Color(model.stickiesOf(model.currentSong!).single.colour);
    final mid = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byWidgetPredicate(
              (w) => w is Material && w.color == paper,
            ),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(mid.transform.storage[0], lessThan(0.99), reason: 'dips (x scale)');
    expect(elevation(), inExclusiveRange(1, 5), reason: 'shadow shrinking');
    await tester.pumpAndSettle();
    expect(elevation(), 1, reason: 'lowered onto the page');
    expect(model.stickiesOf(model.currentSong!).single.pinned, isTrue);
  });

  testWidgets('find songs online: search every site in the side pane, import', (
    tester,
  ) async {
    final asked = <String>[];
    final oldFetch = fetchPage, oldJson = fetchServerJson;
    addTearDown(() {
      fetchPage = oldFetch;
      fetchServerJson = oldJson;
    });
    fetchPage = (url) async {
      asked.add(url);
      if (url.contains('chordie.com/results')) {
        return '<a href="/chord.pere/x/m.html"><span style="font-size: 18px; color: black;" >Morning Light</span> <span>The Hill</span></a>';
      }
      if (url.contains('chordie.com/chord.pere')) {
        return '<h1 class="titleLeft">Morning Light <a href="/a">The Hill</a></h1>'
            '<div id="song"><div class="textline"> [Verse 1]</div>'
            '<div class="chordline"> The <span>[</span>G<span>]</span>morning</div>';
      }
      if (url.contains('solr.sscdn.co')) {
        return '{"response":{"docs":[{"tipo":"2","txt":"Luz","art":"A","dns":"a","url":"luz"}]}}';
      }
      throw SongSourceError('Offline');
    };
    fetchServerJson = (path) async => [
      {'lang': 'en', 'id': 7, 'title': 'Morning Hymn', 'author': 'Someone'},
    ];

    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('New…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find songs online'));
    await tester.pumpAndSettle();
    expect(find.text('Find songs'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('find-songs')), 'morning');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Morning Light'), findsOneWidget);
    expect(find.text('Morning Hymn'), findsOneWidget, reason: 'Worship Leader');
    expect(find.text('Luz'), findsOneWidget, reason: 'Cifra Club');
    expect(find.text('Offline'), findsWidgets, reason: 'a site that failed');
    expect(
      asked.any((u) => u.contains('ultimate-guitar.com/search.php')),
      isTrue,
    );

    // Open one, preview it, add it.
    await tester.tap(find.text('Morning Light'));
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(
      find.byKey(const Key('found-song-text')),
    );
    expect(text.data, 'Verse 1:\nThe [G]morning');
    final before = model.songs.length;
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    // The full editor opens; nothing is added until Save.
    expect(find.byTooltip('Save'), findsOneWidget); // the song editor
    expect(find.text('Apply'), findsNothing, reason: 'not in the library yet');
    expect(model.songs.length, before);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(model.songs.length, before, reason: 'cancelled: not added');
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(model.songs.length, before + 1);
    final added = model.currentSong!;
    expect(added.title, 'Morning Light');
    expect(added.artist, 'The Hill');
    expect(added.extra['source'], contains('chordie.com'));
    expect(find.text('Added'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to results'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('In your library'), findsOneWidget);

    // The disclaimer, at the end of the pane.
    await tester.scrollUntilVisible(
      find.byKey(const Key('find-disclaimer')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(FindSongsPane),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('find-disclaimer')), findsOneWidget);

    // Paste a song copied from a site.
    await tester.scrollUntilVisible(
      find.text('Paste a song copied from any website'),
      -300,
      scrollable: find
          .descendant(
            of: find.byType(FindSongsPane),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste a song copied from any website'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('paste-song')),
      'River Song - Someone\n\n[Chorus]\nC       G\nWe sing tonight',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('paste-title')))
          .controller!
          .text,
      'River Song',
    );
    await tester.ensureVisible(find.text('Add to library').last);
    await tester.tap(find.text('Add to library').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save'), findsOneWidget); // the song editor
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(model.currentSong!.title, 'River Song');
    expect(model.currentSong!.artist, 'Someone');
    expect(model.currentSong!.raw, 'Chorus:\n[C]We sing [G]tonight');

    // Back to the song list.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Find songs'), findsNothing);
  });

  testWidgets('sidebar top row: menu, search and sidebar button evenly spaced', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    // (Breeze: compact; the others as on phones, with padded tap targets)
    for (final style in [UiStyle.material, UiStyle.breeze, UiStyle.adwaita]) {
      model.updateSettings((s) => s.uiStyle = style);
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byTooltip('Menu').first);
      final search = tester.getRect(find.byType(TextField).first);
      final side = tester.getRect(find.byTooltip('Hide sidebar').first);
      expect(
        search.left - menu.right,
        closeTo(side.left - search.right, .5),
        reason: '${style.name}: same gaps',
      );
      expect(menu.left, closeTo(300 - side.right, .5), reason: '${style.name}: same margins');
      expect(side.center.dy, closeTo(search.center.dy, 1), reason: style.name);
    }
  }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.linux}));

  testWidgets('sidebar button lines up with the top bar in every theme', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    for (final style in UiStyle.values) {
      model.updateSettings((s) => s.uiStyle = style);
      await tester.pumpAndSettle();
      // open: in the sidebar's top row, beside the search, inside the pane
      var side = tester.getRect(find.byType(SidebarIcon));
      final search = tester.getRect(find.byType(TextField).first);
      expect(side.center.dy, closeTo(search.center.dy, 4), reason: style.name);
      expect(side.left, greaterThan(search.right), reason: style.name);
      expect(side.right, lessThan(301), reason: '${style.name}: in the pane');
      // closed: at the song's left, lined up with its top bar
      await tester.tap(find.byTooltip('Hide sidebar'));
      await tester.pumpAndSettle();
      side = tester.getRect(find.byType(SidebarIcon));
      final edit = tester.getRect(find.byType(EditSongIcon));
      expect(side.center.dy, edit.center.dy, reason: style.name);
      expect(side.height, edit.height, reason: style.name);
      expect(side.left, lessThan(60), reason: style.name);
      await tester.tap(find.byTooltip('Show sidebar'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('phone: closing Format turns its button off', (tester) async {
    await pumpApp(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    bool on() => tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byWidgetPredicate(
              (w) => w is MotionIcon && w.motion == IconMotion.format,
            ),
            matching: find.byType(IconButton),
          ),
        )
        .isSelected!;

    // With the panel's own close button…
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    expect(find.byType(FormatPane), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(FormatPane),
        matching: find.byTooltip('Close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FormatPane), findsNothing);
    expect(on(), isFalse);

    // …and by tapping outside it.
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.byType(FormatPane), findsNothing);
    expect(on(), isFalse);
  });

  testWidgets('phone: compact bars with a More menu, finger-sized A–Z', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    // The essentials stay; the rest are in More.
    expect(find.byTooltip('Edit song'), findsOneWidget);
    expect(find.byTooltip('Share / export'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    for (final t in [
      'Share / export',
      'Add sticky note',
      'Song structure',
      'Settings',
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    await tester.tap(find.text('Add sticky note'));
    await tester.pumpAndSettle();
    expect(model.stickiesOf(model.currentSong!), hasLength(1));

    // The top bar keeps clear of the sidebar button.
    final bar = tester.getRect(find.byTooltip('Edit song'));
    final side = tester.getRect(find.byTooltip('Show sidebar'));
    expect(bar.left, greaterThan(side.right - 1));

    // A wider A–Z strip for fingers (in the song list drawer).
    expect(AlphaScrubber.touchWidth, greaterThanOrEqualTo(40));
  });

  testWidgets('sticky notes: pin to the page scrolls with it, unpin floats', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    // Long enough that the sheet scrolls.
    model.addOrUpdate(
      Song(
        title: 'Long',
        raw: [
          '{title: Long}',
          for (var i = 0; i < 60; i++) 'Line [G]number $i of the song',
        ].join('\n'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add sticky note'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    // Into the middle of the page (at its edge, pinning keeps it inside).
    await tester.drag(
      find.byIcon(BrambleIcons.equals).last,
      const Offset(-500, 60),
    );
    await tester.pumpAndSettle();
    final floating = tester.getTopLeft(find.byType(StickyCard));
    await mouse.moveTo(tester.getRect(find.byType(StickyCard)).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin to the page (scrolls with it)'));
    await tester.pumpAndSettle();

    expect(model.stickiesOf(model.currentSong!).single.pinned, isTrue);
    final inSheet = find.descendant(
      of: find.byType(ChordSheet),
      matching: find.byType(StickyCard),
    );
    expect(inSheet, findsOneWidget, reason: 'now part of the page');
    final pinnedAt = tester.getTopLeft(inSheet);
    expect(pinnedAt.dx, closeTo(floating.dx, 1), reason: 'stays put');
    expect(pinnedAt.dy, closeTo(floating.dy, 1));

    // Scrolling the page carries it along.
    final scroll = tester.state<ScrollableState>(
      find.ancestor(of: inSheet, matching: find.byType(Scrollable)).first,
    );
    scroll.position.jumpTo(120);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(inSheet).dy, closeTo(pinnedAt.dy - 120, 1));

    // Unpin: floats again, where it is now.
    final now = tester.getTopLeft(inSheet);
    await mouse.moveTo(tester.getRect(inSheet).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unpin (float over the app)'));
    await tester.pumpAndSettle();
    expect(model.stickiesOf(model.currentSong!).single.pinned, isFalse);
    expect(inSheet, findsNothing);
    final back = tester.getTopLeft(find.byType(StickyCard));
    expect(back.dy, closeTo(now.dy, 1));
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(StickyCard)).dy, closeTo(back.dy, 1));
  });

  testWidgets('group by letter and filter by key', (tester) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(Song(title: 'Blessed Be', raw: '[A]Blessed [E]be [A]x'));
    model.addOrUpdate(
      Song(title: 'Agnus Dei', raw: '[A]Alle [D]lu [E]ia [A]x'),
    );
    model.addOrUpdate(
      Song(title: 'Cornerstone', raw: '[C]My [F]hope [G]is [C]x'),
    );
    await tester.pumpAndSettle();

    // Grouped by letter by default.
    // Headers are the only plain "B" text (no song is in the key of B).
    expect(find.text('B'), findsOneWidget);
    // "A" appears as a header, the key of two songs, and the open song's
    // key beside its title.
    expect(find.text('A'), findsNWidgets(4));

    await tester.tap(find.byTooltip('Sort & filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Key'));
    await tester.pumpAndSettle();
    expect(find.text('All keys (4)'), findsOneWidget);
    expect(find.text('A (2)'), findsOneWidget);
    await tester.tap(find.text('C (1)'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Cornerstone'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Agnus Dei'), findsNothing);
  });

  testWidgets('song structure editor with a key change', (tester) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Song structure'));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Verse 1:')), findsOneWidget);
    expect(inDialog(find.text('Refrain:')), findsOneWidget);

    await tester.tap(inDialog(find.text('Refrain:')));
    await tester.tap(inDialog(find.text('Modulation')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Verse 1:')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('G (0)')), findsOneWidget);
    await tester.tap(find.byTooltip('Up a semitone'));
    await tester.tap(find.byTooltip('Up a semitone'));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('A (+2)')), findsOneWidget);
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    final structure = model.currentSong!.structure;
    expect(structure.map((i) => i.isModulation ? '+${i.semitones}' : i.name), [
      'Refrain',
      '+2',
      'Verse 1',
    ]);
    expect(model.slides.first, startsWith("'Twas grace"));
    expect(find.text('Key change → A'), findsOneWidget);
    // Verse 1 after the key change: Em becomes F#m.
    expect(chordText('F#m '), findsWidgets);
    expect(chordText('Em '), findsNothing);

    // Tapping a section doesn't throw (it scrolls it to the centre).
    await tester.tap(find.text('Verse 1:'));
    await tester.pumpAndSettle();
  });

  testWidgets('link sections: one slide, dragged together', (tester) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(
        title: 'Grâce',
        raw:
            'Verse 1:\nAmazing grace\nHow sweet the sound\n\n'
            'Couplet 1:\nGrâce infinie\nQuel doux son\n\n'
            'Chorus:\nMy chains are gone',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Song structure'));
    await tester.pumpAndSettle();
    for (final name in ['Verse 1:', 'Couplet 1:', 'Chorus:']) {
      await tester.tap(inDialog(find.text(name)));
      await tester.pumpAndSettle();
    }
    // Broken chains between the three; link the first two.
    const link = 'Link with the next section (one slide)';
    expect(find.byTooltip(link), findsNWidgets(2));
    await tester.tap(find.byTooltip(link).first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unlink (separate slides)'), findsOneWidget);

    // Drag Chorus above the linked pair: the pair moves as one.
    final handles = find.byIcon(BrambleIcons.equals);
    final g = await tester.startGesture(tester.getCenter(handles.last));
    await tester.pump(kLongPressTimeout);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, -25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    final structure = model.currentSong!.structure;
    expect(structure.map((i) => '${i.name}${i.linked ? '+' : ''}'), [
      'Chorus',
      'Verse 1+',
      'Couplet 1',
    ]);
    // Two slides: the chorus, then English and French together.
    expect(model.slides.length, 2);
    expect(model.slides[1], contains('Amazing grace'));
    expect(model.slides[1], contains('Grâce infinie'));

    // Unlink again: three slides.
    await tester.tap(find.byTooltip('Song structure'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unlink (separate slides)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(model.slides.length, 3);
  });

  testWidgets('edit a section from the structure editor', (tester) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Song structure'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Refrain:')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit section'));
    await tester.pumpAndSettle();
    expect(find.text('Edit section'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Refrain:\nNew refrain words',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(model.currentSong!.raw, contains('New refrain words'));
  });

  testWidgets('metronome follows the song tempo and clicks', (tester) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(title: 'Slow', raw: '[C]x', tempo: '60', timeSignature: '3/4'),
    );
    await tester.pumpAndSettle();
    expect(model.metronome.bpm, 60);
    expect(model.metronome.beatsPerBar, 3);
    // Just the icon until it's started.
    expect(find.byType(MetronomeIcon), findsOneWidget);
    expect(find.byKey(const Key('metronome-bpm')), findsNothing);
    expect(find.byTooltip('Metronome settings'), findsNothing);
    final before = clicksPlayed;
    await tester.tap(find.byTooltip('Start metronome'));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(clicksPlayed - before, 3, reason: 'click at 0s, 1s, 2s');

    // Running: − · BPM (typed) · + and the settings open out.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('metronome-bpm')), findsOneWidget);
    await tester.tap(find.byTooltip('Faster'));
    await tester.pump();
    expect(model.metronome.bpm, 61);
    await tester.enterText(find.byKey(const Key('metronome-bpm')), '72');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(model.metronome.bpm, 72);
    FocusManager.instance.primaryFocus?.unfocus();

    await tester.tap(find.byTooltip('Stop metronome'));
    await tester.pumpAndSettle();
    expect(model.metronome.running, isFalse);
    expect(find.byKey(const Key('metronome-bpm')), findsNothing);
  });

  testWidgets('themes, plain music sheet, sidebar toggle', (tester) async {
    final model = await pumpApp(tester);
    model.updateSettings((s) => s.themeId = 'crimson');
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, isNot(Colors.indigo));

    model.updateSettings((s) => s.themeMusic = false);
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: find.byType(ChordSheet), matching: find.byType(Theme)),
      findsWidgets,
    );

    expect(find.byType(TextField), findsWidgets);
    await tester.tap(find.byTooltip('Hide sidebar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sort & filter').hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('Show sidebar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sort & filter').hitTestable(), findsOneWidget);

    // Floating sidebar hides after picking a song.
    model.updateSettings((s) => s.floatingSidebar = true);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Amazing Grace'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sort & filter').hitTestable(), findsNothing);
  });

  testWidgets('chord colour and no caps button for chords', (tester) async {
    final model = await pumpApp(tester);
    model.updateFormat((f) => f[SheetElement.chords].color = 'red');
    await tester.pumpAndSettle();
    final chord = tester.widget<ChordLine>(chordText('Em ').first);
    expect(chord.chordStyle.color, namedColors['red']);

    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    // Title has an all-caps button, Chords does not.
    Finder card(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ElementEditor',
      ),
    );
    final paneScroll = find
        .descendant(
          of: find.byType(FormatPane),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Title'),
      200,
      scrollable: paneScroll,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: card('Title'), matching: find.byTooltip('All caps')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Notes'),
      200,
      scrollable: paneScroll,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: card('Chords').last,
        matching: find.byTooltip('All caps'),
      ),
      findsNothing,
    );
  });

  testWidgets('edit button in the top bar opens the editor', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Edit song'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save'), findsOneWidget); // the song editor
  });

  testWidgets('every desktop style renders, light and dark', (tester) async {
    final model = await pumpApp(tester);
    for (final style in UiStyle.values) {
      for (final mode in [ThemeModeSetting.light, ThemeModeSetting.dark]) {
        model.updateSettings((s) {
          s.uiStyle = style;
          s.mode = mode;
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$style $mode');
        expect(find.text('Amazing Grace'), findsWidgets);
      }
    }
    // Breeze: square-ish toolbars and KDE greys.
    model.updateSettings((s) {
      s.uiStyle = UiStyle.breeze;
      s.mode = ThemeModeSetting.light;
    });
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.surface, const Color(0xFFEFF0F1));
    expect(
      app.theme!.extension<StyleExtras>()!.toolbarShape,
      isNot(isA<StadiumBorder>()),
    );

    // Settings dialog shows all styles.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Settings…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings…'));
    await tester.pumpAndSettle();
    for (final style in UiStyle.values) {
      expect(find.text(style.label), findsWidgets);
    }
    await tester.tap(find.text('Yaru'));
    await tester.pumpAndSettle();
    expect(model.settings.uiStyle, UiStyle.yaru);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview appears while projecting; button hides it', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    expect(find.byTooltip('Show preview'), findsNothing);
    expect(find.byType(FittingSlide), findsNothing);
    (model.sync as dynamic).receive({'type': 'hello'});
    await tester.pumpAndSettle();
    expect(find.byType(FittingSlide), findsOneWidget, reason: 'auto preview');
    await tester.tap(find.byTooltip('Hide preview'));
    await tester.pumpAndSettle();
    expect(find.byType(FittingSlide), findsNothing);
    await tester.tap(find.byTooltip('Show preview'));
    await tester.pumpAndSettle();
    expect(find.byType(FittingSlide), findsOneWidget);
    (model.sync as dynamic).receive({'type': 'bye'});
    await tester.pumpAndSettle();
    expect(find.byType(FittingSlide), findsNothing);
    expect(find.byTooltip('Show preview'), findsNothing);
  });

  testWidgets('keys and pedal keys move the selected part', (tester) async {
    final model = await pumpApp(tester);
    expect(model.slides.length, 2);
    expect(model.selectedPart, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(model.index, 1);
    expect(model.currentSlide, startsWith("'Twas grace"));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(model.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(model.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(model.index, 0);
    // The projector gets told about each move.
    expect(
      (model.sync as dynamic).sent.where((m) => m['type'] == 'index').length,
      greaterThanOrEqualTo(4),
    );

    // Tapping a part selects (and projects) it.
    await tester.tap(find.text('Refrain:'));
    await tester.pumpAndSettle();
    expect(model.index, 1);
  });

  testWidgets('desktop styles use a header bar and stock colours', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    expect(model.settings.themeId, defaultThemeId);
    model.updateSettings((s) {
      s.uiStyle = UiStyle.yaru;
      s.mode = ThemeModeSetting.light;
    });
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, const Color(0xFFE95420));
    expect(app.theme!.extension<StyleExtras>()!.headerBar, isTrue);
    // Title shown in the header bar.
    expect(find.text('Amazing Grace'), findsWidgets);
    // Toolbar buttons still reachable.
    expect(find.byTooltip('Edit song'), findsOneWidget);
    expect(find.byTooltip('Start metronome'), findsOneWidget);

    model.updateSettings((s) => s.uiStyle = UiStyle.breeze);
    await tester.pumpAndSettle();
    final breeze = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(breeze.theme!.colorScheme.primary, const Color(0xFF3DAEE9));
    expect(breeze.theme!.colorScheme.surface, const Color(0xFFEFF0F1));
  });

  testWidgets('moving between parts does not rebuild the whole window', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    var rebuilds = 0;
    model.addListener(() => rebuilds++);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(model.index, 1);
    expect(rebuilds, 0, reason: 'only the selection signal changes');
    expect(model.selection.value, 1);
  });

  testWidgets('colour rows end with + that opens the colour picker', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Title'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(FormatPane),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final plus = find.byTooltip('Custom colour…', skipOffstage: false).first;
    await tester.ensureVisible(plus);
    await tester.pumpAndSettle();
    // The swatches sit in one horizontally scrolling row.
    expect(
      find.ancestor(
        of: plus,
        matching: find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(plus);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), '#123456');
    await tester.pump();
    await tester.tap(find.byTooltip('Use colour'));
    await tester.pumpAndSettle();
    final title = model.format[SheetElement.title];
    expect(title.color, '#123456');
    expect(title.textStyle().color, const Color(0xFF123456));
    expect(find.byTooltip('Custom #123456'), findsOneWidget);

    // Custom highlight survives a save / load.
    title.highlightHex = '#FF0000';
    final copy = ElementStyle(size: 1)..updateFrom(title.toJson());
    expect(
      copy.highlightColor,
      const Color(0xFFFF0000).withValues(alpha: 0.45),
    );
  });

  testWidgets('sidebar: the song follows it, its right side stays put', (
    tester,
  ) async {
    await pumpApp(tester);
    final sheet = find.byType(SongSwipe);
    for (final tooltip in ['Hide sidebar', 'Show sidebar']) {
      final right = tester.getRect(sheet).right;
      final lefts = <double>[tester.getRect(sheet).left];
      await tester.tap(find.byTooltip(tooltip));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final r = tester.getRect(sheet);
        expect(r.right, right, reason: 'right edge stays put ($tooltip)');
        lefts.add(r.left);
      }
      await tester.pumpAndSettle();
      // The left edge glides (many in-between positions), one way only.
      expect(lefts.toSet().length, greaterThan(8), reason: tooltip);
      final opening = tooltip == 'Show sidebar';
      for (var i = 1; i < lefts.length; i++) {
        expect(
          opening ? lefts[i] >= lefts[i - 1] : lefts[i] <= lefts[i - 1],
          isTrue,
          reason: '$tooltip moves smoothly one way',
        );
      }
    }
    expect(find.byTooltip('Hide sidebar'), findsOneWidget);
  });

  testWidgets('arrow keys move the slides only, even after clicking a list', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(Song(title: 'Be Thou My Vision', raw: '[D]Be thou'));
    await tester.pumpAndSettle();
    // Click a song in the list (desktop apps give it the keyboard).
    await tester.tap(
      find
          .descendant(
            of: find.byType(Sidebar),
            matching: find.text('Amazing Grace'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final song = model.currentSong!.title;
    expect(model.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(model.index, 1, reason: 'next slide');
    expect(model.currentSong!.title, song, reason: 'same song');
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    expect(
      focused is ListTile || focused is InkWell,
      isFalse,
      reason: 'no list row holds the keyboard',
    );
  });

  testWidgets('arrow keys never hop the keyboard between controls (Linux)', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(
      Song(
        title: 'Five Parts',
        raw: [for (var i = 1; i <= 5; i++) '{c: Verse $i}\n[G]line $i']
            .join('\n\n'),
      ),
    );
    await tester.pumpAndSettle();
    final song = model.currentSong!.title;
    for (var i = 1; i <= 4; i++) {
      await tester.sendKeyEvent(
        LogicalKeyboardKey.arrowDown,
        platform: 'linux',
      );
      await tester.pumpAndSettle();
      expect(model.index, i, reason: 'one slide per press');
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        focused?.findAncestorWidgetOfExactType<InkWell>() == null &&
            focused?.findAncestorWidgetOfExactType<EditableText>() == null,
        isTrue,
        reason: 'press $i: no button, row or search box took the keyboard',
      );
    }
    expect(model.currentSong!.title, song);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('search box is as tall as the buttons, in every style', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    final search = find.byType(TextField).first;
    for (final style in UiStyle.values) {
      model.updateSettings((s) => s.uiStyle = style);
      await tester.pumpAndSettle();
      final button = tester.getSize(find.byTooltip('Menu')).height;
      expect(tester.getSize(search).height, button, reason: style.name);
      await tester.enterText(search, 'grace');
      await tester.pumpAndSettle();
      expect(tester.getSize(search).height, button, reason: style.name);
      expect(tester.takeException(), isNull, reason: 'clear button fits');
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('swipe between songs on desktop (trackpad pan gesture)', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(Song(title: 'Be Thou My Vision', raw: '[D]Be thou'));
    model.selectSong(
      model.songs.firstWhere((s) => s.title == 'Amazing Grace').id,
    );
    await tester.pumpAndSettle();
    final at = tester.getCenter(find.byType(SongSwipe));
    final pad = TestPointer(7, PointerDeviceKind.trackpad);

    /// Two fingers moving by [moves], then lifting.
    Future<void> swipe(List<double> moves) async {
      await tester.sendEventToBinding(pad.panZoomStart(at));
      var pan = Offset.zero;
      for (final dx in moves) {
        pan += Offset(dx, 0);
        await tester.sendEventToBinding(pad.panZoomUpdate(at, pan: pan));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
    }

    // A short pull, then lifting: springs back.
    await swipe([-10, -10, -10]);
    expect(model.currentSong!.title, 'Amazing Grace');
    // Far enough to the left: the next song.
    await swipe(List.filled(10, -25));
    expect(model.currentSong!.title, 'Be Thou My Vision');
    // And back again to the right.
    await swipe(List.filled(10, 25));
    expect(model.currentSong!.title, 'Amazing Grace');
  });

  testWidgets('swipe between songs: threshold, turn back, trackpad', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.addOrUpdate(Song(title: 'Be Thou My Vision', raw: '[D]Be thou'));
    model.addOrUpdate(Song(title: 'Cornerstone', raw: '[C]My hope'));
    model.selectSong(
      model.songs.firstWhere((s) => s.title == 'Amazing Grace').id,
    );
    await tester.pumpAndSettle();
    final sheet = find.byType(SongSwipe);
    String title() => model.currentSong!.title;
    // The next song is already drawn beside the current one.
    expect(find.text('Be Thou My Vision', skipOffstage: false), findsWidgets);

    /// Finger drag through [moves]; returns before lifting.
    Future<TestGesture> drag(List<double> moves) async {
      final g = await tester.startGesture(tester.getCenter(sheet));
      for (final dx in moves) {
        await g.moveBy(Offset(dx, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return g;
    }

    // Stopping short and letting go springs back.
    var g = await drag([-10, -10, -10, -10, -10]);
    await g.up();
    await tester.pumpAndSettle();
    expect(title(), 'Amazing Grace');

    // Reaching the threshold switches at once, before letting go.
    g = await drag(List.filled(8, -20));
    await tester.pumpAndSettle();
    expect(title(), 'Be Thou My Vision');
    await g.up();
    await tester.pumpAndSettle();
    expect(title(), 'Be Thou My Vision', reason: 'exactly one switch');

    // Changing your mind: turning back springs back.
    g = await drag([20, 20, 15, -12, -12]);
    await tester.pumpAndSettle();
    await g.up();
    await tester.pumpAndSettle();
    expect(title(), 'Be Thou My Vision');

    // Nothing before the first song: pulling right never switches.
    g = await drag(List.filled(8, 20));
    await tester.pumpAndSettle();
    expect(title(), 'Amazing Grace');
    await g.up();
    g = await drag(List.filled(8, 20));
    await g.up();
    await tester.pumpAndSettle();
    expect(title(), 'Amazing Grace');

    // Two-finger trackpad swipe (a stream of sideways scroll events).
    final at = tester.getCenter(sheet);
    Future<void> wheel(double dx) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: at,
          scrollDelta: Offset(dx, 0),
          kind: PointerDeviceKind.trackpad,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    // A short pull, then a pause: gives up.
    for (final dx in <double>[10, 10, 10]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(title(), 'Amazing Grace');

    // Far enough: switches straight away; the rest of the gesture (and
    // macOS coasting) is ignored.
    for (final dx in <double>[20, 26, 22, 30, 24, 28, 22, 18, 12, 8, 4]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(title(), 'Be Thou My Vision');

    // Quick succession on the trackpad: a new swipe straight out of the
    // last one's coasting (no pause) still counts.
    for (final dx in <double>[
      20, 26, 22, 30, 24, // switches
      20, 14, 9, 6, 4, 3, // coasting (ignored)
      6, 12, 20, 26, 22, 28, // new swipe → switches again
    ]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(title(), 'Cornerstone');
    // Lifting after a switch: coasting that jumps up a little and fades
    // never starts another pull (no extra move, no bounce).
    var pulls = SongSwipe.debugPulls;
    for (final dx in <double>[-20, -26, -22, -30, -24, -4, -10, -8, -6, -4]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(title(), 'Be Thou My Vision');
    expect(SongSwipe.debugPulls, pulls + 1);

    // Stopping short, then lifting with a little jitter: just one pull.
    pulls = SongSwipe.debugPulls;
    for (final dx in <double>[10, 10, 10]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 120)); // gives up
    for (final dx in <double>[2, 1, 2, 1]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(SongSwipe.debugPulls, pulls + 1);
    expect(title(), 'Be Thou My Vision');
    for (final dx in <double>[20, 26, 22, 30, 24]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(title(), 'Cornerstone');

    // A swipe that switches while still speeding up: one song only.
    // (Uneven finger speed after the switch: 30 → 18 → 25 → 40.)
    for (final dx in <double>[-20, -26, -22, -30, -24, -18, -25, -40, -30]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(title(), 'Be Thou My Vision');
    for (final dx in <double>[20, 26, 22, 30, 24]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(title(), 'Cornerstone');

    // …and one long swipe still only switches once.
    for (final dx in <double>[-20, -26, -22, -30, -24, -28, -22, -26, -24]) {
      await wheel(dx);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(title(), 'Be Thou My Vision');

    // Quick succession by touch.
    g = await drag(List.filled(8, -20));
    await g.up();
    await tester.pumpAndSettle();
    expect(title(), 'Cornerstone');
  });

  testWidgets('selection style setting and equal bottom buttons', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    // Settings (top right): selected part style and quick buttons.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Highlight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlight'));
    await tester.pumpAndSettle();
    expect(model.format.selectionStyle, SelectionStyle.highlight);
    expect(find.text('Metronome'), findsNothing, reason: 'collapsed');
    await tester.ensureVisible(find.text('Quick buttons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick buttons'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Metronome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metronome'));
    await tester.pumpAndSettle();
    expect(model.settings.showMetronome, isFalse);
    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start metronome'), findsNothing);
    model.updateSettings((s) => s.showMetronome = true);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start metronome'), findsOneWidget);

    final plus = tester.getSize(
      find.ancestor(
        of: find.byIcon(BrambleIcons.plus).last,
        matching: find.byType(FilledButton),
      ),
    );
    final setlists = tester.getSize(
      find.ancestor(
        of: find.text('Setlists'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(plus, setlists);
  });

  testWidgets('share dialog downloads each format', (tester) async {
    await pumpApp(tester);
    for (final (label, ext) in [('ChordPro', '.cho'), ('Text', '.txt')]) {
      await tester.tap(find.byTooltip('Share / export'));
      // The PDF preview's spinner never settles in tests, so pump frames.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Download'));
      await tester.pumpAndSettle();
      expect(lastDownload!.$1, 'Amazing Grace$ext');
    }
  });

  testWidgets('preview is a scale model of the projector window', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    (model.sync as dynamic).receive({'type': 'hello', 'w': 1920, 'h': 1080});
    await tester.pumpAndSettle();
    expect(model.projectorSize, const Size(1920, 1080));
    // The slide is laid out at the projector's real size, then scaled down.
    final slideBox = tester.getSize(find.byType(FittingSlide));
    expect(slideBox, const Size(1920, 1080));
    final shown = tester.getRect(
      find
          .ancestor(of: find.byType(FittedBox), matching: find.byType(Material))
          .first,
    );
    expect(shown.width / shown.height, closeTo(16 / 9, 0.02));

    // A tall (portrait) projector window changes the preview shape.
    (model.sync as dynamic).receive({'type': 'alive', 'w': 1080, 'h': 1920});
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(FittingSlide)), const Size(1080, 1920));
    (model.sync as dynamic).receive({'type': 'bye'});
    await tester.pumpAndSettle();
  });

  testWidgets('floating preview: drag, throw, snap to edges, resize', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    (model.sync as dynamic).receive({'type': 'hello', 'w': 1920, 'h': 1080});
    await tester.pumpAndSettle();
    Finder panel() => find
        .ancestor(of: find.byType(FittedBox), matching: find.byType(Material))
        .first;
    final start = tester.getRect(panel());

    // A slow drag follows the pointer (plus a little glide).
    await tester.timedDrag(
      panel(),
      const Offset(300, -200),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    final moved = tester.getRect(panel());
    expect(moved.left, closeTo(start.left + 300, 60));

    // A quick throw glides on further than the drag itself.
    await tester.fling(panel(), const Offset(80, 0), 1500);
    await tester.pumpAndSettle();
    expect(tester.getRect(panel()).left, greaterThan(moved.left + 120));

    // Resting near the bottom edge: snaps flush to it.
    final area = tester.getRect(find.byType(FloatingPanel));
    final r = tester.getRect(panel());
    await tester.timedDrag(
      panel(),
      Offset(0, area.bottom - 16 - 25 - r.bottom),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(panel()).bottom, closeTo(area.bottom - 16, 1.5));

    // The corner grip resizes it and keeps the projector's shape. (Grab
    // it from the middle first so it has room to grow.)
    await tester.timedDrag(
      panel(),
      const Offset(-200, -200),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    final before = tester.getSize(panel());
    await tester.drag(find.byTooltip('Drag to resize'), const Offset(80, 45));
    await tester.pumpAndSettle();
    final after = tester.getSize(panel());
    expect(after.width, greaterThan(before.width + 40));
    expect(after.width / after.height, closeTo(16 / 9, 0.01));

    // Remembered when it comes back.
    final kept = tester.getRect(panel());
    (model.sync as dynamic).receive({'type': 'bye'});
    await tester.pumpAndSettle();
    (model.sync as dynamic).receive({'type': 'hello', 'w': 1920, 'h': 1080});
    await tester.pumpAndSettle();
    expect(tester.getRect(panel()), kept);
    (model.sync as dynamic).receive({'type': 'bye'});
    await tester.pumpAndSettle();
  });

  testWidgets('scrolling the chord shortcut bar never switches tabs', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Edit song'));
    await tester.pumpAndSettle();
    final bar = find.text('[chord]');
    expect(bar, findsOneWidget);
    expect(tester.getSize(find.byType(ListView).last).height, 48); // (room for the chips' shadows)
    final chip = tester.getSize(
      find.ancestor(
        of: find.text('[chord]'),
        matching: find.byType(ActionChip),
      ),
    );
    expect(chip.height, greaterThanOrEqualTo(38), reason: 'touch-sized');
    final hash = tester.getSize(
      find.ancestor(of: find.text('#'), matching: find.byType(ActionChip)),
    );
    expect(hash.width, greaterThanOrEqualTo(44), reason: 'touch-sized');

    final at = tester.getCenter(bar);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(400, 0)));
      await tester.pumpAndSettle();
    }
    // (The bar itself: '[chord]' may have scrolled out of it by now.)
    final chips = find.byType(ListView).last;
    final tabs = DefaultTabController.of(tester.element(chips));
    expect(tabs.index, 0, reason: 'still on the ChordPro tab');
    expect(find.text('Melody (ABC)'), findsOneWidget);
  });

  testWidgets('saved chord beats show on the open sheet', (tester) async {
    final model = await pumpApp(tester);
    model.updateFormat((f) => f.chordBeats = true);
    await tester.pumpAndSettle();
    final song = model.currentSong!.copy();
    setChordBeats(song, {'verse 1#0': 2});
    model.addOrUpdate(song);
    await tester.pumpAndSettle();
    final sheet = tester.widget<ChordSheet>(find.byType(ChordSheet).first);
    expect(chordBeatsOf(sheet.song), {'verse 1#0': 2});
  });

  testWidgets('libraries: a view in the side pane', (tester) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libraries…'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('My Library'), findsOneWidget);
    await tester.tap(find.text('New library'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'French');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(model.currentLibrary.name, 'French');
    expect(model.songs, isEmpty);
    // Back to the first library from the side pane.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libraries…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Library'));
    await tester.pumpAndSettle();
    expect(model.currentLibrary.name, 'My Library');
    expect(model.songs, isNotEmpty);
  });

  testWidgets('customize the toolbar: reorder, put away in ⋯, reset', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Customize toolbar'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Customize toolbar'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolbarEditor), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // Share goes to the ⋯ menu: gone from the bar, in the menu.
    await tester.tap(find.byTooltip('Move to the ⋯ menu').first);
    await tester.pumpAndSettle();
    expect(model.settings.toolbarMore, ['share']);
    expect(find.byTooltip('Share / export'), findsNothing);
    // The toolbar's ⋯ (the rightmost "More").
    final more = find.byTooltip('More').evaluate().toList()
      ..sort(
        (a, b) => tester
            .getCenter(find.byElementPredicate((e) => e == a))
            .dx
            .compareTo(
              tester.getCenter(find.byElementPredicate((e) => e == b)).dx,
            ),
      );
    await tester.tap(find.byElementPredicate((e) => e == more.last));
    await tester.pumpAndSettle();
    expect(find.text('Share / export'), findsWidgets);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Drag Settings (last in the bar) to the top.
    final settingsRow = find.ancestor(
      of: find.text('Settings').last,
      matching: find.byType(ReorderableDelayedDragStartListener),
    );
    final handle = find.descendant(
      of: settingsRow,
      matching: find.byIcon(BrambleIcons.dotsSixVertical),
    );
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout);
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, -50));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(model.settings.toolbarBar!.first, 'settings');

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(model.settings.toolbarBar, isNull);
    expect(find.byTooltip('Share / export'), findsOneWidget);
  });

  testWidgets('tuner floats; full screen and back', (tester) async {
    await pumpApp(tester);
    // (The tuner keeps animating: wait a set time instead of settling.)
    await tester.tap(find.byTooltip('Tuner'));
    await tester.pump(const Duration(milliseconds: 800));
    final panel = find.byType(TunerPanel);
    expect(panel, findsOneWidget);
    final small = tester.getRect(panel);
    expect(small.width, lessThan(500));
    // Dragged by its title bar, it moves.
    await tester.drag(find.text('Tuner').last, const Offset(-300, -200));
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getRect(panel).left, lessThan(small.left - 100));

    await tester.tap(find.byTooltip('Full screen'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getRect(panel).width, greaterThan(1300));
    // The tuner itself grows (capped), and covers the sidebar button.
    // (The tuner face's FittedBox: the title's tabs have one too.)
    final face = find
        .descendant(of: panel, matching: find.byType(FittedBox))
        .last;
    expect(tester.getRect(face).width, greaterThan(600));
    final under = tester.hitTestOnBinding(
      tester.getCenter(find.byType(SidebarIcon)),
    );
    expect(
      under.path.any(
        (e) =>
            e.target is RenderObject &&
            (e.target as RenderObject).debugCreator.toString().contains(
              'SidebarIcon',
            ),
      ),
      isFalse,
    );
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getRect(panel).width, lessThan(500));
    await tester.tap(find.byTooltip('Close tuner'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(panel, findsNothing);
  });

  testWidgets('Band Sync: a view in the side pane', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Band Sync…'));
    await tester.pump(); // (menu actions run once the menu has closed)
    // (Looking for sessions spins for a few seconds.)
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Available sessions'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to songs'));
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Available sessions'), findsNothing);
  });

  testWidgets('chord diagrams: strip, play, chord buttons, choose a shape', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    model.updateSettings((s) => s.showChordDiagrams = true);
    await tester.pumpAndSettle();
    // Amazing Grace: Em, D, G.
    final strip = find.byType(ChordStrip);
    expect(strip, findsOneWidget);
    final diagrams = find.descendant(
      of: strip,
      matching: find.byType(ChordDiagram),
    );
    expect(diagrams, findsNWidgets(3));
    final before = soundsPlayed;
    await tester.tap(diagrams.first);
    await tester.pump();
    expect(soundsPlayed, before + 1);

    // Fold the strip away.
    await tester.tap(find.byTooltip('Hide chord diagrams'));
    await tester.pumpAndSettle();
    expect(diagrams, findsNothing);
    expect(model.settings.diagramsCollapsed, isTrue);

    // Tap a chord in the song: its diagrams (the sheet's layout and the
    // selected part don't change).
    model.updateSettings((s) => s.tapChords = true);
    await tester.pumpAndSettle();
    final line = find.byWidgetPredicate(
      (w) => w is ChordLine && w.pieces.first.chord.startsWith('Em'),
    );
    expect(line, findsWidgets);
    final selectedBefore = model.index;
    final chordAt = tester.getTopLeft(line.first) + const Offset(6, 6);
    await tester.tapAt(chordAt);
    await tester.pumpAndSettle();
    expect(model.index, selectedBefore);
    // A small popover just above the chord, with its shapes.
    final shapes = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
      matching: find.byType(ChordDiagram),
    );
    expect(shapes.evaluate().length, greaterThan(1));
    final pop = tester.getRect(shapes.first);
    expect(pop.bottom, lessThanOrEqualTo(chordAt.dy));
    // Tapping a diagram plays it (and uses it); the popover stays.
    final sounds = soundsPlayed;
    await tester.tap(shapes.at(1));
    await tester.pumpAndSettle();
    expect(soundsPlayed, sounds + 1);
    expect(model.settings.chordPrefs, hasLength(1));
    expect(shapes, findsWidgets);
    // Anywhere else closes it.
    await tester.tapAt(const Offset(700, 850));
    await tester.pumpAndSettle();
    expect(shapes, findsNothing);
  });

  testWidgets('chord library and editor: make your own shape', (tester) async {
    final model = await pumpApp(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools')); // a submenu now
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chord Library…'));
    await tester.pumpAndSettle();
    final grid = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(ChordDiagram),
    );
    expect(grid.evaluate().length, greaterThan(3)); // C major shapes
    await tester.tap(find.byTooltip('Make your own shape'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cadd9');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(model.settings.customChords.single.suffix, 'add9');
    expect(find.text('My chords (1)'), findsOneWidget);
  });

  testWidgets('tags scroll with two fingers, sideways or up and down', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    for (var i = 0; i < 20; i++) {
      model.addTag('A long tag name $i');
    }
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(FilterChip, 'A long tag name 0');
    final list = find
        .ancestor(of: chip, matching: find.byType(Scrollable))
        .first;
    final pos = tester.state<ScrollableState>(list).position;
    final p = TestPointer(1, PointerDeviceKind.trackpad);
    p.hover(tester.getCenter(chip));
    await tester.sendEventToBinding(p.scroll(const Offset(80, 3)));
    await tester.pump();
    expect(pos.pixels, 80);
    await tester.sendEventToBinding(p.scroll(const Offset(0, 50)));
    await tester.pump();
    expect(pos.pixels, 130);
  });
}

// The toolbar's menu buttons (Project, ⋯) draw their icons in the same
// colour as the buttons beside them, in each style, light and dark.
void _toolbarMenuColourTests() {
  for (final style in UiStyle.values) {
    testWidgets('toolbar menu icons match the others (${style.name})', (
      tester,
    ) async {
      final model = await pumpApp(tester);
      // (the colour the icon is drawn in)
      Color? colourOf(String tooltip) => IconTheme.of(
        tester.element(
          find
              .descendant(
                of: find.byTooltip(tooltip),
                matching: find.byType(MotionIcon),
              )
              .first,
        ),
      ).color;
      for (final mode in [ThemeModeSetting.light, ThemeModeSetting.dark]) {
        model.updateSettings(
          (s) => s
            ..uiStyle = style
            ..mode = mode,
        );
        await tester.pumpAndSettle();
        final share = colourOf('Share / export');
        expect(share, isNotNull);
        expect(colourOf('Project'), share, reason: '${style.name} $mode');
      }
    });
  }
}

abstract final class _StickyWidths {
  static const toolbar = 7 * 36.0 + 8;
}
