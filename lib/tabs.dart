// Guitar and ukulele tabs: a block of string lines (`e|---0---3---|`)
// between {start_of_tab} and {end_of_tab} (or {sot} / {eot}), or tab lines
// pasted on their own. Read into strings, notes and bar lines, so the
// sheet can draw them (solid strings with the frets on them, or the text as
// typed) and play them.

import 'dart:math' as math;
import 'dart:typed_data';

/// One string's line of a tab.
class TabString {
  /// Its label as written ("e", "B", "D#"), or "" when there's none.
  final String label;

  /// What comes after the label and the first bar ("--0---3--|--").
  final String body;

  /// The open string's note (MIDI number).
  final int open;

  const TabString(this.label, this.body, this.open);
}

/// A note on the tab: the column it starts at, its string (0 = top line)
/// and fret, and what's written there ("12", "x", "7h9"…).
class TabNote {
  final int column, string, fret;
  final String text;
  const TabNote(this.column, this.string, this.fret, this.text);
}

/// A row of strings read together (one "system" of a tab).
class TabSystem {
  final List<TabString> strings;

  /// Every note, in column order.
  final List<TabNote> notes;

  /// Columns with a bar line on every string.
  final Set<int> bars;

  /// Width in columns (the longest string).
  final int columns;

  const TabSystem(this.strings, this.notes, this.bars, this.columns);
}

/// A tab block: its systems, with any other lines (a riff's name, the
/// chords above it) kept as they are, in order.
class TabBlock {
  /// A [TabSystem] or a plain line (String).
  final List<Object> parts;
  const TabBlock(this.parts);

  Iterable<TabSystem> get systems => parts.whereType<TabSystem>();
}

// Marks a tab line may hold besides frets and dashes: hammer-on, pull-off,
// bend, release, slide, vibrato, tap, dead note, harmonics, palm mute,
// let ring, accents and the like.
final RegExp _tabLine = RegExp(
  r'^\s*([A-Ga-g][#b]?)?\s*([|:])([-0-9|hpbrsxXtvVTPMlL/\\~()<>\[\].,^=*+!\s]*)$',
);

/// Whether [line] is a tab string line ("e|--0--3--|", "D|-----").
bool isTabLine(String line) {
  final m = _tabLine.firstMatch(line);
  if (m == null) return false;
  return '-'.allMatches(m.group(3)!).length >= 4;
}

const _names = {
  'c': 0,
  'c#': 1,
  'db': 1,
  'd': 2,
  'd#': 3,
  'eb': 3,
  'e': 4,
  'f': 5,
  'f#': 6,
  'gb': 6,
  'g': 7,
  'g#': 8,
  'ab': 8,
  'a': 9,
  'a#': 10,
  'bb': 10,
  'b': 11,
};

/// The open notes of strings labelled [labels] (top line first): standard
/// guitar and ukulele as they are, other tunings from the labels (each
/// string the nearest below the one above it).
List<int> tuningFor(List<String> labels) {
  final n = labels.length;
  final upper = [for (final l in labels) l.toUpperCase()];
  if (n == 4 && upper.join() == 'AECG') return [69, 64, 60, 67]; // ukulele
  if (labels.every((l) => l.isEmpty)) {
    if (n == 4) return [69, 64, 60, 67]; // ukulele
    return [64, 59, 55, 50, 45, 40, 35].take(n).toList(); // guitar
  }
  final out = <int>[];
  for (var i = 0; i < n; i++) {
    final pc = _names[labels[i].toLowerCase()];
    if (pc == null) {
      out.add(out.isEmpty ? 64 : out.last - 5);
      continue;
    }
    if (out.isEmpty) {
      // The top string: the octave nearest the high E (64).
      var m = 60 + pc;
      if (m < 58) m += 12;
      if (m > 70) m -= 12;
      out.add(m);
    } else {
      var m = out.last - 1;
      while (m % 12 != pc) {
        m--;
      }
      out.add(m);
    }
  }
  return out;
}

/// Reads tab [lines] into systems (runs of string lines) and plain lines.
TabBlock parseTab(List<String> lines) {
  final parts = <Object>[];
  var run = <String>[];
  void flushRun() {
    if (run.length >= 2) {
      parts.add(_system(run));
    } else {
      parts.addAll(run);
    }
    run = [];
  }

  for (final line in lines) {
    if (isTabLine(line)) {
      run.add(line);
    } else {
      flushRun();
      if (line.trim().isNotEmpty) parts.add(line.trimRight());
    }
  }
  flushRun();
  return TabBlock(parts);
}

