import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'music.dart';

/// How the selected part is marked on the chord sheet.
enum SelectionStyle { bar, highlight, both }

/// How chord beats are drawn on the chord sheet (as in JustChords).
enum ChordBeatStyle {
  dots('Dots'),
  dotsHideFull('Dots – Hide Full Measures'),
  stacks('Stacks'),
  pills('Pills'),
  timeline('Timeline');

  final String label;
  const ChordBeatStyle(this.label);

  /// Drawn as bars in boxes (with "Bars per line"), not over the lyrics.
  bool get boxed => this == stacks || this == pills || this == timeline;
}

enum SheetElement {
  title,
  artist,
  details,
  headings,
  lyrics,
  chords,
  notes,
  footer,
}

extension SheetElementLabel on SheetElement {
  String get label => switch (this) {
    SheetElement.title => 'Title',
    SheetElement.artist => 'Artist / Subtitle',
    SheetElement.details => 'Details (key, tempo, time)',
    SheetElement.notes => 'Notes',
    SheetElement.footer => 'Footer (copyright, CCLI)',
    SheetElement.headings => 'Headings',
    SheetElement.lyrics => 'Lyrics',
    SheetElement.chords => 'Chords',
  };

  /// All caps would turn "Am" into "AM" (major), so chords can't use it.
  bool get allowsCaps => this != SheetElement.chords;
}

/// Highlight choices (index 0 = none). Semi-transparent so they work in
/// light and dark mode.
const List<Color?> highlightColors = [
  null,
  Color(0x80FFEB3B), // yellow
  Color(0x6666BB6A), // green
  Color(0x6642A5F5), // blue
  Color(0x66F06292), // pink
  Color(0x66FFA726), // orange
];

class ElementStyle {
  bool bold;
  bool italic;
  bool caps;
  bool underline;
  bool hidden;
  double size;
  int highlight;

  /// Custom highlight colour (#RRGGBB, drawn see-through); overrides
  /// [highlight] when set.
  String? highlightHex;

  /// Text colour: a name from [namedColors] or a custom #RRGGBB;
  /// null = theme default.
  String? color;

  ElementStyle({
    this.bold = false,
    this.italic = false,
    this.caps = false,
    this.underline = false,
    this.hidden = false,
    required this.size,
    this.highlight = 0,
    this.highlightHex,
    this.color,
  });

  /// The highlight colour actually drawn (null = none).
  Color? get highlightColor {
    final custom = colorFromHex(highlightHex);
    if (custom != null) return custom.withValues(alpha: 0.45);
    return highlightColors[highlight];
  }

  TextStyle textStyle({Color? color, String? family}) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    decoration: underline ? TextDecoration.underline : null,
    backgroundColor: highlightColor,
    color: colorNamed(this.color) ?? color,
  );

  String apply(String text) => caps ? text.toUpperCase() : text;

  Map<String, dynamic> toJson() => {
    'bold': bold,
    'italic': italic,
    'caps': caps,
    'underline': underline,
    'hidden': hidden,
    'size': size,
    'highlight': highlight,
    'highlightHex': highlightHex,
    'color': color,
  };

  void updateFrom(Map<String, dynamic> j) {
    bold = j['bold'] as bool? ?? bold;
    italic = j['italic'] as bool? ?? italic;
    caps = j['caps'] as bool? ?? caps;
    underline = j['underline'] as bool? ?? underline;
    hidden = j['hidden'] as bool? ?? hidden;
    size = (j['size'] as num?)?.toDouble() ?? size;
    final h = j['highlight'] as int? ?? highlight;
    highlight = (h >= 0 && h < highlightColors.length) ? h : 0;
    highlightHex = j.containsKey('highlightHex')
        ? j['highlightHex'] as String?
        : highlightHex;
    color = j.containsKey('color') ? j['color'] as String? : color;
  }
}

/// Everything on the "Page" tab of the Format panel.
class SheetFormat {
  final Map<SheetElement, ElementStyle> styles = {
    SheetElement.title: ElementStyle(bold: true, size: 24),
    SheetElement.artist: ElementStyle(size: 15),
    SheetElement.details: ElementStyle(size: 12),
    SheetElement.notes: ElementStyle(italic: true, size: 13),
    SheetElement.footer: ElementStyle(size: 10),
    SheetElement.headings: ElementStyle(bold: true, italic: true, size: 14),
    SheetElement.lyrics: ElementStyle(size: 13),
    SheetElement.chords: ElementStyle(bold: true, size: 13),
  };
  bool pinHeader = false;
  bool chordsInline = false;

