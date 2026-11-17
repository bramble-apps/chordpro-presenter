// Gospelizer (the ✨ button): a gospel reharmonization of a song, the way
// church keyboard players do it — sparingly, where the music breathes:
// approach chords into the ends of phrases (ii–V of the chord arrived at,
// minor-plagal "Amen" endings, diminished walk-ups), and, when allowed,
// richer colours for the song's own chords (maj7, m9, F/G before the final
// chord, a tritone substitute at the end of a section).
//
// The changes are a layer kept beside the song (in Song.extra), never
// written into its text: they're merged in only where the song is shown or
// exported, so turning the layer off gives back the song exactly as it was.
// Each change is stored with its place in the song text and is spelled in
// the key the song is written in, so it follows transposing and capo like
// the song's own chords. When the text changes, the layer is worked out
// again from the new text.

import 'chordpro.dart';
import 'music.dart';
import 'state.dart';

/// Put before an added chord's name in the text the sheet is drawn from
/// (`[\u2064D7]`): the sheet draws such chords as passing chords (glow, or
/// in brackets), and renderChord drops it, so exports show a plain `[D7]`.
const String passingMark = '\u2064';

/// Put before a song chord the Gospelizer changed (`[\u2062Cmaj7]`): it
/// glows, but it's still the song's chord (no brackets, keeps its beats).
const String changedMark = '\u2062';

/// One change: a chord added at [at] (an offset into Song.raw), or, when
/// [replace] > 0, the song's chord at [at] (its `[…]`, [replace] long)
/// given as [chord] instead. Spelled in the song's key; [why] says what it
/// is ("ii/V", "iv (minor plagal)", "colour"…).
class PassingChord {
  final int at;
  final String chord;
  final String why;
  final int replace;
  const PassingChord(this.at, this.chord, this.why, {this.replace = 0});

  bool get isSubstitute => replace > 0;

  Map<String, dynamic> toJson() => {
    'at': at,
    'chord': chord,
    'why': why,
    if (replace > 0) 'len': replace,
  };

