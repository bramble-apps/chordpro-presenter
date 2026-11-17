// A score read from sheet music: its notes and rests (with where each was
// found on the page, for highlighting and corrections), measures, clefs,
// key and time. Kept as JSON; played, exported and turned into chords from
// here.

import 'dart:math' as math;

/// A box on a page (pixels of that page's image).
class Box {
  final double l, t, r, b;
  const Box(this.l, this.t, this.r, this.b);

  double get w => r - l;
  double get h => b - t;
  double get cx => (l + r) / 2;
  double get cy => (t + b) / 2;

  bool contains(double x, double y) => x >= l && x <= r && y >= t && y <= b;
  Box expand(double by) => Box(l - by, t - by, r + by, b + by);
  Box union(Box o) => Box(
    math.min(l, o.l),
    math.min(t, o.t),
    math.max(r, o.r),
    math.max(b, o.b),
  );

  List<double> toJson() => [
    for (final v in [l, t, r, b]) (v * 10).roundToDouble() / 10,
  ];
  static Box fromJson(Object? j) {
    final v = [for (final n in j as List) (n as num).toDouble()];
    return Box(v[0], v[1], v[2], v[3]);
  }
}

enum Clef {
  treble('Treble', 38),
  bass('Bass', 26),
  alto('Alto', 32),
  tenor('Tenor', 30);

  final String label;

  /// The note on the top line, as a diatonic number (C4 = 28).
  final int topLine;
  const Clef(this.label, this.topLine);
}

const _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
const _semis = [0, 2, 4, 5, 7, 9, 11];

/// The MIDI note of diatonic number [diatonic] (C4 = 28) raised by [alter].
int midiOf(int diatonic, int alter) =>
    12 * (diatonic ~/ 7 + 1) + _semis[diatonic % 7] + alter;

/// The step letter of [diatonic].
String stepOf(int diatonic) => _steps[diatonic % 7];

/// How a key signature with [fifths] (+ sharps, − flats) changes [diatonic].
int keyAlter(int fifths, int diatonic) {
  final step = diatonic % 7; // 0 = C
  const sharps = [3, 0, 4, 1, 5, 2, 6]; // F C G D A E B
  const flats = [6, 2, 5, 1, 4, 0, 3]; // B E A D G C F
  if (fifths > 0 && sharps.take(fifths).contains(step)) return 1;
  if (fifths < 0 && flats.take(-fifths).contains(step)) return -1;
  return 0;
}

/// Note values, in quarters.
const noteTypes = {
  'whole': 4.0,
  'half': 2.0,
  'quarter': 1.0,
  'eighth': 0.5,
  '16th': 0.25,
  '32nd': 0.125,
};

/// A note or a rest.
class ScoreNote {
  /// Where it is: page, system on the page, staff in the system (= part),
  /// voice in the staff (1 or 2), measure (whole score).
  int page, system, staff, voice, measure;

  /// When (quarters from the start of the score, as written, before
  /// repeats) and for how long.
  double onset, duration;

  bool rest;

  /// Its line or space as a diatonic number (C4 = 28), and the sharp or
  /// flat it sounds with (key, accidental and earlier accidentals in the
  /// bar counted).
  int diatonic, alter;

  /// An accidental printed before it (null: none; 0 natural, ±1, ±2).
  int? accidental;

  /// whole, half, quarter, eighth, 16th, 32nd; dots; a triplet.
  String type;
  int dots;
  bool triplet;

  /// Tied to the next note of the same pitch (it isn't struck again).
  bool tie;

  /// Notes of one chord share a number (one stem); −1: on its own.
  int chord;

  /// Its stem: 1 up, −1 down, 0 none.
  int stem;

  /// Where on its page.
  Box box;