  /// Section labels as short badges on a rail in a margin, as tall as the
  /// section ("V1", "C"): 'left' or 'right' ('' off: labels above as text).
  String marginLabels = '';

  /// Guitar tabs: solid strings with the frets on them (modern), or the
  /// text as typed in a fixed-width font (classic).
  bool tabsModern = true;

  /// Show songs as printed pages (with columns) instead of one long sheet.
  /// A song can have its own setting (see [SheetLayout]).
  bool pageMode = false;

  /// Columns per page (page mode and PDF).
  int columns = 1;

  /// Chord beats: how long each chord lasts, shown on the chord sheet.
  /// A song can have its own setting (see [BeatSettings]).
  bool chordBeats = false;
  ChordBeatStyle beatStyle = ChordBeatStyle.dots;
  int barsPerLine = 4;

  /// A4 paper instead of US Letter (page mode and PDF).
  bool paperA4 = false;

  /// Play sections in the song's (or setlist entry's) arrangement order.
  bool followArrangement = true;

  /// Selected part: a bar on the left, a tinted background, or both.
  SelectionStyle selectionStyle = SelectionStyle.both;
  ChordNotation notation = ChordNotation.standard;

  /// Dual chords: a second notation shown beside each chord, e.g. "G (1)"
  /// (null: off).
  ChordNotation? dualNotation;
  MinorStyle minorStyle = MinorStyle.m;
  Accidentals accidentals = Accidentals.auto;

  /// How major sevenths, half-diminished and diminished chords are written
  /// (as in the song unless chosen), and where extensions sit.
  MajorSymbol majorSymbol = MajorSymbol.asWritten;
  HalfDimSymbol halfDimSymbol = HalfDimSymbol.asWritten;
  DimSymbol dimSymbol = DimSymbol.asWritten;
  ChordExtensions chordExtensions = ChordExtensions.inline;

  ChordSymbols get symbols =>
      ChordSymbols(major: majorSymbol, halfDim: halfDimSymbol, dim: dimSymbol);

  ElementStyle operator [](SheetElement e) => styles[e]!;

  /// How linked sections (a verse's translation…) look on the chord sheet,
  /// stage view and PDF.
  final LinkedStyle linked = LinkedStyle();

  Map<String, dynamic> toJson() => {
    'styles': {for (final e in styles.entries) e.key.name: e.value.toJson()},
    'linked': linked.toJson(),
    'pinHeader': pinHeader,
    'marginLabels': marginLabels,
    'pageMode': pageMode,
    'columns': columns,
    'chordBeats': chordBeats,
    'beatStyle': beatStyle.name,
    'barsPerLine': barsPerLine,
    'paperA4': paperA4,
    'chordsInline': chordsInline,
    'tabsModern': tabsModern,
    'followArrangement': followArrangement,
    'selectionStyle': selectionStyle.name,
    'notation': notation.name,
    'dualNotation': dualNotation?.name,
    'minorStyle': minorStyle.name,
    'accidentals': accidentals.name,
    'majorSymbol': majorSymbol.name,
    'halfDimSymbol': halfDimSymbol.name,
    'dimSymbol': dimSymbol.name,
    'chordExtensions': chordExtensions.name,
  };

