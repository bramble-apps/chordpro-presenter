import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/media.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/fitting_slide.dart';
import 'package:bilingual_projector/widgets/format_pane.dart';
import 'package:bilingual_projector/widgets/projection_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilingual_projector/widgets/chord_line.dart';

Future<PresenterModel> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final model = PresenterModel();
  await model.load();
  // (Counts lyric slides: no blank / title slides.)
  model.updateProjection(
    (p) => p
      ..blankSlide = false
      ..titleSlide = false,
  );
  await tester.pumpWidget(
    BilingualProjectorApp(
      model: model,
      home: OperatorScreen(model: model),
    ),
  );
  await tester.pumpAndSettle();
  return model;
}

Future<void> openProjector(WidgetTester tester, PresenterModel m) async {
  (m.sync as dynamic).receive({'type': 'hello', 'w': 1920, 'h': 1080});
  await tester.pumpAndSettle();
}

Future<void> closeProjector(WidgetTester tester, PresenterModel m) async {
  (m.sync as dynamic).receive({'type': 'bye'});
  await tester.pumpAndSettle();
}

/// 1×1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A chord shown above the words (chord lines are drawn as one element).
Finder chordText(String chord) => find.byWidgetPredicate(
  (w) => w is ChordLine && w.pieces.any((p) => p.chord == chord),
  description: 'chord "$chord"',
);

