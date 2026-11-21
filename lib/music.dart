// Chord parsing, transposition and display notation.

enum ChordNotation { standard, solfege, roman, numbers }

enum MinorStyle { m, mi, min, dash, lower }

enum Accidentals { auto, sharps, flats }

/// How a major seventh (ninth…) is written: as in the song, or one way.
enum MajorSymbol { asWritten, maj, ma, upperM, triangle }

/// How a half-diminished chord is written: as in the song, m7♭5 or ø7.
enum HalfDimSymbol { asWritten, m7b5, slashedO }

/// How a diminished chord is written: as in the song, dim or °.
enum DimSymbol { asWritten, dim, circle }

/// Where a chord's extension (7, maj7, sus4, add9…) sits: on the line,
/// raised as a superscript, or lowered as a subscript.
enum ChordExtensions { inline, raised, lowered }

extension MajorSymbolText on MajorSymbol {
  String get text => switch (this) {
    MajorSymbol.asWritten => '',
    MajorSymbol.maj => 'maj',
    MajorSymbol.ma => 'ma',
    MajorSymbol.upperM => 'M',
    MajorSymbol.triangle => '\u2206',
  };
}

/// The chord symbols chosen in the Format pane (all "as written" by
/// default: the song's own text).
class ChordSymbols {
  final MajorSymbol major;
  final HalfDimSymbol halfDim;
  final DimSymbol dim;
  const ChordSymbols({
    this.major = MajorSymbol.asWritten,
    this.halfDim = HalfDimSymbol.asWritten,
    this.dim = DimSymbol.asWritten,
  });
}

final _majorQuality = RegExp(r'^(maj|Maj|MAJ|ma|M|\u0394|\u2206|\u25B3)(?=\d)');
final _halfDimMinor = RegExp(r'^7\(?[b\u266D]5\)?');
final _halfDimSign = RegExp(r'^[\u00F8\u00D8]7?');
final _dimQuality = RegExp(r'^(dim|\u00B0|o(?=\d|$))');
const _noteHead =
    r'(?:[A-G]|[a-g]|Do|R\u00E9|Re|Mi|Fa|Sol|La|Si|Ti|[ivIV]{1,4}|[1-7])[#b\u266F\u266D]?';
final _shownChord = RegExp(
  // (an extension never starts with the bass's slash: "G/B" has none)
  '^($_noteHead(?:min|mi|m(?!aj|a\\d)|-)?)([^/].*?)?(/$_noteHead)?\$',
);

/// A chord as shown ("Cmaj7/E", "Am7", "G (1)") cut where its extension
/// starts and ends: (root and minor marker, extension, bass and the rest).
/// Null when it has no extension or isn't a chord.
(String, String, String)? splitChordExtension(String shown) {
  final cut = shown.indexOf(' (');
  final main = cut < 0 ? shown : shown.substring(0, cut);
  final after = cut < 0 ? '' : shown.substring(cut);
  final m = _shownChord.firstMatch(main);
  if (m == null || (m.group(2) ?? '').isEmpty) return null;
  return (m.group(1)!, m.group(2)!, '${m.group(3) ?? ''}$after');
}

extension AccidentalsLabel on Accidentals {
  String get label => switch (this) {
    Accidentals.auto => 'Auto',
    Accidentals.sharps => 'Sharps',
    Accidentals.flats => 'Flats',
  };
}

extension ChordNotationLabel on ChordNotation {
  String get label => switch (this) {
    ChordNotation.standard => 'Standard',
    ChordNotation.solfege => 'Solfège',
    ChordNotation.roman => 'Roman',
    ChordNotation.numbers => 'Numbers',
  };

  String get example => switch (this) {
    ChordNotation.standard => 'C F G',
    ChordNotation.solfege => 'Do Fa Sol',
    ChordNotation.roman => 'I IV V',
    ChordNotation.numbers => '1 4 5',
  };
}

