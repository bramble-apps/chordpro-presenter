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
      right: find.widgetWithIcon(IconButton, Icons.check),
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
      right: find.widgetWithIcon(IconButton, Icons.check),
      reason: 'sheet',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