  static PassingChord? fromJson(Object? j) {
    if (j is! Map || j['at'] is! num || j['chord'] is! String) return null;
    return PassingChord(
      (j['at'] as num).toInt(),
      j['chord'] as String,
      j['why'] as String? ?? '',
      replace: (j['len'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PassingChord &&
      other.at == at &&
      other.chord == chord &&
      other.why == why &&
      other.replace == replace;

  @override
  int get hashCode => Object.hash(at, chord, why, replace);

  @override
  String toString() => '$chord@$at ($why${replace > 0 ? ', sub' : ''})';
}

const _sharp = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
];
const _flat = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B', //
];

int _mod12(int n) => ((n % 12) + 12) % 12;

final _chordInText = RegExp(r'\[([^\]\n]*)\]');
final _blockStart = RegExp(
  r'^\s*\{\s*(start_of_tab|sot|start_of_grid|sog|start_of_abc|'
  r'start_of_ly|start_of_svg|start_of_textblock)\b',
  caseSensitive: false,
);
final _blockEnd = RegExp(
  r'^\s*\{\s*(end_of_tab|eot|end_of_grid|eog|end_of_abc|end_of_ly|'
  r'end_of_svg|end_of_textblock)\b',
  caseSensitive: false,
);
final _barMark = RegExp(r'^[|:/.%x\d\s-]+$');
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// A chord of the song, as met in its text.
class _Met {
  final int start, end; // the brackets
  final Chord chord;
  final String text;
  final bool plain; // no "*comment" in the brackets
  final int line;
  bool lineFirst = false, lineLast = false, sectionLast = false;

  /// Word starts sung while it lasts, after its own first word.
  List<int> free = const [];
  _Met(this.start, this.end, this.chord, this.text, this.plain, this.line);
}

/// The Gospelizer's changes for [raw] (written in [key]). With [keep] it
/// only adds chords between the song's own; without, it may also recolour
/// and substitute them.
///
/// Where (as players do it — not under every chord):
/// - Only within a section (a blank line, label, directive or "N.C." ends
///   it), never in tab, grid or ABC blocks.
/// - Only where the chord before is held long enough: two words after its
///   own for one chord, three for two (a ii–V); and only into the end of a
///   phrase (the first or last chord of a lyric line, the last of the
///   section), unless the chord is held four words or more.
/// - At most one move per lyric line (the strongest: section endings, then
///   line ends), none in lines that already change chords four times.
///
/// What (in the song's key, before the chord arrived at, the target):
/// - IV → I at the end of a section: the minor plagal "Amen", iv6 (F Fm6 C).
/// - IV → V: the #iv diminished walk-up (F F#dim7 G); I → ii: #i dim (C
///   C#dim7 Dm).
/// - ii → its I: just the V7 (Dm G7 C).
/// - Otherwise the target's ii–V with room for two (C Gm7 C7 F, C Bm7b5 E7
///   Am), else its dominant seventh (G7 → C, A7 → Dm, E7 → Am).
/// - Nothing when the chord before already leads there (the target, its
///   dominant seventh, its tritone substitute), and only into chords of the
///   key (I ii IV V vi; minor i III iv v V VI).
///
/// Without [keep], also:
/// - The song's plain triads get their gospel colours: I add9, ii m9, iii
///   m7, IV maj7, vi m7 (minor keys: i m9, iv m7, III and VI maj7).
/// - V before I at a phrase end becomes IV/V (F/G), with the V7 after it
///   when there's room.
/// - The last cadence of a section takes the tritone substitute: Dm7 Db7 C.
List<PassingChord> gospelize(String raw, MusicKey key, {bool keep = true}) {
  final flats = key.prefersFlats;
  String name(int root, String quality) =>
      (flats ? _flat : _sharp)[_mod12(root)] + quality;
  int deg(Chord c) => _mod12(c.root - key.root);

  // Chords of the key: major I ii IV V vi, minor i III iv v V VI.
  bool target(Chord c) {
    final d = deg(c);
    return key.minor
        ? switch (d) {
            0 || 5 => c.minor,
            7 => true,
            3 || 8 => !c.minor,
            _ => false,
          }
        : switch (d) {
            0 || 5 || 7 => !c.minor,
            2 || 9 => c.minor,
            _ => false,
          };
  }

  String degree(Chord c) {
    const major = {0: 'I', 2: 'ii', 4: 'iii', 5: 'IV', 7: 'V', 9: 'vi'};
    const minor = {0: 'i', 3: 'III', 5: 'iv', 7: 'v', 8: 'VI'};
    final n = (key.minor ? minor : major)[deg(c)] ?? '?';
    return c.minor ? n.toLowerCase() : n.toUpperCase();
  }

  // ---- Read the song: its sections, as runs of chords ----
  final sections = <List<_Met>>[];
  var run = <_Met>[];
  void endRun() {
    if (run.isNotEmpty) {
      run.last.sectionLast = true;
      sections.add(run);
    }
    run = [];
  }

  final chordsPerLine = <int, int>{};
  var offset = 0;
  var inBlock = false;
  var words = <int>[];
  var sung = false;
  final lines = raw.split('\n');
  for (var ln = 0; ln < lines.length; ln++) {
    final line = lines[ln];
    final lineStart = offset;
    offset += line.length + 1;
    final t = line.trim();
    if (inBlock) {
      if (_blockEnd.hasMatch(line)) inBlock = false;
      continue;
    }
    if (_blockStart.hasMatch(line)) {
      inBlock = true;
      endRun();
      continue;
    }
    if (t.startsWith('#')) continue;
    if (t.isEmpty ||
        t.startsWith('{') ||
        ChordPro.sectionName(line) != null ||
        ChordPro.isDivider(line) ||
        line.contains(linkSeparator)) {
      if (run.isNotEmpty) run.last.free = words;
      words = [];
      endRun();
      continue;
    }
    final found = _chordInText.allMatches(line).toList();
    var ci = 0;
    _Met? firstHere, lastHere;
    for (var i = 0; i < line.length; i++) {
      if (ci < found.length && i == found[ci].start) {
        final m = found[ci++];
        final inner = m.group(1)!;
        final star = inner.indexOf('*');
        final text = (star < 0 ? inner : inner.substring(0, star)).trim();
        i = m.end - 1;
        if (text.isEmpty || _barMark.hasMatch(text)) continue; // bar lines
        final c = Chord.parse(text);
        if (c == null) {
          // N.C. and the like: the harmony stops.
          if (run.isNotEmpty) run.last.free = words;
          words = [];
          endRun();
          continue;
        }
        if (run.isNotEmpty) run.last.free = words;
        final met = _Met(
          lineStart + m.start,
          lineStart + m.end,
          c,
          text,
          star < 0,
          ln,
        );
        run.add(met);
        firstHere ??= met;
        lastHere = met;
        chordsPerLine[ln] = (chordsPerLine[ln] ?? 0) + 1;
        words = [];
        sung = false;
        continue;
      }
      if (run.isEmpty || !_wordChar.hasMatch(line[i])) continue;
      if (sung && (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
        words.add(lineStart + i);
      }
      sung = true;
    }
    firstHere?.lineFirst = true;
    lastHere?.lineLast = true;
  }
  if (run.isNotEmpty) run.last.free = words;
  endRun();

  // Which line a word start is on.
  final lineStarts = <int>[];
  var at = 0;
  for (final l in lines) {
    lineStarts.add(at);
    at += l.length + 1;
  }
  int lineAt(int pos) {
    var ln = 0;
    while (ln + 1 < lineStarts.length && lineStarts[ln + 1] <= pos) {
      ln++;
    }
    return ln;
  }

  final out = <PassingChord>[];

  // ---- 1. The song's own chords, reharmonized (when they may change) ----
  final changed = <_Met, String>{}; // chord -> why
  if (!keep) {
    for (final sec in sections) {
      for (var k = 0; k < sec.length; k++) {
        final m = sec[k];
        if (!m.plain) continue;
        final n = k + 1 < sec.length ? sec[k + 1] : null;
        final moves = _reharm(
          m,
          n,
          key,
          finalCadence: identical(sec, sections.last) && k == sec.length - 2,
          target: target,
          degree: degree,
          name: name,
          deg: deg,
        );
        if (moves.isEmpty) continue;
        // (Kept as it was, or only coloured, with a chord added after it:
        // no approach of its own then either.)
        changed[m] = moves.any((p) => !p.isSubstitute)
            ? 'added'
            : moves.first.why;
        out.addAll(moves);
      }
    }
  }

  // ---- 2. Approaches into every change, where there's a word for them ----
  final used = <int>{
    for (final p in out)
      if (!p.isSubstitute) p.at,
  };
  List<int> unused(_Met m) => [
    for (final w in m.free)
      if (!used.contains(w)) w,
  ];
  for (final sec in sections) {
    for (var k = 0; k + 1 < sec.length; k++) {
      final a = sec[k], b = sec[k + 1];
      // Already reharmonized (beyond a colour): it leads there itself. (A
      // V turned IV/V is still approached: D7 → F/G.)
      if ((changed[a] ?? 'colour') != 'colour') continue;
      if (!const {'colour', 'added', 'IV/V'}.contains(changed[b] ?? 'colour')) {
        continue;
      }
      final free = unused(a);
      if (free.isEmpty) continue;
      final ln = lineAt(free.last);
      if ((chordsPerLine[ln] ?? 0) >= 6) continue;
      final moves = _approach(
        a,
        b,
        free,
        key,
        keep: keep,
        target: target,
        degree: degree,
        name: name,
        deg: deg,
      );
      out.addAll(moves);
      used.addAll([for (final p in moves) p.at]);
    }
  }

  // ---- 3. Long-held tonics and turnarounds ----
  String shown(_Met m) {
    for (final p in out) {
      if (p.isSubstitute && p.at == m.start) return p.chord;
    }
    return m.text;
  }

  bool tonic(Chord c) => deg(c) == 0 && c.minor == key.minor && c.bass == null;
  for (var si = 0; si < sections.length; si++) {
    final sec = sections[si];
    for (final m in sec) {
      if (!tonic(m.chord) || !m.plain) continue;
      final free = unused(m);
      if (m.sectionLast) {
        // The end of a section going back home: a turnaround into the next
        // one (… Am7 Dm7 G7 → C).
        final next = si + 1 < sections.length ? sections[si + 1].first : null;
        if (next == null || !tonic(next.chord) || free.isEmpty) continue;
        final ii = name(key.root + 2, key.minor ? 'm7b5' : 'm7');
        final seq = [
          if (free.length >= 3)
            (
              name(key.root + (key.minor ? 8 : 9), key.minor ? 'maj7' : 'm7'),
              key.minor ? 'VI' : 'vi',
            ),
          if (free.length >= 2) (ii, 'ii'),
          (name(key.root + 7, '7'), 'V7'),
        ];
        final at = free.sublist(free.length - seq.length);
        for (var i = 0; i < seq.length; i++) {
          out.add(PassingChord(at[i], seq[i].$1, '${seq[i].$2} (turnaround)'));
          used.add(at[i]);
        }
        continue;
      }
      // Held a while: the gospel 1–4–1, IV over the tonic's bass and back
      // (C … F/C C …).
      if (key.minor || free.length < 3) continue;
      final i = (free.length - 1) ~/ 2;
      final home = shown(m);
      out
        ..add(
          PassingChord(
            free[i],
            '${name(key.root + 5, '')}/${name(key.root, '')}',
            'IV/I (plagal neighbour)',
          ),
        )
        ..add(PassingChord(free[i + 1], home, 'I'));
      used.addAll([free[i], free[i + 1]]);
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Qualities a song chord may have and still be reharmonized (anything
/// richer the songwriter chose on purpose is left alone).
final _simple = RegExp(r'^(|2|add9|sus|sus2|sus4|7|maj7|6|9|maj9)$');

/// The song's chord [m] (going to [n]), reharmonized: its replacement
/// first, then any chord added while it lasts. Empty: left as it is.
List<PassingChord> _reharm(
  _Met m,
  _Met? n,
  MusicKey key, {
  required bool finalCadence,
  required bool Function(Chord) target,
  required String Function(Chord) degree,
  required String Function(int, String) name,
  required int Function(Chord) deg,
}) {
  final c = m.chord;
  if (!_simple.hasMatch(c.rest)) return const [];
  final len = m.end - m.start;
  final bass = c.bass == null ? '' : '/${name(c.bass!, '')}';
  PassingChord sub(String chord, String why) =>
      PassingChord(m.start, chord, why, replace: len);
  // (Borrowed and tritone chords are flat degrees: Db7, Abmaj7, Bb.)
  String flat(int root, String q) => _flat[_mod12(root)] + q;
  final free = m.free;
  final nc = n?.chord;
  final hasSeventh = c.rest.contains('7') || c.rest.contains('9');

  if (n != null && nc != null && target(nc) && c.root == _mod12(nc.root + 7)) {
    final toTonic = nc.root == key.root && nc.minor == key.minor;
    if (toTonic && !c.minor) {
      // V → I. The song's last cadence: the borrowed bVI–bVII–I ("Lord's
      // Prayer" ending), or the backdoor bVII9 with no room.
      if (finalCadence && !key.minor) {
        if (free.isEmpty) {
          return [sub(flat(key.root + 10, '9'), 'bVII9 (backdoor)')];
        }
        return [
          sub(flat(key.root + 8, 'maj7'), 'bVI (borrowed)'),
          PassingChord(free.last, flat(key.root + 10, ''), 'bVII (borrowed)'),
        ];
      }
      // End of a section: the tritone substitute (Db7 → C).
      if (n.sectionLast && c.bass == null) {
        return [sub(flat(nc.root + 1, '7'), 'bII7 (tritone)')];
      }
      // End of a phrase: the gospel IV/V, then V7 (F/G … G7 → C).
      if ((n.lineLast || n.lineFirst) && c.bass == null) {
        return [
          sub('${name(nc.root + 5, '')}/${name(c.root, '')}', 'IV/V'),
          if (free.isNotEmpty) PassingChord(free.last, name(c.root, '7'), 'V7'),
        ];
      }
      if (hasSeventh) return const [];
      return [sub(name(c.root, '7') + bass, 'V7')];
    }
    // A chord a fifth above where it goes turns into its dominant: the
    // gospel circle (C A7 Dm, Em E7 Am, Dm D7 G, C C7 F). Held a while, it
    // keeps its own colour and turns dominant on its last word (C … C7 F,
    // Am … A7 Dm).
    if (c.rest.contains('7') && !c.minor) return const [];
    final dom = name(c.root, '7');
    final why = 'V7/${degree(nc)} (secondary dominant)';
    // (The tonic itself is never replaced — it's home: it turns I7 only
    // on a later word, C … C7 → F.)
    final tonic = deg(c) == 0 && c.minor == key.minor;
    if (tonic && free.isEmpty) {
      final q = c.rest.isEmpty
          ? _colour(0, c.minor, key.minor, slash: c.bass != null)
          : null;
      return [if (q != null) sub(name(c.root, q) + bass, 'colour')];
    }
    if (free.length >= 2 || tonic) {
      final q = c.rest.isEmpty && target(c)
          ? _colour(deg(c), c.minor, key.minor, slash: c.bass != null)
          : null;
      return [
        if (q != null) sub(name(c.root, q) + bass, 'colour'),
        PassingChord(free.last, dom, why),
      ];
    }
    return [sub(dom + bass, why)];
  }
  // IV → I at a phrase end: IV, then the borrowed minor iv (F Fm6 C).
  if (!key.minor &&
      n != null &&
      nc != null &&
      deg(c) == 5 &&
      !c.minor &&
      deg(nc) == 0 &&
      !nc.minor &&
      (n.lineLast || n.sectionLast) &&
      free.isNotEmpty) {
    return [
      sub(name(c.root, 'maj7') + bass, 'IV (colour)'),
      PassingChord(free.last, name(c.root, 'm6'), 'iv (borrowed)'),
    ];
  }
  // Otherwise its gospel colour.
  if (c.rest.isNotEmpty || !target(c)) return const [];
  final q = _colour(deg(c), c.minor, key.minor, slash: c.bass != null);
  if (q == null) return const [];
  return [sub(name(c.root, q) + bass, 'colour')];
}

/// The gospel colour for a song chord on [degree] (semitones above the
/// tonic), or null to leave it. [slash]: it has its own bass note.
String? _colour(int degree, bool minor, bool minorKey, {required bool slash}) {
  if (minorKey) {
    return switch (degree) {
      0 when minor => 'm9',
      5 when minor => 'm7',
      7 when minor => 'm7',
      3 || 8 when !minor => 'maj7',
      _ => null,
    };
  }
  return switch (degree) {
    // (add9 on I: maj7 rubs when the melody sits on the tonic; "2" over a
    // bass note, as worship charts write it.)
    0 when !minor => slash ? '2' : 'add9',
    2 when minor => 'm9',
    4 when minor => 'm7',
    5 when !minor => 'maj7',
    9 when minor => 'm7',
    _ => null,
  };
}

/// The chords added on [free] words while [a] lasts, leading into [b] (see
/// [gospelize]); empty when none fits.
List<PassingChord> _approach(
  _Met a,
  _Met b,
  List<int> free,
  MusicKey key, {
  required bool keep,
  required bool Function(Chord) target,
  required String Function(Chord) degree,
  required String Function(int, String) name,
  required int Function(Chord) deg,
}) {
  final ca = a.chord, cb = b.chord;
  if (ca.root == cb.root) return const [];
  final dom = _mod12(cb.root + 7);
  final ii = _mod12(cb.root + 2);
  final toTonic = cb.root == key.root && cb.minor == key.minor;
  final da = deg(ca), db = deg(cb);
  final n = free.length;
  PassingChord at(int fromEnd, String chord, String why) =>
      PassingChord(free[n - fromEnd], chord, why);

  // A whole step up: the diminished chord between walks up to it (C C#dim7
  // Dm, F F#dim7 G, G G#dim7 Am, Dm D#dim7 Em) — into any chord.
  // (The bass has to walk: not from or to a slash chord's other bass.)
  if (cb.root == _mod12(ca.root + 2) &&
      ca.bass == null &&
      cb.bass == null &&
      !(ca.rest.contains('7') && !ca.minor)) {
    return [at(1, '${_sharp[_mod12(ca.root + 1)]}dim7', '#°7 (walk-up)')];
  }
  if (!target(cb)) return const [];
  final why = toTonic ? '' : '/${degree(cb)}';

  // Already leading there: its dominant seventh, its tritone substitute.
  if (ca.root == dom && ca.rest.contains('7')) return const [];
  if (ca.root == _mod12(cb.root + 1) && !ca.minor) return const [];

  if (!key.minor) {
    // IV → I at the end of a section: the minor plagal "Amen" (F Fm6 C).
    // (Only there: with the melody on the 3rd of IV the minor iv clashes.)
    if (da == 5 && !ca.minor && db == 0 && b.sectionLast) {
      return [at(1, name(cb.root + 5, 'm6'), 'iv (minor plagal)')];
    }
    // I → IV: with room, the target's own ii–V (C Gm7 C7 F); two words,
    // the 1–4 walk-up, bass 1 2 3 4 (C Dm7 C/E F); one word: I7.
    if (da == 0 && !ca.minor && db == 5 && !cb.minor && ca.bass == null) {
      if (n >= 3) {
        return [
          at(2, name(key.root + 7, 'm7'), 'ii/IV'),
          at(1, name(key.root, '7'), 'V7/IV'),
        ];
      }
      if (n == 2) {
        return [
          at(2, name(key.root + 2, 'm7'), 'ii7 (1–4 walk-up)'),
          at(1, '${name(key.root, '')}/${name(key.root + 4, '')}', 'I/3'),
        ];
      }
      return [at(1, name(key.root, '7'), 'I7')];
    }
    // I → vi: walking the bass down, C C/B E7/G# Am.
    if (da == 0 && !ca.minor && db == 9 && cb.minor && ca.bass == null) {
      return [
        if (n >= 2)
          at(2, '${name(key.root, '')}/${name(key.root + 11, '')}', 'I/7'),
        at(1, '${name(key.root + 4, '7')}/${name(key.root + 8, '')}', 'V7/vi'),
      ];
    }
  }
  // A triad a fifth above: its seventh, or with room the ii–V of the
  // target around a major one (C Gm7 C7 F); a minor one just turns
  // dominant (Dm … D7 G).
  if (ca.root == dom && (n < 3 || toTonic || ca.minor)) {
    return [at(1, name(dom, '7'), 'V7$why')];
  }
  // ii → its I: only the V7 (Dm G7 C).
  if (ca.root == ii) {
    return [at(1, name(dom, '7'), 'V7$why')];
  }
  if (n >= 2) {
    return [
      at(2, name(ii, cb.minor ? 'm7b5' : 'm7'), 'ii$why'),
      at(1, name(dom, '7'), 'V7$why'),
    ];
  }
  // One word: the dominant, or (when the song's chords may change) its
  // tritone substitute, a half step above (Db7 → C).
  return [
    keep || cb.bass != null
        ? at(1, name(dom, '7'), 'V7$why')
        : at(1, '${_flat[_mod12(cb.root + 1)]}7', 'bII7$why (tritone)'),
  ];
}

/// [raw] with [layer]'s changes made (added chords marked with
/// [passingMark], changed ones with [changedMark], when [mark] — for the
/// sheet). Changes whose place doesn't fit the text are skipped.
String mergePassing(String raw, List<PassingChord> layer, {bool mark = false}) {
  if (layer.isEmpty) return raw;
  final sorted = [...layer]..sort((a, b) => a.at.compareTo(b.at));
  final buf = StringBuffer();
  var last = 0;
  for (final p in sorted) {
    if (p.at < last || p.at + p.replace > raw.length) continue;
    if (p.isSubstitute &&
        (raw[p.at] != '[' || raw[p.at + p.replace - 1] != ']')) {
      continue;
    }
    final m = !mark ? '' : (p.isSubstitute ? changedMark : passingMark);
    buf
      ..write(raw.substring(last, p.at))
      ..write('[$m${p.chord}]');
    last = p.at + p.replace;
  }
  buf.write(raw.substring(last));
  return buf.toString();
}

/// A steady fingerprint of a song text (the same on every platform), to
/// tell whether the layer was worked out for the text as it is now.
String textPrint(String s) {
  var a = 7, b = 11;
  for (final c in s.codeUnits) {
    a = (a * 31 + c) % 2147483647;
    b = (b * 131 + c) % 1000000007;
  }
  return '${s.length}.${a.toRadixString(36)}.${b.toRadixString(36)}';
}

/// The Gospelizer is shelved for now (2026-11-17: not in the release build):
/// off, its button and settings are hidden and every song shows exactly as
/// written, whatever its stored layer says. The code stays for later (its
/// tests switch it on).
bool gospelizerEnabled = false;

/// The rules' version: a layer worked out by older rules is worked out
/// again.
const _version = 4;

/// The Gospelizer layer of a song, in Song.extra['gospel'].
extension Gospelizer on Song {
  Map<String, dynamic>? get _layer {
    final g = extra['gospel'];
    return g is Map<String, dynamic> ? g : null;
  }

  /// Whether the added chords are shown (and exported).
  bool get gospelOn => _layer?['on'] == true;

  /// The added chords for the song text as it is now (worked out again if
  /// the text, the key or the style changed since).
  List<PassingChord> get passingChords {
    final g = _layer;
    if (g == null) return const [];
    final key = writtenKey;
    if (key == null) return const [];
    final keep = g['keep'] != false;
    if (g['base'] != textPrint(raw) ||
        g['key'] != key.name ||
        g['v'] != _version) {
      _store(
        gospelize(raw, key, keep: keep),
        on: gospelOn,
        keep: keep,
      );
    }
    final list = _layer?['chords'];
    return [
      if (list is List)
        for (final j in list) ?PassingChord.fromJson(j),
    ];
  }

  void _store(
    List<PassingChord> chords, {
    required bool on,
    required bool keep,
  }) {
    final key = writtenKey;
    extra['gospel'] = <String, dynamic>{
      'on': on,
      'keep': keep,
      'v': _version,
      'base': textPrint(raw),
      'key': key?.name,
      'chords': [for (final c in chords) c.toJson()],
    };
  }

  /// Turns the Gospelizer on (only adding chords when [keep], else also
  /// changing the song's own) or off. Off keeps nothing: the song is
  /// exactly as written.
  void setGospel(bool on, {bool keep = true}) {
    if (!on) {
      extra.remove('gospel');
      return;
    }
    final key = writtenKey;
    _store(
      key == null ? const [] : gospelize(raw, key, keep: keep),
      on: true,
      keep: keep,
    );
  }

  /// The song text as shown: with the added chords when on (marked with
  /// [passingMark] when [mark]), else [raw] itself.
  String gospelRaw({bool mark = false}) => gospelizerEnabled && gospelOn
      ? mergePassing(raw, passingChords, mark: mark)
      : raw;

  /// The song text for exports (JustChords, backups to other apps): the
  /// added chords as plain chords while on.
  String get exportRaw => gospelRaw();
}