extension MinorStyleLabel on MinorStyle {
  /// How A minor looks in this style.
  String get label => switch (this) {
    MinorStyle.m => 'Am',
    MinorStyle.mi => 'Ami',
    MinorStyle.min => 'Amin',
    MinorStyle.dash => 'A-',
    MinorStyle.lower => 'a',
  };
}

const _sharpNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
];
const _flatNames = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B', //
];
const _letterIndex = {
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11, //
};
const _solfege = {
  'C': 'Do', 'D': 'Re', 'E': 'Mi', 'F': 'Fa', 'G': 'Sol', 'A': 'La',
  'B': 'Si', //
};
const _romanDegrees = [
  'I', 'bII', 'II', 'bIII', 'III', 'IV', '#IV', 'V', 'bVI', 'VI', 'bVII',
  'VII', //
];
const _numberDegrees = [
  '1', 'b2', '2', 'b3', '3', '4', '#4', '5', 'b6', '6', 'b7', '7', //
];

int _mod12(int n) => ((n % 12) + 12) % 12;

/// Keeps a transposition in the range -6..+5 semitones.
int normalizeTranspose(int n) => _mod12(n + 6) - 6;

int? _noteIndex(String letter, String accidental) {
  final base = _letterIndex[letter];
  if (base == null) return null;
  return switch (accidental) {
    '#' || '♯' => _mod12(base + 1),
    'b' || '♭' => _mod12(base - 1),
    _ => base,
  };
}

class MusicKey {
  final int root;
  final bool minor;
  const MusicKey(this.root, this.minor);

  /// Conventional spelling: F, Bb, Eb... use flats; G, D, A... use sharps.
  bool get prefersFlats => minor
      ? const {2, 7, 0, 5, 10, 3}.contains(root)
      : const {5, 10, 3, 8, 1}.contains(root);

  MusicKey transposed(int semitones) =>
      MusicKey(_mod12(root + semitones), minor);

  String get name =>
      (prefersFlats ? _flatNames : _sharpNames)[root] + (minor ? 'm' : '');

  /// Parses "G", "Em", "Bb major", "F# minor".
  static MusicKey? parse(String text) {
    final t = text.trim();
    final m = RegExp(r'^([A-G])([#b♯♭]?)\s*(.*)$').firstMatch(t);
    if (m == null) return null;
    final root = _noteIndex(m.group(1)!, m.group(2)!);
    if (root == null) return null;
    final rest = m.group(3)!.toLowerCase();
    final minor =
        rest.startsWith('min') ||
        (rest.startsWith('m') && !rest.startsWith('maj')) ||
        rest.startsWith('-');
    return MusicKey(root, minor);
  }
}

class Chord {
  final int root;
  final String spelledRoot; // as written, e.g. "Bb"
  final bool minor;
  final String rest; // quality after the minor marker, e.g. "7", "sus4"
  final int? bass;
  final String? spelledBass;

  const Chord(
    this.root,
    this.spelledRoot,
    this.minor,
    this.rest,
    this.bass,
    this.spelledBass,
  );

  static final _chordPattern = RegExp(
    r'^([A-G])([#b♯♭]?)(.*?)(?:/([A-G])([#b♯♭]?))?$',
  );
  // ("ma7" is a major seventh, not minor + "a7")
  static final _minorPattern = RegExp(r'^(min|mi|m(?!aj|a\d)|-)(.*)$');

  static Chord? parse(String text) {
    final m = _chordPattern.firstMatch(text.trim());
    if (m == null) return null;
    final root = _noteIndex(m.group(1)!, m.group(2)!)!;
    var quality = m.group(3)!;
    var minor = false;
    final mm = _minorPattern.firstMatch(quality);
    if (mm != null) {
      minor = true;
      quality = mm.group(2)!;
    }
    int? bass;
    String? spelledBass;
    if (m.group(4) != null) {
      bass = _noteIndex(m.group(4)!, m.group(5) ?? '');
      spelledBass = '${m.group(4)}${m.group(5) ?? ''}';
    }
    return Chord(
      root,
      '${m.group(1)}${m.group(2)}',
      minor,
      quality,
      bass,
      spelledBass,
    );
  }
}

