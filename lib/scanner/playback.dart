// Playing a score: what sounds when (repeats, ties, swing, the tempo, the
// pitch it's played at), and the sound itself — built-in instruments made
// here, or a SoundFont sound taken in for the pads.

import 'dart:math' as math;
import 'dart:typed_data';

import '../pads/sf2.dart';
import 'score.dart';

const playbackRate = 32000;

/// Built-in instruments.
enum Instrument {
  piano('Grand piano'),
  electricPiano('Electric piano'),
  organ('Organ'),
  churchOrgan('Church organ'),
  strings('Strings'),
  guitar('Guitar'),
  nylonGuitar('Nylon guitar'),
  bass('Bass'),
  flute('Flute'),
  clarinet('Clarinet'),
  oboe('Oboe'),
  trumpet('Trumpet'),
  brass('Brass section'),
  harmonica('Harmonica'),
  choir('Choir'),
  sine('Pure tone');

  final String label;
  const Instrument(this.label);
}

/// Instruments that read music written higher than it sounds.
enum Transposing {
  concert('Concert pitch', 0),
  bFlat('B♭ instrument (trumpet, clarinet)', -2),
  bFlatTenor('B♭ tenor sax', -14),
  eFlat('E♭ alto sax', -9),
  eFlatBari('E♭ baritone sax', -21),
  f('F horn', -7),
  octaveDown('Guitar (sounds an octave lower)', -12);

  final String label;

  /// Semitones from written to sounding.
  final int semitones;
  const Transposing(this.label, this.semitones);
}

/// One staff's part in the mix.
class PartMix {
  Instrument instrument;

  /// A SoundFont sound (pads' id) in place of [instrument].
  String? soundId;
  double volume;
  bool muted;
  PartMix({
    this.instrument = Instrument.piano,
    this.soundId,
    this.volume = 0.8,
    this.muted = false,
  });

  Map<String, dynamic> toJson() => {
    'i': instrument.name,
    if (soundId != null) 's': soundId,
    'v': volume,
    if (muted) 'm': true,
  };

  static PartMix fromJson(Map<String, dynamic> j) => PartMix(
    instrument: Instrument.values.firstWhere(
      (i) => i.name == j['i'],
      orElse: () => Instrument.piano,
    ),
    soundId: j['s'] as String?,
    volume: (j['v'] as num?)?.toDouble() ?? 0.8,
    muted: j['m'] == true,
  );
}

/// How to play: speed, pitch, mix, metronome.
class PlaySettings {
  int tempo;
  int transpose;
  Transposing written;
  double referenceA;
  bool swing;
  bool metronome;
  bool countIn;

  /// A little pedal: notes ring on after they end.
  bool sustain;

  /// Room sound.
  bool reverb;
  List<PartMix> parts;

  PlaySettings({
    this.tempo = 100,
    this.transpose = 0,
    this.written = Transposing.concert,
    this.referenceA = 440,
    this.swing = false,
    this.metronome = false,
    this.countIn = false,
    this.sustain = false,
    this.reverb = false,
    List<PartMix>? parts,
  }) : parts = parts ?? [];

  PartMix part(int staff) {
    while (parts.length <= staff) {
      parts.add(PartMix());
    }
    return parts[staff];
  }

  Map<String, dynamic> toJson() => {
    'tempo': tempo,
    'transpose': transpose,
    'written': written.name,
    'a': referenceA,
    if (swing) 'swing': true,
    if (metronome) 'metronome': true,
    if (countIn) 'countIn': true,
    if (sustain) 'sustain': true,
    if (reverb) 'reverb': true,
    'parts': [for (final p in parts) p.toJson()],
  };

  static PlaySettings fromJson(Map<String, dynamic> j) => PlaySettings(
    tempo: j['tempo'] as int? ?? 100,
    transpose: j['transpose'] as int? ?? 0,
    written: Transposing.values.firstWhere(
      (t) => t.name == j['written'],
      orElse: () => Transposing.concert,
    ),
    referenceA: (j['a'] as num?)?.toDouble() ?? 440,
    swing: j['swing'] == true,
    metronome: j['metronome'] == true,
    countIn: j['countIn'] == true,
    sustain: j['sustain'] == true,
    reverb: j['reverb'] == true,
    parts: [
      for (final p in (j['parts'] as List?) ?? const [])
        PartMix.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
  );
}

/// A note as played: start and length in quarters (from the playback's
/// start), sounding MIDI note, staff, and which note of the score.
class PlayedNote {
  final double start, length;
  final int midi, staff, note;
  const PlayedNote(this.start, this.length, this.midi, this.staff, this.note);
}

/// What the playback does, measure by measure: where each measure starts
/// (quarters), in order, and the notes.
class Performance {
  final List<(int measure, double start)> measures;
  final List<PlayedNote> notes;
  final double length;