  ScoreNote({
    required this.page,
    required this.system,
    required this.staff,
    this.voice = 1,
    this.measure = 0,
    this.onset = 0,
    this.duration = 1,
    this.rest = false,
    this.diatonic = 35,
    this.alter = 0,
    this.accidental,
    this.type = 'quarter',
    this.dots = 0,
    this.triplet = false,
    this.tie = false,
    this.chord = -1,
    this.stem = 0,
    required this.box,
  });

  int get midi => midiOf(diatonic, alter);

  /// The written length from type, dots and triplet.
  double get written {
    var d = noteTypes[type] ?? 1;
    var add = d;
    for (var i = 0; i < dots; i++) {
      add /= 2;
      d += add;
    }
    return triplet ? d * 2 / 3 : d;
  }

  Map<String, dynamic> toJson() => {
    'p': page,
    's': system,
    'st': staff,
    'v': voice,
    'm': measure,
    'o': onset,
    'd': duration,
    if (rest) 'r': true,
    'n': diatonic,
    'a': alter,
    if (accidental != null) 'acc': accidental,
    't': type,
    if (dots > 0) 'dots': dots,
    if (triplet) 'tri': true,
    if (tie) 'tie': true,
    if (chord >= 0) 'c': chord,
    if (stem != 0) 'sd': stem,
    'b': box.toJson(),
  };

  static ScoreNote fromJson(Map<String, dynamic> j) => ScoreNote(
    page: j['p'] as int,
    system: j['s'] as int,
    staff: j['st'] as int,
    voice: j['v'] as int? ?? 1,
    measure: j['m'] as int? ?? 0,
    onset: (j['o'] as num).toDouble(),
    duration: (j['d'] as num).toDouble(),
    rest: j['r'] == true,
    diatonic: j['n'] as int? ?? 35,
    alter: j['a'] as int? ?? 0,
    accidental: j['acc'] as int?,
    type: j['t'] as String? ?? 'quarter',
    dots: j['dots'] as int? ?? 0,
    triplet: j['tri'] == true,
    tie: j['tie'] == true,
    chord: j['c'] as int? ?? -1,
    stem: j['sd'] as int? ?? 0,
    box: Box.fromJson(j['b']),
  );
}

/// A measure: when it starts and how long it is, where it is on each staff
/// row (for tapping it), and repeat signs.
class ScoreMeasure {
  double onset, length;
  int page, system;
  Box box;
  bool repeatStart, repeatEnd;

  /// A new time signature from this measure on (null: as before).
  (int, int)? time;

  /// Under a first / second ending: the times through it's played (null:
  /// every time).
  List<int>? ending;

  /// The key signature from this measure on (null: as before).
  int? fifths;

  ScoreMeasure({
    required this.onset,
    required this.length,
    required this.page,
    required this.system,
    required this.box,
    this.repeatStart = false,
    this.repeatEnd = false,
    this.time,
    this.ending,
    this.fifths,
  });

  Map<String, dynamic> toJson() => {
    if (time case (final b, final t)) 't': [b, t],
    if (ending != null) 'e': ending,
    if (fifths != null) 'k': fifths,
    'o': onset,
    'l': length,
    'p': page,
    's': system,
    'b': box.toJson(),
    if (repeatStart) 'rs': true,
    if (repeatEnd) 're': true,
  };

  static ScoreMeasure fromJson(Map<String, dynamic> j) => ScoreMeasure(
    onset: (j['o'] as num).toDouble(),
    length: (j['l'] as num).toDouble(),
    page: j['p'] as int,
    system: j['s'] as int,
    box: Box.fromJson(j['b']),
    repeatStart: j['rs'] == true,
    repeatEnd: j['re'] == true,
    time: j['t'] is List
        ? ((j['t'] as List)[0] as int, (j['t'] as List)[1] as int)
        : null,
    ending: (j['e'] as List?)?.cast<int>(),
    fifths: j['k'] as int?,
  );
}

/// A row of staves on a page (played together), and its staves' lines.
class ScoreSystem {
  int page;
  Box box;

