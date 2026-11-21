import 'package:bilingual_projector/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The font size [text] is drawn at.
double _size(WidgetTester tester, String text) {
  final p = tester.renderObject<RenderParagraph>(find.text(text).last);
  double? size;
  p.text.visitChildren((span) {
    size ??= span.style?.fontSize;
    return size == null;
  });
  return size ?? p.text.style!.fontSize!;
}

void main() {
  // A popup menu's items and a dropdown list's items: the same size, in
  // every style.
  for (final style in UiStyle.values) {
    testWidgets('menus and dropdown lists alike (${style.name})', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(appThemes.first, Brightness.light, style: style),
          home: Scaffold(
            body: Column(
              children: [
                PopupMenuButton<int>(
                  child: const Text('menu'),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 1,
                      child: Text('Open projector window'),
                    ),
                  ],
                ),
                DropdownButton<int>(
                  value: 1,
                  onChanged: (_) {},
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Nothing')),
                    DropdownMenuItem(value: 2, child: Text('Solfège')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      final menu = _size(tester, 'Open projector window');
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nothing'));
      await tester.pumpAndSettle();
      final list = _size(tester, 'Solfège');
      expect(menu, list, reason: 'popup $menu, dropdown $list');
    });
  }
}