  /// Quarters of count-in before the music.
  final double lead;
  const Performance(this.measures, this.notes, this.length, this.lead);

  /// The measure playing at [q] quarters.
  int? measureAt(double q) {
    for (final (m, start) in measures.reversed) {
      if (q >= start) return m;
    }
    return null;
  }

  /// When measure [m] first plays.
  double? startOf(int m) {
    for (final (mm, start) in measures) {
      if (mm == m) return start;
    }
    return null;
  }
}

/// [score] as played with [s] (repeats, ties, swing, transposition).
Performance perform(Score score, PlaySettings s) {
  final lead = s.countIn ? score.measureLength : 0.0;
  final measures = <(int, double)>[];
  final notes = <PlayedNote>[];
  final byMeasure = <int, List<int>>{};
  for (final (i, n) in score.notes.indexed) {
    if (!n.rest) byMeasure.putIfAbsent(n.measure, () => []).add(i);
  }
  final shift = s.transpose + s.written.semitones;
  var t = lead;
  final order = score.playOrder;
  // Tied notes: carried over until the note they're tied to.
  final open =
      <
        (int, int),
        (double, double, int)
      >{}; // (staff, midi) → (start, length, note)
  for (final mi in order) {
    final m = score.measures[mi];
    measures.add((mi, t));
    final ids = byMeasure[mi] ?? const <int>[];
    final sorted = [...ids]
      ..sort((a, b) => score.notes[a].onset.compareTo(score.notes[b].onset));
    for (final i in sorted) {
      final n = score.notes[i];
      var start = t + n.onset - m.onset;
      var length = n.duration;
      if (s.swing) {
        // Long-short eighths: the one on the off-beat comes later.
        final beatPos = (n.onset - m.onset) % 1.0;
        if ((beatPos - 0.5).abs() < 0.01 && n.duration <= 0.5) {
          start += 1 / 6;
          length -= 1 / 6;
        } else if (beatPos.abs() < 0.01 && n.duration == 0.5) {
          length += 1 / 6;
        }
      }
      final midi = (n.midi + shift).clamp(0, 127);
      final key = (n.staff, midi);
      final held = open.remove(key);
      if (held != null && (held.$1 + held.$2 - start).abs() < 0.05) {
        // Continues a tie.
        length += held.$2;
        start = held.$1;
        if (n.tie) {
          open[key] = (start, length, held.$3);
        } else {
          notes.add(PlayedNote(start, length, midi, n.staff, held.$3));
        }
        continue;
      } else if (held != null) {
        notes.add(PlayedNote(held.$1, held.$2, midi, n.staff, held.$3));
      }
      if (n.tie) {
        open[key] = (start, length, i);
      } else {
        notes.add(PlayedNote(start, length, midi, n.staff, i));
      }
    }
    t += m.length;
  }
  for (final e in open.entries) {
    notes.add(
      PlayedNote(e.value.$1, e.value.$2, e.key.$2, e.key.$1, e.value.$3),
    );
  }
  notes.sort((a, b) => a.start.compareTo(b.start));
  return Performance(measures, notes, t, lead);
}

/// The key under which [render] finds the built-in sampled piano in its
/// sounds (the app loads it from its assets).
const grandPiano = 'builtin:piano';

/// The sound of [perf] from [fromQ] quarters on: mono samples at
/// [playbackRate]. [sounds] has the SoundFont sounds the mix uses (and the
/// sampled piano under [grandPiano]).
Float32List render(
  Score score,
  Performance perf,
  PlaySettings s, {
  double fromQ = 0,
  Map<String, PadSound> sounds = const {},
}) {
  final spq = 60 / s.tempo.clamp(20, 400); // seconds per quarter
  final total = ((perf.length - fromQ) * spq + 2.5) * playbackRate;
  final out = Float32List(math.max(1, total.round()));
  final random = math.Random(7);
  for (final n in perf.notes) {
    if (n.start + n.length <= fromQ) continue;
    final part = s.part(n.staff);
    if (part.muted) continue;
    final hz = s.referenceA * math.pow(2, (n.midi - 69) / 12).toDouble();
    final begin = math.max(0.0, (n.start - fromQ) * spq);
    // Notes already sounding when playback starts are cut in.
    final skip = math.max(0.0, (fromQ - n.start) * spq);
    var secs = n.length * spq - skip;
    if (secs <= 0) continue;
    // A little pedal: held a touch longer, overlapping the next note.
    if (s.sustain) secs += 0.45;
    final sound = part.soundId != null
        ? sounds[part.soundId]
        : (part.instrument == Instrument.piano ? sounds[grandPiano] : null);
    final vol = part.volume * 0.35;
    if (sound != null) {
      _sampled(
        out,
        sound,
        n.midi,
        hz,
        begin,
        secs,
        vol,
        release: s.sustain ? 0.8 : 0.25,
      );
    } else {
      _voice(out, part.instrument, hz, begin, secs, vol, random);
    }
  }
  if (s.metronome || s.countIn) {
    final beat =
        4 /
        score.beatType *
        (score.beatType == 8 && score.beats % 3 == 0 ? 3 : 1);
    var q = 0.0;
    var k = 0;
    final perBar = score.measureLength / beat;
    while (q < perf.length) {
      final inLead = q < perf.lead;
      if ((s.metronome || inLead) && q >= fromQ) {
        _click(out, (q - fromQ) * spq, k % perBar.round() == 0);
      }
      q += beat;
      k++;
    }
  }
  if (s.reverb) _reverb(out);
  // Keep it below clipping.
  var peak = 0.0;
  for (final v in out) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak > 0.95) {
    final g = 0.95 / peak;
    for (var i = 0; i < out.length; i++) {
      out[i] *= g;
    }
  }
  return out;
}

