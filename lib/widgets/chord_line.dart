// One line of a chord sheet with chords above the words, as a single
// render object. Each chord and each piece of lyric is measured once (and
// again only if the text, style or text size changes); when the line's
// width changes (the sidebar sliding, the window resizing) it only works
// out again where the line wraps — arithmetic, no text layout — so long
// songs resize smoothly. (It replaces a Wrap of Column(chord, lyric) per
// word: thousands of widgets laid out again on every width change.)

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../inline_format.dart';
import '../music.dart' show ChordExtensions, splitChordExtension;
import '../eink.dart';

/// A chord (or none) over the words that follow it; [runs]: the words
/// with inline formatting (bold, colours…), when they have any.
typedef ChordPiece = ({String chord, String lyric, List<StyledRun>? runs});

class ChordLine extends LeafRenderObjectWidget {
  final List<ChordPiece> pieces;
  final TextStyle chordStyle;
  final TextStyle lyricStyle;

  /// A chord was tapped: the piece's index, and where the chord is on
  /// screen. Null: chords aren't tappable.
  final void Function(int index, Rect onScreen)? onChordTap;

  /// Pieces whose chord gets the Gospelizer's rainbow glow behind it.
  final Set<int> glowing;

  /// Where the chords' extensions (7, maj7, sus4…) sit.
  final ChordExtensions extensions;

  const ChordLine({
    super.key,
    required this.pieces,
    required this.chordStyle,
    required this.lyricStyle,
    this.onChordTap,
    this.glowing = const {},
    this.extensions = ChordExtensions.inline,
  });

  @override
  RenderChordLine createRenderObject(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return RenderChordLine(
        pieces: pieces,
        chordStyle: base.merge(chordStyle),
        lyricStyle: base.merge(lyricStyle),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )
      ..onChordTap = onChordTap
      ..glowing = glowing
      ..extensions = extensions;
  }

  @override
  void updateRenderObject(BuildContext context, RenderChordLine renderObject) {
    final base = DefaultTextStyle.of(context).style;
    renderObject.update(
      pieces: pieces,
      chordStyle: base.merge(chordStyle),
      lyricStyle: base.merge(lyricStyle),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    );
    renderObject
      ..onChordTap = onChordTap
      ..glowing = glowing
      ..extensions = extensions;
  }
}

