// ABC notation (JustChords' sheet music): a melody written as text,
//   X:1
//   T:Amazing Grace
//   M:3/4
//   L:1/4
//   K:G
//   D | G2 B/G/ | B2 A | G2 E | D2 D |
// read into the sheet music scanner's Score, so it's drawn by the same
// engraver and played by the same piano. Covers what lead sheets use:
// header fields, notes and rests with lengths, accidentals and octaves,
// broken rhythm (> <), chords [CEG], ties, triplets, bar lines, repeats
// and first / second endings, and key / meter changes mid-tune. Chord
// symbols, lyrics (w:), grace notes and decorations are skipped; only the
// first voice is read. A Score goes back to ABC with [scoreToAbc].

import 'dart:math' as math;

import 'scanner/score.dart';

final RegExp abcStart = RegExp(
  r'^\{\s*start_of_abc(\s*:[^}]*)?\s*\}$',
  caseSensitive: false,
);
final RegExp abcEnd = RegExp(r'^\{\s*end_of_abc\s*\}$', caseSensitive: false);

/// An empty tune for the editor's ABC button.
const String abcTemplate =
    '{start_of_abc}\n'
    'X:1\n'
    'M:4/4\n'
    'L:1/8\n'
    'K:C\n'
    'C2 D2 E2 F2 | G4 G4 | A2 A2 G4 | F2 F2 E4 |]\n'
    '{end_of_abc}';

const _majorFifths = {
  'C': 0, 'G': 1, 'D': 2, 'A': 3, 'E': 4, 'B': 5, 'F#': 6, 'C#': 7, //
  'F': -1, 'Bb': -2, 'Eb': -3, 'Ab': -4, 'Db': -5, 'Gb': -6, 'Cb': -7,
  'G#': 8, 'D#': 9, 'A#': 10, 'E#': 11, 'B#': 12, 'Fb': -8,
};

const _modeShift = {
  'maj': 0, 'ion': 0, 'min': -3, 'm': -3, 'aeo': -3, 'mix': -1, //
  'dor': -2, 'phr': -4, 'lyd': 1, 'loc': -5,
};

/// The key signature of an ABC key ("G", "Dm", "Bb", "A dorian", "none"),
/// as + sharps / − flats, and its clef.
(int, Clef) abcKey(String k) {
  var clef = Clef.treble;
  final lower = k.toLowerCase();
  if (lower.contains('clef=bass') || RegExp(r'\bbass\b').hasMatch(lower)) {
    clef = Clef.bass;
  } else if (lower.contains('clef=alto') || lower.contains(' alto')) {
    clef = Clef.alto;
  } else if (lower.contains('clef=tenor') || lower.contains(' tenor')) {
    clef = Clef.tenor;
  }
  final m = RegExp(r'^\s*([A-Ga-g])([#b]?)\s*([A-Za-z]*)')
      .firstMatch(k.replaceAll('♭', 'b').replaceAll('♯', '#'));
  if (m == null || lower.trim().startsWith('none')) return (0, clef);
  final tonic = m[1]!.toUpperCase() + m[2]!;
  var mode = m[3]!.toLowerCase();
  mode = mode.length > 3 ? mode.substring(0, 3) : mode;
  if (mode == 'm' || mode.isEmpty) mode = mode.isEmpty ? 'maj' : 'min';
  final base = _majorFifths[tonic] ?? 0;
  final fifths = base + (_modeShift[mode] ?? 0);
  // Keys past 7 are written as their enharmonic neighbour.
  return (
    fifths > 7 ? fifths - 12 : (fifths < -7 ? fifths + 12 : fifths),
    clef,
  );
}

/// A fraction field ("3/4", "C", "C|", "1/8") as (top, bottom).
(int, int)? _fraction(String v) {
  final t = v.trim();
  if (t == 'C') return (4, 4);
  if (t == 'C|') return (2, 2);
  final m = RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(t);
  if (m == null) return null;
  return (int.parse(m[1]!), int.parse(m[2]!));
}

/// Note type and dots for a written length in quarters (triplets taken
/// off first).
(String, int) _typeOf(double q) {
  const types = [
    ('whole', 4.0),
    ('half', 2.0),
    ('quarter', 1.0),
    ('eighth', 0.5),
    ('16th', 0.25),
    ('32nd', 0.125),
  ];
  for (final (name, len) in types) {
    if ((q - len).abs() < 0.01) return (name, 0);
    if ((q - len * 1.5).abs() < 0.01) return (name, 1);
    if ((q - len * 1.75).abs() < 0.01) return (name, 2);
  }
  for (final (name, len) in types) {
    if (q >= len) return (name, q >= len * 1.5 ? 1 : 0);
  }
  return ('32nd', 0);
}

