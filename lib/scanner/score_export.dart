// A read score saved for other apps: MusicXML (MuseScore, Finale, Sibelius,
// Dorico…), MIDI, and the playback as a WAV file.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'playback.dart';
import 'score.dart';

const _divisions = 48; // per quarter: 16ths, 32nds and triplets fit

String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

/// [score] as MusicXML (partwise; staves in one part, like a piano score,
/// or one staff).
String scoreToMusicXml(Score score) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">',
    )
    ..writeln('<score-partwise version="4.0">');
  if (score.title.isNotEmpty) {
    b.writeln('  <work><work-title>${_esc(score.title)}</work-title></work>');
  }
  b
    ..writeln(
      '  <part-list><score-part id="P1"><part-name>Music</part-name></score-part></part-list>',
    )
    ..writeln('  <part id="P1">');
  final staves = score.staves;
  final byMeasure = <int, List<ScoreNote>>{};
  for (final n in score.notes) {
    byMeasure.putIfAbsent(n.measure, () => []).add(n);
  }
  for (final (mi, m) in score.measures.indexed) {
    b.writeln('    <measure number="${mi + 1}">');
    if (mi == 0) {
      b.write('      <attributes><divisions>$_divisions</divisions>');
      b.write('<key><fifths>${score.fifths}</fifths></key>');
      b.write(
        '<time><beats>${score.beats}</beats><beat-type>${score.beatType}</beat-type></time>',
      );
      if (staves > 1) b.write('<staves>$staves</staves>');
      for (final (i, c) in score.clefs.indexed) {
        final (sign, line) = switch (c) {
          Clef.treble => ('G', 2),
          Clef.bass => ('F', 4),
          Clef.alto => ('C', 3),
          Clef.tenor => ('C', 4),
        };
        b.write(
          '<clef number="${i + 1}"><sign>$sign</sign><line>$line</line></clef>',
        );
      }
      b.writeln('</attributes>');
      b.writeln(
        '      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>${score.tempo}</per-minute></metronome></direction-type><sound tempo="${score.tempo}"/></direction>',
      );
    }
    if (m.repeatStart) {
      b.writeln(
        '      <barline location="left"><bar-style>heavy-light</bar-style><repeat direction="forward"/></barline>',
      );
    }
    final inM = byMeasure[mi] ?? const <ScoreNote>[];
    final voices = <(int, int), List<ScoreNote>>{};
    for (final n in inM) {
      voices.putIfAbsent((n.staff, n.voice), () => []).add(n);
    }
    final keys = voices.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    var first = true;
    for (final k in keys) {
      final v = voices[k]!
        ..sort((a, b) {
          final c = a.onset.compareTo(b.onset);
          return c != 0 ? c : b.diatonic.compareTo(a.diatonic);
        });
      if (!first) {
        b.writeln(
          '      <backup><duration>${(m.length * _divisions).round()}</duration></backup>',
        );
      }
      first = false;
      var t = m.onset;
      double? lastOnset;
      final voiceNo = k.$1 * 2 + k.$2;
      for (final n in v) {
        final chord =
            !n.rest && lastOnset != null && (n.onset - lastOnset).abs() < 1e-6;
        if (!chord && n.onset > t + 1e-6) {
          // A gap: fill with a hidden-ish rest so the voice lines up.
          final gap = ((n.onset - t) * _divisions).round();
          b.writeln('      <forward><duration>$gap</duration></forward>');
          t = n.onset;
        }
        final dur = (n.duration * _divisions).round();
        b.write('      <note>');
        if (chord) b.write('<chord/>');
        if (n.rest) {
          b.write('<rest/>');
        } else {
          b.write('<pitch><step>${stepOf(n.diatonic)}</step>');
          if (n.alter != 0) b.write('<alter>${n.alter}</alter>');
          b.write('<octave>${n.diatonic ~/ 7}</octave></pitch>');
        }
        b.write('<duration>${math.max(1, dur)}</duration>');
        if (n.tie && !n.rest) b.write('<tie type="start"/>');
        b.write('<voice>$voiceNo</voice><type>${n.type}</type>');
        for (var d = 0; d < n.dots; d++) {
          b.write('<dot/>');
        }
        if (n.accidental != null) {
          b.write(
            '<accidental>${switch (n.accidental!) {
              1 => 'sharp',
              -1 => 'flat',
              2 => 'double-sharp',
              -2 => 'flat-flat',
              _ => 'natural',
            }}</accidental>',
          );
        }
        if (n.triplet) {
          b.write(
            '<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>',
          );
        }
        if (staves > 1) b.write('<staff>${n.staff + 1}</staff>');
        if (n.tie && !n.rest) {
          b.write('<notations><tied type="start"/></notations>');
        }
        b.writeln('</note>');
        if (!chord) {
          t = n.onset + n.duration;
          lastOnset = n.onset;
        }
      }
    }
    if (m.repeatEnd) {
      b.writeln(
        '      <barline location="right"><bar-style>light-heavy</bar-style><repeat direction="backward"/></barline>',
      );
    }
    b.writeln('    </measure>');
  }
  b
    ..writeln('  </part>')
    ..writeln('</score-partwise>');
  return b.toString();
}

