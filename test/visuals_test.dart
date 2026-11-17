import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/widgets/color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readable colours on the stage screen', () {
    const white = Colors.white;
    const lightGrey = Color(0xFFCCCCCC);
    final fixed = readableOn(lightGrey, white);
    expect(contrastRatio(fixed, white), greaterThanOrEqualTo(4.5));
    // Already readable colours are left alone.
    expect(readableOn(Colors.black, white), Colors.black);
    expect(
      contrastRatio(
        readableOn(const Color(0xFF222222), Colors.black),
        Colors.black,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('gradient defaults: black fading to transparent, bottom to top', () {
    final p = ProjectionSettings()..gradient = true;
    final g = overlayGradient(p)!;
    expect(g.colors.first, const Color(0xFF000000));
    expect(g.colors.last.a, 0);
    expect(g.begin, const Alignment(0, 1), reason: 'starts at the bottom');
    p.gradientAngle = 90;
    final r = overlayGradient(p)!;
    expect(
      (r.end as Alignment).x,
      closeTo(1, 1e-9),
      reason: 'towards the right',
    );
    p.gradient = false;
    expect(overlayGradient(p), isNull);
  });

  testWidgets('angle wheel snaps to 15° and the box sets exact degrees', (
    tester,
  ) async {
    var angle = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => AngleField(
                value: angle,
                onChanged: (v) => setState(() => angle = v),
              ),
            ),
          ),
        ),
      ),
    );
    final wheel = tester.getRect(
      find.byTooltip('Drag to set the direction (snaps to 15°)'),
    );
    // Drag to the right-hand side of the wheel, slightly below centre.
    await tester.dragFrom(
      wheel.center + const Offset(25, 3),
      const Offset(1, 0),
    );
    await tester.pump();
    expect(angle % 15, 0);
    expect(angle, 90);
    await tester.enterText(find.byType(TextField), '37');
    await tester.pump();
    expect(angle, 37);
  });

  testWidgets('colour picker accepts a hex code', (tester) async {
    Color picked = Colors.black;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorField(value: picked, onChanged: (c) => picked = c),
        ),
      ),
    );
    await tester.tap(find.byType(ColorField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#3584E4');
    await tester.pump();
    await tester.tap(find.text('Use colour'));
    await tester.pumpAndSettle();
    expect(picked, const Color(0xFF3584E4));
  });
}