/// Reads ABC [text] (one tune) into a score; null when there are no notes.
Score? parseAbc(String text) => _AbcReader(text).read();

class _AbcReader {
  final String text;
  _AbcReader(this.text);

  String title = '';
  int fifths = 0, beats = 4, beatType = 4, tempo = 100;
  Clef clef = Clef.treble;
  double unit = 0.5; // L: in quarters
  bool unitSet = false;

  final notes = <ScoreNote>[];
  final measures = <ScoreMeasure>[];
  double t = 0; // where the next note goes (quarters)
  double measureStart = 0;
  bool repeatStartNext = false;
  List<int>? endingNext;
  (int, int)? timeNext;
  int? fifthsNext;
  final barAccidentals = <int, int>{};
  int chordId = 0;

  // Tuplets: notes left and the factor.
  int tupletLeft = 0;
  double tupletFactor = 1;
  bool tupletIsTriplet = false;

  // Broken rhythm: what the next note is multiplied by.
  double brokenNext = 1;

  static const _box = Box(0, 0, 0, 0);

  Score? read() {
    final body = <String>[];
    var inBody = false;
    for (final raw in text.split('\n')) {
      final line = raw.replaceFirst(RegExp(r'%.*$'), '').trimRight();
      if (line.trim().isEmpty) continue;
      final field = RegExp(r'^([A-Za-z]):\s*(.*)$').firstMatch(line.trim());
      if (field != null && !(inBody && field[1] == '|')) {
        final (k, v) = (field[1]!, field[2]!);
        if (k == 'V' && inBody && body.isNotEmpty) break; // first voice only
        if (k == 'w' || k == 'W') continue;
        _field(k, v, inBody: inBody);
        if (k == 'K') inBody = true;
        continue;
      }
      inBody = true;
      body.add(line);
    }
    if (!unitSet) {
      unit = beats / beatType < 0.75 ? 0.25 : 0.5;
    }
    timeNext = null;
    fifthsNext = null;
    _body(body.join('\n'));
    _closeMeasure(force: false);
    if (notes.where((n) => !n.rest).isEmpty) return null;
    return Score(
      title: title,
      pages: const [(1000, 1000)],
      systems: [
        ScoreSystem(0, const Box(0, 0, 1000, 1000), const [(0.0, 10.0)]),
      ],
      clefs: [clef],
      fifths: measures.firstOrNull?.fifths ?? fifths,
      beats: beats,
      beatType: beatType,
      measures: measures,
      notes: notes,
      tempo: tempo,
    );
  }

  void _field(String k, String v, {required bool inBody}) {
    switch (k) {
      case 'T':
        if (title.isEmpty) title = v.trim();
      case 'M':
        final f = _fraction(v);
        if (f != null) {
          if (inBody) timeNext = f;
          beats = f.$1;
          beatType = f.$2;
        }
      case 'L':
        final f = _fraction(v);
        if (f != null && f.$2 > 0) {
          unit = 4 * f.$1 / f.$2;
          unitSet = true;
        }
      case 'Q':
        // "1/4=100", "100", "3/8=60".
        final m = RegExp(r'(?:(\d+)/(\d+)\s*=\s*)?(\d+)').firstMatch(v);
        if (m != null) {
          final bpm = int.parse(m[3]!);
          final beat = m[1] == null
              ? 1.0
              : 4 * int.parse(m[1]!) / int.parse(m[2]!);
          tempo = (bpm * beat).round().clamp(20, 400);
        }
      case 'K':
        final (f, c) = abcKey(v);
        if (inBody) fifthsNext = f;
        fifths = f;
        if (!inBody) clef = c;
    }
  }

  void _closeMeasure({required bool force, bool repeatEnd = false}) {
    final length = t - measureStart;
    if (length < 0.001 && !force) {
      if (repeatEnd && measures.isNotEmpty) measures.last.repeatEnd = true;
      return;
    }
    measures.add(
      ScoreMeasure(
        onset: measureStart,
        length: math.max(length, 0.001),
        page: 0,
        system: 0,
        box: _box,
        repeatStart: repeatStartNext,
        repeatEnd: repeatEnd,
        ending: endingNext,
        time: measures.isEmpty ? null : timeNext,
        fifths: measures.isEmpty ? fifths : fifthsNext,
      ),
    );
    repeatStartNext = false;
    endingNext = null;
    timeNext = null;
    fifthsNext = null;
    measureStart = t;
    barAccidentals.clear();
  }