  void updateFrom(Map<String, dynamic> j) {
    final s = j['styles'];
    if (s is Map<String, dynamic>) {
      for (final e in SheetElement.values) {
        final v = s[e.name];
        if (v is Map<String, dynamic>) styles[e]!.updateFrom(v);
      }
    }
    final l = j['linked'];
    if (l is Map<String, dynamic>) linked.updateFrom(l);
    pinHeader = j['pinHeader'] as bool? ?? pinHeader;
    marginLabels = j['marginLabels'] as String? ?? marginLabels;
    pageMode = j['pageMode'] as bool? ?? pageMode;
    columns = ((j['columns'] as num?)?.toInt() ?? columns).clamp(1, 3);
    paperA4 = j['paperA4'] as bool? ?? paperA4;
    chordBeats = j['chordBeats'] as bool? ?? chordBeats;
    beatStyle = ChordBeatStyle.values.asNameMap()[j['beatStyle']] ?? beatStyle;
    barsPerLine = ((j['barsPerLine'] as num?)?.toInt() ?? barsPerLine).clamp(
      1,
      8,
    );
    chordsInline = j['chordsInline'] as bool? ?? chordsInline;
    tabsModern = j['tabsModern'] as bool? ?? tabsModern;
    followArrangement = j['followArrangement'] as bool? ?? followArrangement;
    selectionStyle =
        SelectionStyle.values.asNameMap()[j['selectionStyle']] ??
        selectionStyle;
    notation = ChordNotation.values.asNameMap()[j['notation']] ?? notation;
    dualNotation = j.containsKey('dualNotation')
        ? ChordNotation.values.asNameMap()[j['dualNotation']]
        : dualNotation;
    minorStyle = MinorStyle.values.asNameMap()[j['minorStyle']] ?? minorStyle;
    accidentals =
        Accidentals.values.asNameMap()[j['accidentals']] ?? accidentals;
    majorSymbol =
        MajorSymbol.values.asNameMap()[j['majorSymbol']] ?? majorSymbol;
    halfDimSymbol =
        HalfDimSymbol.values.asNameMap()[j['halfDimSymbol']] ?? halfDimSymbol;
    dimSymbol = DimSymbol.values.asNameMap()[j['dimSymbol']] ?? dimSymbol;
    chordExtensions =
        ChordExtensions.values.asNameMap()[j['chordExtensions']] ??
        chordExtensions;
  }
}

/// Named colours used by tags and setlist items (same names as the
/// imported library: blue, red, green...).
const Map<String, Color> namedColors = {
  'red': Color(0xFFE53935),
  'orange': Color(0xFFFB8C00),
  'yellow': Color(0xFFFDD835),
  'green': Color(0xFF43A047),
  'mint': Color(0xFF26A69A),
  'teal': Color(0xFF00897B),
  'cyan': Color(0xFF00ACC1),
  'blue': Color(0xFF1E88E5),
  'indigo': Color(0xFF3949AB),
  'purple': Color(0xFF8E24AA),
  'pink': Color(0xFFD81B60),
  'brown': Color(0xFF6D4C41),
  'gray': Color(0xFF757575),
};

/// A named colour, or a custom `#RRGGBB`.
Color? colorNamed(String? name) => namedColors[name] ?? colorFromHex(name);

/// Parses `#RRGGBB` (null if it isn't one).
Color? colorFromHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

double _lum(Color c) => c.computeLuminance();

double contrastRatio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// [c], darkened or lightened just enough to be readable on [bg]
/// (WCAG 4.5:1), e.g. a light chord colour on a white stage screen.
Color readableOn(Color c, Color bg, {double ratio = 4.5}) {
  if (contrastRatio(c, bg) >= ratio) return c;
  final toward = _lum(bg) > 0.5 ? Colors.black : Colors.white;
  for (var t = 0.1; t <= 1.0; t += 0.1) {
    final m = Color.lerp(c, toward, t)!;
    if (contrastRatio(m, bg) >= ratio) return m;
  }
  return toward;
}

/// How one song is laid out: page mode and columns, from the song's own
/// setting if it has one, otherwise everyone's.
class SheetLayout {
  final bool pageMode;
  final int columns;
  final bool paperA4;

  /// The song has its own setting (not following all songs).
  final bool own;

  const SheetLayout({
    required this.pageMode,
    required this.columns,
    required this.paperA4,
    this.own = false,
  });

  /// Paper size in points (what the PDF uses too).
  Size get paper => paperA4 ? const Size(595.28, 841.89) : const Size(612, 792);

  static SheetLayout of(SheetFormat f, Map<String, dynamic> songExtra) {
    final o = songExtra['layout'];
    if (o is Map) {
      return SheetLayout(
        pageMode: o['pageMode'] as bool? ?? f.pageMode,
        columns: ((o['columns'] as num?)?.toInt() ?? f.columns).clamp(1, 3),
        paperA4: f.paperA4,
        own: true,
      );
    }
    return SheetLayout(
      pageMode: f.pageMode,
      columns: f.columns,
      paperA4: f.paperA4,
    );
  }
}

/// Chord beats for one song: its own setting if it has one, otherwise
/// everyone's.
class BeatSettings {
  final bool show;
  final ChordBeatStyle style;
  final int barsPerLine;