void _click(Float32List out, double at, bool accent) {
  final start = (at * playbackRate).round();
  final hz = accent ? 1760.0 : 1320.0;
  final len = (0.03 * playbackRate).round();
  for (var i = 0; i < len && start + i < out.length; i++) {
    final env = math.exp(-i / (len / 5));
    out[start + i] += 0.5 * env * math.sin(2 * math.pi * hz * i / playbackRate);
  }
}

double _saw(double phase) => 2 * (phase - phase.floorToDouble()) - 1;

/// A built-in instrument's note.
void _voice(
  Float32List out,
  Instrument inst,
  double hz,
  double at,
  double secs,
  double vol,
  math.Random random,
) {
  const sr = playbackRate;
  final start = (at * sr).round();
  if (start >= out.length) return;
  switch (inst) {
    case Instrument.guitar || Instrument.nylonGuitar || Instrument.bass:
      _pluck(out, start, secs, hz, vol, random, inst);
      return;
    default:
  }
  // Envelope: attack, decay to sustain, release (seconds).
  final (attack, decay, sustain, release) = switch (inst) {
    Instrument.piano => (0.003, secs.clamp(0.4, 3.0), 0.0, 0.12),
    Instrument.electricPiano => (0.004, 1.6, 0.25, 0.15),
    Instrument.organ || Instrument.churchOrgan => (0.01, 0.0, 1.0, 0.06),
    Instrument.strings => (0.09, 0.2, 0.85, 0.25),
    Instrument.choir => (0.12, 0.2, 0.85, 0.3),
    Instrument.flute => (0.04, 0.1, 0.9, 0.08),
    Instrument.clarinet || Instrument.oboe => (0.03, 0.1, 0.85, 0.06),
    Instrument.trumpet || Instrument.brass => (0.03, 0.15, 0.8, 0.08),
    Instrument.harmonica => (0.03, 0.1, 0.85, 0.07),
    _ => (0.01, 0.1, 0.8, 0.05),
  };
  final n = ((secs + release) * sr).round();
  final end = math.min(out.length, start + n);
  final held = secs;
  var phase = 0.0;
  var phase2 = random.nextDouble();
  var lp = 0.0;
  for (var i = start; i < end; i++) {
    final t = (i - start) / sr;
    // Envelope.
    double env;
    if (t < attack) {
      env = t / attack;
    } else if (t < held) {
      if (inst == Instrument.piano) {
        env =
            math.exp(-(t - attack) * 3.2 / decay) * 0.9 +
            0.1 * math.exp(-t * 0.6);
      } else if (decay > 0 && t < attack + decay) {
        env = 1 - (1 - sustain) * (t - attack) / decay;
      } else {
        env = inst == Instrument.electricPiano
            ? math.max(sustain, math.exp(-(t - attack) * 1.4))
            : sustain;
      }
    } else {
      final atRelease = inst == Instrument.piano
          ? math.exp(-(held - attack) * 3.2 / decay) * 0.9 +
                0.1 * math.exp(-held * 0.6)
          : (inst == Instrument.electricPiano
                ? math.max(sustain, math.exp(-(held - attack) * 1.4))
                : sustain);
      env = atRelease * math.max(0, 1 - (t - held) / release);
    }
    if (env <= 0) continue;
    // Vibrato on held winds and strings.
    final vib = switch (inst) {
      Instrument.strings ||
      Instrument.choir ||
      Instrument.flute ||
      Instrument.oboe =>
        1 + 0.004 * math.sin(2 * math.pi * 5.2 * t) * math.min(1, t * 2),
      Instrument.harmonica => 1 + 0.006 * math.sin(2 * math.pi * 6 * t),
      _ => 1.0,
    };
    final f = hz * vib;
    phase += f / sr;
    final p = phase * 2 * math.pi;
    double v;
    switch (inst) {
      case Instrument.piano:
        // Partials, the high ones fading faster, slightly stretched.
        v = 0;
        for (var k = 1; k <= 8; k++) {
          final stretch = k * (1 + 0.0004 * k * k);
          v += math.sin(p * stretch) * math.exp(-t * k * 0.9) / (k * 0.9);
        }
        v *= 0.6;
      case Instrument.electricPiano:
        // FM: a bell-ish tine.
        final mod = math.sin(p) * 1.8 * math.exp(-t * 3);
        v = math.sin(p + mod) * 0.7;
      case Instrument.organ:
        v =
            (math.sin(p) +
                0.6 * math.sin(2 * p) +
                0.45 * math.sin(3 * p) +
                0.3 * math.sin(4 * p) +
                0.2 * math.sin(6 * p)) *
            0.35;
      case Instrument.churchOrgan:
        v =
            (math.sin(p / 2) * 0.5 +
                math.sin(p) +
                0.5 * math.sin(2 * p) +
                0.35 * math.sin(3 * p) +
                0.25 * math.sin(4 * p) +
                0.18 * math.sin(5 * p) +
                0.15 * math.sin(8 * p)) *
            0.3;
      case Instrument.strings || Instrument.brass || Instrument.trumpet:
        phase2 += f * 1.003 / sr;
        final raw = (_saw(phase) + _saw(phase2)) * 0.5;
        // Brighter as the note opens (brass), softer for strings.
        final cut = inst == Instrument.strings
            ? 0.12
            : (0.08 + 0.25 * math.min(1, t / 0.08));
        lp += (raw - lp) * cut;
        v = lp * 0.9;
      case Instrument.choir:
        // Soft saw through a vowel-ish formant pair.
        phase2 += f * 0.997 / sr;
        final raw = (_saw(phase) + _saw(phase2)) * 0.5;
        lp += (raw - lp) * 0.07;
        v = (lp * 0.8 + 0.15 * math.sin(p * 3)) * 0.9;
      case Instrument.flute:
        v =
            (math.sin(p) +
                0.12 * math.sin(2 * p) +
                0.04 * (random.nextDouble() - 0.5)) *
            0.8;
      case Instrument.clarinet:
        // Odd harmonics.
        v =
            (math.sin(p) +
                0.45 * math.sin(3 * p) +
                0.25 * math.sin(5 * p) +
                0.12 * math.sin(7 * p)) *
            0.5;
      case Instrument.oboe:
        v =
            (math.sin(p) * 0.5 +
                0.8 * math.sin(2 * p) +
                0.6 * math.sin(3 * p) +
                0.4 * math.sin(4 * p) +
                0.2 * math.sin(5 * p)) *
            0.35;
      case Instrument.harmonica:
        final sq = math.sin(p) > 0 ? 1.0 : -1.0;
        lp += (sq - lp) * 0.18;
        v = (lp * 0.6 + 0.3 * math.sin(2 * p)) * 0.6;
      default:
        v = math.sin(p) * 0.8;
    }
    out[i] += v * env * vol;
  }
}

