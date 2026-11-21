import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // With the sidebar closed, the sidebar button (as seen: its round backing,
  // or the button itself in a header bar) is as far from the window's left
  // edge as the toolbar (its pill, or its last button) is from the right.
  for (final style in UiStyle.values) {
    testWidgets('sidebar button and toolbar: the same gap (${style.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      KeyValueStore.memory.clear();
      PresenterModel.saveDelay = Duration.zero;
      final model = PresenterModel();
      await model.load();
      model.updateSettings((s) => s..uiStyle = style);
      await tester.pumpWidget(
        BilingualProjectorApp(
          model: model,
          home: OperatorScreen(model: model),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide sidebar'));
      await tester.pumpAndSettle();
      final width = tester.view.physicalSize.width;

      /// The outermost surface round [f] that isn't the whole window.
      Rect seen(Finder f) {
        final rects = [
          for (final e
              in find
                  .ancestor(of: f, matching: find.byType(Material))
                  .evaluate())
            tester.getRect(find.byElementPredicate((x) => x == e)),
        ].where((r) => r.width < width / 2).toList();
        return rects.last;
      }

      final left = seen(find.byTooltip('Show sidebar')).left;
      final right = width - seen(find.byTooltip('Settings')).right;
      expect(left, closeTo(right, .5), reason: 'left $left, right $right');
    });
  }
}