TabSystem _system(List<String> lines) {
  final labels = <String>[];
  final bodies = <String>[];
  for (final line in lines) {
    final m = _tabLine.firstMatch(line)!;
    labels.add(m.group(1) ?? '');
    bodies.add(m.group(3)!.trimRight());
  }
  final tuning = tuningFor(labels);
  final strings = [
    for (var i = 0; i < lines.length; i++)
      TabString(labels[i], bodies[i], tuning[i]),
  ];
  final notes = <TabNote>[];
  for (var s = 0; s < bodies.length; s++) {
    final b = bodies[s];
    for (final m in RegExp(r'\d+|[xX]').allMatches(b)) {
      final t = m.group(0)!;
      final fret = int.tryParse(t);
      if (fret != null && fret > 24) {
        // "12" can't be two notes here; a long run is likely 2 notes.
        notes.add(
          TabNote(m.start, s, int.parse(t.substring(0, 2)), t.substring(0, 2)),
        );
        continue;
      }
      notes.add(TabNote(m.start, s, fret ?? -1, t));
    }
  }
  notes.sort((a, b) => a.column.compareTo(b.column));
  final width = bodies.fold(0, (w, b) => math.max(w, b.length));
  final bars = <int>{
    for (var c = 0; c < width; c++)
      if (bodies.every((b) => c < b.length && b[c] == '|')) c,
  };
  return TabSystem(strings, notes, bars, width);
}

// ---- Sound ----

const tabSampleRate = 22050;

/// How long one column of dashes lasts: a sixteenth note at [bpm].
double tabColumnSeconds(int bpm) => 60 / bpm.clamp(30, 300) / 4;

/// [system] played (each string a plucked string, a new note stopping the
/// one before it on that string), and when each column sounds.
(Float32List, double Function(int column)) renderTab(
  TabSystem system, {
  int bpm = 90,
  int capo = 0,
}) {
  final step = tabColumnSeconds(bpm);
  final played = system.notes.where((n) => n.fret >= 0).toList();
  final start = played.isEmpty ? 0 : played.first.column;
  double at(int column) => (column - start) * step;
  final length = played.isEmpty ? 0.5 : at(played.last.column) + 1.6;
  final out = Float32List((length * tabSampleRate).round());
  final random = math.Random(3);
  // When each string's next note starts (to stop the one ringing).
  for (var i = 0; i < played.length; i++) {
    final n = played[i];
    final next = played
        .skip(i + 1)
        .where((m) => m.string == n.string)
        .firstOrNull;
    final from = (at(n.column) * tabSampleRate).round();
    final until = next == null
        ? math.min(out.length, from + (2.2 * tabSampleRate).round())
        : (at(next.column) * tabSampleRate).round();
    final midi = system.strings[n.string].open + n.fret + capo;
    _pluck(
      out,
      from,
      until,
      440 * math.pow(2, (midi - 69) / 12).toDouble(),
      random,
    );
  }
  var peak = 0.0;
  for (final v in out) {
    peak = math.max(peak, v.abs());
  }
  if (peak > 0) {
    for (var i = 0; i < out.length; i++) {
      out[i] *= 0.8 / peak;
    }
  }
  return (out, at);
}

void _pluck(
  Float32List out,
  int start,
  int end,
  double hz,
  math.Random random,
) {
  final period = math.max(2, (tabSampleRate / hz).round());
  final line = Float32List(period);
  var prev = 0.0;
  for (var i = 0; i < period; i++) {
    final noise = random.nextDouble() * 2 - 1;
    prev = (noise + prev) / 2;
    line[i] = prev;
  }
  var p = 0;
  final stop = math.min(end, out.length);
  // A short damp at the end so a stopped string doesn't click.
  final damp = math.min(220, math.max(1, stop - start));
  for (var i = start; i < stop; i++) {
    final next = (p + 1) % period;
    final v = line[p];
    line[p] = 0.996 * 0.5 * (line[p] + line[next]);
    final fade = stop - i < damp ? (stop - i) / damp : 1.0;
    out[i] += v * 0.5 * fade;
    p = next;
  }
}