/// Plucked strings (Karplus–Strong).
void _pluck(
  Float32List out,
  int start,
  double secs,
  double hz,
  double vol,
  math.Random random,
  Instrument inst,
) {
  const sr = playbackRate;
  final period = math.max(2, (sr / hz).round());
  final line = Float32List(period);
  var prev = 0.0;
  final soft = inst == Instrument.nylonGuitar || inst == Instrument.bass;
  for (var i = 0; i < period; i++) {
    final noise = random.nextDouble() * 2 - 1;
    prev = soft ? (noise + prev * 3) / 4 : (noise + prev) / 2;
    line[i] = prev;
  }
  final ring = math.min(secs + 0.15, inst == Instrument.bass ? 3.0 : 4.0);
  final stop = math.min(out.length, start + (ring * sr).round());
  final damp = 300;
  final decay = inst == Instrument.bass ? 0.995 : 0.997;
  var p = 0;
  for (var i = start; i < stop; i++) {
    final next = (p + 1) % period;
    final v = line[p];
    line[p] = decay * 0.5 * (line[p] + line[next]);
    final fade = stop - i < damp ? (stop - i) / damp : 1.0;
    out[i] += v * vol * 1.3 * fade;
    p = next;
  }
}

/// A note from a SoundFont sound (looped if it loops), released at its end.
void _sampled(
  Float32List out,
  PadSound sound,
  int midi,
  double hz,
  double at,
  double secs,
  double vol, {
  double release = 0.25,
}) {
  const sr = playbackRate;
  final start = (at * sr).round();
  for (final z in sound.zonesFor(midi)) {
    // Pitch: the zone's root and tuning give its recorded frequency.
    final rootHz =
        440 * math.pow(2, (z.root - 69) / 12 - z.tune / 1200).toDouble();
    final cents = (midi - z.root) * (z.scale - 100);
    final step = hz / rootHz * math.pow(2, cents / 1200) * z.rate / sr;
    final n = ((secs + release) * sr).round();
    final pcm = sound.pcm;
    final k = vol * z.gain * 1.6 / 32768;
    final held = (secs * sr).round();
    final attack = (0.005 * sr).round();
    final rel = release * sr;
    final looped = z.loop && z.loopEnd > z.loopStart;
    final last = math.min(n, out.length - start);
    var pos = 0.0;
    for (var i = 0; i < last; i++) {
      var idx = pos.toInt();
      if (looped && idx >= z.loopEnd) {
        final len = z.loopEnd - z.loopStart;
        pos -= len * ((idx - z.loopStart) ~/ len);
        idx = pos.toInt();
      }
      if (idx + 1 >= z.length) break;
      final a = pcm[z.offset + idx];
      final v = a + (pcm[z.offset + idx + 1] - a) * (pos - idx);
      final env = i < attack
          ? i / attack
          : (i > held ? math.max(0.0, 1 - (i - held) / rel) : 1.0);
      out[start + i] += v * env * k;
      pos += step;
    }
  }
}