  /// Each staff's top line y and line spacing (at the system's middle).
  List<(double, double)> staves;

  /// The part its top staff plays (lines with fewer staves are the lower
  /// parts).
  int first;
  ScoreSystem(this.page, this.box, this.staves, {this.first = 0});

  Map<String, dynamic> toJson() => {
    'p': page,
    'b': box.toJson(),
    if (first > 0) 'f': first,
    'st': [
      for (final (t, d) in staves) [t, d],
    ],
  };

  static ScoreSystem fromJson(Map<String, dynamic> j) =>
      ScoreSystem(j['p'] as int, Box.fromJson(j['b']), [
        for (final s in j['st'] as List)
          ((s[0] as num).toDouble(), (s[1] as num).toDouble()),
      ], first: j['f'] as int? ?? 0);
}

class Score {
  String title;

  /// Each page's image size.
  List<(int, int)> pages;
  List<ScoreSystem> systems;

  /// One clef per staff (part), top to bottom.
  List<Clef> clefs;

  /// Key signature (+ sharps, − flats), time signature.
  int fifths;
  int beats, beatType;
  List<ScoreMeasure> measures;
  List<ScoreNote> notes;

  /// Tempo printed or chosen (quarter notes a minute).
  int tempo;

  Score({
    this.title = '',
    required this.pages,
    required this.systems,
    required this.clefs,
    this.fifths = 0,
    this.beats = 4,
    this.beatType = 4,
    required this.measures,
    required this.notes,
    this.tempo = 100,
  });

  int get staves => clefs.length;

  /// A name for each part, from its clef and where it sits: two staves at
  /// the bottom under voices are a piano.
  List<String> get partNames {
    final n = clefs.length;
    final piano =
        n >= 3 && clefs[n - 2] == Clef.treble && clefs[n - 1] == Clef.bass;
    return [
      for (var i = 0; i < n; i++)
        if (n == 1)
          'Music'
        else if (piano && i == n - 2)
          'Piano right hand'
        else if (piano && i == n - 1)
          'Piano left hand'
        else if (n == 2 && clefs[0] == Clef.treble && clefs[1] == Clef.bass)
          i == 0 ? 'Upper staff (treble)' : 'Lower staff (bass)'
        else
          piano
              ? 'Voices (${clefs[i].label.toLowerCase()} staff)'
              : 'Staff ${i + 1} (${clefs[i].label.toLowerCase()})',
    ];
  }

  double get measureLength => beats * 4 / beatType;

  /// The time signature in force in measure [index] (changes counted).
  (int, int) timeAt(int index) {
    var t = (beats, beatType);
    for (var i = 0; i <= index && i < measures.length; i++) {
      t = measures[i].time ?? t;
    }
    return t;
  }

  /// The key signature in force in measure [index] (changes counted).
  int fifthsAt(int index) {
    var k = fifths;
    for (var i = 0; i <= index && i < measures.length; i++) {
      k = measures[i].fifths ?? k;
    }
    return k;
  }

  /// How long measure [index] should be by its time signature.
  double lengthOf(int index) {
    final (b, t) = timeAt(index);
    return b * 4 / t;
  }

  double get length =>
      measures.isEmpty ? 0 : measures.last.onset + measures.last.length;

  /// Notes and rests in time order (then top to bottom).
  List<ScoreNote> get ordered => [...notes]
    ..sort((a, b) {
      final c = a.onset.compareTo(b.onset);
      if (c != 0) return c;
      final s = a.staff.compareTo(b.staff);
      return s != 0 ? s : b.diatonic.compareTo(a.diatonic);
    });

