import 'package:bilingual_projector/bramble_icons.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/eink.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/themes.dart';
import 'package:bilingual_projector/widgets/alpha_scrubber.dart';
import 'package:bilingual_projector/widgets/settings_dialog.dart';
import 'package:bilingual_projector/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PresenterModel> pumpEinkApp(
  WidgetTester tester, {
  bool eink = true,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final model = PresenterModel();
  await model.load();
  model.updateSettings((s) => s.eink = eink);
  await tester.pumpWidget(
    BilingualProjectorApp(
      model: model,
      home: OperatorScreen(model: model),
    ),
  );
  await tester.pumpAndSettle();
  return model;
}

void main() {
  test('the e-ink theme is black and white, without shadows', () {
    for (final b in Brightness.values) {
      final t = einkTheme(buildTheme(appThemes.first, b));
      final ink = b == Brightness.light ? Colors.black : Colors.white;
      final paper = b == Brightness.light ? Colors.white : Colors.black;
      expect(t.colorScheme.onSurface, ink);
      expect(t.colorScheme.primary, ink);
      expect(t.colorScheme.surface, paper);
      expect(t.colorScheme.surfaceContainerHigh, paper);
      expect(t.colorScheme.shadow, Colors.transparent);
      expect(t.shadowColor, Colors.transparent);
      expect(t.extension<Eink>(), isNotNull);
      expect(t.extension<StyleExtras>()!.toolbarElevation, 0);
    }
    expect(AppSettings().eink, isFalse);
    expect((AppSettings()..updateFrom({'eink': true})).eink, isTrue);
    expect(AppSettings().toJson()['eink'], isFalse);
  });

  testWidgets('long lists turn pages with arrows', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: einkTheme(ThemeData()),
        home: ScrollConfiguration(
          behavior: const EinkScrollBehavior(),
          child: Scaffold(
            body: SizedBox(
              height: 400,
              child: ListView.builder(
                controller: controller,
                itemExtent: 40,
                itemCount: 50,
                itemBuilder: (_, i) => Text('Row $i'),
              ),
            ),
          ),
        ),
      ),
    );
    // (Measured, then shown, then the list re-measured.)
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    // The arrows take a strip under the list (44 of the 400).
    expect(find.text('1/7'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    // The next page starts at the row the bottom edge cut through (it
    // was blanked out), so no row is ever shown in part.
    expect(controller.offset, closeTo(320, 0.5));
    expect(find.text('2/7'), findsOneWidget);
    // Rows aren't hidden under the arrows.
    expect(
      tester.getBottomLeft(find.byType(Viewport)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byTooltip('Next page')).dy),
    );
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pump();
    expect(controller.offset, 0);
    // A list that fits has no arrows.
    await tester.pumpWidget(
      MaterialApp(
        home: ScrollConfiguration(
          behavior: const EinkScrollBehavior(),
          child: ListView(children: const [Text('Only row')]),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Next page'), findsNothing);
  });

  testWidgets('e-ink song list: a letter grid filters instead of the '
      'scrubber', (tester) async {
    final model = await pumpEinkApp(tester);
    for (final t in ['Aardvark Hymn', 'Aardwolf Song', 'Bxq Anthem']) {
      model.addOrUpdate(Song(title: t, raw: 'words'));
    }
    await tester.pumpAndSettle();
    final sidebar = find.byType(Sidebar);
    Finder inList(String t) =>
        find.descendant(of: sidebar, matching: find.text(t));
    expect(find.byType(AlphaScrubber), findsNothing);
    expect(inList('All'), findsOneWidget);
    expect(inList('Bxq Anthem'), findsOneWidget);

    // B: only the B songs.
    await tester.tap(
      find.descendant(
        of: sidebar,
        matching: find.widgetWithText(TextButton, 'B'),
      ),
    );
    await tester.pumpAndSettle();
    expect(inList('Bxq Anthem'), findsOneWidget);
    expect(inList('Aardvark Hymn'), findsNothing);
    // Letters without songs can't be picked.
    final z = tester.widget<TextButton>(
      find.descendant(
        of: sidebar,
        matching: find.widgetWithText(TextButton, 'Z'),
      ),
    );
    expect(z.onPressed, isNull);
    // All again.
    await tester.tap(inList('All'));
    await tester.pumpAndSettle();
    expect(inList('Aardvark Hymn'), findsOneWidget);
    // (Animations back to normal speed for the other tests.)
    setEink(false);
    expect(timeDilation, 1);
    expect(EditableText.debugDeterministicCursor, isFalse);
  });

  testWidgets('e-ink dropdowns: an outlined menu, the choice ticked', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: einkTheme(ThemeData()),
        home: Scaffold(
          body: AppDropdown<String>(
            value: 'a',
            items: const [
              DropdownMenuItem(value: 'a', child: Text('Apple')),
              DropdownMenuItem(value: 'b', child: Text('Banana')),
            ],
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    );
    // Not Flutter's dropdown (soft shadow, no edge).
    expect(find.byType(DropdownButton<String>), findsNothing);
    await tester.tap(find.text('Apple'));
    await tester.pump();
    expect(find.text('Banana'), findsOneWidget);
    expect(find.byIcon(BrambleIcons.check), findsOneWidget);
    await tester.tap(find.text('Banana'));
    await tester.pump();
    expect(picked, 'b');
  });

  testWidgets('e-ink spinners hold still', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: einkTheme(ThemeData()),
        home: const Scaffold(body: Center(child: AppSpinner())),
      ),
    );
    expect(find.byIcon(BrambleIcons.hourglass), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('e-ink Settings: sections to open, not one long scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    KeyValueStore.memory.clear();
    final model = PresenterModel();
    await tester.pumpWidget(
      MaterialApp(
        theme: einkTheme(ThemeData()),
        home: Scaffold(body: SettingsDialog(model: model)),
      ),
    );
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Buttons'), findsOneWidget);
    expect(find.text('E-ink'), findsNothing);
    await tester.tap(find.text('Mode'));
    await tester.pump();
    expect(find.text('E-ink'), findsOneWidget);
    expect(find.text('Sidebar'), findsNothing);
    // Back to the list.
    await tester.tap(find.byIcon(BrambleIcons.caretLeft));
    await tester.pump();
    expect(find.text('Sidebar'), findsOneWidget);
  });

  testWidgets('e-ink pages hold whole rows, none cut off', (tester) async {
    var pages = 0;
    Widget at(int page) => MaterialApp(
      home: Center(
        child: SizedBox(
          height: 120,
          width: 200,
          child: EinkPagedRows(
            page: page,
            onPages: (n) => pages = n,
            children: [
              for (var i = 1; i <= 5; i++)
                SizedBox(height: 50, child: Text('Row $i')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(at(0));
    await tester.pump();
    // 120 holds two rows of 50 (a third would be cut off).
    expect(pages, 3);
    expect(find.text('Row 1').hitTestable(), findsOneWidget);
    expect(find.text('Row 2').hitTestable(), findsOneWidget);
    expect(find.text('Row 3').hitTestable(), findsNothing);
    await tester.pumpWidget(at(1));
    expect(find.text('Row 1').hitTestable(), findsNothing);
    expect(find.text('Row 3').hitTestable(), findsOneWidget);
    expect(find.text('Row 4').hitTestable(), findsOneWidget);
  });

  testWidgets('e-ink: tags are in the filter menu, all at once', (
    tester,
  ) async {
    final model = await pumpEinkApp(tester);
    model.addTag('Offertory');
    await tester.pumpAndSettle();
    final sidebar = find.byType(Sidebar);
    // No strip of tags along the top.
    expect(
      find.descendant(of: sidebar, matching: find.byType(FilterChip)),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Sort & filter'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Offertory'), findsOneWidget);
    expect(find.text('Manage tags'), findsOneWidget);
    setEink(false);
  });

  testWidgets('with e-ink off (or back off), animations run as before', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final model = PresenterModel();
    await model.load();
    await tester.pumpWidget(
      BilingualProjectorApp(
        model: model,
        home: OperatorScreen(model: model),
      ),
    );
    await tester.pumpAndSettle();
    for (final round in ['never on', 'on, then off']) {
      if (round != 'never on') {
        model.updateSettings((s) => s.eink = true);
        await tester.pumpAndSettle();
        model.updateSettings((s) => s.eink = false);
        await tester.pumpAndSettle();
      }
      expect(timeDilation, 1, reason: round);
      // A dialog fades in…
      showAppDialog<void>(
        context: tester.element(find.byType(OperatorScreen)),
        builder: (_) => const AlertDialog(content: Text('Hi')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final fade = tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('Hi'),
              matching: find.byType(FadeTransition),
            ),
          )
          .first;
      expect(fade.opacity.value, inExclusiveRange(0, 1), reason: round);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Hi'))).pop();
      await tester.pumpAndSettle();
      // …and the sidebar slides away rather than vanishing.
      final start = tester.getTopLeft(find.byTooltip('Hide sidebar')).dx;
      await tester.tap(find.byTooltip('Hide sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.getTopLeft(find.byTooltip('Show sidebar')).dx;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(find.byTooltip('Show sidebar')).dx;
      expect(mid, lessThan(start), reason: round);
      expect(mid, greaterThan(end), reason: round);
      await tester.tap(find.byTooltip('Show sidebar'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('e-ink: the side pane\'s top row and the header bar line up', (
    tester,
  ) async {
    await pumpEinkApp(tester);
    double centre(Finder f) => tester.getCenter(f).dy;
    final toggle = centre(find.byTooltip('Hide sidebar'));
    expect(centre(find.byTooltip('Sort & filter')), closeTo(toggle, 0.5));
    expect(
      centre(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.byType(TextField),
        ),
      ),
      closeTo(toggle, 0.5),
    );
    setEink(false);
  });

  testWidgets('e-ink: the Project menu keeps its titles on one line', (
    tester,
  ) async {
    await pumpEinkApp(tester);
    await tester.tap(find.byTooltip('Project'));
    await tester.pumpAndSettle();
    for (final t in ['Open projector window', 'Copy projection link']) {
      final line = tester.getSize(find.text(t)).height;
      expect(line, lessThan(30), reason: t);
    }
    setEink(false);
  });

  testWidgets('song rows: the key and ⋯ sit on the row\'s centre line', (
    tester,
  ) async {
    final model = await pumpEinkApp(tester, eink: false);
    model.addOrUpdate(
      Song(title: 'Zzz Row Test', artist: 'Someone', raw: '{key: F}\nwords'),
    );
    await tester.pumpAndSettle();
    // The row: its own Material (the tile with the key and ⋯ beside it).
    final tile = find.ancestor(
      of: find.text('Zzz Row Test').last,
      // The song row's own Material (its InkWell spans tile, key and ⋯).
      matching: find.byWidgetPredicate(
        (w) => w is Material && w.child is InkWell,
      ),
    );
    final row = tester.getCenter(tile).dy;
    final more = find.descendant(of: tile, matching: find.byTooltip('More'));
    final key = find.descendant(of: tile, matching: find.text('F'));
    expect(tester.getCenter(more).dy, closeTo(row, 1.5));
    expect(tester.getCenter(key).dy, closeTo(row, 1.5));
  });
}
