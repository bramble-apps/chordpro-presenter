import 'package:bilingual_projector/widgets/motion_icon.dart';
import 'package:bilingual_projector/widgets/motion_paths.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the moving icons\' shapes are on the 24 grid', () {
    for (final MapEntry(key: name, value: shapes) in motionPaths.entries) {
      expect(shapes, isNotEmpty, reason: name);
      for (final d in shapes) {
        final numbers = RegExp(r'-?\d*\.?\d+')
            .allMatches(d)
            .map((m) => double.parse(m[0]!));
        expect(
          numbers.every((v) => v > -2 && v < 26),
          isTrue,
          reason: '$name: $d',
        );
      }
    }
  });

  // Each icon moves while the pointer is over its button, then comes back
  // to rest (nothing left running).
  for (final m in IconMotion.values) {
    testWidgets('${m.name} moves on hover and settles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MotionHover(
              child: SizedBox.square(
                dimension: 48,
                child: Center(child: MotionIcon(m)),
              ),
            ),
          ),
        ),
      );
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      await g.moveTo(tester.getCenter(find.byType(MotionIcon)));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue, reason: 'moving');
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await g.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse, reason: 'at rest');
      await g.removePointer();
    });
  }
}
