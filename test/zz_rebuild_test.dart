import 'dart:io';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rebuilds while scrolling the song list', (tester) async {
    tester.view.physicalSize = const Size(1140, 912);
    tester.view.devicePixelRatio = 1;
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final model = PresenterModel();
    await model.load();
    model.importFiles([
      (
        'l.json',
        File('.backup-sample/library_2026-10-05.json').readAsStringSync(),
      ),
    ]);
    await tester.pumpWidget(
      BilingualProjectorApp(
        model: model,
        home: OperatorScreen(model: model),
      ),
    );
    await tester.pumpAndSettle();
    final counts = <String, int>{};
    debugOnRebuildDirtyWidget = (e, builtOnce) {
      final k = e.widget.runtimeType.toString();
      counts[k] = (counts[k] ?? 0) + 1;
    };
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    for (var i = 0; i < 20; i++) {
      await tester.sendEventToBinding(pointer.hover(const Offset(150, 450)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = null;
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print(
      'total rebuilds over 20 scroll frames: ${counts.values.fold(0, (a, b) => a + b)}',
    );
    // ignore: avoid_print
    print(top.take(25).map((e) => '${e.key}=${e.value}').join('  '));
  });
}
