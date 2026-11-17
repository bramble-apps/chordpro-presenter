import 'package:bilingual_projector/ink.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:bilingual_projector/widgets/ink_layer.dart';
import 'package:bilingual_projector/widgets/ink_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show pumpApp;

void main() {
  test('strokes: saved, hit, moved and resized', () {
    final s = InkStroke(
      highlighter: true,
      color: const Color(0xFFFFEB3B),
      width: 0.02,
      points: const [Offset(0.1, 0.1), Offset(0.3, 0.1)],
    );
    final back = InkStroke.fromJson(s.toJson())!;
    expect(back.highlighter, isTrue);
    expect(back.color, s.color);
    expect(back.points, s.points);
    expect(s.hits(const Offset(0.2, 0.105), 0.001), isTrue);
    expect(s.hits(const Offset(0.2, 0.3), 0.001), isFalse);
    expect(s.moved(const Offset(0.1, 0)).points.first, const Offset(0.2, 0.1));
    final big = s.fitted(
      s.bounds,
      Rect.fromLTWH(0, 0, s.bounds.width * 2, s.bounds.height * 2),
    );
    expect(big.bounds.width, closeTo(s.bounds.width * 2, 0.02));
  });

  testWidgets('annotate the chord sheet: draw, undo, redo, erase, move', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    final song = model.currentSong!;
    await tester.tap(find.byTooltip('Annotate (draw / highlight)'));
    await tester.pumpAndSettle();
    expect(find.byType(InkToolbar), findsOneWidget);

    // Sideways strokes draw; they never swipe to another song.
    model.addOrUpdate(Song(title: 'Zz other', raw: '[C]Other'));
    model.selectSong(song.id);
    await tester.pumpAndSettle();
    final sheetRect = tester.getRect(
      find.byWidgetPredicate((w) => w is ChordSheet && w.song.id == song.id),
    );
    await tester.dragFrom(
      sheetRect.center + const Offset(150, -120),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(model.currentSong!.id, song.id);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(model.sheetInk(song), isEmpty);

    final sheet = tester.getRect(
      find.byWidgetPredicate((w) => w is ChordSheet && w.song.id == song.id),
    );
    final at = sheet.center;
    await tester.dragFrom(at, const Offset(120, 30));
    await tester.pumpAndSettle();
    expect(model.sheetInk(song), hasLength(1));
    expect(model.sheetInk(song).single.highlighter, isFalse);

    // Highlighter.
    await tester.tap(find.byTooltip('Highlighter'));
    await tester.pump();
    await tester.dragFrom(at + const Offset(0, 80), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(model.sheetInk(song).map((s) => s.highlighter), [false, true]);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(model.sheetInk(song), hasLength(1));
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(model.sheetInk(song), hasLength(2));

    // Move the pen stroke.
    await tester.tap(find.byTooltip('Move and resize'));
    await tester.pump();
    final before = model.sheetInk(song).first.bounds;
    await tester.dragFrom(at + const Offset(60, 15), const Offset(40, -60));
    await tester.pumpAndSettle();
    final after = model.sheetInk(song).first.bounds;
    expect(after.top, lessThan(before.top));

    // Erase it where it went.
    await tester.tap(find.byTooltip('Eraser'));
    await tester.pump();
    await tester.dragFrom(at + const Offset(100, -45), const Offset(0, 1));
    await tester.pumpAndSettle();
    expect(model.sheetInk(song).map((s) => s.highlighter), [true]);

    // The tool pill floats: dragged, it moves (and stays put).
    final pill = tester.getRect(find.byType(InkToolbar));
    await tester.dragFrom(
      pill.centerLeft + const Offset(14, 0),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(InkToolbar)).top,
      lessThan(pill.top - 100),
    );
    expect(model.sheetInk(song).map((s) => s.highlighter), [true]);

    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(InkToolbar), findsNothing);
  });

  testWidgets(
    'annotate a slide: a big preview; the ink goes to the projector',
    (tester) async {
      final model = await pumpApp(tester);
      // Presentation mode (the slide grid): annotating draws on slides.
      model.updateSettings((s) => s.presentationMode = true);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Annotate (draw / highlight)'));
      await tester.pumpAndSettle();
      final board = find.byWidgetPredicate((w) => w is InkCanvas && w.editable);
      expect(board, findsOneWidget);
      // As wide as the song area (clear of the sidebar).
      expect(tester.getRect(board).left, greaterThan(300));
      expect(tester.getRect(board).width, greaterThan(700));

      await tester.dragFrom(tester.getCenter(board), const Offset(100, 20));
      await tester.pumpAndSettle();
      expect(model.slideInk[model.selection.value], hasLength(1));
      expect(model.projectionData.ink![model.selection.value], hasLength(1));
      // Other slides have none.
      expect(model.slideInk.where((s) => s.isNotEmpty), hasLength(1));
    },
  );

  testWidgets('tapping the pen again: sizes and opacity', (tester) async {
    final model = await pumpApp(tester);
    final song = model.currentSong!;
    await tester.tap(find.byTooltip('Annotate (draw / highlight)'));
    await tester.pumpAndSettle();
    expect(find.byType(InkStyleMenu), findsNothing);
    await tester.tap(find.byTooltip('Pen'));
    await tester.pumpAndSettle();
    expect(find.byType(InkStyleMenu), findsOneWidget);
    await tester.tap(find.byTooltip('Size 5'));
    await tester.drag(find.byType(Slider), const Offset(-60, 0));
    await tester.pumpAndSettle();
    // Tapping elsewhere closes it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(InkStyleMenu), findsNothing);

    final sheetRect = tester.getRect(
      find.byWidgetPredicate((w) => w is ChordSheet && w.song.id == song.id),
    );
    await tester.dragFrom(sheetRect.center, const Offset(0, 80));
    await tester.pumpAndSettle();
    final stroke = model.sheetInk(song).single;
    expect(stroke.width, InkController.penSizes.last);
    expect(stroke.color.a, lessThan(1));
  });
}