  /// The measures in playing order: repeats taken (as many times as the
  /// first and second endings say, else twice), each ending on its pass. A
  /// repeat sign without its start goes back to the beginning or to just
  /// after the last repeat.
  List<int> get playOrder {
    final out = <int>[];
    var start = 0;
    var pass = 1;
    final done = <int>{};
    // How many times the repeat ending at [end] is played.
    int passes(int end) {
      var most = 2;
      for (var k = start; k < measures.length; k++) {
        final e = measures[k].ending;
        if (k > end && e == null) break;
        if (e != null && e.isNotEmpty) {
          most = math.max(most, e.reduce(math.max));
        }
      }
      return most;
    }

    var i = 0;
    var guard = 0;
    var lastEnd = -1;
    while (i < measures.length && guard++ < measures.length * 16) {
      final m = measures[i];
      if (m.repeatStart && pass == 1) start = i;
      final e = m.ending;
      if (e != null && !e.contains(pass)) {
        i++;
        continue;
      }
      if (e == null && pass > 1 && i > lastEnd) {
        // Past the endings: back to the first time through.
        pass = 1;
        start = i;
      }
      out.add(i);
      if (m.repeatEnd && !done.contains(i)) {
        lastEnd = math.max(lastEnd, i);
        if (pass < passes(i)) {
          pass++;
          i = start;
          continue;
        }
        done.add(i);
        start = i + 1;
      }
      i++;
    }
    return out;
  }