/// Song key from `{key: X}`; otherwise the key that best fits all chords.
MusicKey? detectKey(String raw, String? declaredKey) {
  if (declaredKey != null && declaredKey.isNotEmpty) {
    final k = MusicKey.parse(declaredKey);
    if (k != null) return k;
  }
  final chords = [
    for (final m in RegExp(r'\[([^\]]+)\]').allMatches(raw))
      ?Chord.parse(m.group(1)!),
  ];
  if (chords.isEmpty) return null;

  // Diatonic triads as (semitones above tonic, isMinor).
  const majorScale = [
    (0, false),
    (2, true),
    (4, true),
    (5, false),
    (7, false),
    (9, true),
  ];
  const minorScale = [
    (0, true),
    (3, false),
    (5, true),
    (7, true),
    (7, false),
    (8, false),
    (10, false),
  ];

  MusicKey? best;
  var bestScore = -1;
  for (var root = 0; root < 12; root++) {
    for (final minor in [false, true]) {
      final scale = minor ? minorScale : majorScale;
      bool isTonic(Chord c) => c.root == root && c.minor == minor;
      var score = 0;
      for (final c in chords) {
        final degree = _mod12(c.root - root);
        if (scale.contains((degree, c.minor))) score += 10;
        if (isTonic(c)) score += 2;
      }
      // V -> I resolutions are the strongest sign of the home key.
      for (var i = 1; i < chords.length; i++) {
        if (isTonic(chords[i]) && chords[i - 1].root == _mod12(root + 7)) {
          score += 4;
        }
      }
      if (isTonic(chords.last)) score += 5;
      if (isTonic(chords.first)) score += 3;
      if (!minor) score += 2; // prefer major over its relative minor
      if (score > bestScore) {
        bestScore = score;
        best = MusicKey(root, minor);
      }
    }
  }
  return best;
}

/// "Rewrite into key": the song text with every `[chord]` moved by
/// [semitones] (spelled as [target] prefers: Bb in F, A# in B) and its
/// `{key:}` set to [target]. Chord comments (`[G*soft]`) and bar lines
/// (`[|]`) are kept; anything that isn't a chord stays as written.
String rewriteIntoKey(String raw, int semitones, MusicKey target) {
  final flats = target.prefersFlats;
  var out = raw.replaceAllMapped(RegExp(r'\[([^\]\n]*)\]'), (m) {
    var inner = m.group(1)!;
    // (A Gospelizer chord keeps its mark, see gospelizer.dart.)
    final mark = inner.startsWith('\u2064') || inner.startsWith('\u2062')
        ? inner[0]
        : '';
    inner = inner.substring(mark.length);
    final star = inner.indexOf('*');
    final chord = (star < 0 ? inner : inner.substring(0, star)).trim();
    final comment = star < 0 ? '' : inner.substring(star);
    if (chord.isEmpty || Chord.parse(chord) == null) return m.group(0)!;
    final moved = renderChord(
      chord,
      transpose: semitones,
      key: null,
      notation: ChordNotation.standard,
      minorStyle: MinorStyle.m,
      accidentals: flats ? Accidentals.flats : Accidentals.sharps,
    );
    return '[$mark$moved$comment]';
  });
  out = out.replaceAllMapped(
    RegExp(r'\{\s*key\s*:[^}]*\}', caseSensitive: false),
    (_) => '{key: ${target.name}}',
  );
  return out;
}

/// [renderChord], plus the same chord in a second notation beside it
/// ("G (1)", "Em (vi)") when [dual] is set and gives something different.
String renderDualChord(
  String text, {
  required int transpose,
  required MusicKey? key,
  required ChordNotation notation,
  required ChordNotation? dual,
  required MinorStyle minorStyle,
  required Accidentals accidentals,
  ChordSymbols symbols = const ChordSymbols(),
}) {
  String as(ChordNotation n) => renderChord(
    text,
    transpose: transpose,
    key: key,
    notation: n,
    minorStyle: minorStyle,
    accidentals: accidentals,
    symbols: symbols,
  );
  final main = as(notation);
  if (dual == null || dual == notation) return main;
  final second = as(dual);
  return second == main ? main : '$main ($second)';
}

