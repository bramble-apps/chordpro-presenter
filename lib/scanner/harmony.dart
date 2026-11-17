// Chords for a read score: the notes sounding in each bar (or half bar)
// matched against chord shapes, the bass note giving inversions. Works from
// a melody alone too (less surely).

import 'dart:math' as math;

import 'score.dart';

class ChordGuess {
  final int measure;

  /// Quarters into the measure.
  final double offset;
  final String name;

  /// How well the notes fit (0–1).
  final double confidence;
  const ChordGuess(this.measure, this.offset, this.name, this.confidence);
}

const _sharpNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
const _flatNames = [
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

/// (suffix, intervals, how much simpler shapes are preferred).
const _shapes = [
  ('', [0, 4, 7], 0.0),
  ('m', [0, 3, 7], 0.0),
  ('7', [0, 4, 7, 10], 0.08),
  ('maj7', [0, 4, 7, 11], 0.1),
  ('m7', [0, 3, 7, 10], 0.08),
  ('sus4', [0, 5, 7], 0.1),
  ('sus2', [0, 2, 7], 0.12),
  ('dim', [0, 3, 6], 0.12),
  ('aug', [0, 4, 8], 0.18),
  ('5', [0, 7], 0.2),
];

/// Chords for [score], sounding [shift] semitones from what's written.
List<ChordGuess> guessChords(Score score, {int shift = 0}) {
  // The key's notes (major scale from the key signature), for a nudge
  // toward chords that belong, and flat keys spelled with flats.
  final tonic = ((score.fifths * 7) % 12 + 12 + shift) % 12;
  final names = const {5, 10, 3, 8, 1, 6}.contains(tonic)
      ? _flatNames
      : _sharpNames;
  final inKey = {
    for (final i in [0, 2, 4, 5, 7, 9, 11]) (tonic + i) % 12,
  };

  final out = <ChordGuess>[];
  final byMeasure = <int, List<ScoreNote>>{};
  for (final n in score.notes) {
    if (!n.rest) byMeasure.putIfAbsent(n.measure, () => []).add(n);
  }
  String? last;
  for (final (mi, m) in score.measures.indexed) {
    final notes = byMeasure[mi] ?? const <ScoreNote>[];
    if (notes.isEmpty) continue;
    final whole = _best(notes, m.onset, m.onset + m.length, shift, inKey);
    final half = m.length / 2;
    final a = _best(notes, m.onset, m.onset + half, shift, inKey);
    final b = _best(notes, m.onset + half, m.onset + m.length, shift, inKey);
    // Two chords in the bar only when both halves clearly say so.
    final split =
        a != null &&
        b != null &&
        whole != null &&
        (a.$1 != b.$1 || a.$2 != b.$2) &&
        (a.$3 + b.$3) / 2 > whole.$3 + 0.12 &&
        m.length >= 2;
    for (final (offset, g) in split ? [(0.0, a), (half, b)] : [(0.0, whole)]) {
      if (g == null) continue;
      final (root, suffix, score_, bass) = g;
      var name = '${names[root]}$suffix';
      if (bass != null && bass != root) name += '/${names[bass]}';
      // The same chord again: written once.
      if (name == last && offset > 0) continue;
      out.add(ChordGuess(mi, offset, name, score_.clamp(0.0, 1.0)));
      last = name;
    }
  }
  return out;
}

/// The best chord for notes sounding between [from] and [to]: root,
/// suffix, fit, and a bass note when it isn't the root.
(int, String, double, int?)? _best(
  List<ScoreNote> notes,
  double from,
  double to,
  int shift,
  Set<int> inKey,
) {
  final weight = List<double>.filled(12, 0);
  var lowest = 999;
  var lowestPc = -1;
  var total = 0.0;
  for (final n in notes) {
    final s = math.max(from, n.onset), e = math.min(to, n.onset + n.duration);
    if (e <= s) continue;
    final midi = n.midi + shift;
    final pc = midi % 12;
    // Longer and on the beat counts more.
    var w = e - s;
    if ((n.onset - from).abs() < 0.01) w *= 1.3;
    weight[pc] += w;
    total += w;
    if (midi < lowest) {
      lowest = midi;
      lowestPc = pc;
    }
  }
  if (total == 0) return null;
  (int, String, double, int?)? best;
  var bestScore = -1e9;
  for (var root = 0; root < 12; root++) {
    for (final (suffix, ivs, penalty) in _shapes) {
      final tones = {for (final i in ivs) (root + i) % 12};
      var hit = 0.0, miss = 0.0;
      for (var pc = 0; pc < 12; pc++) {
        if (tones.contains(pc)) {
          hit += weight[pc];
        } else {
          miss += weight[pc];
        }
      }
      // Every tone of a seventh chord should be there.
      var absent = 0;
      for (final t in tones) {
        if (weight[t] == 0) absent++;
      }
      var sc = (hit - miss * 0.8) / total - penalty - absent * 0.12;
      if (weight[root] > 0) sc += 0.1;
      if (lowestPc == root) sc += 0.15;
      if (inKey.contains(root)) sc += 0.05;
      if (sc > bestScore) {
        bestScore = sc;
        best = (
          root,
          suffix,
          sc,
          tones.contains(lowestPc) && lowestPc != root ? lowestPc : null,
        );
      }
    }
  }
  return best;
}

/// [chords] as ChordPro lines: bars between "|", four bars a line.
String chordsToChordPro(
  List<ChordGuess> chords,
  int measures, {
  int perLine = 4,
}) {
  final byMeasure = <int, List<ChordGuess>>{};
  for (final c in chords) {
    byMeasure.putIfAbsent(c.measure, () => []).add(c);
  }
  final lines = <String>[];
  var line = StringBuffer('|');
  for (var m = 0; m < measures; m++) {
    final cs = byMeasure[m];
    line.write(' ');
    line.write(cs == null ? '%' : cs.map((c) => '[${c.name}]').join(' '));
    line.write(' |');
    if ((m + 1) % perLine == 0 || m == measures - 1) {
      lines.add(line.toString());
      line = StringBuffer('|');
    }
  }
  return lines.join('\n');
}
