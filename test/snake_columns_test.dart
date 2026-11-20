import 'package:bilingual_projector/widgets/snake_columns.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('columns fall back to fewer (to one) when they would be too narrow', () {
    expect(snakeColumnsFor(2, 1000), 2);
    expect(snakeColumnsFor(3, 1000), 3);
    expect(snakeColumnsFor(3, 700), 2);
    // a phone, a fold's cover screen
    expect(snakeColumnsFor(2, 400), 1);
    expect(snakeColumnsFor(3, 344), 1);
  });

  Widget lines() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < 60; i++)
        SeamLine(child: SizedBox(height: 30, child: Text('Line $i'))),
    ],
  );

  testWidgets('one flow: the second column carries on from the first, scrolling together', (t) async {
    t.view.physicalSize = const Size(800, 400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = ScrollController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SnakeColumns(
          controller: c,
          columns: 2,
          padding: const EdgeInsets.all(20),
          first: lines(),
          others: lines,
        ),
      ),
    ));
    await t.pumpAndSettle();
    // a column shows 360 (400 less its padding): 12 lines; the second
    // starts with line 12
    // (each line is in both columns: .first the first's, .last the second's)
    expect(t.getTopLeft(find.text('Line 0').first).dx, lessThan(400));
    expect(t.getTopLeft(find.text('Line 12').last).dx, greaterThan(400));
    expect(t.getTopLeft(find.text('Line 12').last).dy, closeTo(20, 1));
    // scrolled by 3 lines: line 12 is now at the foot of the first column,
    // and the second starts at 15
    c.jumpTo(90);
    await t.pumpAndSettle();
    expect(t.getRect(find.text('Line 14').first).bottom, closeTo(20 + 360, 1));
    expect(t.getTopLeft(find.text('Line 15').last).dy, closeTo(20, 1));
    expect(t.getTopLeft(find.text('Line 15').last).dx, greaterThan(400));
  });

  testWidgets('a line shows only while it fits whole in its column', (t) async {
    t.view.physicalSize = const Size(800, 400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = ScrollController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SnakeColumns(
          controller: c,
          columns: 2,
          padding: const EdgeInsets.all(20),
          first: lines(),
          others: lines,
        ),
      ),
    ));
    await t.pumpAndSettle();
    // half a line along: line 0 is half out of the first column's top
    c.jumpTo(15);
    await t.pumpAndSettle();
    double opacity(Finder f) => t.widget<AnimatedOpacity>(
      find.ancestor(of: f, matching: find.byType(AnimatedOpacity)).first,
    ).opacity;
    expect(opacity(find.text('Line 0').first), 0);
    expect(opacity(find.text('Line 1').first), 1);
    // line 12 straddles the seam: whole in neither column, shown in neither
    expect(opacity(find.text('Line 12').first), 0);
    expect(opacity(find.text('Line 12').last), 0);
    // line 13: whole in the second column
    expect(opacity(find.text('Line 13').last), 1);
  });

  testWidgets('dragging or the wheel in the second column scrolls them all', (t) async {
    t.view.physicalSize = const Size(800, 400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = ScrollController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SnakeColumns(
          controller: c,
          columns: 2,
          padding: const EdgeInsets.all(20),
          first: lines(),
          others: lines,
        ),
      ),
    ));
    await t.drag(find.text('Line 14').last, const Offset(0, -120));
    await t.pumpAndSettle();
    expect(c.offset, greaterThan(60));
    final was = c.offset;
    t.binding.handlePointerEvent(PointerScrollEvent(position: const Offset(600, 200), scrollDelta: const Offset(0, 60)));
    await t.pumpAndSettle();
    expect(c.offset, closeTo(was + 60, 1));
  });
}