  /// The measure tapped at ([x], [y]) on [page], if any.
  int? measureAt(int page, double x, double y) {
    for (final (i, m) in measures.indexed) {
      if (m.page == page && m.box.contains(x, y)) return i;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'title': title,
    'pages': [
      for (final (w, h) in pages) [w, h],
    ],
    'systems': [for (final s in systems) s.toJson()],
    'clefs': [for (final c in clefs) c.name],
    'fifths': fifths,
    'time': [beats, beatType],
    'tempo': tempo,
    'measures': [for (final m in measures) m.toJson()],
    'notes': [for (final n in notes) n.toJson()],
  };

  static Score fromJson(Map<String, dynamic> j) => Score(
    title: j['title'] as String? ?? '',
    pages: [for (final p in j['pages'] as List) (p[0] as int, p[1] as int)],
    systems: [
      for (final s in j['systems'] as List)
        ScoreSystem.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
    clefs: [
      for (final c in j['clefs'] as List)
        Clef.values.firstWhere((v) => v.name == c, orElse: () => Clef.treble),
    ],
    fifths: j['fifths'] as int? ?? 0,
    beats: (j['time'] as List?)?[0] as int? ?? 4,
    beatType: (j['time'] as List?)?[1] as int? ?? 4,
    tempo: j['tempo'] as int? ?? 100,
    measures: [
      for (final m in j['measures'] as List)
        ScoreMeasure.fromJson(Map<String, dynamic>.from(m as Map)),
    ],
    notes: [
      for (final n in j['notes'] as List)
        ScoreNote.fromJson(Map<String, dynamic>.from(n as Map)),
    ],
  );

  /// Works out again, after a correction, each note's sound (key,
  /// accidentals in the bar) and when each note starts (voices in order,
  /// measures one after another).
  void retime() {
    // Pitches: key signature, then accidentals lasting the bar.
    final byMeasure = <int, List<ScoreNote>>{};
    for (final n in notes) {
      byMeasure.putIfAbsent(n.measure, () => []).add(n);
    }
    for (final MapEntry(key: mi, value: group) in byMeasure.entries) {
      final key = fifthsAt(mi);
      group.sort((a, b) => a.box.l.compareTo(b.box.l));
      final held = <(int, int), int>{}; // (staff, line) → alter
      for (final n in group) {
        if (n.rest) continue;
        final k = (n.staff, n.diatonic);
        if (n.accidental != null) {
          held[k] = n.accidental!;
          n.alter = n.accidental!;
        } else {
          n.alter = held[k] ?? keyAlter(key, n.diatonic);
        }
      }
    }
    // Times: in each staff and voice, one after another by position.
    var onset = 0.0;
    var time = (beats, beatType);
    for (final (mi, m) in measures.indexed) {
      time = m.time ?? time;
      final measureLength = time.$1 * 4 / time.$2;
      final inM = byMeasure[mi] ?? const <ScoreNote>[];
      var longest = 0.0;
      final voices = <(int, int), List<ScoreNote>>{};
      for (final n in inM) {
        voices.putIfAbsent((n.staff, n.voice), () => []).add(n);
      }
      final totals = <(int, int), double>{};
      for (final MapEntry(key: k, value: v) in voices.entries) {
        v.sort((a, b) => a.box.cx.compareTo(b.box.cx));
        var t = 0.0;
        ScoreNote? prev;
        for (final n in v) {
          final d = n.rest && n.type == 'whole' && v.length == 1
              ? measureLength
              : n.written;
          // A chord: notes stacked at the same place start together.
          if (prev != null &&
              !n.rest &&
              !prev.rest &&
              ((n.chord >= 0 && n.chord == prev.chord) ||
                  (n.box.cx - prev.box.cx).abs() < n.box.w * 0.6 ||
                  // whole notes a second apart sit side by side
                  (n.type == 'whole' &&
                      prev.type == 'whole' &&
                      (n.box.cx - prev.box.cx).abs() < n.box.w * 1.3))) {
            n.onset = prev.onset;
            n.duration = d;
            continue;
          }
          n.onset = onset + t;
          n.duration = d;
          t += d;
          prev = n;
        }
        totals[k] = t;
        longest = math.max(longest, t);
      }
      // A voice that doesn't add up (a length misread, a note missed): its
      // notes take their times from the parts that do, by where they stand
      // (things above each other sound together), so one mistake doesn't
      // shift the rest of the bar.
      final fits = [
        for (final e in totals.entries)
          if ((e.value - measureLength).abs() < 0.01) e.key,
      ];
      if (fits.isNotEmpty && fits.length < voices.length) {
        final anchors = <(double, double)>[
          (m.box.l, 0),
          for (final k in fits)
            for (final n in voices[k]!) (n.box.cx, n.onset - onset),
          (m.box.r, measureLength),
        ]..sort((a, b) => a.$1.compareTo(b.$1));
        double timeAt(double x, double near) {
          for (final (ax, at) in anchors) {
            if ((ax - x).abs() < near) return at;
          }
          for (var i = 0; i + 1 < anchors.length; i++) {
            final (x0, t0) = anchors[i];
            final (x1, t1) = anchors[i + 1];
            if (x >= x0 && x <= x1 && x1 > x0) {
              final t = t0 + (t1 - t0) * (x - x0) / (x1 - x0);
              return (t * 8).round() / 8; // nearest 32nd
            }
          }
          return 0;
        }

        for (final MapEntry(key: k, value: v) in voices.entries) {
          if (fits.contains(k)) continue;
          for (final n in v) {
            n.onset = onset + timeAt(n.box.cx, n.box.w * 0.7);
          }
          // Lengths: as written, but not past the next note or the bar's end.
          final starts = {for (final n in v) n.onset}.toList()..sort();
          for (final n in v) {
            final next = starts.where((t) => t > n.onset + 1e-6);
            final end = next.isEmpty ? onset + measureLength : next.first;
            n.duration = math.max(0.125, math.min(n.duration, end - n.onset));
          }
        }
        longest = measureLength;
      }
      m.onset = onset;
      // A full bar is the time signature's length. A short first bar is a
      // pickup when every part agrees on its length (else a note is more
      // likely missing).
      final agreed =
          totals.values.isNotEmpty &&
          totals.values.every((t) => (t - longest).abs() < 0.01);
      m.length = longest == 0 || (longest - measureLength).abs() < 0.3
          ? measureLength
          : (mi == 0 &&
                    longest < measureLength &&
                    (longest <= measureLength / 2 ||
                        (agreed && totals.length > 1))
                ? longest
                : measureLength);
      onset += m.length;
    }
  }
}
