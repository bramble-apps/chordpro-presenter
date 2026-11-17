import 'dart:typed_data';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/pdfs.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/pdf_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crop finds the printing, with a little air around it', () {
    const w = 100, h = 200;
    final rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
    // A dark block from (30, 40) to (69, 159).
    for (var y = 40; y < 160; y++) {
      for (var x = 30; x < 70; x++) {
        final i = (y * w + x) * 4;
        rgba[i] = rgba[i + 1] = rgba[i + 2] = 0;
      }
    }
    final r = inkBounds(rgba, w, h);
    expect(r.left, closeTo(0.26, 0.03));
    expect(r.right, closeTo(0.74, 0.03));
    expect(r.top, closeTo(0.18, 0.02));
    expect(r.bottom, closeTo(0.82, 0.02));
    // A blank page stays whole.
    expect(
      inkBounds(Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255), w, h),
      const Rect.fromLTWH(0, 0, 1, 1),
    );
  });

  test('theme colours: white paper → background, black ink → text', () {
    final m = themeColorFilter(
      const Color(0xFF101418),
      const Color(0xFFE0E4E8),
    );
    // ColorFilter.matrix keeps its matrix; apply it to white and black.
    final values = (m.toString().split('[').last.split(']').first)
        .split(',')
        .map((v) => double.parse(v.trim()))
        .toList();
    List<double> apply(double r, double g, double b) => [
      for (var row = 0; row < 3; row++)
        values[row * 5] * r +
            values[row * 5 + 1] * g +
            values[row * 5 + 2] * b +
            values[row * 5 + 4],
    ];
    expect(apply(255, 255, 255).map((v) => v.round()), [0x10, 0x14, 0x18]);
    expect(apply(0, 0, 0).map((v) => v.round()), [0xE0, 0xE4, 0xE8]);
  });

  testWidgets('crop and theme colours are toggles beside the tabs', (
    tester,
  ) async {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final model = PresenterModel();
    await model.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongDocTabs(
            song: Song(id: 's', title: 'S', raw: ''),
            chordPro: null,
            pdfs: const [PdfRef('missing', 'Lead.png')],
            model: model,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Crop the margins'));
    await tester.pump();
    expect(model.settings.sheetCrop, isTrue);
    expect(find.byTooltip('Show whole pages'), findsOneWidget);
    await tester.tap(find.byTooltip('Match the theme’s colours'));
    await tester.pump();
    expect(model.settings.sheetThemeColors, isTrue);
  });
}