  /// The song has its own setting (not following all songs).
  final bool own;

  const BeatSettings({
    required this.show,
    required this.style,
    required this.barsPerLine,
    this.own = false,
  });

  static BeatSettings of(SheetFormat f, Map<String, dynamic> songExtra) {
    final o = songExtra['beats'];
    if (o is Map) {
      return BeatSettings(
        show: o['show'] as bool? ?? f.chordBeats,
        style: ChordBeatStyle.values.asNameMap()[o['style']] ?? f.beatStyle,
        barsPerLine: ((o['barsPerLine'] as num?)?.toInt() ?? f.barsPerLine)
            .clamp(1, 8),
        own: true,
      );
    }
    return BeatSettings(
      show: f.chordBeats,
      style: f.beatStyle,
      barsPerLine: f.barsPerLine,
    );
  }
}

/// Accidentals for one song: its own choice if it has one, otherwise
/// everyone's.
class SongAccidentals {
  final Accidentals accidentals;

  /// The song has its own setting (ignores the global one).
  final bool own;

  const SongAccidentals(this.accidentals, {this.own = false});

  static SongAccidentals of(SheetFormat f, Map<String, dynamic> songExtra) {
    final o = songExtra['accidentals'];
    if (o is String) {
      final a = Accidentals.values.asNameMap()[o];
      if (a != null) return SongAccidentals(a, own: true);
    }
    return SongAccidentals(f.accidentals);
  }
}

/// Beats in a bar from a time signature ("6/8" → 6; 4 if unknown).
int beatsPerBar(String timeSignature) {
  final m = RegExp(r'^\s*(\d+)\s*/\s*\d+').firstMatch(timeSignature);
  final n = m == null ? 4 : int.parse(m.group(1)!);
  return n < 1 || n > 16 ? 4 : n;
}

/// The look of linked sections (the second section of a linked pair, e.g.
/// a verse's translation). One for the chord sheet, one for the projector.
class LinkedStyle {
  /// Shown at all (here).
  bool show = true;

  /// Text size, % of the main section's.
  int size = 100;
  bool bold = false;
  bool italic = false;

  /// Drawn fainter.
  bool dim = false;

  /// Own colour (null = same as the main section).
  Color? color;

  /// Projector only: drop shadow.
  bool shadow = false;

  /// Projector only: beside the main section instead of under it.
  bool sideBySide = false;

  /// The colour to draw with ([recolor] off keeps [base], e.g. chords).
  Color? colorOn(Color? base, {bool recolor = true}) {
    final c = recolor ? (color ?? base) : base;
    if (c == null || !dim) return c;
    return c.withValues(alpha: c.a * 0.55);
  }

  /// Applies this look to [base] (sizes scaled, colour, bold, italic).
  /// Chords keep their own colour ([recolor] off) but still dim.
  TextStyle apply(
    TextStyle base, {
    Color? fallbackColor,
    bool recolor = true,
  }) => base.copyWith(
    fontSize: base.fontSize == null ? null : base.fontSize! * size / 100,
    fontWeight: bold ? FontWeight.bold : null,
    fontStyle: italic ? FontStyle.italic : null,
    color: colorOn(base.color ?? fallbackColor, recolor: recolor),
  );

  /// For caches: changes whenever the look changes.
  String get signature =>
      '$show|$size|$bold|$italic|$dim|${color?.toARGB32()}|$shadow|$sideBySide';

  Map<String, dynamic> toJson() => {
    'show': show,
    'size': size,
    'bold': bold,
    'italic': italic,
    'dim': dim,
    'color': color?.toARGB32(),
    'shadow': shadow,
    'sideBySide': sideBySide,
  };

  void updateFrom(Map<String, dynamic> j) {
    show = j['show'] as bool? ?? show;
    size = ((j['size'] as num?)?.toInt() ?? size).clamp(40, 200);
    bold = j['bold'] as bool? ?? bold;
    italic = j['italic'] as bool? ?? italic;
    dim = j['dim'] as bool? ?? dim;
    if (j.containsKey('color')) {
      final c = j['color'];
      color = c is num ? Color(c.toInt()) : null;
    }
    shadow = j['shadow'] as bool? ?? shadow;
    sideBySide = j['sideBySide'] as bool? ?? sideBySide;
  }
}
