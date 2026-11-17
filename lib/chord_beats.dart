// Chord beats (as in JustChords): how many beats each chord lasts. Kept on
// the song (not in its text), one number per chord, edited in the song
// editor's "Chord Beats" tab. A chord without a number lasts a bar.
//
// Each chord is known by its section and its place in that section
// ("verse 1#2" = the third chord of Verse 1), so the numbers survive
// transposing, a capo and the song structure repeating or reordering
// sections.

import 'chordpro.dart';
import 'state.dart';

/// Beat counts set on [song] (chord key -> beats).
Map<String, int> chordBeatsOf(Song song) {
  final m = song.extra['chordBeats'];
  return {
    if (m is Map)
      for (final e in m.entries)
        if (e.value is num) '${e.key}': (e.value as num).toInt(),
  };
}

/// Stores [beats] on [song] (none: the entry is removed).
void setChordBeats(Song song, Map<String, int> beats) {
  if (beats.isEmpty) {
    song.extra.remove('chordBeats');
  } else {
    song.extra['chordBeats'] = Map<String, int>.of(beats);
  }
}

/// Walks a song's lines in order, naming each chord met (see the top of
/// this file).
class ChordKeys {
  String _section = '';
  int _next = 0;

  /// Call for every line, labels included (a label starts a section).
  void line(String line) {
    final name = ChordPro.sectionName(line);
    if (name != null) {
      _section = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      _next = 0;
    }
  }

  /// The key of the next chord in the current section.
  String next() => '$_section#${_next++}';
}

/// What follows a chord in Dots style: a dot per beat, a number past 8,
/// nothing for 0 beats (or a full bar, when [hideFull]).
String beatDots(int beats, int barBeats, {bool hideFull = false}) {
  if (beats <= 0 || (hideFull && beats == barBeats)) return '';
  return beats > 8 ? '·$beats' : '•' * beats;
}
