import 'package:bilingual_projector/bramble_icons.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/song_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'padding_check.dart';

void main() {
  // The top line (title field, ✕ and ✓) sits as far from the top as from
  // the sides: in the dialog (desktop) and in the phone's sheet.
  testWidgets('the editor\'s top line is evenly padded', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SongEditor.show(
                context,
                Song(title: 'Song', raw: '[G]Bless'),
                tags: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // the surface it's on: the dialog's, or the sheet's
    final frame = find
        .ancestor(of: find.byType(TabBar), matching: find.byType(Material))
        .last;
    expectEvenPadding(
      tester,
      frame: frame,
      left: find.byType(TextField).first,
      top: find.byType(TextField).first,
      right: find.widgetWithIcon(IconButton, BrambleIcons.check),
      reason: 'dialog',
    );
    // The editor's text lines up with the title field's edge.
    final frameRect = tester.getRect(frame);
    final text = tester.getRect(find.byType(EditableText).last);
    final title = visibleRect(tester, find.byType(TextField).first);
    expect(
      text.left - frameRect.left,
      closeTo(title.left - frameRect.left, .5),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the editor\'s top line is evenly padded in the sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SongEditor.show(
                context,
                Song(title: 'Song', raw: '[G]Bless'),
                tags: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final frame = find
        .ancestor(of: find.byType(TabBar), matching: find.byType(Material))
        .last;
    expectEvenPadding(
      tester,
      frame: frame,
      left: find.byType(TextField).first,
      top: find.byType(TextField).first,
      right: find.widgetWithIcon(IconButton, BrambleIcons.check),
      reason: 'sheet',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  // The text area runs from the tabs' line to the bottom edge, scrolling
  // as a whole: lines pass under the bar floating over its foot, and the
  // caret on the last line is brought up clear of the bar.
  testWidgets('the ChordPro text scrolls edge to edge, under the bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final raw = List.generate(80, (i) => '[G]Line $i').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SongEditor.show(
                context,
                Song(title: 'Song', raw: raw),
                tags: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final frame = tester.getRect(
      find
          .ancestor(of: find.byType(TabBar), matching: find.byType(Material))
          .last,
    );
    final scroller = find.byType(SingleChildScrollView).last;
    final view = tester.getRect(scroller);
    expect(view.top, closeTo(tester.getRect(find.byType(TabBar)).bottom, .5));
    expect(view.bottom, closeTo(frame.bottom, .5));
    final bar = tester.getRect(find.byType(ListView).last);
    expect(bar.bottom, lessThan(view.bottom));
    expect(bar.top, greaterThan(view.top));

    // The caret at the very end: the last line is above the bar.
    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    final field = tester.state<EditableTextState>(
      find.byType(EditableText).last,
    );
    field.userUpdateTextEditingValue(
      field.textEditingValue.copyWith(
        selection: TextSelection.collapsed(offset: raw.length),
      ),
      SelectionChangedCause.keyboard,
    );
    await tester.pumpAndSettle();
    final editable = field.renderEditable;
    final caret = MatrixUtils.transformRect(
      editable.getTransformTo(null),
      editable.getLocalRectForCaret(TextPosition(offset: raw.length)),
    );
    expect(caret.bottom, lessThan(bar.top));
    expect(caret.top, greaterThan(view.top));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  // Find & replace lines up with the title: its fields 20 from the left,
  // its ✕ 20 from the right.
  testWidgets('the find bar is padded as the top line', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SongEditor.show(
                context,
                Song(title: 'Song', raw: '[G]Bless'),
                tags: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Find & replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Replace…'));
    await tester.pumpAndSettle();
    final frame = tester.getRect(
      find
          .ancestor(of: find.byType(TabBar), matching: find.byType(Material))
          .last,
    );
    final title = visibleRect(tester, find.byType(TextField).first);
    final findField = visibleRect(
      tester,
      find.widgetWithText(TextField, 'Find'),
    );
    final replaceField = visibleRect(
      tester,
      find.widgetWithText(TextField, 'Replace with'),
    );
    final close = tester.getRect(
      find.descendant(
        of: find.byTooltip('Close (Esc)'),
        matching: find.byType(Icon),
      ),
    );
    expect(findField.left, closeTo(title.left, .5));
    expect(replaceField.left, closeTo(title.left, .5));
    expect(frame.right - close.right, closeTo(title.left - frame.left, .5));
    // a gap under the tabs' line
    expect(
      findField.top - tester.getRect(find.byType(TabBar)).bottom,
      greaterThanOrEqualTo(8),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
