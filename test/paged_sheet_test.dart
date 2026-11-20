import 'package:bilingual_projector/widgets/paged_sheet.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => pageZoom.value = 1);

  Widget pages(ScrollController c) => MaterialApp(
    home: Scaffold(
      body: ZoomablePages(
        controller: c,
        padding: const EdgeInsets.all(16),
        paperWidth: 600,
        builder: (scale) => PagedSheet(
          scale: scale,
          paper: const Size(600, 800),
          columns: 1,
          spanning: 0,
          pageColor: Colors.white,
          edgeColor: Colors.grey,
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(height: 60, child: Text('Line $i')),
          ],
        ),
      ),
    ),
  );

  testWidgets('pages at true size, centred, one after another (no gap)', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(pages(ScrollController()));
    final box = t.renderObject<RenderBox>(find.byType(PagedSheet));
    // 600 pt at 1 px a point, in the 968 of room: 184 each side
    expect(t.getTopLeft(find.text('Line 0')).dx, closeTo(16 + 184 + 40, 1));
    // 40 lines of 60 on 720-high columns: 12 a page, 4 pages, no gaps
    expect(box.size.height, 4 * 800);
  });

  testWidgets('a pinch zooms about the fingers and settles there', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = ScrollController();
    await t.pumpWidget(pages(c));
    final before = t.getTopLeft(find.text('Line 3'));
    final at = before + const Offset(300, 10);
    final a = await t.createGesture(kind: PointerDeviceKind.touch, pointer: 1);
    final b = await t.createGesture(kind: PointerDeviceKind.touch, pointer: 2);
    await a.down(at - const Offset(50, 0));
    await b.down(at + const Offset(50, 0));
    await t.pump();
    // (to 2×: wider than the window, so it keeps its place across too; a
    // page still narrower stays centred)
    await a.moveTo(at - const Offset(100, 0));
    await b.moveTo(at + const Offset(100, 0));
    await t.pump();
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    expect(pageZoom.value, closeTo(2, .01));
    // the point under the fingers is still under them
    final after = t.getTopLeft(find.text('Line 3'));
    expect(at - after, offsetMoreOrLessEquals((at - before) * 2, epsilon: 2));
  });
}
