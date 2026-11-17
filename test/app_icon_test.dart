import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android: every icon shape is the plain one (no bevel, no rim)', () {
    final dir = Directory('android/app/src/main/res/mipmap-anydpi-v26');
    final icons = dir.listSync().whereType<File>().toList();
    expect(icons, isNotEmpty);
    for (final f in icons) {
      final xml = f.readAsStringSync();
      expect(xml, contains('@mipmap/ic_launcher_background'), reason: f.path);
      expect(xml, isNot(contains('ic_launcher_bg_')), reason: f.path);
    }
  });
}