/// Renders one chord in the chosen notation after transposing.
/// [key] is the song's key *after* transposition (needed for Roman/Numbers
/// and for choosing sharps vs flats). Unrecognised text (e.g. "N.C.") is
/// returned unchanged.
String renderChord(
  String text, {
  required int transpose,
  required MusicKey? key,
  required ChordNotation notation,
  required MinorStyle minorStyle,
  required Accidentals accidentals,
  ChordSymbols symbols = const ChordSymbols(),
}) {
  // A Gospelizer chord's mark (U+2064, see gospelizer.dart) isn't shown.
  if (text.startsWith('\u2064') || text.startsWith('\u2062')) {
    text = text.substring(1);
  }
  final c = Chord.parse(text);
  if (c == null) return text;

  final flats = switch (accidentals) {
    Accidentals.auto => key?.prefersFlats ?? c.spelledRoot.contains('b'),
    Accidentals.sharps => false,
    Accidentals.flats => true,
  };

  String spell(int original, String asWritten) {
    // Keep the author's spelling unless sharps/flats were chosen explicitly.
    if (transpose == 0 && accidentals == Accidentals.auto) return asWritten;
    return (flats ? _flatNames : _sharpNames)[_mod12(original + transpose)];
  }

  String noteName(int original, String asWritten) {
    final spelled = spell(original, asWritten);
    switch (notation) {
      case ChordNotation.standard:
        return spelled;
      case ChordNotation.solfege:
        return _solfege[spelled[0]]! + spelled.substring(1);
      case ChordNotation.roman:
      case ChordNotation.numbers:
        if (key == null) return spelled;
        final degree = _mod12(original + transpose - key.root);
        return (notation == ChordNotation.roman
            ? _romanDegrees
            : _numberDegrees)[degree];
    }
  }

  var rootName = noteName(c.root, c.spelledRoot);
  // The chosen symbols for major sevenths, half-diminished and diminished
  // chords (as written unless chosen).
  var rest = c.rest;
  var minor = c.minor;
  if (symbols.major != MajorSymbol.asWritten) {
    final m = _majorQuality.firstMatch(rest);
    if (m != null) rest = symbols.major.text + rest.substring(m.end);
  }
  if (symbols.halfDim != HalfDimSymbol.asWritten) {
    final m = minor
        ? _halfDimMinor.firstMatch(rest)
        : _halfDimSign.firstMatch(rest);
    if (m != null) {
      final tail = rest.substring(m.end);
      if (symbols.halfDim == HalfDimSymbol.slashedO) {
        minor = false;
        rest = '\u00F87$tail';
      } else {
        minor = true;
        rest = '7\u266D5$tail';
      }
    }
  }
  if (symbols.dim != DimSymbol.asWritten) {
    final m = _dimQuality.firstMatch(rest);
    if (m != null) {
      rest =
          (symbols.dim == DimSymbol.circle ? '\u00B0' : 'dim') +
          rest.substring(m.end);
    }
  }
  var marker = '';
  if (minor) {
    switch (minorStyle) {
      case MinorStyle.m:
        marker = 'm';
      case MinorStyle.mi:
        marker = 'mi';
      case MinorStyle.min:
        marker = 'min';
      case MinorStyle.dash:
        marker = '-';
      case MinorStyle.lower:
        // Digits have no lowercase; Nashville numbers use "-" for minor.
        if (notation == ChordNotation.numbers && key != null) {
          marker = '-';
        } else {
          rootName = rootName.toLowerCase();
        }
    }
  }
  final bass = c.bass == null ? '' : '/${noteName(c.bass!, c.spelledBass!)}';
  return '$rootName$marker$rest$bass';
}
