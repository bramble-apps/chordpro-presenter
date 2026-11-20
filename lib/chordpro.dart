// ChordPro parsing, ported from the Swift app (ContentView.swift).
//
// Two outputs:
//  * [ChordPro.parseToSlides] – lyrics-only slides for the projector.
//  * [ChordPro.sheetLines]    – lines for the formatted chord sheet
//                               (chords kept, metadata removed).

import 'dart:math' as math;

import 'abc.dart' show abcStart, abcEnd;
import 'inline_format.dart';
import 'tabs.dart';

const String pageBreakMarker = '--PAGE_BREAK--';

/// Sheet line meaning "from here on, transpose by N semitones" (a key change
/// in the song structure). Followed by the number, e.g. `--TRANSPOSE--2`.
const String transposeMarker = '--TRANSPOSE--';

/// Sheet line holding a strum pattern (`{rhythm: D>-DU-UDU}`), followed by
/// the pattern.
const String rhythmMarker = '--RHYTHM--';

/// Sheet line holding a tab block, followed by its lines joined with
/// [tabLineBreak].
const String tabMarker = '--TAB--';
const String tabLineBreak = '\u001F';

/// Sheet line holding an ABC tune ({start_of_abc}…{end_of_abc}, see
/// abc.dart), its lines joined with [tabLineBreak]. It starts like a tab
/// line, so it's kept off slides and out of chord reading the same way.
const String abcMarker = '$tabMarker--ABC--';

final RegExp _startTab = RegExp(
  r'^\{\s*(start_of_tab|sot)(\s*:[^}]*)?\s*\}$',
  caseSensitive: false,
);
final RegExp _endTab = RegExp(
  r'^\{\s*(end_of_tab|eot)\s*\}$',
  caseSensitive: false,
);

/// [text] with each tab (a {start_of_tab}…{end_of_tab} block, or two or
/// more tab lines in a row) turned into one [tabMarker] line, and each ABC
/// tune into one [abcMarker] line, so nothing else reads into them.
String collapseTabs(String text) {
  final lines = text.split('\n');
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trim();
    if (abcStart.hasMatch(t)) {
      final block = <String>[];
      i++;
      while (i < lines.length && !abcEnd.hasMatch(lines[i].trim())) {
        block.add(lines[i]);
        i++;
      }
      out.add('$abcMarker${block.join(tabLineBreak)}');
      continue;
    }
    if (_startTab.hasMatch(t)) {
      final block = <String>[];
      i++;
      while (i < lines.length && !_endTab.hasMatch(lines[i].trim())) {
        block.add(lines[i]);
        i++;
      }
      out.add('$tabMarker${block.join(tabLineBreak)}');
      continue;
    }
    if (isTabLine(lines[i])) {
      var j = i;
      while (j < lines.length && isTabLine(lines[j])) {
        j++;
      }
      if (j - i >= 2) {
        out.add('$tabMarker${lines.sublist(i, j).join(tabLineBreak)}');
        i = j - 1;
        continue;
      }
    }
    out.add(lines[i]);
  }
  return out.join('\n');
}

final RegExp _rhythmDirective = RegExp(
  r'^\{\s*rhythm\s*:\s*(.*?)\s*\}$',
  caseSensitive: false,
);

/// One slot of a strum pattern (JustChords' rhythm diagrams): its action
/// (`D` down, `U` up, `X` muted, `-` nothing, or another capital) and the
/// marks after it (`>` accent, `<` soft, `p`/`pm` palm mute, `b` bass
/// note…).
class Stroke {
  final String action;
  final String marks;
  const Stroke(this.action, this.marks);

  bool get rest => action == '-';
  bool get accent => marks.contains('>');
  bool get soft => marks.contains('<');
  bool get palmMute => marks.contains('p');
  bool get bass => marks.contains('b');

  /// How it's drawn: an arrow for a strum, × muted, · nothing.
  String get symbol => switch (action) {
    'D' => '↓',
    'U' => '↑',
    'X' => '×',
    '-' => '·',
    _ => action,
  };
}

/// The slots of a strum pattern ("D>-DU-UDU"); spaces are ignored.
List<Stroke> parseRhythm(String pattern) {
  final out = <Stroke>[];
  for (final m in RegExp(r'([A-Z\-–—])([^A-Z\-–—\s]*)').allMatches(pattern)) {
    final a = m.group(1)!;
    out.add(Stroke(a == '–' || a == '—' ? '-' : a, m.group(2)!));
  }
  return out;
}

/// The count under each of [slots] slots of a bar of [beats] beats: "1 2 3
/// 4", "1 + 2 +…", "1 + a…" (triplets), "1 e + a…"; longer patterns run
/// over several bars. Empty labels when it doesn't divide evenly.
List<String> rhythmCounts(int slots, int beats) {
  final per = _rhythmPer(slots, beats);
  if (per != null) {
    final bars = slots ~/ (beats * per);
    const subs = {
      1: [''],
      2: ['', '+'],
      3: ['', '+', 'a'],
      4: ['', 'e', '+', 'a'],
    };
    return [
      for (var b = 0; b < bars; b++)
        for (var beat = 1; beat <= beats; beat++)
          for (final s in subs[per]!) s.isEmpty ? '$beat' : s,
    ];
  }
  return List.filled(slots, '');
}

/// The slots per bar in [rhythmCounts]' reading (0: no bar lines).
int rhythmBarLength(int slots, int beats) {
  final per = _rhythmPer(slots, beats);
  return per == null ? 0 : beats * per;
}

/// Slots per beat: one bar if the pattern fills one (8 slots in 4/4 are
/// eighths), else the fewest per beat over up to four bars.
int? _rhythmPer(int slots, int beats) {
  for (final per in [1, 2, 3, 4]) {
    if (slots == beats * per) return per;
  }
  for (final per in [1, 2, 3, 4]) {
    if (slots % (beats * per) == 0 && slots ~/ (beats * per) <= 4) return per;
  }
  return null;
}

final RegExp _transposeDirective = RegExp(
  r'^\{\s*transpose\s*:\s*([+-]?\d+)\s*\}$',
  caseSensitive: false,
);

/// One step in a song structure: a section to play, or a key change.
class StructureItem {
  final String name;

