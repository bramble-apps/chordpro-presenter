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
        builder: (scale, laidOut) => PagedSheet(
          scale: scale,
          onLayout: laidOut,
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

  testWidgets('pages fit the width at first, one after another (no gap)', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(pages(ScrollController()));
    final box = t.renderObject<RenderBox>(find.byType(PagedSheet));
    const fit = 968 / 600;
    expect(box.size.width, closeTo(968, .5));
    expect(t.getTopLeft(find.text('Line 0')).dx, closeTo(16 + 40 * fit, 1));
    // 40 lines of 60 on 720-high columns: 12 a page, 4 pages, no gaps
    expect(box.size.height, closeTo(4 * 800 * fit, 1));
  });

  var fingers = 0;
  Future<(TestGesture, TestGesture)> pinch(WidgetTester t, Offset at, double from, double to, {bool release = true}) async {
    final a = await t.createGesture(kind: PointerDeviceKind.touch, pointer: ++fingers);
    final b = await t.createGesture(kind: PointerDeviceKind.touch, pointer: ++fingers);
    await a.down(at - Offset(from, 0));
    await b.down(at + Offset(from, 0));
    await t.pump();
    for (var i = 1; i <= 4; i++) {
      final d = from + (to - from) * i / 4;
      await a.moveTo(at - Offset(d, 0));
      await b.moveTo(at + Offset(d, 0));
      await t.pump();
    }
    if (release) {
      await a.up();
      await b.up();
    }
    return (a, b);
  }

  testWidgets('a pinch zooms as it goes, about the fingers, with nothing cut off', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(pages(ScrollController()));
    final before = t.getTopLeft(find.text('Line 3'));
    final at = before + const Offset(300, 10);
    final (a, b) = await pinch(t, at, 50, 100, release: false);
    // already zoomed mid-pinch (laid out, not a scaled picture)
    expect(pageZoom.value, closeTo(2, .01));
    final after = t.getTopLeft(find.text('Line 3'));
    expect(at - after, offsetMoreOrLessEquals((at - before) * 2, epsilon: 2));
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    // zooming out shows the whole page, not the old view shrunk
    await pinch(t, at, 100, 25);
    await t.pumpAndSettle();
    expect(pageZoom.value, closeTo(.5, .01), reason: '2 × 25/100');
    // the whole page, half the width, centred
    expect(t.getRect(find.byType(PagedSheet)), rectMoreOrLessEquals(Rect.fromLTWH(16 + 242, t.getTopLeft(find.byType(PagedSheet)).dy, 484, 4 * 800 * 968 / 600 / 2), epsilon: 1));
  });

  testWidgets('let go close to fitting the width, it snaps back to it', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(pages(ScrollController()));
    await pinch(t, const Offset(500, 300), 100, 106);
    await t.pump();
    expect(pageZoom.value, closeTo(1.06, .01));
    await t.pumpAndSettle();
    expect(pageZoom.value, 1);
    // further off, it stays
    await pinch(t, const Offset(500, 300), 100, 140);
    await t.pumpAndSettle();
    expect(pageZoom.value, closeTo(1.4, .01));
  });

  testWidgets('a trackpad pinch (zoom steps from a browser) zooms with each step', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(pages(ScrollController()));
    final at = t.getCenter(find.text('Line 3'));
    for (var i = 0; i < 5; i++) {
      t.binding.handlePointerEvent(PointerScaleEvent(position: at, scale: 1.1));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(pageZoom.value, closeTo(1.61, .01));
    await t.pumpAndSettle(const Duration(milliseconds: 50));
    expect(pageZoom.value, closeTo(1.61, .01), reason: 'too far to snap back');
  });

  testWidgets('pages run up behind whatever is above them (not cut at the padding)', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = ScrollController();
    await t.pumpWidget(pages(c));
    final clip = find.ancestor(of: find.text('Line 0'), matching: find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    ));
    expect(t.widget<SingleChildScrollView>(clip).clipBehavior, Clip.none);
  });
}
