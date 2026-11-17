import 'package:flutter/material.dart';

/// The look of one character in a sticky note.
@immutable
class CharStyle {
  final bool bold;
  final bool italic;
  final double size;
  const CharStyle({this.bold = false, this.italic = false, this.size = 16});

  CharStyle copyWith({bool? bold, bool? italic, double? size}) => CharStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    size: size ?? this.size,
  );

  @override
  bool operator ==(Object other) =>
      other is CharStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.size == size;

  @override
  int get hashCode => Object.hash(bold, italic, size);
}

/// A text field controller where every character has its own bold /
/// italic / size, kept in step as text is typed or deleted. Formatting
/// applies to the selection, or to everything when nothing is selected.
class RichNoteController extends TextEditingController {
  List<CharStyle> _styles;

  /// The look of newly typed text when the note is empty.
  CharStyle base;

  RichNoteController({
    required String text,
    required this.base,
    List<CharStyle>? styles,
  }) : _styles = styles != null && styles.length == text.length
           ? List.of(styles)
           : List.filled(text.length, base, growable: true),
       super(text: text);

  /// Builds a controller from saved runs (`[{t, b, i, s}, …]`), or from
  /// plain text in one style (older notes).
  factory RichNoteController.fromRuns(
    List<Map<String, dynamic>>? runs, {
    required String text,
    required CharStyle base,
  }) {
    if (runs == null || runs.isEmpty) {
      return RichNoteController(text: text, base: base);
    }
    final buf = StringBuffer();
    final styles = <CharStyle>[];
    for (final r in runs) {
      final t = r['t'] as String? ?? '';
      final st = CharStyle(
        bold: r['b'] == true,
        italic: r['i'] == true,
        size: (r['s'] as num?)?.toDouble() ?? base.size,
      );
      buf.write(t);
      styles.addAll(List.filled(t.length, st));
    }
    return RichNoteController(text: buf.toString(), base: base, styles: styles);
  }

  /// Consecutive characters with the same look, for saving.
  List<Map<String, dynamic>> toRuns() {
    final runs = <Map<String, dynamic>>[];
    var i = 0;
    while (i < text.length) {
      final st = _styles[i];
      var j = i + 1;
      while (j < text.length && _styles[j] == st) {
        j++;
      }
      runs.add({
        't': text.substring(i, j),
        'b': st.bold,
        'i': st.italic,
        's': st.size,
      });
      i = j;
    }
    return runs;
  }

  @override
  set value(TextEditingValue next) {
    final old = text;
    final now = next.text;
    if (old != now) {
      // What changed: the part between the common start and common end.
      var start = 0;
      final shorter = old.length < now.length ? old.length : now.length;
      while (start < shorter &&
          old.codeUnitAt(start) == now.codeUnitAt(start)) {
        start++;
      }
      var end = 0;
      while (end < shorter - start &&
          old.codeUnitAt(old.length - 1 - end) ==
              now.codeUnitAt(now.length - 1 - end)) {
        end++;
      }
      final inserted = now.length - start - end;
      // New text takes the look of the character before it.
      final typing = start > 0
          ? _styles[start - 1]
          : (_styles.isNotEmpty ? _styles.first : base);
      _styles = [
        ..._styles.sublist(0, start),
        ...List.filled(inserted, typing),
        ..._styles.sublist(old.length - end),
      ];
    }
    super.value = next;
  }

  /// The range formatting applies to: the selection, or everything.
  (int, int) get _range {
    final s = selection;
    if (!s.isValid || s.isCollapsed) return (0, text.length);
    return (s.start, s.end);
  }

  bool get _wholeNote {
    final s = selection;
    return !s.isValid || s.isCollapsed;
  }

  /// Whether all of the range has [test] (for the toolbar's on / off).
  bool all(bool Function(CharStyle) test) {
    final (a, b) = _range;
    if (a == b) return test(base);
    for (var i = a; i < b; i++) {
      if (!test(_styles[i])) return false;
    }
    return true;
  }

  void _apply(CharStyle Function(CharStyle) change) {
    final (a, b) = _range;
    for (var i = a; i < b; i++) {
      _styles[i] = change(_styles[i]);
    }
    if (_wholeNote) base = change(base);
    notifyListeners();
  }

  void toggleBold() {
    final on = !all((s) => s.bold);
    _apply((s) => s.copyWith(bold: on));
  }

  void toggleItalic() {
    final on = !all((s) => s.italic);
    _apply((s) => s.copyWith(italic: on));
  }

  void resize(double by) =>
      _apply((s) => s.copyWith(size: (s.size + by).clamp(10, 48)));

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    TextStyle look(CharStyle s) => TextStyle(
      fontWeight: s.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
      fontSize: s.size,
    );
    final children = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final st = _styles[i];
      var j = i + 1;
      while (j < text.length && _styles[j] == st) {
        j++;
      }
      children.add(TextSpan(text: text.substring(i, j), style: look(st)));
      i = j;
    }
    return TextSpan(style: style, children: children);
  }
}