void main() {
  test('settings survive JSON round trip', () {
    final p = ProjectionSettings()
      ..view = ProjectionView.stage
      ..bgType = BackgroundType.media
      ..bgMedia = const MediaRef('m1', 'bg.jpg', 'image/jpeg')
      ..textMode = TextMode.song
      ..textSize = 95
      ..textColor = const Color(0xFFFFF59D)
      ..textAlign = HAlign.left
      ..tidyLyrics = false
      ..logo = const MediaRef('m2', 'logo.png', 'image/png')
      ..footer = true
      ..stageScheme = StageScheme.light
      ..stageMargin = 5;
    final q = ProjectionSettings.fromJson(p.toJson());
    expect(q.toJson(), p.toJson());
    expect(q.bgMedia!.name, 'bg.jpg');
  });

  test('tidy lyrics can be turned off', () {
    const raw = 'Verse:\nJe - sus  loves  me\n-\n';
    expect(ChordPro.parseToSlides(raw), ['Jesus loves me']);
    expect(ChordPro.parseToSlides(raw, tidy: false), [
      'Je - sus  loves  me\n-',
    ]);
  });

  testWidgets('B blacks out the projector; preview follows', (tester) async {
    final m = await pumpApp(tester);
    await openProjector(tester, m);
    expect(m.blackout, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(m.blackout, isTrue);
    final sent = (m.sync as dynamic).sent as List<Map<String, dynamic>>;
    expect(sent.last['blackout'], isTrue);
    await tester.tap(find.byTooltip('Show lyrics again (B)'));
    await tester.pumpAndSettle();
    expect(m.blackout, isFalse);
    await closeProjector(tester, m);
  });

  testWidgets('song mode shows every part, current one highlighted', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    m.updateProjection((p) => p.textMode = TextMode.song);
    await openProjector(tester, m);
    final slide = tester.widget<FittingSlide>(find.byType(FittingSlide));
    expect(slide.allSlides, m.slides);
    expect(slide.current, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(tester.widget<FittingSlide>(find.byType(FittingSlide)).current, 1);
    await closeProjector(tester, m);
  });

  testWidgets('stage view: header, chord sheet, section chips, next song', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    // Open the song from a setlist so there is a next song.
    final set = m.createSetlist('Sunday');
    m.addOrUpdate(Song(title: 'Second', raw: '[C]Two'));
    m.addSongsToSetlist(set, [m.songs.first.id, m.songs.last.id]);
    m.selectEntry(set, set.entries.first);
    m.updateProjection((p) => p.view = ProjectionView.stage);
    await openProjector(tester, m);
    final preview = find.byType(ProjectorDisplay);
    expect(preview, findsOneWidget);
    Finder inPreview(Finder f) => find.descendant(of: preview, matching: f);
    expect(inPreview(find.text('Amazing Grace')), findsOneWidget);
    expect(inPreview(find.textContaining('Key G')), findsOneWidget);
    expect(inPreview(chordText('Em ')), findsWidgets, reason: 'chords shown');
    expect(inPreview(find.text('Verse 1')), findsOneWidget, reason: 'chip');
    expect(inPreview(find.text('Refrain')), findsOneWidget, reason: 'chip');
    expect(inPreview(find.text('Next: Second')), findsOneWidget);
    expect(inPreview(find.byType(StageClock)), findsOneWidget);

    m.updateProjection((p) => p.stageFooter = false);
    await tester.pumpAndSettle();
    expect(inPreview(find.text('Next: Second')), findsNothing);
    await closeProjector(tester, m);
  });

  testWidgets('Projection tab: choose a background picture and a logo', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projection').last);
    await tester.pumpAndSettle();
    expect(find.text('Lyrics view'), findsOneWidget);
    expect(find.text('Stage view'), findsOneWidget);

    final pane = find
        .descendant(
          of: find.byType(FormatPane),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Image & Video'),
      200,
      scrollable: pane,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image & Video'));
    await tester.pumpAndSettle();
    expect(m.projection.bgType, BackgroundType.media);
    nextPickedMedia = [('sky.png', 'image/png', _png)];
    await tester.scrollUntilVisible(
      find.text('Choose…').first,
      200,
      scrollable: pane,
    );
    await tester.tap(find.text('Choose…').first);
    await tester.pumpAndSettle();
    expect(m.projection.bgMedia!.name, 'sky.png');
    expect(KeyValueStore.bytes['media:${m.projection.bgMedia!.id}'], _png);

    // Size stepper.
    await tester.scrollUntilVisible(find.text('Mode'), -200, scrollable: pane);
    await tester.pumpAndSettle();
    final before = m.projection.textSize;
    await tester.tap(
      find
          .descendant(
            of: find.byType(FormatPane),
            matching: find.byTooltip('More'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(m.projection.textSize, before + 5);

    // Switch to stage view: its own settings appear.
    await tester.scrollUntilVisible(
      find.text('Stage view'),
      -300,
      scrollable: pane,
    );
    await tester.tap(find.text('Stage view'));
    await tester.pumpAndSettle();
    expect(m.projection.view, ProjectionView.stage);
    expect(find.text('Colour scheme'), findsOneWidget);
    expect(find.byType(FormatPane), findsOneWidget);
  });

  testWidgets('cast dialog: cast, stop, AirPlay steps', (tester) async {
    final m = await pumpApp(tester);
    await tester.tap(find.byTooltip('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cast to a TV or display…'));
    await tester.pumpAndSettle();
    expect(find.text('Show on another screen'), findsOneWidget);
    expect(find.textContaining('Use As Separate Display'), findsOneWidget);
    await tester.tap(find.text('Cast…'));
    await tester.pumpAndSettle();
    expect(m.casting, isTrue);
    expect(find.text('Stop casting'), findsOneWidget);
    await tester.tap(find.text('Stop casting'));
    await tester.pumpAndSettle();
    expect(m.casting, isFalse);
  });

  testWidgets('cast screen gets pictures from the operator in pieces', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    // A ~600 KB "picture" so it is split into several pieces.
    final big = Uint8List.fromList(List.generate(600 * 1024, (i) => i % 251));
    nextPickedMedia = [('big.jpg', 'image/jpeg', big)];
    final ref = await MediaStore.pick();
    m.updateProjection((p) => p.bgMedia = ref);

    final projector = ProjectorModel()..start();
    final sent = (m.sync as dynamic).sent as List<Map<String, dynamic>>;
    // Wire the two test channels together: projector requests -> operator,
    // operator chunks -> projector.
    Uint8List? got;
    projector.fetchMedia(ref!).then((v) => got = v);
    final request =
        ((projector.sync as dynamic).sent as List<Map<String, dynamic>>).last;
    expect(request['type'], 'mediaRequest');
    final before = sent.length;
    (m.sync as dynamic).receive(request);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    final chunks = sent
        .skip(before)
        .where((x) => x['type'] == 'mediaChunk')
        .toList();
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      (projector.sync as dynamic).receive(c);
    }
    await tester.pump(const Duration(milliseconds: 1));
    expect(got, big);
    projector.dispose();
  });

  testWidgets('dim and gradient layers are drawn on the projector', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    m.updateProjection((p) {
      p.bgDim = 40;
      p.bgDimColor = const Color(0xFF102030);
      p.gradient = true;
    });
    await openProjector(tester, m);
    final display = find.byType(ProjectorDisplay);
    final dim = tester
        .widgetList<ColoredBox>(
          find.descendant(of: display, matching: find.byType(ColoredBox)),
        )
        .where(
          (b) => b.color == const Color(0xFF102030).withValues(alpha: 0.4),
        );
    expect(dim, isNotEmpty);
    final gradients = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: display, matching: find.byType(DecoratedBox)),
        )
        .where((b) => (b.decoration as BoxDecoration?)?.gradient != null);
    expect(gradients, isNotEmpty);
    await closeProjector(tester, m);
  });

  test('projector screens go dark on stop and wake on start', () async {
    final projector = ProjectorModel();
    projector.start();
    (projector.sync as dynamic).receive({'type': 'stop'});
    await Future<void>.delayed(Duration.zero);
    expect(projector.stopped, isTrue);
    (projector.sync as dynamic).receive({'type': 'start'});
    await Future<void>.delayed(Duration.zero);
    expect(projector.stopped, isFalse);
    projector.dispose();
  });

  testWidgets('stage text stays dark on white inside a dark window', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    m.updateProjection((p) {
      p.view = ProjectionView.stage;
      p.stageScheme = StageScheme.light;
    });
    final data = m.projectionData;
    // The real projector window uses a dark theme.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 720,
            child: ProjectorDisplay(data: data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((t) => t.text.toPlainText().contains('grace'));
    expect(texts, isNotEmpty);
    for (final t in texts) {
      final c = (t.text as TextSpan).style?.color ?? Colors.transparent;
      expect(c.computeLuminance(), lessThan(0.2), reason: 'lyrics readable');
    }
  });

  testWidgets('countdown timer: adjust, timeline, projector, format', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    m.updateSettings((s) => s.presentationMode = true);
    await tester.pumpAndSettle();
    expect(find.text('5:00'), findsOneWidget);

    // ±1 minute changes the timer's length.
    await tester.tap(find.text('+1 min'));
    await tester.pump();
    expect(find.text('6:00'), findsOneWidget);
    expect(m.timerTotalSeconds, 360);
    await tester.tap(find.text('−1 min'));
    await tester.tap(find.text('−1 min'));
    await tester.pump();
    expect(find.text('4:00'), findsOneWidget);
    expect(m.timerTotalSeconds, 240);

    // The timeline runs over the whole timer: halfway = 2:00 left.
    final slider = find.byType(Slider).last;
    final r = tester.getRect(slider);
    await tester.tapAt(Offset(r.center.dx, r.center.dy));
    await tester.pumpAndSettle();
    expect(m.timerSeconds.value, closeTo(120, 15));
    expect(m.timerTotalSeconds, 240, reason: 'length unchanged');

    // Not on the projector until started.
    expect(m.countdown.active, isFalse);
    await tester.tap(find.byTooltip('Start timer'));
    await tester.pump();
    expect(m.timerRunning, isTrue);
    final sent = (m.sync as dynamic).sent as List<Map<String, dynamic>>;
    final timer = sent.last['timer'] as Map<String, dynamic>;
    expect(timer['running'], isTrue);
    expect(timer['active'], isTrue);

    // A projector screen shows it (counting down by itself).
    final projector = ProjectorModel()..start();
    (projector.sync as dynamic).receive(
      sent.lastWhere((x) => x['type'] == 'state'),
    );
    await tester.pump();
    expect(projector.countdown?.active, isTrue);
    expect(find.byType(CountdownOverlay), findsWidgets, reason: 'preview');

    await tester.tap(find.byTooltip('Pause timer'));
    await tester.pump();
    expect(m.timerRunning, isFalse);

    // Format opens under the timer: placement dots, icons, font.
    await tester.tap(find.byTooltip('Timer format'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('Right'));
    await tester.pumpAndSettle();
    expect(m.projection.timerPlace, TimerPlace.right);
    await tester.tap(find.byTooltip('Top left'));
    await tester.tap(find.byTooltip('Italic'));
    await tester.tap(find.byTooltip('Bold'));
    await tester.pumpAndSettle();
    expect(m.projection.timerPlace, TimerPlace.topLeft);
    expect(m.projection.timerItalic, isTrue);
    expect(m.projection.timerBold, isFalse);
    expect(find.textContaining('#'), findsNothing, reason: 'swatch only');
    await tester.tap(find.text('Same as slides'));
    await tester.pumpAndSettle();
    final font = m.settings.fontOptions.last;
    await tester.tap(find.text(font.label).last);
    await tester.pumpAndSettle();
    expect(m.projection.timerFont, font.id);
    await tester.tap(find.byTooltip('Hide timer format'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Italic'), findsNothing);

    // The eye beside stop hides / shows it on the projector.
    await tester.tap(find.byTooltip('Hide timer on the projector'));
    await tester.pumpAndSettle();
    expect(m.projection.timerShow, isFalse);
    expect(find.byType(CountdownOverlay), findsNothing);
    await tester.tap(find.byTooltip('Show timer on the projector'));
    await tester.pumpAndSettle();
    expect(m.projection.timerShow, isTrue);

    // Stop: back to the full length, off the projector.
    await tester.tap(find.byTooltip(RegExp('^Stop timer')));
    await tester.pump();
    expect(m.timerSeconds.value, 240);
    expect(m.countdown.active, isFalse);
    projector.dispose();
  });

  test('countdown text', () {
    expect(formatCountdown(300000), '5:00');
    expect(formatCountdown(299001), '5:00');
    expect(formatCountdown(59000), '0:59');
    expect(formatCountdown(0), '0:00');
    expect(formatCountdown(3723000), '1:02:03');
  });

  testWidgets('linked sections: own look and visibility per screen', (
    tester,
  ) async {
    final m = await pumpApp(tester);
    m.addOrUpdate(
      Song(
        title: 'Grâce',
        raw:
            'Verse 1:\nAmazing grace\n\nCouplet 1:\nGrâce infinie\n\n'
            'Chorus:\nMy chains are gone',
        structure: const [
          StructureItem.section('Verse 1', linked: true),
          StructureItem.section('Couplet 1'),
          StructureItem.section('Chorus'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(m.slides.first, contains(linkSeparator));

    // Chord sheet: italic, then hidden (stage view follows the sheet).
    m.updateFormat((f) => f.linked.italic = true);
    await tester.pumpAndSettle();
    final french = tester.widgetList<Text>(find.text('Grâce infinie')).first;
    expect(french.style?.fontStyle, FontStyle.italic);
    m.updateFormat((f) => f.linked.show = false);
    await tester.pumpAndSettle();
    expect(find.text('Grâce infinie'), findsNothing);
    expect(m.slides.first, contains('Grâce infinie'), reason: 'projector');
    expect(m.stageData!.format.linked.show, isFalse);

    // Projector: side by side, then hidden there too.
    m.updateFormat((f) => f.linked.show = true);
    m.updateProjection((p) {
      p.linked.sideBySide = true;
      p.linked.dim = true;
    });
    await openProjector(tester, m);
    final preview = find.byType(ProjectorDisplay);
    final row = find.descendant(of: preview, matching: find.byType(Row));
    expect(
      find.descendant(of: row, matching: find.text('Grâce infinie')),
      findsOneWidget,
      reason: 'beside the English',
    );
    m.updateProjection((p) => p.linked.show = false);
    await tester.pumpAndSettle();
    expect(m.slides.first, isNot(contains('Grâce infinie')));
    expect(
      find.descendant(of: preview, matching: find.text('Grâce infinie')),
      findsNothing,
    );
    // …but the chord sheet still shows it.
    expect(find.text('Grâce infinie'), findsWidgets);
    await closeProjector(tester, m);

    // Format panel controls.
    m.updateProjection((p) => p.linked.show = true);
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projection'));
    await tester.pumpAndSettle();
    // Collapsed until opened.
    const title = 'Linked Section (Song Structure)';
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find
          .descendant(
            of: find.byType(FormatPane),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Top & bottom'), findsNothing);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Top & bottom'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Top & bottom'));
    await tester.pumpAndSettle();
    // Same style buttons as the Text section.
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Card)),
        matching: find.byTooltip('Bold'),
      ),
    );
    await tester.pumpAndSettle();
    expect(m.projection.linked.bold, isTrue);
    expect(m.projection.linked.sideBySide, isFalse);
  });
}
