import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'padding_check.dart';

void main() {
  // Done is the round ✓ at the top right, as far from the dialog's corner
  // as the title is from its edge; the list scrolls to the dialog's foot.
  for (final width in [1000.0, 400.0]) {
    testWidgets('settings: ✓ at the top, evenly padded ($width wide)', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      KeyValueStore.memory.clear();
      final model = PresenterModel();
      await model.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SettingsDialog(model: model),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
      final frame = find
          .ancestor(of: find.text('Settings'), matching: find.byType(Material))
          .first;
      final done = find.ancestor(
        of: find.byTooltip('Done'),
        matching: find.byType(IconButton),
      );
      final g = paddingGaps(
        tester,
        frame: frame,
        left: find.text('Settings'),
        top: done,
        right: done,
      );
      expect(g.top, closeTo(g.right, .5), reason: '$g');
      // the list reaches the dialog's foot (no button row under it)
      final list = tester.getRect(find.byType(SingleChildScrollView).last);
      expect(list.bottom, closeTo(tester.getRect(frame).bottom, 1));
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
    });
  }
}
