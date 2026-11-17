import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/widgets/slide_capture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'projection_test.dart' show pumpApp;

void main() {
  testWidgets('cast pictures follow stage view, one per highlighted part', (
    tester,
  ) async {
    final model = await pumpApp(tester);
    expect(model.slides.length, greaterThanOrEqualTo(2));
    final context = tester.element(find.byType(OperatorScreen));

    Future<List<Uint8List>> lyrics() async => [
      for (final s in await captureSlides(
        context,
        slides: [model.slides[0]],
        settings: model.projection,
        font: model.projectorFont,
        projectorSize: model.projectorSize,
        stage: model.stageData,
        width: 320,
        firstWait: Duration.zero,
      ))
        s.png,
    ];

    Future<List<Uint8List>> stage() => captureStageSlides(
      context,
      slides: model.slides,
      indices: [0, 1],
      settings: model.projection,
      font: model.projectorFont,
      projectorSize: model.projectorSize,
      stage: model.stageData,
      width: 320,
      firstWait: Duration.zero,
    );

    // Frames only advance when the test pumps them.
    Future<T> run<T>(Future<T> Function() f) async {
      T? result;
      var done = false;
      f().then((r) {
        result = r;
        done = true;
      });
      for (var i = 0; i < 600 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue, reason: 'capture finished');
      return result as T;
    }

    final plain = await run(lyrics);
    model.projection.view = ProjectionView.stage;
    final sheet = await run(stage);

    expect(sheet, hasLength(2));
    expect(sheet.every((p) => p.isNotEmpty), isTrue);
    // Stage view isn't the lyrics look…
    expect(listEquals(sheet[0], plain.single), isFalse);
    // …and each slide highlights a different part.
    expect(listEquals(sheet[0], sheet[1]), isFalse);
  });
}
