// Reads printed sheet music from page images (a scan, a photo, a PDF page)
// into a [Score]. Offline, in plain Dart, the classic way:
//
//  1. ink and paper (a threshold that follows uneven light), straightened;
//  2. staves: rows of five evenly spaced lines; their spacing sets the size
//     of everything else;
//  3. the staff lines (and ledger lines) are taken out, leaving symbols;
//  4. noteheads (filled or hollow) on each line and space; their stems,
//     beams or flags, dots; accidentals before them;
//  5. clef, key signature, time signature at the start of each staff;
//     bar lines (and repeat dots), rests, ties;
//  6. into voices, measures and times, pitches from clef, key and
//     accidentals.
//
// Works best on clean printed music (about 300 dpi, even light). Shapes are
// compared with the Bravura font's symbols (glyphs.dart).

import 'dart:math' as math;
import 'dart:typed_data';

import 'score.dart';
import 'shapes.dart';

/// A page to read: grey levels (0 black … 255 white), row by row.
class PageImage {
  final int width, height;
  final Uint8List gray;
  const PageImage(this.width, this.height, this.gray);
}

/// Debugging notes (null: none kept).
List<String>? readerLog;

/// A point (page pixels, straightened) to print the ink around (debugging).
(int, int)? readerProbe;

/// What the reader found on a page, for checking it (tests, debugging).
class PageReport {
  double angle = 0;
  double space = 0, line = 0;
  int staves = 0, systems = 0;
}

/// The score in [pages] (in order). [onPage] is told as each page is done.
Score readScore(
  List<PageImage> pages, {
  String title = '',
  void Function(int done)? onPage,
  List<PageReport>? reports,
}) {
  final r = ScoreReader(title: title, reports: reports);
  for (final page in pages) {
    r.addPage(page);
    onPage?.call(r.pagesRead);
  }
  return r.finish();
}

/// [readScore] a page at a time, letting the app draw in between (the web
/// build has no background threads).
Future<Score> readScoreAsync(
  List<PageImage> pages, {
  String title = '',
  void Function(int done)? onPage,
}) async {
  final r = ScoreReader(title: title);
  for (final page in pages) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    r.addPage(page);
    onPage?.call(r.pagesRead);
  }
  await Future<void>.delayed(const Duration(milliseconds: 16));
  return r.finish();
}

/// Reads pages one by one into a score.
class ScoreReader {
  final String title;
  final List<PageReport>? reports;
  ScoreReader({this.title = '', this.reports});

  final systems = <ScoreSystem>[];
  final notes = <ScoreNote>[];
  final measures = <ScoreMeasure>[];
  var clefs = <Clef>[];
  int? fifths;
  (int, int)? time;
  final sizes = <(int, int)>[];
  final endingState = <Object?>[1, null];
  final lineClefs = <List<Clef>>[];
  int pagesRead = 0;

  void addPage(PageImage page) {
    final pi = pagesRead++;
    final report = PageReport();
    final r = _PageReader(page, pi, report, endingState);
    r.read();
    sizes.add((page.width, page.height));
    for (final sys in r.systems) {
      final si = systems.length;
      systems.add(
        ScoreSystem(pi, sys.box, [
          for (final st in sys.staves) (st.yAt(0, st.midX), st.space),
        ]),
      );
      lineClefs.add([for (final st in sys.staves) st.clef]);
      fifths ??= sys.staves.first.fifths;
      time ??= sys.time;
      for (final m in sys.measures) {
        final mi = measures.length;
        measures.add(
          ScoreMeasure(
            onset: 0,
            length: 0,
            page: pi,
            system: si,
            box: m.box,
            repeatStart: m.repeatStart,
            repeatEnd: m.repeatEnd,
            // The opening time signature is the score's, not a change.
            time: measures.isEmpty ? null : m.time,
            ending: m.ending,
            fifths: measures.isEmpty ? null : m.fifths,
          ),
        );
        for (final n in m.notes) {
          n
            ..system = si
            ..measure = mi;
          notes.add(n);
        }
      }
    }
    reports?.add(report);
  }

  Score finish() {
    // Parts line up from the bottom: a line with fewer staves (the piano
    // alone before the voices come in) is the lower parts.
    final most = systems.fold(0, (m, s) => math.max(m, s.staves.length));
    for (final (i, sys) in systems.indexed) {
      sys.first = most - sys.staves.length;
      if (sys.first == 0) continue;
      for (final n in notes) {
        if (n.system == i) n.staff += sys.first;
      }
    }
    // Each part keeps its clef from line to line: one misread (a dynamic
    // beside it, a smudge) takes the clef most of its lines have.
    final votes = [for (var i = 0; i < most; i++) <Clef, int>{}];
    for (final (i, sys) in systems.indexed) {
      for (final (k, c) in lineClefs[i].indexed) {
        final part = sys.first + k;
        votes[part][c] = (votes[part][c] ?? 0) + 1;
      }
    }
    final partClefs = [
      for (final v in votes)
        v.isEmpty
            ? Clef.treble
            : v.entries.reduce((a, b) => b.value > a.value ? b : a).key,
    ];
    for (final n in notes) {
      final sys = systems[n.system];
      final read = lineClefs[n.system][n.staff - sys.first];
      final want = partClefs[n.staff];
      if (read != want) n.diatonic += want.topLine - read.topLine;
    }
    clefs = partClefs;
    final score = Score(
      title: title,
      pages: sizes,
      systems: systems,
      clefs: clefs.isEmpty ? [Clef.treble] : clefs,
      fifths: fifths ?? 0,
      measures: measures,
      notes: notes,
    );
    _dropDuplicateWholes(score);
    // Each staff's notes take its key (accidentals by bar), then times.
    score.retime();
    if (time case final t?) {
      score
        ..beats = t.$1
        ..beatType = t.$2;
    } else {
      _guessTime(score);
    }
    _splitOverfull(score);
    _fixTuplets(score);
    score.retime();
    return score;
  }
}

/// No time signature read: the most common bar length decides it.
void _guessTime(Score score) {
  final counts = <double, int>{};
  final byMeasure = <int, double>{};
  for (final n in score.notes) {
    final end = n.onset + n.duration - score.measures[n.measure].onset;
    byMeasure[n.measure] = math.max(byMeasure[n.measure] ?? 0, end);
  }
  for (final v in byMeasure.values) {
    final q = (v * 4).round() / 4;
    counts[q] = (counts[q] ?? 0) + 1;
  }
  if (counts.isEmpty) return;
  final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final (b, t) = switch (best) {
    1.5 => (3, 8),
    2 => (2, 4),
    3 => (3, 4),
    4.5 => (9, 8),
    6 => (6, 4),
    _ => ((best).round().clamp(1, 12), 4),
  };
  score
    ..beats = b
    ..beatType = t;
}

/// Two whole notes of one pitch on a staff in one bar: one is a misread
/// (a dynamic or a smudge beside a chord); keep the one with the chord.
void _dropDuplicateWholes(Score score) {
  final groups = <(int, int), List<ScoreNote>>{};
  for (final n in score.notes) {
    if (!n.rest && n.type == 'whole') {
      groups.putIfAbsent((n.measure, n.staff), () => []).add(n);
    }
  }
  final drop = <ScoreNote>{};
  for (final g in groups.values) {
    if (g.length < 2) continue;
    final xs = [for (final n in g) n.box.cx]..sort();
    final mid = xs[xs.length ~/ 2];
    final byPitch = <int, List<ScoreNote>>{};
    for (final n in g) {
      byPitch.putIfAbsent(n.diatonic, () => []).add(n);
    }
    for (final same in byPitch.values) {
      if (same.length < 2) continue;
      same.sort(
        (a, b) => (a.box.cx - mid).abs().compareTo((b.box.cx - mid).abs()),
      );
      drop.addAll(same.skip(1));
    }
  }
  score.notes.removeWhere(drop.contains);
}

/// A staff with stems both ways whose notes, one after another, overfill
/// the bar: two voices (stems up and stems down) that don't line up note
/// for note. Rests go with the voice on their side of the staff.
void _splitOverfull(Score score) {
  final groups = <(int, int), List<ScoreNote>>{};
  for (final n in score.notes) {
    groups.putIfAbsent((n.measure, n.staff), () => []).add(n);
  }
  var changed = false;
  for (final e in groups.entries) {
    final notes = e.value;
    if (notes.any((n) => n.voice == 2)) continue;
    final ups = notes.where((n) => n.stem > 0).length;
    final downs = notes.where((n) => n.stem < 0).length;
    if (ups == 0 || downs == 0) continue;
    final m = score.measures[e.key.$1];
    final end =
        notes.map((n) => n.onset + n.duration).reduce(math.max) - m.onset;
    if (end <= score.lengthOf(e.key.$1) + 0.01) continue;
    final sys = score.systems[m.system];
    final (top, space) =
        sys.staves[(e.key.$2 - sys.first).clamp(0, sys.staves.length - 1)];
    final middle = top + space * 2;
    for (final n in notes) {
      if (n.stem < 0) {
        n.voice = 2;
      } else if (n.stem == 0 && !n.rest && n.box.cy > middle) {
        n.voice = 2;
      }
    }
    // Each rest goes in the voice it fits (the other is busy there), else
    // by its side of the staff.
    double length(int voice, {ScoreNote? without}) {
      final v = [
        for (final n in notes)
          if (n.voice == voice && n != without) n,
      ]..sort((a, b) => a.box.cx.compareTo(b.box.cx));
      var t = 0.0;
      ScoreNote? prev;
      for (final n in v) {
        if (prev != null &&
            !n.rest &&
            !prev.rest &&
            n.chord >= 0 &&
            n.chord == prev.chord) {
          continue;
        }
        t += n.written;
        prev = n;
      }
      return t;
    }

    final want = score.lengthOf(e.key.$1);
    for (final n in notes.where((n) => n.rest)) {
      n.voice = n.box.cy > middle ? 2 : 1;
      final here = length(n.voice), other = 3 - n.voice;
      if (here > want + 0.01) {
        n.voice = other;
        if (length(other) > want + 0.01) n.voice = 3 - other;
      }
    }
    changed = true;
  }
  if (changed) score.retime();
}

/// A voice too long for its bar with runs of three equal short notes:
/// those are triplets.
void _fixTuplets(Score score) {
  final voices = <(int, int, int), List<ScoreNote>>{};
  for (final n in score.notes) {
    voices.putIfAbsent((n.measure, n.staff, n.voice), () => []).add(n);
  }
  for (final v in voices.values) {
    final want = score.lengthOf(v.first.measure);
    final lead = <ScoreNote>[];
    for (final n in v..sort((a, b) => a.box.cx.compareTo(b.box.cx))) {
      if (lead.isEmpty || n.chord < 0 || n.chord != lead.last.chord) {
        lead.add(n);
      }
    }
    double total() => lead.fold(0.0, (t, n) => t + n.written);
    var i = 0;
    while (total() > want + 0.01 && i + 2 < lead.length) {
      final a = lead[i], b = lead[i + 1], c = lead[i + 2];
      if (!a.triplet &&
          a.type == b.type &&
          b.type == c.type &&
          a.dots == 0 &&
          (a.written <= 1)) {
        for (final n in v) {
          if (n == a ||
              n == b ||
              n == c ||
              (n.chord >= 0 && [a, b, c].any((x) => x.chord == n.chord))) {
            n.triplet = true;
          }
        }
        i += 3;
      } else {
        i++;
      }
    }
    if ((total() - want).abs() > 0.01 && lead.any((n) => n.triplet)) {
      // Didn't come out right: leave it as it was.
      for (final n in v) {
        n.triplet = false;
      }
    }
  }
}