  /// Non-null for a key change: semitones from the song's key from here on.
  final int? modulation;

  /// Joined to the next section: shown together as one slide (e.g. a verse
  /// in English with the same verse in French).
  final bool linked;

  const StructureItem.section(this.name, {this.linked = false})
    : modulation = null;
  const StructureItem.keyChange(int semitones)
    : name = '',
      modulation = semitones,
      linked = false;

  StructureItem withLinked(bool value) =>
      isModulation ? this : StructureItem.section(name, linked: value);

  bool get isModulation => modulation != null;
  int get semitones => modulation ?? 0;

  Map<String, dynamic> toJson() => isModulation
      ? {'type': 'modulation', 'semitones': semitones}
      : {'type': 'section', 'name': name, if (linked) 'linked': true};

  /// Accepts this app's maps, plain strings (older saves) and the library
  /// backup's `{type: section, sectionName}` maps.
  static StructureItem? fromJson(Object? j) {
    if (j is String) return StructureItem.section(j);
    if (j is! Map) return null;
    if (j['type'] == 'modulation') {
      return StructureItem.keyChange((j['semitones'] as num?)?.toInt() ?? 0);
    }
    // JustChords' key change ("Modulation").
    if (j['type'] == 'transpose') {
      return StructureItem.keyChange((j['transpo'] as num?)?.toInt() ?? 0);
    }
    final name = j['name'] ?? j['sectionName'];
    return name is String
        ? StructureItem.section(name, linked: j['linked'] == true)
        : null;
  }

  static List<StructureItem> listFromJson(Object? j) => [
    if (j is List)
      for (final e in j) ?fromJson(e),
  ];
}

const String _labelWords =
    r'verse|vers|couplet|strophe|chorus|refrain|ref|hook|bridge|pont|tag|'
    r'ending|outro|intro|pre[\s-]?chorus|prechorus|post[\s-]?chorus|vamp|'
    r'interlude|solo|instrumental|inst|turnaround|break|coda|rap|spoken|'
    r'pr[eé][\s-]?refrain|final|fin';

/// "Verse 1", "Final chorus:", "CHORUS 2", "Pré-refrain", "Instrumental x2"…
final RegExp _labelRegex = RegExp(
  '^\\s*(?:(?:final|last|repeat|reprise)\\s+)?(?:$_labelWords)'
  '(?:\\s*\\d+[a-z]?)?(?:\\s*\\(?\\s*x\\s*\\d+\\s*\\)?)?(?:\\s*[-:.)])?\\s*\$',
  caseSensitive: false,
);

/// `{c: Verse 1:}` / `{comment: CHORUS}`: a section label written as a
/// comment (common in imported libraries).
final RegExp _commentLabel = RegExp(
  r'^\s*\{\s*(?:c|comment|ci|comment_italic|cb|comment_box)\s*:\s*(.*?)\s*\}\s*$',
  caseSensitive: false,
);

/// Turns comment-style labels into plain label lines ("Verse 1:").
String _labelsFromComments(String line) {
  final m = _commentLabel.firstMatch(line);
  if (m == null) return line;
  final text = m.group(1)!;
  if (!_labelRegex.hasMatch(text) &&
      !_shortLabel.hasMatch(text)) {
    return line;
  }
  return text.endsWith(':') ? text : '$text:';
}

const String _metaKeys =
    'title|subtitle|artist|album|composer|lyricist|copyright|key|time|tempo|'
    'footer|ccli_license|ccli|capo|duration|sorttitle';

final RegExp _hasLetter = RegExp(r'\p{L}', unicode: true);

// (patterns used line by line, made once)
final RegExp _metaLine = RegExp(
  '^\\s*(?:\\{\\s*)?($_metaKeys)\\s*:\\s*(.*?)\\s*(?:\\}\\s*)?\$',
  caseSensitive: false,
);
final RegExp _shortLabel = RegExp(r'^[^\[\]]{1,30}:$');
final RegExp _dashes = RegExp(r'^-{3,}$');
final RegExp _labelEnd = RegExp(r'[:.\-)]+$');
final RegExp _dividerLine = RegExp(r'^\s*([-_=*~])\1{2,}\s*$');
final RegExp _colonsSpaces = RegExp(r'[:\s]+');
final RegExp _shortMeta = RegExp(
  r'^\s*\{\s*(t|st)\s*:\s*(.*?)\s*\}\s*$',
  caseSensitive: false,
);

final RegExp _anyDirective = RegExp(r'\{[^}]*\}');
final RegExp _chordRegex = RegExp(r'\[[^\]]*\]');
final RegExp _multiSpace = RegExp(r' {2,}');

/// A sung syllable break: a hyphen with space on either side (any amount)
/// between two letters ("mea  -  sure", "glo  -ry", "Ho - san - na").
final RegExp _syllableBreak = RegExp(
  r'(\p{L})(?:[ \t]+-[ \t]*|[ \t]*-[ \t]+)(?=(\p{L}))',
  unicode: true,
);

/// Credit lines in the lyrics ("CCLI# 155810", "© 1995 Thankyou Music"):
/// not sung, so not on slides and not translated.
final RegExp _creditLine = RegExp(
  r'^\s*(ccli\b|©|℗|\(c\)\s|copyright\b)',
  caseSensitive: false,
);

final List<RegExp> _commentPatterns = [
  RegExp(r'^\s*\{\s*comment\s*:\s*(.*?)\s*\}\s*$', caseSensitive: false),
  RegExp(r'^\s*\{\s*comment_italic\s*:\s*(.*?)\s*\}\s*$', caseSensitive: false),
  RegExp(r'^\s*\{\s*comment_box\s*:\s*(.*?)\s*\}\s*$', caseSensitive: false),
  RegExp(r'^\s*comment\s*:\s*(.*?)\s*$', caseSensitive: false),
];

/// Unifies line endings and decodes the HTML entities some apps leave in
/// (e.g. `{time: 4/4&nbsp;}`).
String _normalizeNewlines(String s) => s
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .split('\n')
    .map(_labelsFromComments)
    .join('\n');

/// `#` lines are ChordPro comments for the author, never shown.
bool _isHashComment(String line) => line.trimLeft().startsWith('#');