class RenderChordLine extends RenderBox
    with EinkLine, RelayoutWhenSystemFontsChangeMixin {
  RenderChordLine({
    required List<ChordPiece> pieces,
    required TextStyle chordStyle,
    required TextStyle lyricStyle,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    _pieces = pieces;
    _chordStyle = chordStyle;
    _lyricStyle = lyricStyle;
    _textScaler = textScaler;
    _textDirection = textDirection;
  }

  late List<ChordPiece> _pieces;

  /// See [ChordLine.extensions].
  ChordExtensions get extensions => _extensions;
  ChordExtensions _extensions = ChordExtensions.inline;
  set extensions(ChordExtensions v) {
    if (v == _extensions) return;
    _extensions = v;
    _dispose();
    markNeedsLayout();
  }

  /// See [ChordLine.glowing].
  Set<int> get glowing => _glowing;
  Set<int> _glowing = const {};
  set glowing(Set<int> v) {
    if (setEquals(v, _glowing)) return;
    _glowing = v;
    markNeedsPaint();
  }

  late TextStyle _chordStyle;
  late TextStyle _lyricStyle;
  late TextScaler _textScaler;
  late TextDirection _textDirection;

  /// Measured text: [chord, lyric] per piece (null until needed).
  List<(_ChordText, TextPainter)>? _painters;

  /// Where each piece goes (from the last layout).
  final List<Offset> _chordAt = [];
  final List<Offset> _lyricAt = [];

  /// Where each chord and its words were put (tests).
  @visibleForTesting
  List<(Offset, Offset)> get placed => [
    for (var i = 0; i < _chordAt.length; i++) (_chordAt[i], _lyricAt[i]),
  ];

  void update({
    required List<ChordPiece> pieces,
    required TextStyle chordStyle,
    required TextStyle lyricStyle,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    if (_samePieces(pieces) &&
        chordStyle == _chordStyle &&
        lyricStyle == _lyricStyle &&
        textScaler == _textScaler &&
        textDirection == _textDirection) {
      return;
    }
    _pieces = pieces;
    _chordStyle = chordStyle;
    _lyricStyle = lyricStyle;
    _textScaler = textScaler;
    _textDirection = textDirection;
    _dispose();
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  bool _samePieces(List<ChordPiece> other) {
    if (identical(other, _pieces)) return true;
    if (other.length != _pieces.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != _pieces[i]) return false;
    }
    return true;
  }

  TextPainter _painter(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: _textDirection,
    textScaler: _textScaler,
  )..layout();

  /// How many times the text was measured (tests).
  @visibleForTesting
  int measures = 0;

  List<(_ChordText, TextPainter)> get _measured =>
      _painters ?? (measures++, _painters = _measure()).$2;

  List<(_ChordText, TextPainter)> _measure() => [
    for (final p in _pieces)
      (
        _ChordText.of(
          p.chord,
          _chordStyle,
          _extensions,
          _textDirection,
          _textScaler,
        ),
        p.runs == null
            ? _painter(p.lyric, _lyricStyle)
            : (TextPainter(
                text: TextSpan(
                  style: _lyricStyle,
                  children: [
                    for (final r in p.runs!)
                      TextSpan(
                        text: r.text,
                        style: r.style.isPlain ? null : r.style.on(_lyricStyle),
                      ),
                  ],
                ),
                textDirection: _textDirection,
                textScaler: _textScaler,
              )..layout()),
      ),
  ];

  void _dispose() {
    for (final (c, l) in _painters ?? const <(_ChordText, TextPainter)>[]) {
      c.dispose();
      l.dispose();
    }
    _painters = null;
  }

  /// A font arrived (on the web, the fallback font for letters the app's
  /// fonts lack, e.g. styled 𝘐𝘵𝘢𝘭𝘪𝘤𝘴, loads after the first layout): the
  /// text measured with boxes is measured again.
  @override
  void systemFontsDidChange() {
    _dispose();
    super.systemFontsDidChange();
  }

  @override
  void dispose() {
    _dispose();
    _tap.dispose();
    super.dispose();
  }

  /// Lays the pieces out in rows no wider than [maxWidth]; returns the
  /// size, and (when [place]) records where each piece goes.
  Size _flow(double maxWidth, {required bool place}) {
    final painters = _measured;
    if (place) {
      _chordAt.clear();
      _lyricAt.clear();
    }
    var x = 0.0, rowTop = 0.0, rowHeight = 0.0, widest = 0.0;
    final row = <int>[];

    void endRow() {
      if (place) {
        // Pieces sit on the row's bottom (as the words line up).
        for (final i in row) {
          final (c, l) = painters[i];
          final top = rowTop + rowHeight - (c.height + l.height);
          _chordAt[i] = Offset(_chordAt[i].dx, top);
          _lyricAt[i] = Offset(_lyricAt[i].dx, top + c.height);
        }
      }
      row.clear();
      rowTop += rowHeight;
      rowHeight = 0;
      x = 0;
    }

    for (var i = 0; i < painters.length; i++) {
      final (c, l) = painters[i];
      // Natural width, unless the piece is wider than the whole line:
      // then it wraps its own words.
      if (l.width != l.maxIntrinsicWidth) l.layout();
      if (maxWidth.isFinite && l.width > maxWidth + 0.5) {
        l.layout(maxWidth: maxWidth);
      }
      final w = math.max(c.width, l.width);
      if (x > 0 && x + w > maxWidth) endRow();
      if (place) {
        _chordAt.add(Offset(x, 0));
        _lyricAt.add(Offset(x, 0));
      }
      row.add(i);
      x += w;
      widest = math.max(widest, x);
      rowHeight = math.max(rowHeight, c.height + l.height);
    }
    endRow();
    if (place && _textDirection == TextDirection.rtl) {
      // Right to left: each row starts at the right, and a chord sits
      // over the right-hand end of its words (where they begin).
      for (var i = 0; i < _chordAt.length; i++) {
        final (c, l) = painters[i];
        final right = widest - _chordAt[i].dx;
        _chordAt[i] = Offset(right - c.width, _chordAt[i].dy);
        _lyricAt[i] = Offset(right - l.width, _lyricAt[i].dy);
      }
    }
    return Size(widest, rowTop);
  }

  @override
  void performLayout() {
    final s = _flow(constraints.maxWidth, place: true);
    size = constraints.constrain(s);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(_flow(constraints.maxWidth, place: false));

  @override
  double computeMinIntrinsicWidth(double height) {
    var w = 0.0;
    for (final (c, l) in _measured) {
      w = math.max(w, math.max(c.minIntrinsicWidth, l.minIntrinsicWidth));
    }
    return w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var w = 0.0;
    for (final (c, l) in _measured) {
      w += math.max(c.maxIntrinsicWidth, l.maxIntrinsicWidth);
    }
    return w;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _flow(width, place: false).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _flow(width, place: false).height;

  @override
  void paint(PaintingContext context, Offset offset) {
    final painters = _measured;
    for (final i in _glowing) {
      if (i < painters.length && i < _chordAt.length) {
        _paintGlow(context.canvas, offset + _chordAt[i], painters[i].$1, i);
      }
    }
    for (var i = 0; i < painters.length && i < _chordAt.length; i++) {
      final (c, l) = painters[i];
      c.paint(context.canvas, offset + _chordAt[i]);
      l.paint(context.canvas, offset + _lyricAt[i]);
    }
  }

  /// The Gospelizer's glow: a soft coloured shadow behind the chord's name
  /// (blue → violet → magenta → red → amber, as Apple Intelligence's glow),
  /// blurred until it has no edge.
  void _paintGlow(Canvas canvas, Offset at, _ChordText c, int i) {
    final text = _pieces[i].chord.trimRight();
    if (text.isEmpty) return;
    final w = c.letters;
    final h = c.height;
    // A little below the letters, like a shadow.
    final r = Rect.fromLTWH(at.dx, at.dy + h * 0.22, w, h * 0.66);
    final shader = LinearGradient(
      colors: const [
        Color(0xFF2E6BFF),
        Color(0xFF9B5CFF),
        Color(0xFFE14FD8),
        Color(0xFFFF4D5E),
        Color(0xFFFFA23A),
      ],
      // (Each chord's colours run a different way.)
      begin: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
      end: i.isEven ? Alignment.centerRight : Alignment.centerLeft,
    ).createShader(r.inflate(h * 0.2));
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(h * 0.33)),
      Paint()
        ..shader = shader
        ..color = const Color(0x99FFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.3),
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;

  // ---- Tapping a chord ----

  void Function(int index, Rect onScreen)? onChordTap;
  int? _tapped;
  late final TapGestureRecognizer _tap = TapGestureRecognizer(debugOwner: this)
    ..onTap = () {
      final i = _tapped;
      if (i == null || !attached || i >= _chordAt.length) return;
      final c = _measured[i].$1;
      final topLeft = localToGlobal(_chordAt[i]);
      onChordTap?.call(i, topLeft & c.size);
    };

  /// The piece whose chord is at [position] (a little slack around it).
  int? _chordAtPosition(Offset position) {
    final painters = _measured;
    for (var i = 0; i < painters.length && i < _chordAt.length; i++) {
      if (_pieces[i].chord.trim().isEmpty) continue;
      final c = painters[i].$1;
      final r = (_chordAt[i] & c.size).inflate(4);
      if (r.contains(position)) return i;
    }
    return null;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (onChordTap == null || event is! PointerDownEvent) return;
    final i = _chordAtPosition(entry.localPosition);
    if (i == null) return;
    // Joins the gesture arena first (innermost), so a tap on a chord
    // doesn't also select the part around it.
    _tapped = i;
    _tap.addPointer(event);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = _pieces.map((p) => p.lyric).join()
      ..textDirection = _textDirection;
  }
}

/// A chord's name as drawn: its root and minor marker, then its extension
/// (smaller, raised or lowered when chosen), then its bass ("C", "maj7",
/// "/E"). Measured once; laid out as one piece of text would be.
class _ChordText {
  final TextPainter head;
  final TextPainter? ext, tail;

  /// Where the extension sits from the top, and how far everything is
  /// moved down so a raised one stays inside the chord's box.
  final double extTop, top;

  /// The width of the letters, without the spaces after them.
  final double letters;

  _ChordText._(
    this.head,
    this.ext,
    this.tail,
    this.extTop,
    this.top,
    this.letters,
  );

  factory _ChordText.of(
    String chord,
    TextStyle style,
    ChordExtensions place,
    TextDirection direction,
    TextScaler scaler,
  ) {
    TextPainter paint(String t, TextStyle st) => TextPainter(
      text: TextSpan(text: t, style: st),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    final word = chord.trimRight();
    final spaces = chord.substring(word.length);
    final split = place == ChordExtensions.inline
        ? null
        : splitChordExtension(word);
    if (split == null) {
      final p = paint(chord, style);
      final letters = spaces.isEmpty
          ? p.width
          : p
                .getOffsetForCaret(TextPosition(offset: word.length), Rect.zero)
                .dx;
      return _ChordText._(p, null, null, 0, 0, letters);
    }
    final (root, extension, bass) = split;
    final size = style.fontSize ?? 14;
    final head = paint(root, style);
    final ext = paint(extension, style.copyWith(fontSize: size * .72));
    final tail = paint('$bass$spaces', style);
    double base(TextPainter p) =>
        p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    // (its baseline a third of the size up, or a fifth down)
    final shift = place == ChordExtensions.raised ? -size * .34 : size * .2;
    final extTop = base(head) - base(ext) + scaler.scale(shift);
    final top = extTop < 0 ? -extTop : 0.0;
    final bassLetters = bass.isEmpty
        ? 0.0
        : tail
              .getOffsetForCaret(TextPosition(offset: bass.length), Rect.zero)
              .dx;
    return _ChordText._(
      head,
      ext,
      tail,
      extTop,
      top,
      head.width + ext.width + bassLetters,
    );
  }

  double get width => head.width + (ext?.width ?? 0) + (tail?.width ?? 0);

  // (a chord never wraps: its narrowest and widest are its width)
  double get minIntrinsicWidth => width;
  double get maxIntrinsicWidth => width;

  double get height => ext == null
      ? head.height
      : math.max(head.height + top, top + extTop + ext!.height);

  Size get size => Size(width, height);

  void paint(Canvas canvas, Offset at) {
    head.paint(canvas, at + Offset(0, top));
    if (ext case final e?) {
      e.paint(canvas, at + Offset(head.width, top + extTop));
      tail!.paint(canvas, at + Offset(head.width + e.width, top));
    }
  }

  void dispose() {
    head.dispose();
    ext?.dispose();
    tail?.dispose();
  }
}
