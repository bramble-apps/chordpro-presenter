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
        builder: (scale, content, laidOut) => PagedSheet(
          scale: scale,
          onLayout: laidOut,
          paper: const Size(600, 800) / content,
          margin: 40 / content,
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

  testWidgets('Fit Width: the page edge to edge, its content laid out once and scaled with it', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(pages(ScrollController()));
    // the page as wide as the view
    expect(t.getRect(find.byType(PagedSheet)).left, 0);
    expect(t.getSize(find.byType(PagedSheet)).width, closeTo(1000, .5));
    // laid out in points (a point 4/3 of a pixel at 100 %): 16 lines of 60
    // a page, 3 pages; on a 1000-wide page (100 % would be 800) all of it
    // 1.25 × its size
    double line() => t.getRect(find.text('Line 0')).height;
    expect(line(), closeTo(60 * 1.25, .5));
    expect(t.getSize(find.byType(PagedSheet)).height, closeTo(3 * 800 * 1000 / 600, 1));
    // a narrower view: the same pages, smaller (not re-flowed)
    t.view.physicalSize = const Size(450, 700);
    await t.pump();
    expect(t.getSize(find.byType(PagedSheet)).width, closeTo(450, .5));
    expect(line(), closeTo(60 * 450 / 800, .5));
    expect(t.getSize(find.byType(PagedSheet)).height, closeTo(3 * 800 * 450 / 600, 1));
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
    // (from wider than the window: narrower, a page stays centred instead)
    pageZoom.value = 1.2;
    await t.pumpWidget(pages(ScrollController()));
    final before = t.getTopLeft(find.text('Line 3'));
    final at = before + const Offset(300, 10);
    final (a, b) = await pinch(t, at, 50, 100, release: false);
    // already zoomed mid-pinch (laid out, not a scaled picture)
    expect(pageZoom.value, closeTo(2.4, .01));
    final after = t.getTopLeft(find.text('Line 3'));
    expect(at - after, offsetMoreOrLessEquals((at - before) * 2, epsilon: 2));
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    // zooming out shows the whole page, not the old view shrunk
    await pinch(t, at, 100, 25);
    await t.pumpAndSettle();
    expect(pageZoom.value, closeTo(.6, .01), reason: '2.4 × 25/100');
    // the whole page, half size, centred
    expect(t.getRect(find.byType(PagedSheet)), rectMoreOrLessEquals(Rect.fromLTWH(200, t.getTopLeft(find.byType(PagedSheet)).dy, 600, 3 * 800 * 1000 / 600 * .6), epsilon: 1));
  });

  testWidgets('let go close to fitting the width, it snaps back to it', (t) async {
    t.view.physicalSize = const Size(1000, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(pages(ScrollController()));
    // passing Fit Width, it holds there a moment (the notch)
    final (a, b) = await pinch(t, const Offset(500, 300), 100, 103, release: false);
    expect(pageZoom.value, 1);
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    // let go within a fifth of it: eases back
    await pinch(t, const Offset(500, 300), 100, 118);
    await t.pump();
    expect(pageZoom.value, closeTo(1.18, .01));
    await t.pump(const Duration(milliseconds: 150));
    expect(pageZoom.value, inExclusiveRange(1, 1.18), reason: 'easing, not jumping');
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