/// Song metadata from `{title: ...}` style directives (braced or bare).
class ChordProHeader {
  final List<String> titles = [];
  String? subtitle;
  String? artist;
  String? album;
  String? composer;
  String? lyricist;
  String? copyright;
  String? key;
  String? time;
  String? tempo;

  static ChordProHeader parse(String input) {
    final header = ChordProHeader();
    for (final line in _normalizeNewlines(input).split('\n')) {
      final short = _shortMeta.firstMatch(line);
      if (short != null) {
        final v = short.group(2)!.trim();
        short.group(1)!.toLowerCase() == 't'
            ? header.titles.add(v)
            : header.subtitle = v;
        continue;
      }
      final m = _metaLine.firstMatch(line);
      if (m == null) continue;
      final value = m.group(2)!.trim();
      switch (m.group(1)!.toLowerCase()) {
        case 'title':
          header.titles.add(value);
        case 'subtitle':
          header.subtitle = value;
        case 'artist':
          header.artist = value;
        case 'album':
          header.album = value;
        case 'composer':
          header.composer = value;
        case 'lyricist':
          header.lyricist = value;
        case 'copyright':
          header.copyright = value;
        case 'key':
          header.key = value;
        case 'time':
          header.time = value;
        case 'tempo':
          header.tempo = value;
      }
    }
    return header;
  }
}

/// One chord with the lyric text that follows it, e.g. `[G]sound` -> (G, sound).
class ChordSegment {
  final String? chord;
  final String text;

  /// The chord was added by the Gospelizer (see gospelizer.dart): drawn as
  /// a passing chord.
  final bool passing;

  /// The song's own chord, changed by the Gospelizer (a substitute or a
  /// richer colour): drawn with its glow, but it's still the song's chord.
  final bool changed;
  const ChordSegment(
    this.chord,
    this.text, {
    this.passing = false,
    this.changed = false,
  });
}

/// One selectable piece of a song: a section (or a chunk of one between
/// blank lines / slide breaks). The chord sheet shows [lines]; the projector
/// shows [slide]. A key-change marker from the song structure is a part
/// with [keyChange] set; it is shown but not selected.
class SongPart {
  final List<String> lines;

  /// Slide text. Linked sections (see [StructureItem.linked]) are kept as
  /// separate pieces joined by [linkSeparator], so screens can lay them out
  /// and style them.
  final String slide;
  final int? keyChange;

  /// Where each linked piece after the first starts in [lines].
  final List<int> cuts;

  const SongPart(this.lines, this.slide, {this.cuts = const []})
    : keyChange = null;
  const SongPart.keyChange(int semitones)
    : lines = const [],
      slide = '',
      cuts = const [],
      keyChange = semitones;

  bool get isMarker => keyChange != null;
  String get raw => lines.join('\n');

  /// The main piece and any linked pieces (e.g. a verse, then its
  /// translation), as lines.
  List<List<String>> get pieceLines {
    final at = [0, ...cuts, lines.length];
    return [
      for (var i = 0; i < at.length - 1; i++) lines.sublist(at[i], at[i + 1]),
    ];
  }

  /// The slide without its linked pieces.
  String get mainSlide => slide.split(linkSeparator).first;
}

/// Separates linked pieces inside a slide's text.
const String linkSeparator = '\u2029';

/// Joins the section before it to the one after it (linked sections in a
/// song structure become one slide).
const String linkMarker = '{link}';
final RegExp _linkDirective = RegExp(r'^\{\s*link\s*\}$', caseSensitive: false);

/// JustChords' "Lyrics Projection Override": inside a section, the text
/// the projector shows instead of its lyrics (the chord sheet keeps the
/// lyrics). An empty block projects the lyrics as usual.
final RegExp _overrideStart = RegExp(
  r'^\{\s*start_of_lyrics_override\s*\}$',
  caseSensitive: false,
);
final RegExp _overrideEnd = RegExp(
  r'^\{\s*end_of_lyrics_override\s*\}$',
  caseSensitive: false,
);
final RegExp _overrideBlock = RegExp(
  r'^[ \t]*\{\s*start_of_lyrics_override\s*\}[\s\S]*?\{\s*end_of_lyrics_override\s*\}[ \t]*$\n?',
  caseSensitive: false,
  multiLine: true,
);

/// [text] without its lyrics-override blocks.
String withoutOverrides(String text) => text.replaceAll(_overrideBlock, '');

const String lyricsOverrideBlock =
    '{start_of_lyrics_override}\n\n{end_of_lyrics_override}';

final RegExp _partBreak = RegExp(
  r'^\{\s*(new_slide|new_page|new_physical_page|np|column_break|section_break)\s*\}$',
  caseSensitive: false,
);

