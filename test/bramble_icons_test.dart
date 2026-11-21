import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every icon of lib/bramble_icons.dart (its character), read from the file.
List<(String, int)> _icons() => [
  for (final m in RegExp(
    r'static const IconData (\w+) = IconData\(\s*0x([0-9A-F]+)',
  ).allMatches(File('lib/bramble_icons.dart').readAsStringSync()))
    (m[1]!, int.parse(m[2]!, radix: 16)),
];

void main() {
  // Each icon's drawing sits centred in its box (as its artwork is in the
  // icon's square): none slid aside by the font's metrics.
  testWidgets('the icons are centred in their box', (tester) async {
    await tester.runAsync(() async {
      final l = FontLoader('BrambleIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/icons/BrambleIcons.ttf').readAsBytesSync(),
            ),
          ),
        );
      await l.load();
    });
    const size = 48.0;
    final icons = _icons();
    expect(icons.length, greaterThan(100));
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final off = <String, Offset>{};
    for (final (name, cp) in icons) {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: Icon(
                // (each icon in turn, read from the file)
                // ignore: non_const_argument_for_const_parameter
                IconData(cp, fontFamily: 'BrambleIcons'),
                size: size,
                color: const Color(0xFF000000),
              ),
            ),
          ),
        ),
      );
      final ink = await tester.runAsync(() async {
        final r =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await r.toImage();
        final px = (await img.toByteData())!;
        var (x0, y0, x1, y1) = (size, size, -1.0, -1.0);
        for (var y = 0; y < img.height; y++) {
          for (var x = 0; x < img.width; x++) {
            if (px.getUint8((y * img.width + x) * 4 + 3) > 64) {
              if (x < x0) x0 = x.toDouble();
              if (y < y0) y0 = y.toDouble();
              if (x > x1) x1 = x.toDouble();
              if (y > y1) y1 = y.toDouble();
            }
          }
        }
        return Rect.fromLTRB(x0, y0, x1 + 1, y1 + 1);
      });
      off[name] = ink!.center - const Offset(size / 2, size / 2);
    }
    // (the artwork's own small offsets: a play triangle sits a little
    // right, a pen nib up and right; never the whole margin)
    final far = {
      for (final e in off.entries)
        if (e.value.dx.abs() > 5 || e.value.dy.abs() > 5) e.key: e.value,
    };
    expect(far, isEmpty, reason: 'off centre (px at $size): $far');
    final mean =
        off.values.fold(0.0, (a, o) => a + o.dx.abs() + o.dy.abs()) /
        off.length;
    expect(mean, lessThan(2), reason: 'average offset $mean px');
  });
}