// ---------------------------------------------------------------------------

class _Comp {
  int x0, y0, x1, y1, area;
  _Comp(this.x0, this.y0, this.x1, this.y1, this.area);
  int get w => x1 - x0 + 1;
  int get h => y1 - y0 + 1;
  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;
  double get fill => area / (w * h);

  /// What it was taken as (so nothing is read twice).
  String? used;
}

class _Staff {
  /// The five lines: y at the left of each strip, strip width.
  final List<double> lines; // at the staff's middle
  final double space;
  int left, right;

  /// Line offsets along the staff (curved photos), per strip.
  List<double> offsets = const [0];
  int strip = 1 << 30;

  Clef clef = Clef.treble;
  int fifths = 0;

  /// Where the music starts (after clef, key, time).
  double contentX = 0;

  /// Where rests may start (the line's music start).
  double restsFrom = 0;

  /// Stretches with no notes (a time signature mid-line).
  final noHeads = <(double, double)>[];

  _Staff(this.lines, this.space, this.left, this.right);

  double get midX => (left + right) / 2;
  double get top => lines.first;
  double get bottom => lines.last;

  double _off(double x) {
    if (offsets.length == 1) return offsets.first;
    final f = ((x - left) / strip - 0.5).clamp(0, offsets.length - 1.0);
    final i = f.floor().clamp(0, offsets.length - 2);
    final t = f - i;
    return offsets[i] * (1 - t) + offsets[i + 1] * t;
  }

  /// y of line [i] (0 top … 4 bottom) at x.
  double yAt(int i, double x) => lines[i] + _off(x);

  /// y of position [p] (half spaces down from the top line) at x.
  double posY(double p, double x) => lines[0] + _off(x) + p * space / 2;

  /// The position (half spaces from the top line) of y at x.
  double posOf(double y, double x) => (y - lines[0] - _off(x)) / (space / 2);
}

class _Head {
  double x, y; // centre
  int pos; // half spaces below the top line
  bool hollow;
  double score;
  double width;
  _Staff staff;

  // Stem: x, far end y, up?
  double? stemX, stemEnd;
  bool up = true;
  int beams = 0;
  int dots = 0;
  int? accidental;
  int chord = -1;
  bool tieNext = false;

  /// A hollow head's side thickness (spaces): whole notes' are thick.
  double sides = 0;
  _Head(
    this.x,
    this.y,
    this.pos,
    this.hollow,
    this.score,
    this.width,
    this.staff,
  );
}

class _Measure {
  Box box;
  bool repeatStart = false, repeatEnd = false;
  (int, int)? time;
  List<int>? ending;

  /// The key from this measure on (set at each line's start and where it
  /// changes).
  int? fifths;
  final notes = <ScoreNote>[];
  _Measure(this.box);
}

class _System {
  final List<_Staff> staves;
  Box box;
  (int, int)? time;

  /// The time signature printed at this line's start, if any.
  (int, int)? startTime;
  final measures = <_Measure>[];
  _System(this.staves, this.box);
}

class _PageReader {
  final PageImage page;
  final int index;
  final PageReport report;
  _PageReader(this.page, this.index, this.report, this.endings);

  /// The next ending's number and the last one's (kept from page to page).
  final List<Object?> endings;

  late int w, h;

  /// Ink (1) after straightening; ink without staff lines.
  late Uint8List ink, sym;
  late Int32List labels;
  final comps = <_Comp>[];
  double sp = 20, lt = 2;
  final staves = <_Staff>[];
  final systems = <_System>[];
  double angle = 0;