class ChordPro {
  /// Splits a song into parts. A new part starts at every section label,
  /// blank line, slide/page break (`---`, `{new_slide}`, `{section_break}`…)
  /// and key change. Parts with nothing to show (only metadata) are dropped.
  static List<SongPart> parts(String raw, {bool tidy = true}) {
    final chunks = <List<String>>[];
    final markers = <int, int>{}; // chunk index -> key change
    // The section each chunk is in (a new one at each label, `{link}` and
    // key change), and the sections linked to the next one.
    final sectionOf = <int>[];
    var section = 0;
    final links = <int>{};
    var current = <String>[];
    void flush() {
      if (current.isNotEmpty) {
        chunks.add(current);
        sectionOf.add(section);
      }
      current = [];
    }

    // Each section's projected-text override (JustChords), kept apart.
    final overrides = <int, List<String>>{};
    List<String>? inOverride;
    // Inside {start_of_tab}…{end_of_tab} (or an ABC tune): blank lines
    // don't split it.
    var inTab = false;
    var inAbc = false;

    for (final line in _normalizeNewlines(raw).split('\n')) {
      final t = line.trim();
      if (inAbc || abcStart.hasMatch(t)) {
        inAbc = !abcEnd.hasMatch(t);
        current.add(line);
        continue;
      }
      if (inTab || _startTab.hasMatch(t)) {
        inTab = !_endTab.hasMatch(t);
        current.add(line);
        continue;
      }
      if (inOverride != null) {
        if (_overrideEnd.hasMatch(t)) {
          inOverride = null;
        } else {
          inOverride.add(line);
        }
        continue;
      }
      if (_overrideStart.hasMatch(t)) {
        inOverride = overrides[section] = [];
        continue;
      }
      if (_linkDirective.hasMatch(t)) {
        flush();
        if (chunks.isNotEmpty) links.add(section);
        section++;
        continue;
      }
      final transpose = _transposeDirective.firstMatch(t);
      if (transpose != null) {
        flush();
        markers[chunks.length] = int.parse(transpose.group(1)!);
        chunks.add(const []);
        sectionOf.add(++section);
        section++;
        continue;
      }
      if (t.isEmpty ||
          _partBreak.hasMatch(t) ||
          _dashes.hasMatch(t) ||
          (isSectionLabel(t) && !_hasLetter.hasMatch(t))) {
        flush();
        continue;
      }
      if (sectionName(line) != null) {
        flush();
        section++;
      }
      current.add(line);
    }
    flush();

    // A label with a blank line under it ("Chorus:" ⏎ ⏎ lyrics) belongs to
    // the section it names: join it to the next chunk so it isn't a part
    // of its own (one press per section, not two).
    for (var i = 0; i < chunks.length - 1; i++) {
      final c = chunks[i];
      final labelOnly =
          c.isNotEmpty &&
          !markers.containsKey(i) &&
          c.every((l) => sectionName(l) != null || l.trim().isEmpty);
      final next = chunks[i + 1];
      if (labelOnly &&
          !markers.containsKey(i + 1) &&
          next.isNotEmpty &&
          sectionName(next.first) == null) {
        chunks[i + 1] = [...c, ...next];
        chunks[i] = const [];
      }
    }

    bool hasWords(int i) =>
        chunks[i].isNotEmpty &&
        !markers.containsKey(i) &&
        parseToSlides(chunks[i].join('\n'), tidy: tidy).isNotEmpty;

    // A section with an override projects it instead: its paragraphs in
    // turn on the section's paragraphs with words (extra ones join the
    // last).
    final ovr = <int, String>{};
    for (final MapEntry(key: sec, value: lines) in overrides.entries) {
      final paras = parseToSlides(lines.join('\n'), tidy: tidy);
      if (paras.isEmpty) continue; // empty: the lyrics as usual
      var own = [
        for (var i = 0; i < chunks.length; i++)
          if (sectionOf[i] == sec && hasWords(i)) i,
      ];
      // A section with only a label (or chords): its first piece.
      if (own.isEmpty) {
        own = [
          for (var i = 0; i < chunks.length; i++)
            if (sectionOf[i] == sec && chunks[i].isNotEmpty) i,
        ].take(1).toList();
      }
      for (var k = 0; k < own.length; k++) {
        ovr[own[k]] = k == own.length - 1
            ? paras.skip(k).join('\n')
            : (k < paras.length ? paras[k] : '');
      }
    }
    final pieceOvr = <int, List<String?>>{};

    // Linked sections (e.g. English then French) become shared slides,
    // paragraph by paragraph: the first paragraph with words of each goes
    // on one slide, the second on the next… Chord-only paragraphs (an
    // instrumental after a chorus) aren't paired: they stay where they are.
    // Where each joined piece starts, so the slide can keep them apart.
    final pieces = <int, List<int>>{};
    final order = <int>[];
    for (var i = 0; i < chunks.length; i++) {
      if (order.isEmpty || order.last != sectionOf[i]) order.add(sectionOf[i]);
    }
    final markerSections = {for (final i in markers.keys) sectionOf[i]};
    var g = 0;
    while (g < order.length) {
      final group = [order[g]];
      while (links.contains(group.last) &&
          g + 1 < order.length &&
          !markerSections.contains(group.last) &&
          !markerSections.contains(order[g + 1])) {
        group.add(order[++g]);
      }
      g++;
      if (group.length < 2) continue;
      final rowsOf = [
        for (final sec in group)
          [
            for (var i = 0; i < chunks.length; i++)
              if (sectionOf[i] == sec && hasWords(i)) i,
          ],
      ];
      final rows = rowsOf.fold(0, (n, r) => math.max(n, r.length));
      for (var r = 0; r < rows; r++) {
        final members = [
          for (final list in rowsOf)
            if (r < list.length) list[r],
        ];
        if (members.length < 2) continue;
        final target = members.first;
        final joined = <String>[];
        final cuts = <int>[];
        for (final m in members) {
          if (joined.isNotEmpty) cuts.add(joined.length);
          joined.addAll(chunks[m]);
          if (m != target) chunks[m] = const [];
        }
        chunks[target] = joined;
        pieces[target] = cuts;
        pieceOvr[target] = [for (final m in members) ovr[m]];
      }
    }

    final result = <SongPart>[];
    for (var i = 0; i < chunks.length; i++) {
      if (markers.containsKey(i)) {
        result.add(SongPart.keyChange(markers[i]!));
        continue;
      }
      if (chunks[i].isEmpty) continue;
      final text = chunks[i].join('\n');
      final visible = sheetLines(text).any((l) => l.trim().isNotEmpty);
      if (!visible) continue;
      // Linked pieces (e.g. English then French) with a gap between.
      final cuts = [0, ...?pieces[i], chunks[i].length];
      final own = pieceOvr[i] ?? [ovr[i]];
      final slide = [
        for (var c = 0; c < cuts.length - 1; c++)
          (c < own.length ? own[c] : null) ??
              parseToSlides(
                chunks[i].sublist(cuts[c], cuts[c + 1]).join('\n'),
                tidy: tidy,
              ).join('\n'),
      ].where((t) => t.trim().isNotEmpty).join(linkSeparator);
      // Chord-only lines in a row (an instrumental): one blank slide, not
      // one per line.
      if (slide.isEmpty &&
          result.isNotEmpty &&
          !result.last.isMarker &&
          result.last.slide.isEmpty &&
          sectionName(chunks[i].first) == null) {
        result[result.length - 1] = SongPart([
          ...result.last.lines,
          '',
          ...chunks[i],
        ], '');
        continue;
      }
      result.add(SongPart(chunks[i], slide, cuts: pieces[i] ?? const []));
    }
    return result;
  }

