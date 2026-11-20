import 'package:bilingual_projector/widgets/resize_hold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('while the window is being resized the content keeps its layout, then lays out once', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final widths = <double>[];
    await t.pumpWidget(MaterialApp(
      home: ResizeHold(
        child: LayoutBuilder(builder: (context, c) {
          widths.add(c.maxWidth);
          return const SizedBox.expand();
        }),
      ),
    ));
    expect(widths.last, 800);
    final laidOut = widths.length;
    // dragging the window's edge, frame by frame
    for (var w = 790.0; w >= 700; w -= 10) {
      t.view.physicalSize = Size(w, 600);
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(widths.length, laidOut, reason: 'no layouts while resizing');
    await t.pump(const Duration(milliseconds: 200));
    await t.pump();
    expect(widths.last, 700, reason: 'laid out at the new size once it stopped');
  });
}
