// Chord shapes for guitar and ukulele (from chords-db by David Rubert, MIT
// licence: assets/chords/LICENSE-chords-db.txt) and piano voicings worked
// out from the chord's intervals. Looks up the shapes for a chord name as
// the song shows it (after transposing).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../music.dart';

enum Instrument {
  guitar('Guitar'),
  ukulele('Ukulele'),
  piano('Piano');

  final String label;
  const Instrument(this.label);

  bool get fretted => this != piano;
}

/// The open strings (MIDI notes), lowest first.
const Map<Instrument, List<int>> stringTuning = {
  Instrument.guitar: [40, 45, 50, 55, 59, 64], // E2 A2 D3 G3 B3 E4
  Instrument.ukulele: [67, 60, 64, 69], // G4 C4 E4 A4 (re-entrant G)
};

/// One way to play a chord.
class ChordShape {
  final Instrument instrument;

  /// Pitch classes (0 = C) of the root and the bass (slash chords).
  final int root;
  final String suffix;
  final int? bass;

  // Fretted instruments: strings low → high. frets: -1 muted, 0 open,
  // n = n-th fret from [baseFret]. fingers: 0 none, 1–4. barres: relative
  // frets played with a barre.
  final int baseFret;
  final List<int> frets;
  final List<int> fingers;
  final List<int> barres;

  /// Piano: the keys (MIDI notes).
  final List<int> keys;

  /// A shape the person made (Chord Editor), and its id.
  final String? customId;

  const ChordShape({
    required this.instrument,
    required this.root,
    required this.suffix,
    this.bass,
    this.baseFret = 1,
    this.frets = const [],
    this.fingers = const [],
    this.barres = const [],
    this.keys = const [],
    this.customId,
  });

  /// A key for remembering it as someone's preferred shape.
  String get id => customId ?? '$baseFret:${frets.join(',')}:${keys.join(',')}';

  /// The notes it sounds (MIDI), lowest string first; [capo] raises them.
  List<int> midi({int capo = 0}) {
    if (!instrument.fretted) return [for (final k in keys) k + capo];
    final open = stringTuning[instrument]!;
    return [
      for (var i = 0; i < frets.length && i < open.length; i++)
        if (frets[i] >= 0)
          open[i] + capo + (frets[i] == 0 ? 0 : baseFret + frets[i] - 1),
    ];
  }

  Map<String, dynamic> toJson() => {
    'instrument': instrument.name,
    'root': root,
    'suffix': suffix,
    'bass': ?bass,
    'baseFret': baseFret,
    'frets': frets,
    'fingers': fingers,
    'barres': barres,
    'keys': keys,
    'id': ?customId,
  };

  static ChordShape? fromJson(Object? j) {
    if (j is! Map) return null;
    final inst = Instrument.values.asNameMap()[j['instrument']];
    if (inst == null) return null;
    List<int> ints(Object? v) => [
      for (final e in (v as List?) ?? const [])
        if (e is num) e.toInt(),
    ];
    return ChordShape(
      instrument: inst,
      root: (j['root'] as num?)?.toInt() ?? 0,
      suffix: '${j['suffix'] ?? 'major'}',
      bass: (j['bass'] as num?)?.toInt(),
      baseFret: (j['baseFret'] as num?)?.toInt() ?? 1,
      frets: ints(j['frets']),
      fingers: ints(j['fingers']),
      barres: ints(j['barres']),
      keys: ints(j['keys']),
      customId: j['id'] as String?,
    );
  }
}

/// A chord name split into what the shape lookup needs.
class ChordName {
  final int root;
  final String suffix;
  final int? bass;
  const ChordName(this.root, this.suffix, this.bass);

