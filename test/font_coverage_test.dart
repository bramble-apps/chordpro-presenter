import 'dart:convert';
import 'dart:io';

import 'package:bilingual_projector/export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  final real = File('.backup-sample/library_2026-10-05.json');
  test('every character in the library prints with Noto Sans', () {
    final parser = TtfParser(
      File('assets/fonts/NotoSans-Regular.ttf')
          .readAsBytesSync()
          .buffer
          .asByteData(),
    );
    final json = jsonDecode(real.readAsStringSync()) as Map<String, dynamic>;
    final missing = <int, int>{};
    for (final s in (json['songs'] as List).cast<Map<String, dynamic>>()) {
      for (final field in [
        'title',
        'rawData',
        'artist',
        'copyright',
        'footer',
      ]) {
        final text = s[field];
        if (text is! String) continue;
        for (final (run, _, _) in foldStyledLetters(text)) {
          for (final cp in run.runes) {
            if (cp < 0x20) continue;
            if (!parser.charToGlyphIndexMap.containsKey(cp)) {
              missing[cp] = (missing[cp] ?? 0) + 1;
            }
          }
        }
      }
    }
    expect(
      missing.map((k, v) => MapEntry('U+${k.toRadixString(16)}', v)),
      isEmpty,
    );
  }, skip: !real.existsSync() ? 'backup not downloaded' : false);
}