  /// Joins words split into sung syllables, however they are spaced:
  /// "mea  -  sure" → "measure", "Ho - san - na" → "Hosanna". A dash before
  /// a capital ("Lord - You") is punctuation and stays, unless the words
  /// are all capitals ("HO - SAN - NA").
  static String joinSyllables(String line) =>
      line.replaceAllMapped(_syllableBreak, (m) {
        final before = m.group(1)!, after = m.group(2)!;
        final capital = after != after.toLowerCase();
        final allCaps = before != before.toLowerCase();
        return capital && !allCaps ? m.group(0)! : before;
      });

  /// "CCLI# 155810", "© 1995 Thankyou Music"…
  static bool isCreditLine(String line) => _creditLine.hasMatch(line);

  /// Section labels like "Verse 1:", "Chorus", or any line ending with ":".
  static bool isSectionLabel(String line) {
    if (line.trim().endsWith(':')) return true;
    return _labelRegex.hasMatch(line);
  }

  /// A section name shortened for a margin badge: "Verse 1" -> "V1",
  /// "Chorus" -> "C", "Pre-Chorus 2" -> "PC2", "Bridge" -> "B" (French
  /// too: "Couplet 2" -> "V2", "Refrain" -> "C", "Pont" -> "B"); a
  /// translation's "(FR)" is left out. Other names: their first two letters.
  static String sectionAbbreviation(String name) {
    var n = name.replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'[:.\-)]+$'), '').trim();
    final num = RegExp(r'(\d+)\s*$').firstMatch(n)?.group(1) ?? '';
    n = n.replaceAll(RegExp(r'\d+\s*$'), '').trim().toLowerCase();
    const words = {
      'verse': 'V', 'couplet': 'V', 'strophe': 'V', 'chorus': 'C', 'refrain': 'C',
      'pre-chorus': 'PC', 'prechorus': 'PC', 'pre chorus': 'PC', 'pré-refrain': 'PC', 'pre-refrain': 'PC',
      'post-chorus': 'PoC', 'bridge': 'B', 'pont': 'B', 'intro': 'I', 'introduction': 'I',
      'outro': 'O', 'ending': 'E', 'fin': 'E', 'tag': 'T', 'coda': 'Co', 'interlude': 'In',
      'instrumental': 'Inst', 'solo': 'S', 'vamp': 'Va',
    };
    final w = words[n] ?? (n.isEmpty ? '' : n[0].toUpperCase() + (n.length > 1 ? n[1] : ''));
    return '$w$num';
  }

  /// Section name of a label line ("Verse 1:" -> "Verse 1"), or null.
  static String? sectionName(String line) {
    if (!isSectionLabel(line)) return null;
    var name = line.trim().replaceAll(_labelEnd, '').trim();
    // "Verse 1 (FR):" keeps its closing bracket.
    if (name.contains('(') && !name.contains(')')) name = '$name)';
    return _hasLetter.hasMatch(name) ? name : null;
  }

  /// A divider line ("----", "***", "___"): it ends the section above
  /// (e.g. before a translation pasted under the song with no label).
  static bool isDivider(String line) =>
      _dividerLine.hasMatch(line);

  static String _sectionKey(String name) =>
      name.toLowerCase().replaceAll(_colonsSpaces, ' ').trim();

  /// Section names in the order they appear in the song (duplicates kept).
  static List<String> sectionNames(String raw) => [
    for (final line in _normalizeNewlines(raw).split('\n')) ?sectionName(line),
  ];

  /// Labels a song's sections where the writer didn't, so the structure,
  /// translations and links can use them:
  ///  * lyrics before the first label become "Verse 1" (or "Couplet 1" in
  ///    a French song);
  ///  * in songs that only label their choruses / bridges (common in French:
  ///    "Refrain", "Pont", no "Couplet"), the unlabelled lyrics between them
  ///    become the verses;
  ///  * lyrics after an intro / instrumental label become a verse;
  ///  * a label used again for different words gets the next number
  ///    ("Verse" again → "Verse 2"; the same words again is a repeat).
  /// A verse spread over several paragraphs under one label stays one
  /// section; text after a divider ("----") is left alone. [title]: a first
  /// line that is just the song's title isn't a verse.
  static String labelSections(String raw, {String? title}) =>
      relabel(raw, const [], title: title).$1;

  /// [labelSections], with [structure] kept in step: a new label goes in
  /// after the section its lyrics used to be shown with (after that
  /// section's linked translations), or first for lyrics before any label;
  /// a renamed repeat takes that repeat's place.
  static (String, List<StructureItem>) relabel(
    String raw,
    List<StructureItem> structure, {
    String? title,
  }) {
    var lines = _normalizeNewlines(raw).split('\n');
    final renames = <(String, int, String)>[]; // old name, its n-th use, new
    final autos = <(String, String?)>[]; // new name, the section before

    String plain(List<String> ls) =>
        parseToSlides(ls.join('\n'))
            .join(' ')
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    bool translated(String name) =>
        RegExp(r'\([A-Z]{2,3}(?:-[A-Z]{2})?\)$').hasMatch(name.trim());
    bool kind(String name, String words) => RegExp(
      '^\\s*(?:(?:final|last|repeat|reprise)\\s+)?(?:$words)(?![a-z])',
      caseSensitive: false,
    ).hasMatch(name);
    int? number(String name) =>
        int.tryParse(RegExp(r'\d+').firstMatch(name)?.group(0) ?? '');
    String base(String name) =>
        name.replaceFirst(RegExp(r'\s*\d+\s*[a-zA-Z]?\s*$'), '').trim();

    // 1. The same label again for different words: the next number.
    final blocks = <(int, String, List<String>)>[]; // label line, name, body
    for (var i = 0; i < lines.length; i++) {
      final name = sectionName(lines[i]);
      if (name != null) {
        blocks.add((i, name, []));
      } else if (isDivider(lines[i])) {
        blocks.add((i, '', []));
      } else if (blocks.isNotEmpty) {
        blocks.last.$3.add(lines[i]);
      }
    }
    final firstWords = <String, String>{};
    final uses = <String, int>{};
    for (final (at, name, body) in blocks) {
      if (name.isEmpty || translated(name)) continue;
      final key = _sectionKey(name);
      final use = uses[key] = (uses[key] ?? 0) + 1;
      final words = plain(body);
      final first = firstWords[key];
      if (first == null) {
        if (words.isNotEmpty) firstWords[key] = words;
        continue;
      }
      if (words.isEmpty || words == first) continue; // a repeat
      final b = base(name);
      final taken = {
        for (final (_, n, _) in blocks)
          if (n.isNotEmpty && _sectionKey(base(n)) == _sectionKey(b))
            ?number(n),
      };
      var k = 2;
      while (taken.contains(k)) {
        k++;
      }
      final renamed = '${b.isEmpty ? name : b} $k';
      lines[at] = '$renamed:';
      renames.add((name, use - 1, renamed));
      firstWords[_sectionKey(renamed)] = words;
    }

    // 2. Unlabelled lyrics.
    final names = [
      for (final l in lines)
        if (sectionName(l) case final n? when !translated(n)) n,
    ];
    const verseWords = r'verse|vers|couplet|strophe';
    const soloWords =
        r'intro|instrumental|inst|interlude|solo|turnaround|break';
    final hasVerses = names.any((n) => kind(n, verseWords));
    final french =
        names.any(
          (n) => kind(n, r'couplet|refrain|pont|pr[eé][\s-]?refrain'),
        ) &&
        !names.any((n) => kind(n, r'verse|chorus|bridge'));
    final word = french ? 'Couplet' : 'Verse';
    final used = {
      for (final n in names)
        if (kind(n, verseWords)) ?number(n),
    };

    final out = <String>[];
    String? current; // the section the lyrics are in (null: none yet)
    var currentIsSolo = false, currentHasLyrics = false;
    var inAutoVerse = false, afterDivider = false, seenLyrics = false;
    var i = 0;
    while (i < lines.length) {
      if (lines[i].trim().isEmpty) {
        out.add(lines[i++]);
        continue;
      }
      var end = i;
      while (end < lines.length && lines[end].trim().isNotEmpty) {
        end++;
      }
      final para = lines.sublist(i, end);
      final labels = [for (final l in para) ?sectionName(l)];
      if (para.any(isDivider)) {
        afterDivider = true;
        current = null;
        inAutoVerse = false;
      } else if (labels.isNotEmpty) {
        current = labels.last;
        currentIsSolo = kind(current, soloWords);
        currentHasLyrics = plain([
          for (final l in para)
            if (sectionName(l) == null) l,
        ]).isNotEmpty;
        if (currentHasLyrics) seenLyrics = true;
        inAutoVerse = false;
        afterDivider = false;
      } else if (plain(para).isNotEmpty) {
        final titleLine =
            !seenLyrics &&
            current == null &&
            para.length == 1 &&
            title != null &&
            title.trim().isNotEmpty &&
            plain(para).contains(title.trim().toLowerCase());
        final bool label;
        if (afterDivider || inAutoVerse || titleLine) {
          label = false;
        } else if (current == null) {
          label = true;
        } else if (translated(current)) {
          label = false;
        } else if (currentIsSolo && !currentHasLyrics) {
          label = true;
        } else {
          label = !hasVerses && !kind(current, verseWords);
        }
        if (label) {
          var k = 1;
          while (used.contains(k)) {
            k++;
          }
          used.add(k);
          out.add('$word $k:');
          autos.add(('$word $k', current));
          inAutoVerse = true;
        }
        if (!titleLine) seenLyrics = true;
        currentHasLyrics = true;
      }
      out.addAll(para);
      i = end;
    }
    if (structure.isEmpty || (renames.isEmpty && autos.isEmpty)) {
      return (out.join('\n'), structure);
    }

    // The structure: the n-th use of a renamed label → its new name.
    var items = [...structure];
    final seen = <String, int>{};
    for (var j = 0; j < items.length; j++) {
      final item = items[j];
      if (item.isModulation) continue;
      final key = _sectionKey(item.name);
      final n = seen[key] = (seen[key] ?? 0) + 1;
      for (final (old, use, renamed) in renames) {
        if (_sectionKey(old) == key && use == n - 1) {
          items[j] = StructureItem.section(renamed, linked: item.linked);
        }
      }
    }
    // New sections after the one they were shown with.
    for (final (name, before) in autos.reversed) {
      if (before == null) {
        items.insert(0, StructureItem.section(name));
        continue;
      }
      for (var j = items.length - 1; j >= 0; j--) {
        final item = items[j];
        if (item.isModulation ||
            _sectionKey(item.name) != _sectionKey(before)) {
          continue;
        }
        var end = j;
        while (end < items.length - 1 &&
            !items[end].isModulation &&
            items[end].linked) {
          end++;
        }
        items.insert(end + 1, StructureItem.section(name));
      }
    }
    return (out.join('\n'), items);
  }

  /// Reorders a song's sections to follow [structure] (e.g. Intro, Verse 1,
  /// Chorus, key change +2, Chorus). Lines before the first label are kept
  /// at the top. If a label appears more than once, the copy with the most
  /// lyrics is used. Unknown section names are shown as a heading only.
  /// Key changes become a `{transpose: N}` line that the chord sheet uses.
  static String applyStructure(String raw, List<StructureItem> structure) {
    if (structure.isEmpty) return raw;
    final preamble = <String>[];
    final found = <(String, List<String>)>[];
    for (final line in _normalizeNewlines(raw).split('\n')) {
      final name = sectionName(line);
      if (name != null) {
        found.add((_sectionKey(name), [line]));
      } else if (isDivider(line) && found.isNotEmpty) {
        // What follows (until the next label) isn't part of any section.
        found.add(('', [line]));
      } else if (found.isEmpty) {
        preamble.add(line);
      } else {
        found.last.$2.add(line);
      }
    }

    int weight(List<String> b) => b.where((l) => l.trim().isNotEmpty).length;
    final blocks = <String, List<String>>{};
    for (final (key, block) in found) {
      if (key.isEmpty) continue;
      final existing = blocks[key];
      if (existing == null || weight(block) > weight(existing)) {
        blocks[key] = block;
      }
    }

    final out = [...preamble];
    for (var n = 0; n < structure.length; n++) {
      final item = structure[n];
      if (item.isModulation) {
        out
          ..add('{transpose: ${item.semitones}}')
          ..add('');
        continue;
      }
      final block = [
        ...blocks[_sectionKey(item.name)] ?? ['${item.name}:'],
      ];
      while (block.isNotEmpty && block.last.trim().isEmpty) {
        block.removeLast();
      }
      final linkNext =
          item.linked &&
          n + 1 < structure.length &&
          !structure[n + 1].isModulation;
      out
        ..addAll(block)
        ..add(linkNext ? linkMarker : '');
    }
    return out.join('\n');
  }

  /// Text of one section (its label line plus lyrics), or null.
  static String? sectionText(String raw, String name) {
    final lines = _normalizeNewlines(raw).split('\n');
    final key = _sectionKey(name);
    final start = lines.indexWhere(
      (l) => sectionName(l) != null && _sectionKey(sectionName(l)!) == key,
    );
    if (start < 0) return null;
    var end = start + 1;
    while (end < lines.length &&
        sectionName(lines[end]) == null &&
        !isDivider(lines[end])) {
      end++;
    }
    return lines.sublist(start, end).join('\n').trimRight();
  }

  /// Replaces the first section called [name] with [text].
  static String replaceSection(String raw, String name, String text) {
    final lines = _normalizeNewlines(raw).split('\n');
    final key = _sectionKey(name);
    final start = lines.indexWhere(
      (l) => sectionName(l) != null && _sectionKey(sectionName(l)!) == key,
    );
    if (start < 0) return raw;
    var end = start + 1;
    while (end < lines.length &&
        sectionName(lines[end]) == null &&
        !isDivider(lines[end])) {
      end++;
    }
    // Keep one blank line before the next section.
    final replacement = [
      ...text.trimRight().split('\n'),
      if (end < lines.length) '',
    ];
    return [
      ...lines.sublist(0, start),
      ...replacement,
      ...lines.sublist(end),
    ].join('\n');
  }

  /// Removes `[chords]` and `{directives}` and collapses spaces.
  static String stripArtifacts(String text) {
    var s = text.replaceAll(_chordRegex, '').replaceAll(_anyDirective, '');
    s = s.replaceAll(_multiSpace, ' ');
    return s.trim();
  }

  /// [segments], with inline formatting marks (`*bold*`, `<red>…<`) taken out
  /// of the words (for exports and anything that shows them plain).
  static List<ChordSegment> plainSegments(String line) {
    final segs = segments(line);
    if (!segs.any((s) => hasInlineMarks(s.text))) return segs;
    final runs = formatPieces([for (final s in segs) s.text]);
    return [
      for (final (i, s) in segs.indexed)
        ChordSegment(
          s.chord,
          runs[i].map((r) => r.text).join(),
          passing: s.passing,
          changed: s.changed,
        ),
    ];
  }

  /// Splits a chorded line into segments so each chord sits above its lyric.
  /// Text is split on words so the line can wrap naturally.
  static List<ChordSegment> segments(String line) {
    final result = <ChordSegment>[];
    String? pendingChord;
    var pendingPassing = false;
    var pendingChanged = false;
    final buffer = StringBuffer();

    void flush() {
      final text = buffer.toString();
      buffer.clear();
      if (text.isEmpty && pendingChord == null) return;
      // Split into words (keeping trailing spaces) so long lines wrap.
      final words = RegExp(r'\S*\s*')
          .allMatches(text)
          .map((m) => m.group(0)!)
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.isEmpty) {
        result.add(
          ChordSegment(
            pendingChord,
            '',
            passing: pendingPassing,
            changed: pendingChanged,
          ),
        );
      } else {
        for (var i = 0; i < words.length; i++) {
          result.add(
            i == 0
                ? ChordSegment(
                    pendingChord,
                    words[i],
                    passing: pendingPassing,
                    changed: pendingChanged,
                  )
                : ChordSegment(null, words[i]),
          );
        }
      }
      pendingChord = null;
      pendingPassing = false;
      pendingChanged = false;
    }

    var i = 0;
    while (i < line.length) {
      final ch = line[i];
      if (ch == '[') {
        final close = line.indexOf(']', i);
        if (close != -1) {
          flush();
          var chord = line.substring(i + 1, close).trim();
          // (A Gospelizer chord: marked with U+2064, see gospelizer.dart.)
          if (chord.startsWith('\u2064')) {
            chord = chord.substring(1);
            pendingPassing = true;
          } else if (chord.startsWith('\u2062')) {
            // (One of the song's own, changed by it.)
            chord = chord.substring(1);
            pendingChanged = true;
          }
          pendingChord = chord;
          i = close + 1;
          continue;
        }
      }
      buffer.write(ch);
      i++;
    }
    flush();
    return result;
  }

  /// Lines for the formatted chord sheet: metadata, section markers and
  /// layout directives are removed; comments become visible text; `---`
  /// becomes a page break.
  static List<String> sheetLines(String input) {
    input = collapseTabs(withoutOverrides(_normalizeNewlines(input)));
    final out = <String>[];
    final metaPattern = RegExp(
      '^\\s*(?:\\{\\s*)?($_metaKeys)\\s*:\\s*.*?(?:\\}\\s*)?\$',
      caseSensitive: false,
    );
    final sectionPattern = RegExp(
      r'\{\s*(start_of_verse|end_of_verse|start_of_chorus|end_of_chorus|'
      r'start_of_bridge|end_of_bridge|start_of_tab|end_of_tab|soc|eoc|sov|eov)\s*\}',
      caseSensitive: false,
    );
    final layoutPattern = RegExp(
      r'\{\s*(new_page|new_physical_page|np|column_break|new_song|colb|cole|'
      r'grid\s*:\s*(on|off)|highlight\s*:\s*(on|off))[^}]*\}',
      caseSensitive: false,
    );
    final definePattern = RegExp(r'\{\s*define\s*:', caseSensitive: false);

    for (final line in _normalizeNewlines(input).split('\n')) {
      final trimmed = line.trim();
      if (_isHashComment(line)) continue;
      if (trimmed.startsWith(tabMarker)) {
        out.add(trimmed);
        continue;
      }
      // Labels without letters (e.g. "~~:") just separate sections.
      if (isSectionLabel(trimmed) &&
          trimmed.isNotEmpty &&
          !_hasLetter.hasMatch(trimmed)) {
        out.add('');
        continue;
      }

      if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
        out.add(pageBreakMarker);
        continue;
      }
      final transpose = _transposeDirective.firstMatch(trimmed);
      if (transpose != null) {
        out.add('$transposeMarker${transpose.group(1)}');
        continue;
      }
      final rhythm = _rhythmDirective.firstMatch(trimmed);
      if (rhythm != null) {
        if (parseRhythm(rhythm.group(1)!).isNotEmpty) {
          out.add('$rhythmMarker${rhythm.group(1)}');
        }
        continue;
      }
      if (metaPattern.hasMatch(trimmed) ||
          sectionPattern.hasMatch(trimmed) ||
          layoutPattern.hasMatch(trimmed) ||
          definePattern.hasMatch(trimmed)) {
        continue;
      }

      String? comment;
      for (final rx in _commentPatterns) {
        final m = rx.firstMatch(line);
        if (m != null) {
          comment = m.group(1)!.trim();
          break;
        }
      }
      if (comment != null) {
        out.add(comment);
        continue;
      }
      out.add(line.replaceAll(_anyDirective, ''));
    }

    // Normalize " - " separator tokens; a lone "-" line is just a spacer.
    final normalized = out.map((l) {
      if (l == pageBreakMarker ||
          l.startsWith(transposeMarker) ||
          l.startsWith(rhythmMarker) ||
          l.startsWith(tabMarker)) {
        return l;
      }
      final t = l.replaceAll(' - ', '').trim();
      return t == '-' ? '' : t;
    }).toList();

    // Collapse repeated blank lines, keep page breaks.
    final result = <String>[];
    var lastWasBlank = false;
    for (final l in normalized) {
      if (l == pageBreakMarker ||
          l.startsWith(transposeMarker) ||
          l.startsWith(rhythmMarker) ||
          l.startsWith(tabMarker)) {
        result.add(l);
        lastWasBlank = false;
        continue;
      }
      final isBlank = l.trim().isEmpty;
      if (isBlank) {
        if (!lastWasBlank) result.add('');
      } else {
        result.add(l);
      }
      lastWasBlank = isBlank;
    }
    return result;
  }

  /// Lyrics-only slides. Blank lines, `{new_slide}`, `{new_page}`, `{np}`,
  /// `{column_break}` and `---` all start a new slide.
  /// [tidy] removes " - " syllable breaks, lone "-" lines and double spaces.
  static List<String> parseToSlides(String input, {bool tidy = true}) {
    // Tabs are for the players, not the audience.
    var s = collapseTabs(withoutOverrides(_normalizeNewlines(input)))
        .split('\n')
        .where((l) => !l.trimLeft().startsWith(tabMarker))
        .join('\n');

    for (final pattern in [
      r'\{\s*new_slide\s*\}',
      r'\{\s*new_page\s*\}',
      r'\{\s*new_physical_page\s*\}',
      r'\{\s*np\s*\}',
      r'\{\s*column_break\s*\}',
      r'\{\s*section_break\s*\}',
    ]) {
      s = s.replaceAll(RegExp(pattern, caseSensitive: false), '\n\n');
    }
    s = s.replaceAll(RegExp(r'^\s*-{3,}\s*$', multiLine: true), '\n\n');

    for (final pattern in [
      '^\\s*(?:\\{\\s*)?($_metaKeys)\\s*:[^}\\n]*?(?:\\}\\s*)?\$',
      r'\{\s*(start_of_verse|end_of_verse|start_of_chorus|end_of_chorus|'
          r'start_of_bridge|end_of_bridge|start_of_tab|end_of_tab|soc|eoc|sov|eov)\s*\}',
      r'\{\s*(colb|cole)\s*\}',
      r'\{\s*grid\s*:\s*(on|off)\s*\}',
      r'\{\s*highlight\s*:\s*(on|off)\s*\}',
      r'\{\s*define\s*:[^}]*\}',
    ]) {
      s = s.replaceAll(
        RegExp(pattern, caseSensitive: false, multiLine: true),
        '',
      );
    }

    var lines = s
        .split('\n')
        .where((line) => !_isHashComment(line))
        .where((line) => !isCreditLine(line))
        // Comments are notes for the musicians ("To Chorus", "Repeat"),
        // not for the audience.
        .where((line) => !_commentPatterns.any((rx) => rx.hasMatch(line)))
        .map((line) {
          return line
              .replaceAll(_anyDirective, '')
              .replaceAll(_chordRegex, '')
              .trim();
        })
        .toList();

    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    // Labels, lines ending with ":" and lone hyphens become blank (= break).
    lines = lines.map((line) {
      if (line.isEmpty) return '';
      if (_labelRegex.hasMatch(line)) return '';
      if (RegExp(r':\s*$').hasMatch(line)) return '';
      // Inline formatting marks (*bold*, <red>…<) aren't for the audience.
      line = withoutInlineMarks(line);
      if (!tidy) return line.trim();
      if (RegExp(r'^\s*-\s*$').hasMatch(line)) return '';
      return joinSyllables(line).replaceAll(_multiSpace, ' ').trim();
    }).toList();

    final slides = <String>[];
    final buffer = <String>[];
    for (final l in lines) {
      if (l.isEmpty) {
        if (buffer.isNotEmpty) {
          slides.add(buffer.join('\n'));
          buffer.clear();
        }
      } else {
        buffer.add(l);
      }
    }
    if (buffer.isNotEmpty) slides.add(buffer.join('\n'));

    final cleaned = slides
        .map(
          (slide) => slide
              .split('\n')
              .map(
                (l) => tidy ? l.replaceAll(_multiSpace, ' ').trim() : l.trim(),
              )
              .join('\n')
              .trim(),
        )
        .where((slide) => slide.isNotEmpty)
        .toList();

    // Nothing to sing (e.g. an instrumental): a blank screen, never the raw
    // text with labels and chords.
    return cleaned;
  }
}

const String sampleChordPro = '''{title: Amazing Grace}
{artist: John Newton}
Verse 1:
[Em]Amazing [D]grace, how sweet the [G]sound
That [D]saved a wretch like [G]me
I [Em]once was [D]lost, but [G]now am found
Was [D]blind, but [G]now I [D]see

 -

{new_slide}
Refrain:
'Twas grace   that taught  my heart to fear
And grace my fears relieved
How precious did that grace appear
The hour I first believed''';