  /// Reads a chord as written ("F#m7", "Bb/D", "Cmaj7", "Asus") moved by
  /// [transpose] semitones. Null for anything that isn't a chord (N.C.).
  static ChordName? parse(String text, {int transpose = 0}) {
    final c = Chord.parse(text);
    if (c == null) return null;
    final suffix = normalizeSuffix(c.minor, c.rest);
    if (suffix == null) return null;
    return ChordName(
      (c.root + transpose) % 12,
      suffix,
      c.bass == null ? null : (c.bass! + transpose) % 12,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChordName &&
      other.root == root &&
      other.suffix == suffix &&
      other.bass == bass;

  @override
  int get hashCode => Object.hash(root, suffix, bass);
}

/// The chord type of a quality as written ("maj7", "°", "-7", "add2"…),
/// as the chord data names it. Null when it isn't one we know.
String? normalizeSuffix(bool minor, String rest) {
  var q = rest.replaceAll(RegExp(r'[\s()]'), '').replaceAll('♭', 'b');
  q = q.replaceAll('♯', '#').replaceAll('Δ', 'maj');
  // Capital M before a number = major seventh ("M7", "M9").
  q = q.replaceAllMapped(RegExp(r'^M(?=\d|$)'), (_) => 'maj');
  q = q.replaceFirst(RegExp(r'^(Maj|MAJ|Ma(?!j)|ma(?!j))'), 'maj');
  if (q == 'maj') q = minor ? 'maj7' : (rest.contains('Δ') ? 'maj7' : '');
  final key = '${minor ? 'm' : ''}$q';
  return _suffixAliases[key] ?? (_known.contains(key) ? key : null);
}

const _suffixAliases = <String, String>{
  '': 'major',
  'm': 'minor',
  'maj': 'major',
  'o': 'dim',
  '°': 'dim',
  'o7': 'dim7',
  '°7': 'dim7',
  'ø': 'm7b5',
  'ø7': 'm7b5',
  '+': 'aug',
  '+7': 'aug7',
  '7+': 'aug7',
  '7#5': 'aug7',
  '9+': 'aug9',
  '9#5': 'aug9',
  'sus': 'sus4',
  '2': 'sus2',
  '7sus': '7sus4',
  '69': '6/9',
  'm69': 'm6/9',
  'add2': 'add9',
  'madd2': 'madd9',
  'mM7': 'mmaj7',
  'mmaj': 'mmaj7',
  'm7-5': 'm7b5',
  '7-5': '7b5',
  '7-9': '7b9',
  '7+9': '7#9',
  'dim': 'dim',
  'mdim': 'dim',
  'mb5': 'dim',
};

const _known = {
  'major', 'minor', 'dim', 'dim7', 'sus2', 'sus4', 'sus2sus4', '7sus4', //
  'alt', 'aug', '5', '6', '6/9', '7', '7b5', 'aug7', '9', '9b5', 'aug9', //
  '7b9', '7#9', '11', '9#11', '13', 'maj7', 'maj7b5', 'maj7#5', //
  'maj7sus2', 'maj9', 'maj11', 'maj13', 'm6', 'm6/9', 'm7', 'm7b5', 'm9', //
  'm11', 'm13', 'm7#5', 'mmaj7', 'mmaj7b5', 'mmaj9', 'mmaj11', 'add9', //
  'madd9', 'add11', '7b9#5', '13b9', '13b5b9', 'b13b9', 'b13#9', 'm9b5', //
};

/// Semitones above the root, for piano voicings (and for checking a shape).
const Map<String, List<int>> chordIntervals = {
  'major': [0, 4, 7],
  'minor': [0, 3, 7],
  'dim': [0, 3, 6],
  'dim7': [0, 3, 6, 9],
  'aug': [0, 4, 8],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
  'sus2sus4': [0, 2, 5, 7],
  '5': [0, 7],
  '6': [0, 4, 7, 9],
  'm6': [0, 3, 7, 9],
  '6/9': [0, 4, 7, 9, 14],
  'm6/9': [0, 3, 7, 9, 14],
  '7': [0, 4, 7, 10],
  '7sus4': [0, 5, 7, 10],
  'maj7': [0, 4, 7, 11],
  'maj7sus2': [0, 2, 7, 11],
  'm7': [0, 3, 7, 10],
  'mmaj7': [0, 3, 7, 11],
  'm7b5': [0, 3, 6, 10],
  'm7#5': [0, 3, 8, 10],
  '7b5': [0, 4, 6, 10],
  'aug7': [0, 4, 8, 10],
  'maj7#5': [0, 4, 8, 11],
  'maj7b5': [0, 4, 6, 11],
  '9': [0, 4, 7, 10, 14],
  'maj9': [0, 4, 7, 11, 14],
  'm9': [0, 3, 7, 10, 14],
  'add9': [0, 4, 7, 14],
  'madd9': [0, 3, 7, 14],
  'add11': [0, 4, 7, 17],
  '7b9': [0, 4, 7, 10, 13],
  '7#9': [0, 4, 7, 10, 15],
  '9b5': [0, 4, 6, 10, 14],
  'aug9': [0, 4, 8, 10, 14],
  '11': [0, 4, 7, 10, 14, 17],
  'm11': [0, 3, 7, 10, 14, 17],
  'maj11': [0, 4, 7, 11, 14, 17],
  '9#11': [0, 4, 7, 10, 14, 18],
  '13': [0, 4, 7, 10, 14, 21],
  'maj13': [0, 4, 7, 11, 14, 21],
  'm13': [0, 3, 7, 10, 14, 21],
  'mmaj7b5': [0, 3, 6, 11],
  'mmaj9': [0, 3, 7, 11, 14],
  'mmaj11': [0, 3, 7, 11, 14, 17],
  'alt': [0, 4, 6, 10, 13],
};

/// All the chord shapes (load once with [ChordLibrary.load]).
class ChordLibrary {
  static final Map<Instrument, List<ChordShape>> _shapes = {};
  static Future<void>? _loading;

  static bool get loaded => _shapes.isNotEmpty;

  static Future<void> load([AssetBundle? bundle]) =>
      _loading ??= _load(bundle ?? rootBundle);

  static Future<void> _load(AssetBundle bundle) async {
    for (final inst in [Instrument.guitar, Instrument.ukulele]) {
      final j = jsonDecode(
        await bundle.loadString('assets/chords/${inst.name}.json'),
      );
      _shapes[inst] = [
        for (final s in (j['shapes'] as List).cast<Map<String, dynamic>>())
          ChordShape(
            instrument: inst,
            root: _pc(s['k'] as String),
            suffix: s['s'] as String,
            bass: s['x'] == null ? null : _pc(s['x'] as String),
            baseFret: (s['b'] as num).toInt(),
            frets: (s['f'] as List).cast<int>(),
            fingers: (s['g'] as List).cast<int>(),
            barres: ((s['r'] as List?) ?? const []).cast<int>(),
          ),
      ];
    }
  }

  /// For tests: shapes without loading assets.
  @visibleForTesting
  static void debugSet(Instrument inst, List<ChordShape> shapes) =>
      _shapes[inst] = shapes;

  static int _pc(String note) {
    const letters = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    var n = letters[note[0]]!;
    if (note.length > 1) n += note[1] == '#' ? 1 : -1;
    return n % 12;
  }

  /// Every shape for [chord] on [instrument]: the person's own first,
  /// then the library's. A slash chord with no shape of its own falls back
  /// to the plain chord.
  static List<ChordShape> shapesFor(
    Instrument instrument,
    ChordName chord, {
    List<ChordShape> custom = const [],
  }) {
    final mine = [
      for (final s in custom)
        if (s.instrument == instrument &&
            s.root == chord.root &&
            s.suffix == chord.suffix &&
            s.bass == chord.bass)
          s,
    ];
    if (instrument == Instrument.piano) {
      final v = pianoVoicing(chord);
      return [
        ...mine,
        if (v.isNotEmpty)
          ChordShape(
            instrument: Instrument.piano,
            root: chord.root,
            suffix: chord.suffix,
            bass: chord.bass,
            keys: v,
          ),
      ];
    }
    List<ChordShape> find(int? bass) => [
      for (final s in _shapes[instrument] ?? const <ChordShape>[])
        if (s.root == chord.root && s.suffix == chord.suffix && s.bass == bass)
          s,
    ];
    var found = find(chord.bass);
    if (found.isEmpty && chord.bass != null) found = find(null);
    if (found.isEmpty && chord.suffix == 'sus4') {
      found = [
        for (final s in _shapes[instrument] ?? const <ChordShape>[])
          if (s.root == chord.root && s.suffix == 'sus' && s.bass == null) s,
      ];
    }
    return [...mine, ...found];
  }

  /// The shape to show: the preferred one (by [ChordShape.id]) if it's
  /// still there, else the first.
  static ChordShape? pick(List<ChordShape> shapes, String? preferred) {
    if (shapes.isEmpty) return null;
    for (final s in shapes) {
      if (s.id == preferred) return s;
    }
    return shapes.first;
  }

  /// The chord types the library has (for the Chord Library pickers).
  static List<String> suffixesFor(Instrument instrument) {
    if (instrument == Instrument.piano) return chordIntervals.keys.toList();
    final seen = <String>{};
    return [
      for (final s in _shapes[instrument] ?? const <ChordShape>[])
        if (s.bass == null && seen.add(s.suffix)) s.suffix,
    ];
  }
}

/// Piano keys for [chord] across two octaves from C3: the root in the
/// first octave and each interval above it (a slash chord's bass first,
/// below the chord).
List<int> pianoVoicing(ChordName chord) {
  final intervals = chordIntervals[chord.suffix];
  if (intervals == null) return const [];
  const c3 = 48;
  final keys = <int>[];
  var start = c3 + chord.root;
  if (chord.bass != null) {
    keys.add(c3 + chord.bass!);
    if (start <= keys.first) start += 12;
  }
  for (final i in intervals) {
    keys.add(start + i);
  }
  // Keep it on the two octaves shown (C3–B4).
  return [
    for (final k in keys)
      if (k < c3 + 24) k else k - 12,
  ]..sort();
}

/// How a chord type reads after the root ("major" → "", "minor" → "m").
String suffixLabel(String suffix) => switch (suffix) {
  'major' => '',
  'minor' => 'm',
  _ => suffix,
};

/// A note's name (sharps or flats).
String noteName(int pc, {bool flats = false}) => (flats
    ? const ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B']
    : const [
        'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
      ])[pc % 12];