  bool inkAt(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && ink[y * w + x] == 1;
  bool symAt(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && sym[y * w + x] == 1;

  void read() {
    w = page.width;
    h = page.height;
    final sw = Stopwatch()..start();
    void lap(String what) {
      readerLog?.add('time.$what ${sw.elapsedMilliseconds}');
      sw.reset();
    }

    _binarize();
    lap('binarize');
    _straighten();
    lap('straighten');
    report.angle = angle;
    if (!_measureSpacing()) return;
    _findStaves();
    report.staves = staves.length;
    if (staves.isEmpty) return;
    lap('staves');
    _followCurves();
    _removeLines();
    lap('lines');
    if (readerProbe case (final px, final py)) {
      for (var y = py - 20; y < py + 20; y++) {
        readerLog?.add(
          '$y ${[for (var x = px - 25; x < px + 25; x++) symAt(x, y) ? '#' : (inkAt(x, y) ? '+' : '.')].join()}',
        );
      }
    }
    _components();
    lap('components');
    _groupSystems();
    report.systems = systems.length;
    for (final sys in systems) {
      _readSystem(sys);
    }
    lap('systems');
    readerLog?.add(
      'time.profile ${profile.map((k, v) => MapEntry(k, v ~/ 1000))}',
    );
    // Back to the page as it was (before straightening).
    if (angle != 0) _unrotateBoxes();
  }

  // ---- 1. Ink ----

  void _binarize() {
    final g = page.gray;
    // Average grey around each pixel (integral image), ink well below it.
    final integ = Float64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0.0;
      for (var x = 0; x < w; x++) {
        row += g[y * w + x];
        integ[(y + 1) * (w + 1) + x + 1] = integ[y * (w + 1) + x + 1] + row;
      }
    }
    final r = math.max(16, math.max(w, h) ~/ 60);
    // Ink inside big black shapes is as dark as its surroundings: anything
    // much darker than the page overall counts too.
    final dark = _otsu(g) * 0.75;
    ink = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
        final sum =
            integ[y1 * (w + 1) + x1] -
            integ[y0 * (w + 1) + x1] -
            integ[y1 * (w + 1) + x0] +
            integ[y0 * (w + 1) + x0];
        final mean = sum / ((x1 - x0) * (y1 - y0));
        final v = g[y * w + x];
        if ((v < mean * 0.8 && mean - v > 25) || (v < dark && v <= mean)) {
          ink[y * w + x] = 1;
        }
      }
    }
  }

  /// The grey level that best splits ink from paper (Otsu).
  static double _otsu(Uint8List g) {
    final hist = Float64List(256);
    for (final v in g) {
      hist[v]++;
    }
    final total = g.length.toDouble();
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0.0, best = 0.0, at = 128.0;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB, mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        at = t.toDouble();
      }
    }
    return at;
  }

  // ---- Straightening: the angle that makes rows of ink sharpest ----

  void _straighten() {
    final pts = <int>[];
    final step = math.max(1, (w * h) ~/ 1500000);
    for (var i = 0; i < ink.length; i += step) {
      if (ink[i] == 1) pts.add(i);
    }
    if (pts.length < 1000) return;
    double sharpness(double deg) {
      final t = math.tan(deg * math.pi / 180);
      final rows = Float64List(h * 2 + 10);
      for (final i in pts) {
        final x = i % w, y = i ~/ w;
        final yy = (y - (x - w / 2) * t + h / 2).round();
        if (yy >= 0 && yy < rows.length) rows[yy] += 1;
      }
      var s = 0.0;
      for (final v in rows) {
        s += v * v;
      }
      return s;
    }

    var best = 0.0, bestS = sharpness(0);
    for (var a = -3.0; a <= 3.0; a += 0.25) {
      final s = sharpness(a);
      if (s > bestS) {
        bestS = s;
        best = a;
      }
    }
    final coarse = best;
    for (var a = coarse - 0.25; a <= coarse + 0.25; a += 0.05) {
      final s = sharpness(a);
      if (s > bestS) {
        bestS = s;
        best = a;
      }
    }
    if (best.abs() < 0.05) return;
    angle = best;
    // Rotate the ink (nearest pixel) so the staves are level.
    final t = best * math.pi / 180;
    final c = math.cos(t), s = math.sin(t);
    final out = Uint8List(w * h);
    final cx = w / 2, cy = h / 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Where this straightened pixel came from.
        final dx = x - cx, dy = y - cy;
        final sx = (cx + dx * c - dy * s).round();
        final sy = (cy + dx * s + dy * c).round();
        if (sx >= 0 && sy >= 0 && sx < w && sy < h) {
          out[y * w + x] = ink[sy * w + sx];
        }
      }
    }
    ink = out;
  }

  Box _unrotate(Box b) {
    final t = angle * math.pi / 180;
    final c = math.cos(t), s = math.sin(t);
    final cx = w / 2, cy = h / 2;
    (double, double) map(double x, double y) {
      final dx = x - cx, dy = y - cy;
      return (cx + dx * c - dy * s, cy + dx * s + dy * c);
    }

    final pts = [map(b.l, b.t), map(b.r, b.t), map(b.l, b.b), map(b.r, b.b)];
    return Box(
      pts.map((p) => p.$1).reduce(math.min),
      pts.map((p) => p.$2).reduce(math.min),
      pts.map((p) => p.$1).reduce(math.max),
      pts.map((p) => p.$2).reduce(math.max),
    );
  }

  void _unrotateBoxes() {
    for (final sys in systems) {
      sys.box = _unrotate(sys.box);
      for (final m in sys.measures) {
        m.box = _unrotate(m.box);
        for (final n in m.notes) {
          n.box = _unrotate(n.box);
        }
      }
    }
  }

  // ---- 2. Staves ----

  /// Staff line thickness and spacing, from the commonest ink-then-paper
  /// runs down the columns.
  bool _measureSpacing() {
    final black = Int32List(64), pair = Int32List(160);
    for (var x = 0; x < w; x += 3) {
      var y = 0;
      while (y < h) {
        while (y < h && ink[y * w + x] == 0) {
          y++;
        }
        final b0 = y;
        while (y < h && ink[y * w + x] == 1) {
          y++;
        }
        final b = y - b0;
        final w0 = y;
        while (y < h && ink[y * w + x] == 0) {
          y++;
        }
        final wr = y - w0;
        if (b > 0 && b < 64 && y < h) {
          black[b]++;
          if (b + wr < 160) pair[b + wr]++;
        }
      }
    }
    int mode(Int32List l, int from) {
      var best = from;
      for (var i = from; i < l.length; i++) {
        if (l[i] > l[best]) best = i;
      }
      return best;
    }

    lt = mode(black, 1).toDouble();
    final p = mode(pair, 4);
    if (pair[p] < 20) return false;
    // Refine with the neighbours.
    final a = pair[p - 1], b = pair[p], c = p + 1 < 160 ? pair[p + 1] : 0;
    sp = p + (c - a) / (2.0 * (2 * b - a - c).clamp(1, 1 << 30));
    report
      ..space = sp
      ..line = lt;
    return sp >= 5;
  }

  int get _maxLine => (lt * 1.8).ceil() + 1;

  /// A vertical ink run through (x, y): its top and bottom.
  (int, int) _vrun(Uint8List img, int x, int y) {
    var a = y, b = y;
    while (a > 0 && img[(a - 1) * w + x] == 1) {
      a--;
    }
    while (b < h - 1 && img[(b + 1) * w + x] == 1) {
      b++;
    }
    return (a, b);
  }

  void _findStaves() {
    // Thin ink in each row (not part of a tall shape): staff lines show as
    // rows with a lot of it.
    final thin = Float64List(h);
    for (var x = 0; x < w; x++) {
      var y = 0;
      while (y < h) {
        if (ink[y * w + x] == 0) {
          y++;
          continue;
        }
        final y0 = y;
        while (y < h && ink[y * w + x] == 1) {
          y++;
        }
        if (y - y0 <= _maxLine) {
          for (var k = y0; k < y; k++) {
            thin[k] += 1;
          }
        }
      }
    }
    final maxThin = thin.reduce(math.max);
    if (maxThin < sp * 8) return;
    // Rows of line: well above the rest, grouped into lines.
    final lineYs = <double>[];
    var y = 0;
    final cut = math.max(maxThin * 0.25, sp * 6);
    while (y < h) {
      if (thin[y] < cut) {
        y++;
        continue;
      }
      var sum = 0.0, wsum = 0.0;
      while (y < h && thin[y] >= cut) {
        sum += y * thin[y];
        wsum += thin[y];
        y++;
      }
      lineYs.add(sum / wsum);
    }
    // Five evenly spaced lines make a staff.
    var i = 0;
    while (i + 4 < lineYs.length) {
      final five = lineYs.sublist(i, i + 5);
      final gaps = [for (var k = 0; k < 4; k++) five[k + 1] - five[k]];
      final ok = gaps.every((g) => (g - sp).abs() < sp * 0.3);
      if (!ok) {
        i++;
        continue;
      }
      final space = (five.last - five.first) / 4;
      final (l, r) = _staffExtent(five);
      if (r - l > sp * 8) staves.add(_Staff(five, space, l, r));
      i += 5;
    }
  }

  /// Left and right ends of the staff whose lines are [ys]: the longest
  /// stretch where most of its lines have ink.
  (int, int) _staffExtent(List<double> ys) {
    bool on(int x) {
      var n = 0;
      for (final y in ys) {
        final yi = y.round();
        for (var d = -_maxLine; d <= _maxLine; d++) {
          if (inkAt(x, yi + d)) {
            n++;
            break;
          }
        }
      }
      return n >= 4;
    }

    var best = (0, 0);
    var start = -1, gap = 0;
    for (var x = 0; x <= w; x++) {
      if (x < w && on(x)) {
        if (start < 0) start = x;
        gap = 0;
      } else if (start >= 0) {
        gap++;
        if (gap > sp || x == w) {
          final end = x - gap;
          if (end - start > best.$2 - best.$1) best = (start, end);
          start = -1;
          gap = 0;
        }
      }
    }
    return best;
  }

  /// Photos: staves bend a little. Fit the five lines strip by strip.
  void _followCurves() {
    for (final st in staves) {
      final len = st.right - st.left;
      final strips = math.max(1, (len / (sp * 12)).round());
      final sw = (len / strips).ceil();
      st.strip = sw;
      final offs = <double>[];
      for (var s = 0; s < strips; s++) {
        final x0 = st.left + s * sw, x1 = math.min(st.right, x0 + sw);
        var best = 0.0, bestN = -1;
        for (var o = -(sp / 2).round(); o <= (sp / 2).round(); o++) {
          var n = 0;
          for (var x = x0; x < x1; x += 2) {
            for (final ly in st.lines) {
              if (inkAt(x, (ly + o).round())) n++;
            }
          }
          if (n > bestN || (n == bestN && o.abs() < best.abs())) {
            bestN = n;
            best = o.toDouble();
          }
        }
        offs.add(best);
      }
      st.offsets = offs;
    }
  }

  // ---- 3. Staff and ledger lines out ----

  void _removeLines() {
    sym = Uint8List.fromList(ink);
    final maxRun = _maxLine;
    void clearAt(int x, double yc) {
      final yi = yc.round();
      for (var d = 0; d <= maxRun; d++) {
        for (final y in [yi - d, yi + d]) {
          if (y < 0 || y >= h || ink[y * w + x] == 0) continue;
          final (a, b) = _vrun(ink, x, y);
          if (b - a + 1 <= maxRun) {
            for (var k = a; k <= b; k++) {
              sym[k * w + x] = 0;
            }
          }
          return;
        }
      }
    }

    for (final st in staves) {
      for (
        var x = math.max(0, st.left - 2);
        x <= math.min(w - 1, st.right + 2);
        x++
      ) {
        for (var i = 0; i < 5; i++) {
          clearAt(x, st.yAt(i, x.toDouble()));
        }
      }
      // Ledger lines: short lines above and below, a space apart.
      for (final dir in [-1, 1]) {
        for (var k = 1; k <= 6; k++) {
          for (var x = st.left; x < st.right; x++) {
            final yc = dir < 0
                ? st.yAt(0, x.toDouble()) - k * st.space
                : st.yAt(4, x.toDouble()) + k * st.space;
            final yi = yc.round();
            // A ledger: a horizontal run at least 1.2 spaces long.
            var hit = -1;
            for (var d = -maxRun; d <= maxRun && hit < 0; d++) {
              if (inkAt(x, yi + d)) hit = yi + d;
            }
            if (hit < 0) continue;
            var r = x;
            while (r < w - 1 && inkAt(r + 1, hit)) {
              r++;
            }
            if (r - x >= sp * 1.2) {
              for (var xx = x; xx <= r; xx++) {
                clearAt(xx, hit.toDouble());
              }
            }
            x = r;
          }
        }
      }
    }
  }

  // ---- Connected pieces of ink (no lines) ----

  void _components() {
    labels = Int32List(w * h);
    // Union–find over provisional labels, in a growable typed array.
    var parent = Int32List(1 << 16);
    var count = 1;
    int find(int a) {
      while (parent[a] != a) {
        parent[a] = parent[parent[a]];
        a = parent[a];
      }
      return a;
    }

    void join(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final i = row + x;
        if (sym[i] == 0) continue;
        var l = 0;
        if (x > 0) {
          final lj = labels[i - 1];
          if (lj != 0) l = lj;
        }
        if (y > 0) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            final lj = labels[i - w + dx];
            if (lj == 0) continue;
            if (l == 0) {
              l = lj;
            } else if (lj != l) {
              join(lj, l);
            }
          }
        }
        if (l == 0) {
          if (count == parent.length) {
            parent = Int32List(parent.length * 2)..setRange(0, count, parent);
          }
          l = count;
          parent[count] = count;
          count++;
        }
        labels[i] = l;
      }
    }
    // Final pieces: one per root, with their boxes.
    final index = Int32List(count)..fillRange(0, count, -1);
    final x0 = <int>[],
        y0 = <int>[],
        x1 = <int>[],
        y1 = <int>[],
        area = <int>[];
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final l = labels[row + x];
        if (l == 0) continue;
        final root = find(l);
        var c = index[root];
        if (c < 0) {
          c = x0.length;
          index[root] = c;
          x0.add(x);
          y0.add(y);
          x1.add(x);
          y1.add(y);
          area.add(0);
        }
        if (x < x0[c]) x0[c] = x;
        if (x > x1[c]) x1[c] = x;
        if (y > y1[c]) y1[c] = y;
        area[c]++;
        labels[row + x] = c + 1;
      }
    }
    for (var c = 0; c < x0.length; c++) {
      comps.add(_Comp(x0[c], y0[c], x1[c], y1[c], area[c]));
    }
  }

  _Comp? _compAt(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return null;
    final l = labels[y * w + x];
    return l == 0 ? null : comps[l - 1];
  }

  // ---- Systems: staves joined by a line at their left ----

  void _groupSystems() {
    var cur = <_Staff>[staves.first];
    bool joined(_Staff a, _Staff b) {
      // Ink going down from a's bottom to b's top near their left ends.
      final x0 = math.max(a.left, b.left) - (sp * 1.5).round();
      for (var x = x0; x < x0 + sp * 3; x++) {
        var ok = true;
        for (var y = a.bottom.round(); y <= b.top.round(); y += 2) {
          if (!inkAt(x, y) && !inkAt(x + 1, y) && !inkAt(x - 1, y)) {
            ok = false;
            break;
          }
        }
        if (ok) return true;
      }
      return false;
    }

    for (var i = 1; i < staves.length; i++) {
      if (joined(staves[i - 1], staves[i])) {
        cur.add(staves[i]);
      } else {
        systems.add(_systemOf(cur));
        cur = [staves[i]];
      }
    }
    systems.add(_systemOf(cur));
  }

  _System _systemOf(List<_Staff> st) => _System(
    st,
    Box(
      st.map((s) => s.left).reduce(math.min).toDouble(),
      st.first.top - sp * 3,
      st.map((s) => s.right).reduce(math.max).toDouble(),
      st.last.bottom + sp * 3,
    ),
  );

  // ---- 4–6. One system ----

  static final profile = <String, int>{};
  void _readSystem(_System sys) {
    final psw = Stopwatch()..start();
    void plap(String k) {
      profile[k] = (profile[k] ?? 0) + psw.elapsedMicroseconds;
      psw.reset();
    }

    final bars = <double>{};
    final heads = <_Head>[];
    for (final st in sys.staves) {
      bars.addAll(_barlines(st));
    }
    for (final st in sys.staves) {
      _readStart(st, sys);
    }
    // The staves of a line start their music together: rests aren't
    // looked for before that (bits of a clef that wasn't read).
    final start = sys.staves.map((st) => st.contentX).reduce(math.max);
    for (final st in sys.staves) {
      st.restsFrom = start;
    }
    // Time changes after bar lines (and the warning one at a line's end):
    // read, and kept out of the notes.
    final changes = <double, (int, int)>{};
    final keyChanges = <double, int>{};
    for (final st in sys.staves) {
      for (final x in bars) {
        if (x < st.contentX) continue;
        var at = x + st.space * 0.2;
        // A new key: naturals and / or sharps or flats right after the bar
        // line, not just one note's accidental.
        // (Only after a double bar line, as key changes are written.)
        final double = bars.any(
          (b) => b < x - st.space * 0.25 && b > x - st.space * 1.2,
        );
        final key = double ? _keySigAt(st, at, naturals: true) : null;
        if (key != null && !_isNoteAccidental(st, key)) {
          keyChanges[x] = key.fifths;
          at = key.right;
          for (final o in sys.staves) {
            // A key or time change is printed on every staff of the line.
            o.noHeads.add((x, key.right + st.space * 0.2));
          }
        } else if (key != null) {
          for (final k in key.parts) {
            k.used = null;
          }
        }
        final found = _timeSigAt(st, at, strict: true, span: 2.5);
        if (found == null) continue;
        for (final o in sys.staves) {
          o.noHeads.add((x, found.right + st.space * 0.3));
        }
        if (found.time != null) changes[x] = found.time!;
      }
    }
    plap('start+bars+changes');
    for (final st in sys.staves) {
      final found = _heads(st);
      for (final hd in found) {
        // The head's ink (a hollow one's centre is paper: its ring).
        final dx = hd.width * 0.4, dy = hd.staff.space * 0.35;
        for (final (px, py) in [
          (0.0, 0.0),
          (-dx, 0.0),
          (dx, 0.0),
          (0.0, -dy),
          (0.0, dy),
        ]) {
          _compAt((hd.x + px).round(), (hd.y + py).round())?.used ??= 'head';
        }
      }
      for (final hd in found) {
        _stem(hd);
      }
      heads.addAll(found);
    }
    // A hollow "head" with a stem through it is a flag's curl or the like.
    heads.removeWhere(
      (hd) =>
          hd.hollow &&
          heads.any(
            (o) =>
                o != hd &&
                o.stemX != null &&
                (o.stemX! - hd.x).abs() < hd.width * 0.6 &&
                (hd.y - o.y) * (hd.y - o.stemEnd!) < 0 &&
                // near the stem's end, not stacked on its head (a chord)
                (hd.y - o.stemEnd!).abs() < hd.staff.space * 1.6 &&
                (hd.y - o.y).abs() > hd.staff.space * 1.6,
          ),
    );
    plap('heads+stems');
    _chordsAndBeams(heads);
    // A stemless hollow "head" half over another head is its dots and the
    // lines between them (whole-note chords stack straight up).
    heads.removeWhere(
      (hd) =>
          hd.hollow &&
          hd.stemX == null &&
          heads.any(
            (o) =>
                o != hd &&
                (o.y - hd.y).abs() < hd.staff.space * 1.2 &&
                (o.x - hd.x).abs() > hd.staff.space * 0.3 &&
                (o.x - hd.x).abs() < hd.staff.space * 0.95,
          ),
    );
    // A hollow head with no stem is a whole note: wider than the rest.
    heads.removeWhere(
      (hd) =>
          hd.hollow &&
          hd.stemX == null &&
          hd.width < hd.staff.space * 1.4 &&
          hd.sides < 0.3,
    );
    for (final hd in heads) {
      _dots(hd);
      _accidental(hd);
    }
    plap('chords+dots+acc');
    _ties(heads);
    plap('ties');
    // Bar lines shared by the system (any staff that shows one).
    final xs = bars.toList()..sort();
    final merged = <double>[];
    for (final x in xs) {
      if (merged.isEmpty || x - merged.last > sp * 1.2) {
        merged.add(x);
      } else {
        merged[merged.length - 1] = math.max(merged.last, x);
      }
    }
    final left = sys.staves.map((s) => s.contentX).reduce(math.max);
    final right = sys.staves.map((s) => s.right).reduce(math.max).toDouble();
    final edges = [
      sys.staves.map((s) => s.left).reduce(math.min).toDouble(),
      for (final x in merged)
        if (x > left + sp && x < right - sp) x,
      right,
    ];
    for (var k = 0; k + 1 < edges.length; k++) {
      final m = _Measure(Box(edges[k], sys.box.t, edges[k + 1], sys.box.b));
      for (final e in changes.entries) {
        if ((e.key - edges[k]).abs() < sp * 1.2) m.time = e.value;
      }
      for (final e in keyChanges.entries) {
        if ((e.key - edges[k]).abs() < sp * 1.2) m.fifths = e.value;
      }
      sys.measures.add(m);
    }
    if (sys.startTime != null) sys.measures.first.time ??= sys.startTime;
    // The line's key: what most of its staves say.
    final votes = <int, int>{};
    for (final st in sys.staves) {
      votes[st.fifths] = (votes[st.fifths] ?? 0) + 1;
    }
    final lineKey = votes.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    sys.measures.first.fifths ??= lineKey;
    // After the last bar line only a warning time signature (or nothing):
    // not a measure.
    if (sys.measures.length > 1) {
      final last = sys.measures.last;
      final w = last.box.r - last.box.l;
      if ((w < sp * 4 ||
              sys.staves.any(
                (st) => st.noHeads.any((z) => z.$1 >= last.box.l - sp),
              )) &&
          !heads.any((h) => h.x > last.box.l)) {
        sys.measures.removeLast();
      }
    }
    // Repeat dots next to bar lines.
    for (final (k, m) in sys.measures.indexed) {
      m.repeatStart = k > 0 && _repeatDots(sys.staves.first, m.box.l, 1);
      if (k == 0) {
        m.repeatStart = _repeatDots(
          sys.staves.first,
          sys.staves.first.contentX - sp * 1.5,
          1,
        );
      }
      m.repeatEnd = _repeatDots(sys.staves.first, m.box.r, -1);
    }
    // A bar line (a repeat sign) right after the time signature: the
    // line's opening, not an empty measure.
    if (sys.measures.length > 1) {
      final first = sys.measures.first;
      final start = sys.staves.map((s) => s.contentX).reduce(math.max);
      if (first.box.r - start < sp * 3 &&
          !heads.any((h) => h.x < first.box.r)) {
        final next = sys.measures[1];
        next
          ..box = Box(first.box.l, next.box.t, next.box.r, next.box.b)
          ..repeatStart = next.repeatStart || first.repeatStart
          ..time ??= first.time;
        sys.measures.removeAt(0);
      }
    }
    _endings(sys);
    // Notes and rests into their measures.
    final rests = <ScoreNote>[];
    for (final (si, st) in sys.staves.indexed) {
      rests.addAll(_rests(st, si));
    }
    final all = [..._notesOf(heads, sys), ...rests];
    for (final n in all) {
      final m = sys.measures.firstWhere(
        (m) => n.box.cx >= m.box.l && n.box.cx < m.box.r,
        orElse: () => sys.measures.last,
      );
      m.notes.add(n);
    }
    // Two voices in a staff: stems both ways at once.
    for (final m in sys.measures) {
      for (var si = 0; si < sys.staves.length; si++) {
        _splitVoices(
          m.notes.where((n) => n.staff == si).toList(),
          sys.staves[si],
        );
      }
    }
  }

  /// First / second endings: a line over the measures, with a hook down
  /// at its start and its numbers under it ("1.", "1, 2.", "3."). A line
  /// with no hook at a line's start carries on the ending before it.
  void _endings(_System sys) {
    final st = sys.staves.first;
    final s = st.space;
    final maxRun = _maxLine + 1;
    bool thin(int x, int y) {
      if (!inkAt(x, y)) return false;
      final (a, b) = _vrun(ink, x, y);
      return b - a + 1 <= maxRun;
    }

    // Long thin horizontal lines above the staff.
    final lines = <(int, int, int)>[]; // x0, x1, y
    // (Above the chord names too, but not up into the staff before.)
    final i = staves.indexOf(st);
    final above = i > 0 ? staves[i - 1].bottom + s * 1.5 : 0.0;
    final y0 = math.max(above, st.top - s * 10).round();
    final y1 = (st.top - s * 1.2).round();
    for (var y = math.max(0, y0); y <= y1; y++) {
      var x = st.left;
      while (x < st.right) {
        if (!thin(x, y)) {
          x++;
          continue;
        }
        final a = x;
        while (x < st.right &&
            (thin(x, y) || thin(x, y - 1) || thin(x, y + 1))) {
          x++;
        }
        if (x - a >= s * 2.5 &&
            !lines.any(
              (l) => (l.$3 - y).abs() <= maxRun && l.$1 <= x && l.$2 >= a,
            )) {
          lines.add((a, x, y));
        }
      }
    }
    lines.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (x0, x1, y) in lines) {
      // A box (a section name) has a line below too.
      final boxed =
          lines.any(
            (o) =>
                o.$3 > y + s * 0.4 &&
                o.$3 < y + s * 3.5 &&
                o.$1 < x0 + s &&
                o.$2 > x1 - s,
          ) ||
          lines.any(
            (o) =>
                o.$3 < y - s * 0.4 &&
                o.$3 > y - s * 3.5 &&
                o.$1 < x0 + s &&
                o.$2 > x1 - s,
          );
      if (boxed) continue;
      // The hook: ink going down from its left end.
      var hookLen = 0;
      for (var yy = y + 1; yy < y + s * 2.5; yy++) {
        if ([for (var d = -3; d <= 2; d++) inkAt(x0 + d, yy)].any((v) => v)) {
          hookLen++;
        } else {
          break;
        }
      }
      final hooked = hookLen >= s * 0.8;
      final continues = !hooked && x0 < st.contentX + s * 2;
      if (!hooked && !continues) continue;
      List<int> numbers;
      if (continues && endings[1] is List<int>) {
        numbers = endings[1]! as List<int>;
      } else {
        // Numbers: digit-sized pieces under the line at its start, read
        // where they can be (else counted on from the last ending).
        final digits = [
          for (final c in comps)
            if (c.x0 >= x0 + s * 0.15 &&
                c.x0 <= x0 + s * 3.5 &&
                c.y0 >= y + s * 0.15 &&
                c.y1 <= y + s * 2.0 &&
                c.h >= s * 0.55 &&
                c.h <= s * 1.8 &&
                c.w >= s * 0.15)
              c,
        ]..sort((a, b) => a.x0.compareTo(b.x0));
        final read = <int>[];
        final tallest = digits.isEmpty
            ? 0
            : digits.map((c) => c.h).reduce(math.max);
        digits.removeWhere((c) => c.h < tallest * 0.75); // commas
        for (final c in digits) {
          read.add(_endingDigit(c));
        }
        final next = endings[0]! as int;
        if (read.isNotEmpty && read.every((n) => n >= 1 && n <= 9)) {
          numbers = read;
        } else {
          final count = digits.length.clamp(1, 4);
          numbers = [for (var k = 0; k < count; k++) next + k];
        }
        endings[0] = math.max(next, numbers.reduce(math.max) + 1);
      }
      endings[1] = numbers;
      for (final m in sys.measures) {
        if (m.box.l < x1 - s && m.box.r > x0 + s) m.ending = numbers;
      }
    }
    // A repeat with no endings afterwards starts numbering again.
    if (!lines.any((_) => true) && sys.measures.any((m) => m.repeatEnd)) {
      endings[0] = 1;
    }
  }

  /// An ending's number (1–4), from its shape: a 1 is narrow, a 2 has a
  /// flat foot, a 4 a crossbar low down, else a 3.
  int _endingDigit(_Comp c) {
    if (c.w < c.h * 0.45) return 1;
    double rowFill(int y) {
      var n = 0;
      for (var x = c.x0; x <= c.x1; x++) {
        if (_compAt(x, y) == c) n++;
      }
      return n / c.w;
    }

    var foot = 0.0;
    for (var y = c.y1 - (c.h * 0.15).round(); y <= c.y1; y++) {
      foot = math.max(foot, rowFill(y));
    }
    // A 2's stroke runs down to its foot on the left; a 3 is open there.
    var leftLow = 0;
    for (
      var y = c.y0 + (c.h * 0.55).round();
      y <= c.y0 + (c.h * 0.75).round();
      y++
    ) {
      for (var x = c.x0; x <= c.x0 + (c.w * 0.35).round(); x++) {
        if (_compAt(x, y) == c) leftLow++;
      }
    }
    if (foot > 0.6 && leftLow > 0) return 2;
    var bar = 0.0;
    for (
      var y = c.y0 + (c.h * 0.6).round();
      y <= c.y0 + (c.h * 0.82).round();
      y++
    ) {
      bar = math.max(bar, rowFill(y));
    }
    return bar > 0.75 ? 4 : 3;
  }

  // ---- Clef, key and time at the staff's start ----

  void _readStart(_Staff st, _System sys) {
    final first = index == 0 && sys == systems.first;
    final s = st.space;
    var x = st.left + s * 0.3;
    // The clef: the first tall shape.
    final clef = _shapesIn(
      x,
      st.top - s * 3,
      st.left + s * 5,
      st.bottom + s * 3,
      minH: s * 2.4,
    )..removeWhere((c) => c.w < s * 0.6);
    var clefRight = st.left + s * 3.0;
    if (clef.isNotEmpty) {
      final c = clef.first;
      for (final k in clef) {
        if (k.x0 < c.x1 + s * 0.4) {
          k.used = 'clef';
        }
      }
      final box = clef
          .where((k) => k.used == 'clef')
          .map(
            (k) => Box(
              k.x0.toDouble(),
              k.y0.toDouble(),
              k.x1.toDouble(),
              k.y1.toDouble(),
            ),
          )
          .reduce((a, b) => a.union(b));
      // Bass clef dots.
      for (final k in comps) {
        if (k.used == null &&
            k.x0 > box.r - s * 0.2 &&
            k.x0 < box.r + s * 1.2 &&
            k.cy > st.top &&
            k.cy < st.posY(4, k.cx) &&
            k.w < s * 0.7 &&
            k.h < s * 0.7) {
          k.used = 'clef';
          clefRight = math.max(clefRight, k.x1.toDouble());
        }
      }
      clefRight = math.max(clefRight, box.r);
      final hgt = box.h / s;
      final topPos = st.posOf(box.t, box.cx);
      final midPos = st.posOf(box.cy, box.cx);
      if (hgt > 5.2) {
        st.clef = Clef.treble;
      } else if (topPos > -0.8 && topPos < 1.2 && hgt < 3.8) {
        st.clef = Clef.bass;
      } else {
        st.clef = (midPos - 2).abs() < (midPos - 4).abs()
            ? Clef.tenor
            : Clef.alto;
      }
    }
    // Key: sharps or flats in a row after the clef.
    x = clefRight + s * 0.2;
    final key = _keySigAt(st, x);
    st.fifths = key?.fifths ?? 0;
    if (key != null) x = key.right;
    // Time: two numbers stacked, or C.
    final found = _timeSigAt(st, x, strict: !first);
    if (found != null) {
      x = math.max(x, found.right);
      if (found.time != null) {
        sys.time ??= found.time;
        sys.startTime ??= found.time;
      }
    }
    st.contentX = x;
  }

  /// A key signature starting at [x] on [st]: naturals cancelling the
  /// old key (optional), then sharps or flats in a row. Its key (+ sharps,
  /// − flats), where it ends and how many signs it has; null when there
  /// are none.
  ({int fifths, double right, int signs, List<_Comp> parts})? _keySigAt(
    _Staff st,
    double x, {
    bool naturals = false,
  }) {
    final s = st.space;
    var sharps = 0, flats = 0, cancels = 0;
    var right = x;
    final used = <_Comp>[];
    while (true) {
      final next = _shapesIn(
        right,
        st.top - s * 2,
        right + s * 1.6,
        st.bottom + s * 1.5,
        minH: s * 1.6,
        maxH: s * 3.6,
        maxW: s * 1.4,
      );
      if (next.isEmpty) break;
      // On its own if it reads as a sign; else with the pieces the staff
      // line removal cut off it.
      final alone = next.first.w < s * 0.45
          ? null // a bare stem is part of a sign
          : _classifyParts(
              {next.first},
              const ['sharp', 'flat', 'natural'],
              min: 0.5,
            );
      final parts = alone != null ? {next.first} : _pieces(next.first, s * 1.4);
      final kind =
          alone ??
          _classifyParts(parts, const [
            'sharp',
            'flat',
            'natural',
          ], min: 0.45) ??
          (_looksFlat(parts) ? 'flat' : null);
      if (kind == 'sharp' && flats == 0) {
        sharps++;
      } else if (kind == 'flat' && sharps == 0) {
        flats++;
      } else if (kind == 'natural' && naturals && sharps + flats == 0) {
        cancels++;
      } else {
        break;
      }
      for (final k in parts) {
        used.add(k);
        k.used = 'key';
        right = math.max(right, k.x1 + 1.0);
      }
      if (sharps + flats >= 7) break;
    }
    final signs = sharps + flats + cancels;
    if (signs == 0) return null;
    for (final k in used) {
      k.used = 'key';
    }
    return (
      fifths: sharps > 0 ? sharps : -flats,
      right: right,
      signs: signs,
      parts: used,
    );
  }

  /// Signs right before notes are their accidentals, not a key: a
  /// notehead just after the last sign, level with any of them.
  bool _isNoteAccidental(
    _Staff st,
    ({int fifths, double right, int signs, List<_Comp> parts}) key,
  ) {
    final s = st.space;
    for (final c in key.parts) {
      if (c.h < s * 1.2) continue; // a flat's bowl piece
      for (var dy = -0.6; dy <= 0.6; dy += 0.3) {
        // Solid ink the size of a head just after the signs.
        final cx = (key.right + s * 0.7).round(), cy = (c.cy + dy * s).round();
        var n = 0, k = 0;
        final r = (s * 0.3).round();
        for (var yy = cy - r; yy <= cy + r; yy++) {
          for (var xx = cx - r; xx <= cx + r; xx++) {
            k++;
            if (symAt(xx, yy)) n++;
          }
        }
        if (n > k * 0.6) return true;
      }
    }
    return false;
  }

  /// A time signature starting at [x] on [st] (two numbers stacked, or C):
  /// what it says (null: unreadable) and where it ends. Thin strokes
  /// crossing the staff lines may have been cut, so pieces close together
  /// count as one. [strict]: only when the numbers read clearly.
  ({(int, int)? time, double right})? _timeSigAt(
    _Staff st,
    double x, {
    bool strict = false,
    double span = 3.5,
  }) {
    final s = st.space;
    final t = _shapesIn(
      x,
      st.top - s * 0.4,
      x + s * span,
      st.bottom + s * 0.4,
      minH: s * 0.5,
      maxH: s * 4.4,
      maxW: s * 2.6,
    );
    if (t.isNotEmpty) {
      final a = t.first;
      final mid = st.posY(4, a.cx);
      final stack = <_Comp>[a];
      var sx0 = a.x0, sx1 = a.x1;
      for (var grew = true; grew;) {
        grew = false;
        for (final k in t) {
          if (stack.contains(k)) continue;
          if (k.x0 <= sx1 + s * 0.25 &&
              k.x1 >= sx0 - s * 0.25 &&
              math.max(sx1, k.x1) - math.min(sx0, k.x0) < s * 2.6) {
            stack.add(k);
            sx0 = math.min(sx0, k.x0);
            sx1 = math.max(sx1, k.x1);
            grew = true;
          }
        }
      }
      final x0 = stack.map((k) => k.x0).reduce(math.min);
      final x1 = stack.map((k) => k.x1).reduce(math.max);
      final y0 = stack.map((k) => k.y0).reduce(math.min);
      final y1 = stack.map((k) => k.y1).reduce(math.max);
      // Numbers above and below the middle line (touching it or not):
      // each half solid, not just a stem passing through.
      bool solid(int ya, int yb) {
        var minX = x1, maxX = x0, minY = yb, maxY = ya;
        for (var yy = ya; yy <= yb; yy++) {
          for (var xx = x0; xx <= x1; xx++) {
            if (symAt(xx, yy)) {
              minX = math.min(minX, xx);
              maxX = math.max(maxX, xx);
              minY = math.min(minY, yy);
              maxY = math.max(maxY, yy);
            }
          }
        }
        return maxX - minX >= s * 0.6 && maxY - minY >= s * 1.2;
      }

      // Printed numbers fill the staff from its top line to its bottom one.
      final fills =
          (y0 - st.yAt(0, a.cx)).abs() < s * 0.5 &&
          (y1 - st.yAt(4, a.cx)).abs() < s * 0.5;
      if (fills &&
          y0 < mid - s * 1.2 &&
          y1 > mid + s * 1.2 &&
          x1 - x0 < s * 2.6 &&
          solid(y0, (mid - lt).floor()) &&
          solid((mid + lt).ceil(), y1) &&
          // Later lines rarely repeat it: there it must read clearly
          // (a rest at a line's start can look like two numbers).
          (!strict ||
              (_number(x0, y0, x1, (mid - lt).floor(), min: 0.5) != null &&
                  _number(x0, (mid + lt).ceil(), x1, y1, min: 0.5) != null))) {
        for (final k in stack) {
          k.used = 'time';
        }
        final top = _number(x0, y0, x1, (mid - lt).floor());
        final bottom = _number(x0, (mid + lt).ceil(), x1, y1);
        readerLog?.add('time $top/$bottom');
        if (top != null && bottom != null && top > 0 && top <= 16) {
          var bt = bottom;
          // Commonly confused below: 6 / 9 for 8, others for 4.
          if (![1, 2, 4, 8, 16].contains(bt)) bt = bt == 9 || bt == 6 ? 8 : 4;
          return (time: (top, bt), right: x1.toDouble());
        }
        return (time: null, right: x1.toDouble());
      } else if (!strict &&
          a.h < s * 2.6 &&
          (st.posOf(a.cy, a.cx) - 4).abs() < 1) {
        // (C for 4/4 only where a time signature is expected: a whole note
        // on the middle line looks like it.)
        final c = _classify(a, const ['timeSigCommon', 'timeSigCut']);
        if (c != null) {
          a.used = 'time';
          return (
            time: c == 'timeSigCommon' ? (4, 4) : (2, 2),
            right: a.x1.toDouble(),
          );
        }
      }
    }
    return null;
  }

  /// Unused pieces of ink in a box (by left edge), within size limits.
  List<_Comp> _shapesIn(
    double x0,
    double y0,
    double x1,
    double y1, {
    double minH = 0,
    double maxH = 1e9,
    double maxW = 1e9,
  }) {
    final out = [
      for (final c in comps)
        if (c.used == null &&
            c.x0 >= x0 &&
            c.x0 < x1 &&
            c.cy > y0 &&
            c.cy < y1 &&
            c.h >= minH &&
            c.h <= maxH &&
            c.w <= maxW)
          c,
    ];
    out.sort((a, b) => a.x0.compareTo(b.x0));
    return out;
  }

  /// The best match for [c] among the glyphs [names] (null: none close).
  String? _classify(_Comp c, List<String> names, {double min = 0.55}) =>
      _classifyRegion(c.x0, c.y0, c.x1, c.y1, names, min: min, only: {c});

  String? _classifyParts(
    Set<_Comp> parts,
    List<String> names, {
    double min = 0.55,
  }) => _classifyRegion(
    parts.map((c) => c.x0).reduce(math.min),
    parts.map((c) => c.y0).reduce(math.min),
    parts.map((c) => c.x1).reduce(math.max),
    parts.map((c) => c.y1).reduce(math.max),
    names,
    min: min,
    only: parts,
  );

  /// A thin upright stroke with a small bowl at its lower right: a flat.
  bool _looksFlat(Set<_Comp> parts) {
    final stem = parts.where((c) => c.w <= sp * 0.3 && c.h >= sp * 1.8);
    if (stem.length != 1) return false;
    final st = stem.first;
    return parts.any(
      (c) =>
          c != st &&
          c.h <= sp * 1.3 &&
          c.x0 >= st.x0 &&
          c.cy > st.y0 + st.h * 0.5,
    );
  }

  /// [c] with the unused pieces right next to it (a symbol the staff line
  /// removal cut apart, like a flat's bowl from its stem), up to [maxW]
  /// wide.
  Set<_Comp> _pieces(_Comp c, double maxW) {
    final out = {c};
    final gap = math.max(3, lt * 1.5 + 1);
    var x0 = c.x0, x1 = c.x1, y0 = c.y0, y1 = c.y1;
    var grew = true;
    while (grew) {
      grew = false;
      for (final k in comps) {
        if (k.used != null || out.contains(k)) continue;
        // Another tall piece is the next sign (a flat's stem), not a part.
        if (k.h >= sp * 1.5) continue;
        if (k.x0 > x1 + gap || k.x1 < x0 - gap) continue;
        if (k.y1 < y0 - gap || k.y0 > y1 + gap) continue;
        final nx0 = math.min(x0, k.x0), nx1 = math.max(x1, k.x1);
        if (nx1 - nx0 > maxW) continue;
        if (math.max(y1, k.y1) - math.min(y0, k.y0) > sp * 3.8) continue;
        out.add(k);
        x0 = nx0;
        x1 = nx1;
        y0 = math.min(y0, k.y0);
        y1 = math.max(y1, k.y1);
        grew = true;
      }
    }
    return out;
  }

  /// The number written in the box (digits side by side), if any.
  int? _number(int x0, int y0, int x1, int y1, {double min = 0.2}) {
    // Tight box, then split at empty columns.
    var cols = <int>[];
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        if (symAt(x, y)) {
          cols.add(x);
          break;
        }
      }
    }
    if (cols.isEmpty) return null;
    final digits = <(int, int)>[];
    var start = cols.first;
    for (var i = 1; i <= cols.length; i++) {
      if (i == cols.length || cols[i] != cols[i - 1] + 1) {
        if (digits.isNotEmpty &&
            start - digits.last.$2 <= sp * 0.25 &&
            (cols[i - 1] - digits.last.$1) < sp * 1.6) {
          // A digit broken in two (thin strokes lost): join it up.
          digits[digits.length - 1] = (digits.last.$1, cols[i - 1]);
        } else if (cols[i - 1] - start >= sp * 0.25) {
          digits.add((start, cols[i - 1]));
        }
        if (i < cols.length) start = cols[i];
      }
    }
    // Two "digits" narrower than one real digit: one, broken.
    if (digits.length > 1 && digits.last.$2 - digits.first.$1 < sp * 1.3) {
      digits.replaceRange(0, digits.length, [
        (digits.first.$1, digits.last.$2),
      ]);
    }
    // A digit is narrower than a whole notehead.
    if (digits.any((d) => d.$2 - d.$1 > sp * 1.5)) return null;
    var n = 0;
    for (final (a, b) in digits) {
      final d = _classifyRegion(a, y0, b, y1, [
        for (var i = 0; i <= 9; i++) 'timeSig$i',
      ], min: min);
      if (d == null) return null;
      n = n * 10 + int.parse(d.substring(7));
    }
    return digits.isEmpty ? null : n;
  }

  /// The best match among the glyphs [names] for the ink in a box (only
  /// the piece [only], if given), trimmed to the ink and stretched to a
  /// grid. Null when none is close enough.
  String? _classifyRegion(
    int bx0,
    int by0,
    int bx1,
    int by1,
    List<String> names, {
    double min = 0.55,
    Set<_Comp>? only,
  }) {
    bool on(int x, int y) {
      if (!symAt(x, y)) return false;
      if (only == null) return true;
      final l = labels[y * w + x];
      return l != 0 && only.contains(comps[l - 1]);
    }

    // Trim to the ink.
    var cx0 = bx1, cx1 = bx0, cy0 = by1, cy1 = by0;
    for (var y = by0; y <= by1; y++) {
      for (var x = bx0; x <= bx1; x++) {
        if (on(x, y)) {
          cx0 = math.min(cx0, x);
          cx1 = math.max(cx1, x);
          cy0 = math.min(cy0, y);
          cy1 = math.max(cy1, y);
        }
      }
    }
    if (cx1 < cx0 || cy1 < cy0) return null;
    const gw = 16, gh = 28;
    final cw = cx1 - cx0 + 1, ch = cy1 - cy0 + 1;
    final m = Mask(gw, gh);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        if (on(
          cx0 + ((x + 0.5) / gw * cw).floor(),
          cy0 + ((y + 0.5) / gh * ch).floor(),
        )) {
          m.px[y * gw + x] = 1;
        }
      }
    }
    String? best;
    var bestS = min;
    for (final n in names) {
      final g = _templates.putIfAbsent(n, () => glyphMask(n, gw, gh));
      var both = 0, any = 0;
      for (var i = 0; i < m.px.length; i++) {
        if (m.px[i] == 1 && g.px[i] == 1) both++;
        if (m.px[i] == 1 || g.px[i] == 1) any++;
      }
      final s = any == 0 ? 0.0 : both / any;
      if (s > bestS) {
        bestS = s;
        best = n;
      }
    }
    return best;
  }

  static final _templates = <String, Mask>{};

  // ---- Bar lines ----

  List<double> _barlines(_Staff st) {
    final s = st.space;
    final out = <double>[];
    // Columns with ink all the way from the top line to the bottom one.
    bool full(int x) {
      final top = st.yAt(0, x.toDouble()).round();
      final bot = st.yAt(4, x.toDouble()).round();
      var miss = 0;
      for (var y = top; y <= bot; y++) {
        if (!symAt(x, y) && !symAt(x - 1, y) && !symAt(x + 1, y)) {
          if (++miss > (bot - top) * 0.06 + 1) return false;
        }
      }
      return true;
    }

    var x = math.max(1, st.left - (s * 0.5).round());
    final end = math.min(w - 2, st.right + (s * 0.5).round());
    while (x < end) {
      if (!full(x)) {
        x++;
        continue;
      }
      var x1 = x;
      while (x1 + 1 < end && full(x1 + 1)) {
        x1++;
      }
      final cx = (x + x1) / 2;
      final width = x1 - x + 1;
      x = x1 + 1;
      if (width > s * 0.9) continue; // a solid block, not a line
      // Not a stem: no notehead where the line ends.
      final mid = st.yAt(2, cx).round();
      bool on(int y) =>
          symAt(cx.round(), y) ||
          symAt(cx.round() - 1, y) ||
          symAt(cx.round() + 1, y);
      var a = mid, b = mid;
      var gap = 0;
      while (a > 0 && gap <= 2) {
        gap = on(a - 1) ? 0 : gap + 1;
        a--;
      }
      a += gap;
      gap = 0;
      while (b < h - 1 && gap <= 2) {
        gap = on(b + 1) ? 0 : gap + 1;
        b++;
      }
      b -= gap;
      readerLog?.add(
        'bar? ${cx.round()} w$width run $a-$b top ${st.top.round()} bot ${st.bottom.round()} heads ${_headish(cx, a.toDouble(), s)} ${_headish(cx, b.toDouble(), s)}',
      );
      if (_headish(cx, a.toDouble(), s) || _headish(cx, b.toDouble(), s)) {
        continue;
      }
      // A bar line starts and ends on the outer lines (a stem stops short
      // or runs past).
      final tol = lt + 0.5;
      final i = staves.indexOf(st);
      final above = i > 0 ? staves[i - 1] : null;
      final below = i + 1 < staves.length ? staves[i + 1] : null;
      // Its top: on the top line, or up into the staff above (a grand
      // staff's bar line); its bottom likewise.
      final topOk =
          (a - st.yAt(0, cx)).abs() <= tol ||
          (above != null && a <= above.yAt(4, cx) + tol);
      final botOk =
          (b - st.yAt(4, cx)).abs() <= tol ||
          (below != null && b >= below.yAt(0, cx) - tol);
      if (!topOk || !botOk) continue;
      // Pieces of it aren't symbols.
      for (var y = a; y <= b; y += math.max(1, (s / 2).round())) {
        for (var xx = cx.round() - 1; xx <= cx.round() + 1; xx++) {
          final c = _compAt(xx, y);
          if (c != null && c.w <= s * 0.9) c.used ??= 'bar';
        }
      }
      if (cx < st.left + s) continue; // the system's opening line
      out.add(cx);
    }
    return out;
  }

  /// A solid blob about a notehead in size beside (x, y)?
  bool _headish(double x, double y, double s) {
    for (final dx in [-0.6, 0.6]) {
      for (final dy in [-0.4, 0.0, 0.4]) {
        final cx = (x + dx * s).round(), cy = (y + dy * s).round();
        var n = 0, k = 0;
        final ry = (s * 0.3).round(), rx = (s * 0.3).round();
        for (var yy = cy - ry; yy <= cy + ry; yy++) {
          for (var xx = cx - rx; xx <= cx + rx; xx++) {
            k++;
            if (symAt(xx, yy)) n++;
          }
        }
        if (n > k * 0.6) return true;
      }
    }
    return false;
  }

  bool _repeatDots(_Staff st, double x, int side) {
    final s = st.space;
    var found = 0;
    for (final c in comps) {
      if (c.w > s * 0.7 || c.h > s * 0.7 || c.w < s * 0.2) continue;
      final dx = (c.cx - x) * side;
      if (dx < s * 0.2 || dx > s * 1.6) continue;
      final p = st.posOf(c.cy, c.cx);
      if ((p - 3).abs() < 0.6 || (p - 5).abs() < 0.6) {
        found++;
        c.used = 'repeat';
      }
    }
    return found >= 2;
  }

  // ---- Noteheads ----

  late final List<(int, int)> _inside = _ellipse(0.42, 0.3, 0, 1);
  late final List<(int, int)> _ring = _ellipse(0.56, 0.43, 0.72, 0.95);
  late final List<(int, int)> _core = _ellipse(0.2, 0.12, 0, 1);
  late final List<List<(int, int)>> _ringQuarters = [
    for (final (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)])
      [
        for (final (x, y) in _ring)
          if (x * sx > 0 && y * sy >= 0) (x, y),
      ],
  ];

  /// Sample points (x, y offsets) of an ellipse of half-sizes [rx], [ry]
  /// (in spaces), between normalised radii [r0] and [r1].
  List<(int, int)> _ellipse(double rx, double ry, double r0, double r1) {
    final out = <(int, int)>[];
    final ax = rx * sp, ay = ry * sp;
    final step = math.max(1, (sp / 10).floor());
    for (var y = -ay.ceil(); y <= ay.ceil(); y += step) {
      for (var x = -ax.ceil(); x <= ax.ceil(); x += step) {
        final r = math.sqrt((x / ax) * (x / ax) + (y / ay) * (y / ay));
        if (r >= r0 && r <= r1) out.add((x, y));
      }
    }
    return out;
  }

  double _frac(List<(int, int)> pts, int cx, int cy, {bool lines = false}) {
    final img = lines ? ink : sym;
    var n = 0;
    final margin = (sp * 2).ceil();
    if (cx > margin && cy > margin && cx < w - margin && cy < h - margin) {
      // Away from the edges: no bounds checks.
      final base = cy * w + cx;
      for (final (dx, dy) in pts) {
        if (img[base + dy * w + dx] == 1) n++;
      }
    } else {
      for (final (dx, dy) in pts) {
        if (lines ? inkAt(cx + dx, cy + dy) : symAt(cx + dx, cy + dy)) n++;
      }
    }
    return n / pts.length;
  }

  List<_Head> _heads(_Staff st) {
    final s = st.space;
    final cands = <_Head>[];
    final x0 = (st.contentX + s * 0.4).round();
    final x1 = (st.right - s * 0.3).round();
    // Ledger positions only as far as halfway to the next staff.
    final i = staves.indexOf(st);
    var pLo = -12, pHi = 20;
    if (i > 0) {
      final gap = st.top - staves[i - 1].bottom;
      pLo = math.max(pLo, -((gap / 2) / (s / 2)).floor());
    }
    if (i + 1 < staves.length) {
      final gap = staves[i + 1].top - st.bottom;
      pHi = math.min(pHi, 8 + ((gap / 2) / (s / 2)).floor());
    }
    bool blocked(int x) => st.noHeads.any((z) => x >= z.$1 && x <= z.$2);
    for (var p = pLo; p <= pHi; p++) {
      for (var x = x0; x < x1; x++) {
        final y = st.posY(p.toDouble(), x.toDouble()).round();
        if (!symAt(x, y) || blocked(x)) continue;
        final fin = _frac(_inside, x, y);
        if (fin >= 0.86) {
          cands.add(
            _Head(x.toDouble(), y.toDouble(), p, false, fin, s * 1.2, st),
          );
          continue;
        }
      }
      for (var x = x0; x < x1; x++) {
        final y = st.posY(p.toDouble(), x.toDouble()).round();
        if (symAt(x, y) || blocked(x)) continue;
        // Quick test first: a ring has ink on both sides, near.
        var leftInk = false, rightInk = false;
        for (var d = (s * 0.15).round(); d <= (s * 0.75).round(); d += 2) {
          if (!leftInk && symAt(x - d, y)) leftInk = true;
          if (!rightInk && symAt(x + d, y)) rightInk = true;
        }
        if (!leftInk || !rightInk) continue;
        final core = _frac(_core, x, y);
        if (core > 0.25) continue;
        // The ring on the ink with lines (a head between two lines touches
        // them, and their removal takes its edge too).
        final ring = _frac(_ring, x, y, lines: true);
        if (ring < 0.5) continue;
        // Closed all round (a flag's curl or a letter is open somewhere).
        var closed = true;
        for (final q in _ringQuarters) {
          if (_frac(q, x, y, lines: true) < 0.25) {
            closed = false;
            break;
          }
        }
        if (!closed) continue;
        // Across the middle row: hole, then the ring's sides, alike on both
        // sides.
        var l = x, r = x;
        while (l > x - s && !symAt(l, y)) {
          l--;
        }
        final il = l;
        while (l > x - s * 1.4 && symAt(l, y)) {
          l--;
        }
        while (r < x + s && !symAt(r, y)) {
          r++;
        }
        final ir = r;
        while (r < x + s * 1.4 && symAt(r, y)) {
          r++;
        }
        // Closed on both sides (a hairpin's open end isn't).
        if (ir >= x + s || il <= x - s) continue;
        final width = (r - l) / s;
        if (width < 0.95 || width > 2.1) continue;
        if (((x - il) - (ir - x)).abs() > s * 0.25) continue;
        if ((il - l) > s * 0.8 || (r - ir) > s * 0.8) continue;
        // Something hollow (a letter, a clef's loop) is rarely this round:
        // ink above and below the hole too.
        double hole(bool Function(int, int) at) {
          var ty = y, by = y;
          while (ty > y - s && !at(x, ty)) {
            ty--;
          }
          while (by < y + s && !at(x, by)) {
            by++;
          }
          return (by - ty) / s;
        }

        bool fits(double hl) => hl >= 0.15 && hl <= 0.95;
        if (!fits(hole(symAt)) && (inkAt(x, y) || !fits(hole(inkAt)))) {
          continue;
        }
        cands.add(
          _Head(
            ((l + r) / 2),
            y.toDouble(),
            p,
            true,
            ring - core,
            (r - l).toDouble(),
            st,
          )..sides = math.min(il - l, r - ir) / s,
        );
      }
    }
    // Where two hollow heads stacked a third apart touch, the joint looks
    // solid: it mustn't push the real ones out.
    final hollows = [
      for (final c in cands)
        if (c.hollow) c,
    ];
    cands.removeWhere(
      (c) =>
          !c.hollow &&
          hollows.any(
            (h) =>
                (h.x - c.x).abs() < s * 0.5 &&
                h.y < c.y - s * 0.3 &&
                h.y > c.y - s * 0.8,
          ) &&
          hollows.any(
            (h) =>
                (h.x - c.x).abs() < s * 0.5 &&
                h.y > c.y + s * 0.3 &&
                h.y < c.y + s * 0.8,
          ),
    );
    // Keep the best of overlapping candidates.
    cands.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Head>[];
    for (final c in cands) {
      final clash = kept.any(
        (k) => (k.x - c.x).abs() < s * 0.85 && (k.y - c.y).abs() < s * 0.75,
      );
      if (!clash) kept.add(c);
    }
    // A filled head must be a blob of about that size.
    kept.removeWhere((hd) {
      if (hd.hollow) return false;
      final y = hd.y.round();
      var l = hd.x.round(), r = hd.x.round();
      while (symAt(l - 1, y) && hd.x - l < s * 3) {
        l--;
      }
      while (symAt(r + 1, y) && r - hd.x < s * 3) {
        r++;
      }
      // Taller than a beam.
      final (ta, tb) = _vrun(sym, hd.x.round(), y);
      if ((tb - ta + 1) < s * 0.7) return true;
      // A notehead is oval: its box's corners are paper. A block rest's
      // aren't.
      var corners = 0;
      for (final (dx, dy) in [
        (-0.5, -0.3),
        (0.5, -0.3),
        (-0.5, 0.3),
        (0.5, 0.3),
      ]) {
        if (symAt((hd.x + dx * s).round(), (hd.y + dy * s).round())) corners++;
      }
      if (corners >= 4) return true;
      final run = (r - l + 1) / s;
      readerLog?.add(
        'head ${hd.x.round()},${hd.y.round()} p${hd.pos} run ${run.toStringAsFixed(2)} sc ${hd.score.toStringAsFixed(2)}',
      );
      if (run < 0.9 || run > 2.8) return true;
      // Centre it on its ink.
      hd.x = (l + r) / 2;
      if (run > 1.7) {
        // Two heads side by side (a second): the left one is here; the
        // other is found separately or not at all.
        hd.x = l + s * 0.6;
      }
      return false;
    });
    // Beyond the staff a head sits on or between ledger lines: each one
    // from the staff out to it must show on both sides of it. (Lyrics and
    // chord names have none.)
    kept.removeWhere((hd) {
      final p = hd.pos;
      if (p >= -1 && p <= 9) return false;
      final ledgers = p < 0
          ? [for (var k = -2; k >= p; k -= 2) k]
          : [for (var k = 10; k <= p; k += 2) k];
      final half = hd.hollow ? hd.width / 2 : s * 0.6;
      for (final k in ledgers) {
        final y = st.posY(k.toDouble(), hd.x);
        // Thin ink (a line, not a letter's stroke) just past each side.
        bool sideHas(double x) {
          for (var d = -_maxLine; d <= _maxLine; d++) {
            final yy = (y + d).round(), xx = x.round();
            if (inkAt(xx, yy)) {
              final (a, b) = _vrun(ink, xx, yy);
              return b - a + 1 <= _maxLine + 1;
            }
          }
          return false;
        }

        bool side(int dir) => [
          0.05,
          0.15,
          0.25,
          0.35,
        ].any((o) => sideHas(hd.x + dir * (half + s * o)));
        if (!side(-1) || !side(1)) {
          return true;
        }
      }
      return false;
    });
    return kept;
  }

  // ---- Stems, beams, flags ----

  int _vlen(int x, int y, int dir, int limit) {
    var n = 0, gaps = 0;
    var yy = y;
    while (n < limit) {
      if (symAt(x, yy)) {
        gaps = 0;
      } else if (++gaps > 1) {
        break;
      }
      n++;
      yy += dir;
    }
    return n - gaps;
  }

  void _stem(_Head hd) {
    final s = hd.staff.space;
    final limit = (s * 8).round();
    var bestLen = 0, bestX = 0, bestDir = 0;
    final halfW = hd.hollow ? hd.width / 2 : s * 0.6;
    for (final (dir, side) in [(-1, 1), (1, -1)]) {
      for (var dx = -(s * 0.2).round(); dx <= (s * 0.25).round(); dx++) {
        final x = (hd.x + side * (halfW - s * 0.05) + side * dx).round();
        final len = _vlen(x, (hd.y + dir * s * 0.1).round(), dir, limit);
        if (len > bestLen) {
          bestLen = len;
          bestX = x;
          bestDir = dir;
        }
      }
    }
    if (bestLen < s * 2.2) return;
    hd.stemX = bestX.toDouble();
    hd.up = bestDir < 0;
    hd.stemEnd = hd.y + bestDir * bestLen;
  }

  void _chordsAndBeams(List<_Head> heads) {
    // Heads on one stem: a chord.
    var next = 0;
    final stemmed = heads.where((h) => h.stemX != null).toList()
      ..sort((a, b) => a.stemX!.compareTo(b.stemX!));
    for (final a in stemmed) {
      if (a.chord >= 0) continue;
      a.chord = next++;
      for (final b in stemmed) {
        if (b.chord >= 0 || b.staff != a.staff) continue;
        if ((b.stemX! - a.stemX!).abs() > lt * 2 + 2) continue;
        final lo = math.min(a.y, a.stemEnd!), hi = math.max(a.y, a.stemEnd!);
        final lo2 = math.min(b.y, b.stemEnd!), hi2 = math.max(b.y, b.stemEnd!);
        if (hi2 < lo || lo2 > hi) continue;
        b.chord = a.chord;
      }
    }
    // Heads without a stem next to a chord's stem (seconds): join it.
    for (final hd in heads.where((h) => h.stemX == null && !h.hollow)) {
      for (final o in stemmed) {
        final s = hd.staff.space;
        if (o.staff != hd.staff) continue;
        if ((o.stemX! - hd.x).abs() < s * 1.0 && (o.y - hd.y).abs() < s * 1.6) {
          hd
            ..stemX = o.stemX
            ..stemEnd = o.stemEnd
            ..up = o.up
            ..chord = o.chord;
          break;
        }
      }
    }
    // Beams or flags: count them at each stem's far end.
    final byChord = <int, List<_Head>>{};
    for (final hd in heads.where((h) => h.chord >= 0)) {
      byChord.putIfAbsent(hd.chord, () => []).add(hd);
    }
    for (final group in byChord.values) {
      // The stem's end: the farthest from the heads.
      final a = group.first;
      final s = a.staff.space;
      final end = a.up
          ? group.map((g) => g.stemEnd!).reduce(math.min)
          : group.map((g) => g.stemEnd!).reduce(math.max);
      final dir = a.up ? 1 : -1; // from the end back toward the heads
      final x = a.stemX!.round();
      // Flags and beams cross a line drawn down (or up) beside the stem,
      // once each.
      final heads = group.map((g) => g.y);
      final stop = a.up
          ? heads.reduce(math.min) - s * 0.7
          : heads.reduce(math.max) + s * 0.7;
      int crossings(double px) {
        var n = 0, run = 0;
        final from = end.round(), to = stop.round();
        for (var y = from; dir > 0 ? y <= to : y >= to; y += dir) {
          if (symAt(px.round(), y)) {
            run++;
          } else {
            if (run >= math.max(math.max(2, lt), s * 0.22) && run <= s * 0.95) {
              n++;
            }
            run = 0;
          }
        }
        if (run >= math.max(math.max(2, lt), s * 0.22) && run <= s * 0.95) n++;
        return n;
      }

      var count = 0;
      for (final side in [-1, 1]) {
        final near = crossings(x + side * s * 0.25);
        final far = crossings(x + side * s * 0.42);
        count = math.max(count, math.min(near, far));
      }
      for (final g in group) {
        g.beams = math.min(count, 3);
      }
    }
  }

  // ---- Dots, accidentals, ties ----

  void _dots(_Head hd) {
    final s = hd.staff.space;
    final right = hd.x + hd.width / 2;
    for (final c in comps) {
      if (c.used != null) continue;
      if (c.w > s * 0.65 || c.h > s * 0.65 || c.w < s * 0.2 || c.h < s * 0.2) {
        continue;
      }
      if (c.fill < 0.5) continue;
      final dx = c.cx - right;
      if (dx < s * 0.15 || dx > s * (hd.up && hd.beams > 0 ? 2.0 : 1.3)) {
        continue;
      }
      final dy = c.cy - hd.y;
      if (dy < -s * 0.8 || dy > s * 0.35) continue;
      hd.dots = 1;
      c.used = 'dot';
      // A second dot.
      for (final c2 in comps) {
        if (c2.used == null &&
            (c2.cy - c.cy).abs() < s * 0.3 &&
            c2.cx - c.cx > s * 0.3 &&
            c2.cx - c.cx < s * 0.9 &&
            c2.w < s * 0.65 &&
            c2.h < s * 0.65) {
          hd.dots = 2;
          c2.used = 'dot';
        }
      }
      return;
    }
  }

  void _accidental(_Head hd) {
    final s = hd.staff.space;
    final left = hd.x - hd.width / 2;
    _Comp? best;
    for (final c in comps) {
      if (c.used != null && c.used != 'acc?') continue;
      if (c.x1 > left + s * 0.2 || c.x1 < left - s * 1.6) continue;
      if (c.h < s * 1.4 || c.h > s * 3.6 || c.w > s * 1.4) continue;
      if (hd.y < c.y0 || hd.y > c.y1) continue;
      if (best == null || c.x1 > best.x1) best = c;
    }
    if (best == null) return;
    final parts = _pieces(best, s * 1.4);
    final kind = _classifyParts(parts, const [
      'sharp',
      'flat',
      'natural',
      'doubleFlat',
    ], min: 0.45);
    if (kind == null) return;
    // The head sits on the accidental's middle (a flat's bowl is low).
    final rel = (hd.y - best.y0) / best.h;
    if (kind == 'flat' && rel < 0.45) return;
    if (kind != 'flat' && kind != 'doubleFlat' && (rel < 0.3 || rel > 0.7)) {
      return;
    }
    for (final k in parts) {
      k.used = 'acc';
    }
    hd.accidental = switch (kind) {
      'sharp' => 1,
      'flat' => -1,
      'doubleFlat' => -2,
      _ => 0,
    };
  }

  /// Ties: a thin curve from a note to the next one of the same pitch,
  /// over or under them. Staff lines cut it into pieces, so it's followed
  /// column by column rather than as one piece of ink.
  void _ties(List<_Head> heads) {
    for (final a in heads) {
      final s = a.staff.space;
      _Head? b;
      for (final o in heads) {
        if (o.staff != a.staff || o.pos != a.pos) continue;
        if (o.x <= a.x + s * 1.2 || o.x - a.x > s * 14) continue;
        if (b == null || o.x < b.x) b = o;
      }
      if (b == null) continue;
      final from = (a.x + a.width * 0.5).round();
      final to = (b.x - b.width * 0.5).round();
      if (to - from < s * 0.6) continue;
      // Not across other notes of the same voice (that's a slur).
      final between = heads.any(
        (o) =>
            o.staff == a.staff &&
            o.x > a.x + s * 0.6 &&
            o.x < b!.x - s * 0.6 &&
            o.up == a.up &&
            (o.y - a.y).abs() < s * 3,
      );
      if (between) continue;
      final reach = s * (to - from > s * 6 ? 2.2 : 1.6);
      // Staff lines crossing the band (where the tie may run along one).
      final lineYs = [for (var k = 0; k < 5; k++) a.staff.yAt(k, a.x)];
      bool curve(int side) {
        var hits = 0, cols = 0, neutral = 0, gap = 0, worstGap = 0;
        final depth = <double>[]; // how far from the notes, column by column
        final lo = a.y + side * s * 0.2, hi = a.y + side * reach;
        final linesHere = lineYs.where((ly) => (ly - lo) * (ly - hi) <= 0);
        for (var x = from; x <= to; x += 2) {
          cols++;
          var found = false;
          for (var d = s * 0.2; d <= reach && !found; d += 1) {
            final y = (a.y + side * d).round();
            if (!symAt(x, y)) continue;
            final (ta, tb) = _vrun(sym, x, y);
            if (tb - ta + 1 <= s * 0.4) {
              found = true;
              depth.add(d);
            }
          }
          if (found) {
            hits++;
            gap = 0;
          } else if (linesHere.any((ly) => inkAt(x, ly.round()))) {
            neutral++; // could be running along the line
          } else {
            gap += 2;
            worstGap = math.max(worstGap, gap);
          }
        }
        final seen = cols - neutral;
        // A tie bows away from the notes (a lyric line is straight).
        final k = depth.length;
        final bows =
            k >= 6 &&
            depth.sublist(k ~/ 3, 2 * k ~/ 3).reduce(math.max) -
                    math.min(depth.first, depth.last) >=
                math.max(2, s * 0.08);
        return seen > 0 &&
            bows &&
            hits >= seen * 0.7 &&
            hits >= cols * 0.4 &&
            worstGap <= s * 1.4;
      }

      if (curve(-1) || curve(1)) a.tieNext = true;
    }
  }

  // ---- Rests ----

  List<ScoreNote> _rests(_Staff st, int si) {
    final s = st.space;
    final out = <ScoreNote>[];
    for (final c in comps) {
      if (c.used != null) continue;
      if (c.x0 < math.max(st.contentX, st.restsFrom) || c.x1 > st.right) {
        continue;
      }
      final p = st.posOf(c.cy, c.cx);
      if (p < -3 || p > 11) continue;
      String? type;
      if (c.h < s * 0.75 &&
          c.w > s * 0.8 &&
          c.w < s * 1.6 &&
          c.fill > 0.8 &&
          // hanging from or sitting on a middle line (not a ledger dash)
          p > 1.4 &&
          p < 4.6) {
        // Block rests: whole hangs from the 4th line, half sits on the 3rd.
        type = p < 3 ? 'whole' : 'half';
        // In two voices they move; trust their shape over place.
        final topP = st.posOf(c.y0.toDouble(), c.cx);
        final onLine = (topP / 2 - (topP / 2).round()).abs() < 0.15;
        type = onLine ? 'whole' : 'half';
      } else if (c.h > s * 1.3 &&
          c.h < s * 4 &&
          c.w < s * 1.6 &&
          c.w > s * 0.5) {
        final kind = _classify(c, const [
          'restQuarter',
          'rest8th',
          'rest16th',
          'rest32nd',
        ], min: 0.4);
        type = switch (kind) {
          'restQuarter' => 'quarter',
          'rest8th' => 'eighth',
          'rest16th' => '16th',
          'rest32nd' => '32nd',
          _ => null,
        };
        // Sizes tell an 8th rest (2 spaces) from a quarter (3).
        if (type == 'quarter' && c.h < s * 2.3) type = 'eighth';
        if (type == 'eighth' && c.h > s * 2.5) type = '16th';
      }
      if (type == null) continue;
      c.used = 'rest';
      final n = ScoreNote(
        page: index,
        system: 0,
        staff: si,
        rest: true,
        type: type,
        box: Box(
          c.x0.toDouble(),
          c.y0.toDouble(),
          c.x1.toDouble(),
          c.y1.toDouble(),
        ),
        diatonic: st.clef.topLine - p.round(),
      );
      // A dot after it.
      for (final d in comps) {
        if (d.used == null &&
            d.w < s * 0.65 &&
            d.h < s * 0.65 &&
            d.w > s * 0.2 &&
            d.x0 - c.x1 > 0 &&
            d.x0 - c.x1 < s * 1.0 &&
            d.cy > c.y0 &&
            d.cy < c.y1) {
          n.dots = 1;
          d.used = 'dot';
          break;
        }
      }
      out.add(n);
    }
    return out;
  }

  // ---- Into notes ----

  List<ScoreNote> _notesOf(List<_Head> heads, _System sys) {
    final out = <ScoreNote>[];
    for (final hd in heads) {
      final si = sys.staves.indexOf(hd.staff);
      final s = hd.staff.space;
      final String type;
      if (hd.hollow) {
        type = hd.stemX == null ? 'whole' : 'half';
      } else {
        type = switch (hd.beams) {
          0 => 'quarter',
          1 => 'eighth',
          2 => '16th',
          _ => '32nd',
        };
      }
      out.add(
        ScoreNote(
          page: index,
          system: 0,
          staff: si,
          voice: 1,
          diatonic: hd.staff.clef.topLine - hd.pos,
          accidental: hd.accidental,
          type: type,
          dots: hd.dots,
          tie: hd.tieNext,
          chord: hd.chord < 0 ? -1 : index * 100000 + hd.chord,
          box: Box(
            hd.x - hd.width / 2,
            hd.y - s * 0.5,
            hd.x + hd.width / 2,
            hd.y + s * 0.5,
          ),
        ),
      );
      // Remember which way the stem went (for voices).
      _up[out.last] = hd.stemX == null ? null : hd.up;
      out.last.stem = hd.stemX == null ? 0 : (hd.up ? 1 : -1);
    }
    return out;
  }

  final _up = <ScoreNote, bool?>{};

  void _splitVoices(List<ScoreNote> notes, _Staff st) {
    final s = st.space;
    final ups = notes.where((n) => _up[n] == true).toList();
    final downs = notes.where((n) => _up[n] == false).toList();
    // A whole note held over moving notes: it fills the bar, so the others
    // are another voice.
    final wholes = [
      for (final n in notes)
        if (!n.rest && n.type == 'whole') n,
    ];
    final others = [
      for (final n in notes)
        if (!n.rest && n.type != 'whole') n,
    ];
    if (wholes.isNotEmpty &&
        others.isNotEmpty &&
        (ups.isEmpty || downs.isEmpty)) {
      final avg =
          others.map((n) => n.diatonic).reduce((a, b) => a + b) / others.length;
      final wholeHigh = wholes.first.diatonic >= avg;
      for (final n in wholes) {
        n.voice = wholeHigh ? 1 : 2;
      }
      for (final n in others) {
        n.voice = wholeHigh ? 2 : 1;
      }
      return;
    }
    if (ups.isEmpty || downs.isEmpty) return;
    // Two voices if an up stem and a down stem stand at the same place
    // (different chords), or if one after another they'd overfill the bar.
    final together = ups.any(
      (u) => downs.any(
        (d) => (u.box.cx - d.box.cx).abs() < s * 0.8 && u.chord != d.chord,
      ),
    );
    if (!together) return;
    for (final n in downs) {
      n.voice = 2;
    }
    for (final n in notes.where((n) => n.rest)) {
      if (st.posOf(n.box.cy, n.box.cx) > 4.5) n.voice = 2;
    }
    // Whole-note heads (no stem) go with the voice nearer them.
    for (final n in notes.where((n) => _up[n] == null && !n.rest)) {
      final p = st.posOf(n.box.cy, n.box.cx);
      if (p > 4.5) n.voice = 2;
    }
  }
}
