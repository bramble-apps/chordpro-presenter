// Inline text formatting in lyrics, JustChords' syntax:
//   *bold*   **italic**   ***bold italic***   _underline_
//   <red>red text<   <@yellow>highlighted<   <#33F3FF>hex colour<
//   <#@33F3FF>hex highlight<   <2>bigger<   <-1>smaller<
//   <red,@yellow,2>all three<
// A style ends where its mark comes again (a bare "<" for the tags); one
// left open has no effect (a lone "*" stays a "*"). Colours: blue, brown,
// cyan, gray, green, magenta, orange, purple, red, white, yellow. Sizes:
// each step is 20% (1 ≈ 120%, 2 ≈ 144%, -1 ≈ 83%).
//
// The chord sheet draws the styles; slides, translations and exports get
// the words without the marks.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The look of a run of words.
class InlineStyle {
  final bool bold, italic, underline;
  final Color? color, highlight;

  /// Size steps (0 normal, 1 ≈ 120%, -1 ≈ 83%).
  final int size;

  const InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
    this.highlight,
    this.size = 0,
  });

  static const plain = InlineStyle();

  bool get isPlain =>
      !bold &&
      !italic &&
      !underline &&
      color == null &&
      highlight == null &&
      size == 0;

  TextStyle on(TextStyle base) => base.copyWith(
    fontWeight: bold ? FontWeight.w800 : null,
    fontStyle: italic ? FontStyle.italic : null,
    decoration: underline ? TextDecoration.underline : null,
    color: color,
    backgroundColor: highlight?.withValues(alpha: 0.55),
    fontSize: size == 0
        ? null
        : (base.fontSize ?? 14) * math.pow(1.2, size.clamp(-4, 6)),
  );

  @override
  bool operator ==(Object other) =>
      other is InlineStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.color == color &&
      other.highlight == highlight &&
      other.size == size;

  @override
  int get hashCode =>
      Object.hash(bold, italic, underline, color, highlight, size);
}

/// Some words and their look.
typedef StyledRun = ({String text, InlineStyle style});

const Map<String, Color> _named = {
  'blue': Color(0xFF1E6FD9),
  'brown': Color(0xFF8B5A2B),
  'cyan': Color(0xFF00A3B4),
  'gray': Color(0xFF8A8A8A),
  'grey': Color(0xFF8A8A8A),
  'green': Color(0xFF2E9E44),
  'magenta': Color(0xFFC2189B),
  'orange': Color(0xFFE8820C),
  'purple': Color(0xFF7B3FC4),
  'red': Color(0xFFD93025),
  'white': Color(0xFFFFFFFF),
  'yellow': Color(0xFFF2C200),
};

final RegExp _anyMark = RegExp(r'[*_<]');

/// Whether [text] might hold formatting marks (cheap check).
bool hasInlineMarks(String text) => _anyMark.hasMatch(text);

Color? _color(String s) {
  final t = s.trim().toLowerCase();
  if (_named[t] case final c?) return c;
  final hex = RegExp(r'^#?([0-9a-f]{6})$').firstMatch(t);
  if (hex == null) return null;
  return Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16));
}

/// The tag `<spec>` as (colour, highlight, size), or null when it isn't
/// one ("<" in ordinary words).
(Color?, Color?, int?)? _tag(String spec) {
  if (spec.trim().isEmpty) return null;
  Color? color, highlight;
  int? size;
  for (final raw in spec.split(',')) {
    final p = raw.trim();
    if (p.isEmpty) return null;
    final n = int.tryParse(p);
    if (n != null) {
      size = n;
    } else if (p.startsWith('#@') || p.startsWith('@')) {
      highlight = _color(p.replaceFirst(RegExp(r'^#?@#?'), ''));
      if (highlight == null) return null;
    } else {
      color = _color(p);
      if (color == null) return null;
    }
  }
  return (color, highlight, size);
}

/// [pieces] (consecutive parts of one line, e.g. the words under each
/// chord) as styled runs each, with the marks taken out. Styles may run
/// across pieces.
List<List<StyledRun>> formatPieces(List<String> pieces) {
  final text = pieces.join();
  final pieceAt = <int>[
    for (final (i, p) in pieces.indexed)
      for (var k = 0; k < p.length; k++) i,
  ];

  // The marks: emphasis runs (*, **, ***, _) and tags (<spec> / bare <).
  final marks = <int, (String, int)>{}; // start → (kind, length)
  for (var i = 0; i < text.length;) {
    final c = text[i];
    if (c == '*') {
      var n = 1;
      while (i + n < text.length && text[i + n] == '*') {
        n++;
      }
      if (n <= 3) marks[i] = ('*$n', n);
      i += n;
    } else if (c == '_') {
      marks[i] = ('_', 1);
      i++;
    } else if (c == '<') {
      final close = text.indexOf('>', i + 1);
      final spec = close < 0 ? null : text.substring(i + 1, close);
      if (spec != null && !spec.contains('<') && _tag(spec) != null) {
        marks[i] = ('<open', close - i + 1);
        i = close + 1;
      } else {
        marks[i] = ('<close', 1);
        i++;
      }
    } else {
      i++;
    }
  }

  // Which emphasis marks pair up (an opener needs a closer of the same
  // kind later on the line); a tag needs a closing "<" or runs to the end.
  final paired = <int>{};
  final open = <String, int>{};
  int? openTag;
  for (final at in marks.keys.toList()..sort()) {
    final kind = marks[at]!.$1;
    if (kind == '<open') {
      openTag = at;
      paired.add(at);
    } else if (kind == '<close') {
      if (openTag != null) {
        paired.add(at);
        openTag = null;
      }
    } else if (open.containsKey(kind)) {
      paired
        ..add(open.remove(kind)!)
        ..add(at);
    } else {
      open[kind] = at;
    }
  }

  // Walk the line: style on, style off, words in between.
  final out = [for (final _ in pieces) <StyledRun>[]];
  var bold = false, italic = false, underline = false;
  Color? color, highlight;
  var size = 0;
  final buffer = StringBuffer();
  var bufferPiece = 0;
  InlineStyle style() => InlineStyle(
    bold: bold,
    italic: italic,
    underline: underline,
    color: color,
    highlight: highlight,
    size: size,
  );
  var current = style();
  void flush() {
    if (buffer.isEmpty) return;
    out[bufferPiece].add((text: buffer.toString(), style: current));
    buffer.clear();
  }

  for (var i = 0; i < text.length;) {
    final mark = paired.contains(i) ? marks[i] : null;
    if (mark != null) {
      flush();
      switch (mark.$1) {
        case '*1':
          bold = !bold;
        case '*2':
          italic = !italic;
        case '*3':
          bold = !bold;
          italic = !italic;
        case '_':
          underline = !underline;
        case '<open':
          final t = _tag(text.substring(i + 1, i + mark.$2 - 1))!;
          color = t.$1;
          highlight = t.$2;
          size = t.$3 ?? 0;
        case '<close':
          color = null;
          highlight = null;
          size = 0;
      }
      current = style();
      i += mark.$2;
      continue;
    }
    final piece = pieceAt[i];
    if (piece != bufferPiece) {
      flush();
      bufferPiece = piece;
    }
    buffer.write(text[i]);
    i++;
  }
  flush();
  return out;
}

/// [text] without its formatting marks.
String withoutInlineMarks(String text) {
  if (!hasInlineMarks(text)) return text;
  return formatPieces([text]).first.map((r) => r.text).join();
}