  void _body(String s) {
    var i = 0;
    String peek([int o = 0]) => i + o < s.length ? s[i + o] : '';

    // A length after a note or chord: "2", "/", "3/2", "//".
    double length() {
      var num = 0, den = 1;
      final start = i;
      while (RegExp(r'\d').hasMatch(peek())) {
        num = num * 10 + int.parse(s[i++]);
      }
      if (i == start) num = 1;
      while (peek() == '/') {
        i++;
        var d = 0;
        final ds = i;
        while (RegExp(r'\d').hasMatch(peek())) {
          d = d * 10 + int.parse(s[i++]);
        }
        den *= i == ds ? 2 : d;
      }
      return num / den;
    }

    // One note's pitch at [i]: accidentals, letter, octave marks.
    (int, int?, bool)? pitch() {
      int? acc;
      if (peek() == '^') {
        acc = peek(1) == '^' ? 2 : 1;
        i += acc;
      } else if (peek() == '_') {
        acc = peek(1) == '_' ? -2 : -1;
        i += -acc;
      } else if (peek() == '=') {
        acc = 0;
        i++;
      }
      final c = peek();
      if (c == 'z' || c == 'x') {
        i++;
        return (0, null, true);
      }
      if (!RegExp(r'[A-Ga-g]').hasMatch(c)) return null;
      i++;
      const order = 'CDEFGAB';
      var d = (c == c.toUpperCase() ? 28 : 35) + order.indexOf(c.toUpperCase());
      while (peek() == "'" || peek() == ',') {
        d += peek() == "'" ? 7 : -7;
        i++;
      }
      return (d, acc, false);
    }

    void addNotes(List<(int, int?, bool)> ps, double len, bool tie) {
      var q = len * unit * brokenNext;
      brokenNext = 1;
      // Broken rhythm after it: this one longer, the next shorter.
      var j = i;
      while (j < s.length && s[j] == ' ') {
        j++;
      }
      if (j < s.length && (s[j] == '>' || s[j] == '<')) {
        var n = 0;
        final ch = s[j];
        while (j < s.length && s[j] == ch) {
          n++;
          j++;
        }
        final short = math.pow(0.5, n).toDouble();
        final long = 2 - short;
        q *= ch == '>' ? long : short;
        brokenNext = ch == '>' ? short : long;
        i = j;
      }
      final written = q;
      var triplet = false;
      if (tupletLeft > 0) {
        q *= tupletFactor;
        triplet = tupletIsTriplet;
        tupletLeft--;
      }
      final (type, dots) = _typeOf(written);
      final id = ps.length > 1 ? chordId++ : -1;
      for (final (d, acc, rest) in ps) {
        var alter = keyAlter(fifths, d);
        if (acc != null) {
          barAccidentals[d] = acc;
          alter = acc;
        } else if (barAccidentals[d] case final a?) {
          alter = a;
        }
        notes.add(
          ScoreNote(
            page: 0,
            system: 0,
            staff: 0,
            measure: measures.length,
            onset: t,
            duration: q,
            rest: rest,
            diatonic: rest ? 32 : d,
            alter: rest ? 0 : alter,
            accidental: rest ? null : acc,
            type: type,
            dots: dots,
            triplet: triplet,
            tie: tie && !rest,
            chord: id,
            box: _box,
          ),
        );
      }
      t += q;
    }

    while (i < s.length) {
      final c = s[i];
      // Skipped: spaces, chord symbols, decorations, grace notes, line
      // continuations.
      if (c == ' ' || c == '\t' || c == '\n' || c == '\\' || c == '`') {
        i++;
        continue;
      }
      if (c == '"') {
        final end = s.indexOf('"', i + 1);
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      if (c == '!' || c == '+') {
        final end = s.indexOf(c, i + 1);
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      if (c == '{') {
        final end = s.indexOf('}', i + 1);
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      if ('.~HLMOPSTuv'.contains(c)) {
        i++;
        continue;
      }
      // Tuplets: (3 = three in the time of two.
      if (c == '(' && RegExp(r'\d').hasMatch(peek(1))) {
        final p = int.parse(s[i + 1]);
        i += 2;
        var q = switch (p) {
          2 => 3,
          3 => 2,
          4 => 3,
          _ => (beats % 3 == 0 && beats > 3) ? 3 : 2,
        };
        var r = p;
        if (peek() == ':') {
          i++;
          if (RegExp(r'\d').hasMatch(peek())) q = int.parse(s[i++]);
          if (peek() == ':') {
            i++;
            if (RegExp(r'\d').hasMatch(peek())) r = int.parse(s[i++]);
          }
        }
        tupletLeft = r;
        tupletFactor = q / p;
        tupletIsTriplet = p == 3;
        continue;
      }
      if (c == '(' || c == ')') {
        i++; // slurs
        continue;
      }
      // Inline fields: [K:D], [M:3/4], [L:1/8].
      if (c == '[' && RegExp(r'[A-Za-z]').hasMatch(peek(1)) && peek(2) == ':') {
        final end = s.indexOf(']', i);
        final inner = s.substring(i + 1, end < 0 ? s.length : end);
        _field(inner[0], inner.substring(2), inBody: true);
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      // Endings: [1, [2, |1, :|2.
      if (c == '[' && RegExp(r'\d').hasMatch(peek(1))) {
        i++;
        endingNext = _endingList(s, () => i, (v) => i = v);
        continue;
      }
      // Bar lines.
      if (c == '|' || c == ':' || (c == '[' && peek(1) == '|')) {
        var bar = '';
        while (i < s.length && '|:[]'.contains(s[i])) {
          // "[1" after a bar is an ending, not part of it.
          if (s[i] == '[' &&
              i + 1 < s.length &&
              RegExp(r'\d').hasMatch(s[i + 1])) {
            break;
          }
          bar += s[i];
          i++;
        }
        final repeatEnd = bar.startsWith(':');
        final repeatStart = bar.endsWith(':');
        _closeMeasure(force: false, repeatEnd: repeatEnd);
        if (repeatStart) repeatStartNext = true;
        if (RegExp(r'\d').hasMatch(peek())) {
          endingNext = _endingList(s, () => i, (v) => i = v);
        }
        continue;
      }
      // Broken rhythm with nothing before it, stray characters.
      if (c == '>' || c == '<' || c == '-' || c == ']') {
        i++;
        continue;
      }
      // Multi-measure rest: Z or Z4 (whole bars).
      if (c == 'Z' || c == 'X') {
        i++;
        var bars = 0;
        while (RegExp(r'\d').hasMatch(peek())) {
          bars = bars * 10 + int.parse(s[i++]);
        }
        if (bars == 0) bars = 1;
        for (var b = 0; b < bars; b++) {
          final len = beats * 4 / beatType;
          notes.add(
            ScoreNote(
              page: 0,
              system: 0,
              staff: 0,
              measure: measures.length,
              onset: t,
              duration: len,
              rest: true,
              diatonic: 32,
              type: 'whole',
              box: _box,
            ),
          );
          t += len;
          if (b < bars - 1) _closeMeasure(force: false);
        }
        continue;
      }
      // A chord: [CEG]2.
      if (c == '[') {
        i++;
        final ps = <(int, int?, bool)>[];
        var inner = 1.0;
        while (i < s.length && s[i] != ']') {
          final p = pitch();
          if (p == null) {
            i++;
            continue;
          }
          inner = length();
          ps.add(p);
        }
        if (peek() == ']') i++;
        final len = length() * inner;
        final tie = peek() == '-';
        if (tie) i++;
        if (ps.isNotEmpty) addNotes(ps, len, tie);
        continue;
      }
      final p = pitch();
      if (p == null) {
        i++; // something we don't read
        continue;
      }
      final len = length();
      final tie = peek() == '-';
      if (tie) i++;
      addNotes([p], len, tie);
    }
  }

  /// "1", "1,2", "1-3" at the reader's position.
  List<int> _endingList(String s, int Function() at, void Function(int) set) {
    var i = at();
    final m = RegExp(r'^\d+(?:[,-]\d+)*').firstMatch(s.substring(i));
    if (m == null) return const [1];
    set(i + m[0]!.length);
    final out = <int>[];
    for (final part in m[0]!.split(',')) {
      final r = part.split('-').map(int.parse).toList();
      for (var n = r.first; n <= r.last; n++) {
        out.add(n);
      }
    }
    return out;
  }
}

// ---- Score → ABC ----

/// [score] (from the scanner or ABC) as ABC text: its title, meter, key
/// and tempo, then the first part's notes, one line of four bars at a
/// time. Other parts follow as voices (V:).
String scoreToAbc(Score score) {
  const unit = 0.5; // L:1/8
  final b = StringBuffer()
    ..writeln('X:1')
    ..writeln('T:${score.title.isEmpty ? 'Untitled' : score.title}')
    ..writeln('M:${score.beats}/${score.beatType}')
    ..writeln('L:1/8')
    ..writeln('Q:1/4=${score.tempo}')
    ..writeln('K:${_keyName(score.fifths)}');
  String len(double q) {
    // As a multiple of the unit: 2, /2, 3/2 …
    final units = q / unit;
    for (final den in [1, 2, 4, 8, 3, 6]) {
      final num = units * den;
      if ((num - num.round()).abs() < 0.01) {
        final n = num.round();
        if (den == 1) return n == 1 ? '' : '$n';
        if (n == 1) return den == 2 ? '/' : '/$den';
        return '$n/$den';
      }
    }
    return '';
  }

  String pitch(ScoreNote n, int fifths, Map<int, int> bar) {
    var acc = '';
    final expected = bar[n.diatonic] ?? keyAlter(fifths, n.diatonic);
    if (n.alter != expected) {
      acc = switch (n.alter) {
        2 => '^^',
        1 => '^',
        -1 => '_',
        -2 => '__',
        _ => '=',
      };
      bar[n.diatonic] = n.alter;
    }
    const order = 'CDEFGAB';
    final step = order[n.diatonic % 7];
    final octave = n.diatonic ~/ 7;
    final letter = octave >= 5 ? step.toLowerCase() : step;
    final marks = octave >= 5 ? "'" * (octave - 5) : ',' * (4 - octave);
    return '$acc$letter$marks';
  }

  for (var staff = 0; staff < score.staves; staff++) {
    if (score.staves > 1) {
      final clef = score.clefs[staff] == Clef.bass ? ' clef=bass' : '';
      b.writeln('V:${staff + 1}$clef');
    }
    var fifths = score.fifths;
    final line = StringBuffer();
    var bars = 0;
    for (final (mi, m) in score.measures.indexed) {
      if (m.fifths != null && mi > 0 && m.fifths != fifths) {
        fifths = m.fifths!;
        line.write('[K:${_keyName(fifths)}] ');
      }
      if (m.time case (final bt, final bb) when mi > 0) {
        line.write('[M:$bt/$bb] ');
      }
      if (m.repeatStart) line.write('|: ');
      if (m.ending != null) line.write('[${m.ending!.join(',')} ');
      final ns =
          score.notes
              .where((n) => n.measure == mi && n.staff == staff && n.voice == 1)
              .toList()
            ..sort((a, c) => a.onset.compareTo(c.onset));
      final bar = <int, int>{};
      var k = 0;
      var tripletLeft = 0;
      while (k < ns.length) {
        final n = ns[k];
        final group = [
          for (final o in ns.skip(k))
            if ((o.onset - n.onset).abs() < 0.01) o,
        ];
        k += group.length;
        final written = n.written / (n.triplet ? 2 / 3 : 1);
        if (n.triplet && tripletLeft == 0) {
          line.write('(3');
          tripletLeft = 3;
        }
        if (tripletLeft > 0) tripletLeft--;
        if (n.rest) {
          line.write('z${len(written)}');
        } else if (group.length > 1) {
          line.write('[');
          for (final g in group.where((g) => !g.rest)) {
            line.write(pitch(g, fifths, bar));
          }
          line.write(']${len(written)}');
          if (n.tie) line.write('-');
        } else {
          line.write('${pitch(n, fifths, bar)}${len(written)}');
          if (n.tie) line.write('-');
        }
        line.write(' ');
      }
      final last = mi == score.measures.length - 1;
      line.write(
        m.repeatEnd
            ? ':|'
            : last
            ? '|]'
            : '|',
      );
      bars++;
      if (bars % 4 == 0 || last) {
        b.writeln(line.toString().trim());
        line.clear();
      } else {
        line.write(' ');
      }
    }
  }
  return b.toString();
}

String _keyName(int fifths) {
  const names = {
    0: 'C', 1: 'G', 2: 'D', 3: 'A', 4: 'E', 5: 'B', 6: 'F#', 7: 'C#', //
    -1: 'F', -2: 'Bb', -3: 'Eb', -4: 'Ab', -5: 'Db', -6: 'Gb', -7: 'Cb',
  };
  return names[fifths.clamp(-7, 7)]!;
}