// ---- MIDI ----

List<int> _varLen(int v) {
  final bytes = <int>[v & 0x7f];
  v >>= 7;
  while (v > 0) {
    bytes.insert(0, (v & 0x7f) | 0x80);
    v >>= 7;
  }
  return bytes;
}

const _gmPrograms = {
  Instrument.piano: 0,
  Instrument.electricPiano: 4,
  Instrument.organ: 16,
  Instrument.churchOrgan: 19,
  Instrument.strings: 48,
  Instrument.guitar: 25,
  Instrument.nylonGuitar: 24,
  Instrument.bass: 32,
  Instrument.flute: 73,
  Instrument.clarinet: 71,
  Instrument.oboe: 68,
  Instrument.trumpet: 56,
  Instrument.brass: 61,
  Instrument.harmonica: 22,
  Instrument.choir: 52,
  Instrument.sine: 80,
};

/// The playback of [score] as a standard MIDI file: a track per staff,
/// its instrument and volume, at the chosen tempo and pitch.
Uint8List scoreToMidi(Score score, PlaySettings s) {
  const ppq = 480;
  final perf = perform(
    score,
    PlaySettings.fromJson(s.toJson())..countIn = false,
  );
  List<int> chunk(String id, List<int> data) => [
    ...ascii.encode(id),
    (data.length >> 24) & 0xff,
    (data.length >> 16) & 0xff,
    (data.length >> 8) & 0xff,
    data.length & 0xff,
    ...data,
  ];
  final tracks = <List<int>>[];
  // Track 0: tempo, time and key.
  final mpq = (60000000 / s.tempo).round();
  final fifths = score.fifths < 0 ? 256 + score.fifths : score.fifths;
  tracks.add([
    0,
    0xff,
    0x51,
    3,
    (mpq >> 16) & 0xff,
    (mpq >> 8) & 0xff,
    mpq & 0xff,
    0,
    0xff,
    0x58,
    4,
    score.beats,
    (math.log(score.beatType) / math.ln2).round(),
    24,
    8,
    0,
    0xff,
    0x59,
    2,
    fifths,
    0,
    0,
    0xff,
    0x2f,
    0,
  ]);
  for (var st = 0; st < score.staves; st++) {
    final part = s.part(st);
    final ch = st % 16 == 9 ? 10 : st % 16;
    final events = <(int, List<int>)>[];
    for (final n in perf.notes.where((n) => n.staff == st)) {
      final on = (n.start * ppq).round(),
          off = ((n.start + n.length) * ppq).round();
      final vel = (90 * part.volume / 0.8).round().clamp(1, 127);
      events
        ..add((on, [0x90 | ch, n.midi, part.muted ? 1 : vel]))
        ..add((math.max(on + 1, off - 1), [0x80 | ch, n.midi, 0]));
    }
    events.sort(
      (a, b) =>
          a.$1 != b.$1 ? a.$1 - b.$1 : (a.$2[0] & 0xf0) - (b.$2[0] & 0xf0),
    );
    final data = <int>[
      0,
      0xc0 | ch,
      _gmPrograms[part.instrument] ?? 0,
      0,
      0xb0 | ch,
      7,
      (127 * part.volume).round().clamp(0, 127),
    ];
    var last = 0;
    for (final (t, e) in events) {
      data
        ..addAll(_varLen(t - last))
        ..addAll(e);
      last = t;
    }
    data.addAll([0, 0xff, 0x2f, 0]);
    tracks.add(data);
  }
  return Uint8List.fromList([
    ...chunk('MThd', [0, 1, 0, tracks.length, (ppq >> 8) & 0xff, ppq & 0xff]),
    for (final t in tracks) ...chunk('MTrk', t),
  ]);
}

/// Mono samples (−1…1) as a 16-bit WAV file.
Uint8List samplesToWav(Float32List samples, int rate) {
  final data = ByteData(44 + samples.length * 2);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
