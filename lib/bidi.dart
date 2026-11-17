// Right-to-left text (Hebrew, Arabic, Persian, Urdu, Syriac, Thaana…):
// each line and slide goes right to left when most of its letters do, so
// a bilingual song can mix directions line by line.

import 'package:flutter/painting.dart';

final _chords = RegExp(r'\[[^\]]*\]|\{[^}]*\}');
final _rtl = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final _ltr = RegExp('[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]');

/// Whether most of the letters in [text] (chords and directives left out)
/// are written right to left.
bool isRightToLeft(String text) {
  final t = text.replaceAll(_chords, '');
  final rtl = _rtl.allMatches(t).length;
  if (rtl == 0) return false;
  return rtl > _ltr.allMatches(t).length;
}

/// The direction [text] is written in.
TextDirection directionOf(String text) =>
    isRightToLeft(text) ? TextDirection.rtl : TextDirection.ltr;