/// A small room: Schroeder reverb (four combs, two all-passes) mixed in.
void _reverb(Float32List out) {
  const sr = playbackRate;
  final c0 = Float32List((1116 * sr / 44100).round());
  final c1 = Float32List((1188 * sr / 44100).round());
  final c2 = Float32List((1277 * sr / 44100).round());
  final c3 = Float32List((1356 * sr / 44100).round());
  final a0 = Float32List((556 * sr / 44100).round());
  final a1 = Float32List((441 * sr / 44100).round());
  var p0 = 0, p1 = 0, p2 = 0, p3 = 0, q0 = 0, q1 = 0;
  var d0 = 0.0, d1 = 0.0, d2 = 0.0, d3 = 0.0;
  const fb = 0.8, damp = 0.25, keep = 1 - damp, wet = 0.22;
  for (var i = 0; i < out.length; i++) {
    final x = out[i] * 0.3;
    final v0 = c0[p0], v1 = c1[p1], v2 = c2[p2], v3 = c3[p3];
    d0 = v0 * keep + d0 * damp;
    d1 = v1 * keep + d1 * damp;
    d2 = v2 * keep + d2 * damp;
    d3 = v3 * keep + d3 * damp;
    c0[p0] = x + d0 * fb;
    c1[p1] = x + d1 * fb;
    c2[p2] = x + d2 * fb;
    c3[p3] = x + d3 * fb;
    if (++p0 == c0.length) p0 = 0;
    if (++p1 == c1.length) p1 = 0;
    if (++p2 == c2.length) p2 = 0;
    if (++p3 == c3.length) p3 = 0;
    var y = v0 + v1 + v2 + v3;
    final w0 = a0[q0];
    a0[q0] = y + w0 * 0.5;
    y = w0 - y;
    if (++q0 == a0.length) q0 = 0;
    final w1 = a1[q1];
    a1[q1] = y + w1 * 0.5;
    y = w1 - y;
    if (++q1 == a1.length) q1 = 0;
    out[i] += y * wet;
  }
}
